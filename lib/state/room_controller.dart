import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/ai.dart';
import '../core/feedback.dart';
import '../core/game_logic.dart';
import '../models/chat_message.dart';
import '../models/room.dart';
import '../services/chat_service.dart';
import '../services/room_prefs.dart';
import '../services/room_service.dart';
import '../services/stats_service.dart';
import '../services/supabase_service.dart';

class RoomController extends ChangeNotifier {
  static const _heartbeatInterval = Duration(seconds: 10);
  static const _offlineAfter = Duration(seconds: 90);
  static const _reclaimCooldown = Duration(seconds: 30);

  Room? room;
  bool loading = false;
  String? error;
  String? myUid;
  String? myName;
  RealtimeChannel? _channel;
  String? _lastAiKey;
  Timer? _heartbeat;
  final Set<int> _takeOverInFlight = {};
  DateTime? _lastReclaimAt;
  int? lastIndex;
  Duration? remaining;
  String? timeoutMessage;
  String? undoMessage;
  Timer? _countdown;
  bool _timeoutInFlight = false;
  bool _countedFinished = false;
  List<ChatMessage> messages = [];
  int _lastReadCount = 0;

  /// 未读聊天消息数（打开面板/进房后清零）。
  int get unreadChatCount {
    final n = messages.length - _lastReadCount;
    return n < 0 ? 0 : n;
  }

  /// 标记已读（打开聊天面板时调用）。
  void markChatRead() {
    final n = messages.length;
    if (_lastReadCount == n) return;
    _lastReadCount = n;
    notifyListeners();
  }

  /// 面板内静默同步（不通知，避免 build 期间触发重建）。
  void markChatReadSilently() {
    _lastReadCount = messages.length;
  }

  int get mySlot {
    final r = room;
    if (r == null || myUid == null) return -1;
    return r.players.indexWhere((p) => p.uid == myUid);
  }

  bool get isMyTurn {
    final r = room;
    if (r == null || !r.isPlaying) return false;
    final slot = mySlot;
    if (slot < 0) return false;
    return r.turn == slot && !r.players[slot].isAi;
  }

  Future<bool> create(String name, int aiCount,
      {String difficulty = 'medium', int? turnTimeoutSec}) =>
      _run(() async {
        myUid = await SupabaseService.ensureSignedIn();
        myName = name;
        room = await RoomService.createRoom(name, aiCount,
            difficulty: difficulty, turnTimeoutSec: turnTimeoutSec);
        _countedFinished = room!.isFinished;
        await RoomPrefs.save(room!.code, name);
        await _subscribe();
        _startHeartbeat();
        _scheduleAiIfNeeded();
        await _loadChatHistory();
      });

  Future<bool> join(String code, String name) => _run(() async {
        myUid = await SupabaseService.ensureSignedIn();
        myName = name;
        room = await RoomService.joinRoom(code, name);
        _countedFinished = room!.isFinished;
        await RoomPrefs.save(room!.code, name);
        await _subscribe();
        _startHeartbeat();
        _scheduleAiIfNeeded();
        await _loadChatHistory();
      });

  Future<bool> _run(Future<void> Function() fn) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await fn();
      return true;
    } catch (e) {
      error = e.toString();
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// 应用新房间状态；若检测到新落子则触发音效/震动/动画标记。
  void _applyRoom(Room newRoom) {
    final old = room;
    room = newRoom;
    if (old != null) {
      final idx = _findNewStone(old.board, newRoom.board);
      if (idx != null) {
        lastIndex = idx;
        MoveFeedback.play();
      }
    }
    _trackFinished(newRoom);
    _syncCountdown();
    notifyListeners();
  }

  /// 每局结束记一次战绩；再来一局（回到 playing）后重置，可再记下一局。
  void _trackFinished(Room r) {
    if (r.isPlaying) {
      _countedFinished = false;
      return;
    }
    if (!r.isFinished || _countedFinished) return;
    _countedFinished = true;
    final slot = mySlot;
    if (slot < 0) return;
    if (r.winner == slot) {
      unawaited(StatsService.record(win: true, draw: false));
    } else if (r.winner == null) {
      unawaited(StatsService.record(win: false, draw: true));
    } else {
      unawaited(StatsService.record(win: false, draw: false));
    }
  }

  int? _findNewStone(List<int> oldBoard, List<int> newBoard) {
    for (int i = 0; i < oldBoard.length && i < newBoard.length; i++) {
      if (oldBoard[i] == GameLogic.empty && newBoard[i] != GameLogic.empty) {
        return i;
      }
    }
    return null;
  }

  // ---------- 回合计时 ----------

  /// 根据房间状态启停倒计时：playing 且当前回合为人座且有限时 → 每秒刷新 remaining。
  void _syncCountdown() {
    final r = room;
    final active = r != null &&
        r.isPlaying &&
        r.moveDeadline != null &&
        r.turn >= 0 &&
        r.turn <= 2 &&
        !r.players[r.turn].isAi;
    if (!active) {
      if (remaining != null || _countdown != null) {
        remaining = null;
        _countdown?.cancel();
        _countdown = null;
        notifyListeners();
      }
      return;
    }
    _countdown ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickCountdown(),
    );
    _tickCountdown();
  }

  void _tickCountdown() {
    final r = room;
    if (r == null || !r.isPlaying) {
      remaining = null;
      _countdown?.cancel();
      _countdown = null;
      notifyListeners();
      return;
    }
    final dl = r.moveDeadline;
    if (dl == null) {
      remaining = null;
      _countdown?.cancel();
      _countdown = null;
      notifyListeners();
      return;
    }
    final left = dl.difference(DateTime.now());
    if (left <= Duration.zero) {
      remaining = Duration.zero;
      notifyListeners();
      _handleTimeout(r);
      return;
    }
    if (remaining == null || remaining!.inSeconds != left.inSeconds) {
      remaining = left;
      notifyListeners();
    }
  }

  /// 超时：任何成员均可代该座落子（AI 计算在本地，服务端校验截止时间）。
  Future<void> _handleTimeout(Room r) async {
    if (_timeoutInFlight) return;
    if (!r.isPlaying || r.turn < 0 || r.turn > 2) return;
    if (r.players[r.turn].isAi) return;
    final dl = r.moveDeadline;
    if (dl != null && dl.isAfter(DateTime.now())) return;
    _timeoutInFlight = true;
    try {
      final slot = r.turn;
      final idx = GomokuAI.bestMove(r.board, slot + 1, difficulty: r.aiDifficulty);
      final rr = await RoomService.submitMove(
        r.id,
        slot,
        GameLogic.rowOf(idx),
        GameLogic.colOf(idx),
        asTimeoutAi: true,
      );
      _applyRoom(rr);
      timeoutMessage = '${r.players[slot].displayName} 超时，AI 代下一手';
      notifyListeners();
      _scheduleAiIfNeeded();
    } catch (_) {
      // 竞争失败/校验拒绝：忽略，Realtime 会带来权威状态
    } finally {
      _timeoutInFlight = false;
    }
  }

  void clearTimeoutMessage() {
    if (timeoutMessage != null) {
      timeoutMessage = null;
      notifyListeners();
    }
  }

  void clearUndoMessage() {
    if (undoMessage != null) {
      undoMessage = null;
      notifyListeners();
    }
  }

  // ---------- 悔棋 ----------

  /// 是否有待处理的悔棋请求。
  bool get undoPending => room?.undoPending ?? false;

  /// 我能发起悔棋：对局中、无 pending、且最后一步是我下的（含被 AI 代下的座位）。
  bool get canRequestUndo {
    final r = room;
    if (r == null || !r.isPlaying || r.undoPending) return false;
    final slot = mySlot;
    return slot >= 0 && r.lastMoveSlot == slot;
  }

  /// 我是待同意悔棋的发起者。
  bool get iAmUndoRequester {
    final r = room;
    if (r == null || !r.undoPending || myUid == null) return false;
    final s = r.undoSenderSlot;
    if (s == null || s < 0 || s > 2) return false;
    return r.players[s].uid == myUid;
  }

  /// 我是需要投票的真人座位（非发起者、非 AI）。
  bool get iAmUndoVoter {
    final r = room;
    if (r == null || !r.undoPending || iAmUndoRequester) return false;
    final slot = mySlot;
    if (slot < 0 || r.players[slot].isAi) return false;
    return true;
  }

  Future<void> requestUndo() async {
    final r = room;
    if (r == null || !canRequestUndo) return;
    try {
      final rr = await RoomService.requestUndo(r.id);
      _applyRoom(rr);
      undoMessage = rr.undoPending ? '已发起悔棋，等待其他玩家同意…' : '悔棋成功';
      notifyListeners();
    } catch (e) {
      undoMessage = '悔棋失败：${_friendlyError(e)}';
      notifyListeners();
    }
  }

  Future<void> respondUndo(bool accept) async {
    final r = room;
    if (r == null || !iAmUndoVoter) return;
    try {
      final rr = await RoomService.respondUndo(r.id, accept);
      _applyRoom(rr);
      if (!accept) {
        undoMessage = '已拒绝悔棋';
      } else if (!rr.undoPending) {
        undoMessage = '已同意，悔棋生效';
      } else {
        undoMessage = '已同意，等待其他玩家…';
      }
      notifyListeners();
    } catch (e) {
      undoMessage = '操作失败：${_friendlyError(e)}';
      notifyListeners();
    }
  }

  Future<void> cancelUndo() async {
    final r = room;
    if (r == null || !iAmUndoRequester) return;
    try {
      _applyRoom(await RoomService.cancelUndo(r.id));
      undoMessage = '已取消悔棋请求';
      notifyListeners();
    } catch (e) {
      undoMessage = '取消失败：${_friendlyError(e)}';
      notifyListeners();
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('undo pending')) return '已有悔棋请求待处理';
    if (s.contains('not your last move')) return '只能悔自己下的最后一步';
    if (s.contains('undo expired')) return '悔棋请求已过期';
    if (s.contains('no moves to undo')) return '还没有可悔的落子';
    if (s.contains('not your turn')) return '还没轮到你';
    return s;
  }

  // ---------- 心跳 ----------

  void _startHeartbeat() {
    _heartbeat?.cancel();
    ping();
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) => ping());
  }

  /// 立即发送一次心跳（App 回到前台时调用）。
  Future<void> ping() async {
    final r = room;
    if (r == null || myUid == null) return;
    try {
      await RoomService.setConnected(r.id, true);
      _checkOffline();
    } catch (_) {}
  }

  // ---------- Realtime ----------

  Future<void> _subscribe() async {
    await _unsubscribe();
    final r = room!;
    final ch = SupabaseService.client.channel('room_${r.id}');
    ch.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'rooms',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: r.id,
      ),
      callback: (payload) {
        final rec = payload.newRecord;
        _applyRoom(Room.fromJson(Map<String, dynamic>.from(rec)));
        _maybeReclaim();
        _checkOffline();
        _scheduleAiIfNeeded();
      },
    );
    ch.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'room_id',
        value: r.id,
      ),
      callback: (payload) {
        final m = ChatMessage.fromJson(Map<String, dynamic>.from(payload.newRecord));
        if (messages.any((x) => x.id == m.id)) return;
        messages = [...messages, m];
        if (messages.length > 100) {
          messages = messages.sublist(messages.length - 100);
        }
        notifyListeners();
      },
    ).subscribe();
    _channel = ch;
  }

  Future<void> _unsubscribe() async {
    if (_channel != null) {
      await SupabaseService.client.removeChannel(_channel!);
      _channel = null;
    }
  }

  // ---------- 落子 ----------

  Future<void> submitMove(int row, int col) async {
    final r = room;
    if (r == null) return;
    final slot = mySlot;
    if (slot < 0) return;
    if (r.turn != slot || r.players[slot].isAi) return;
    final idx = GameLogic.indexOf(row, col);
    if (r.board[idx] != GameLogic.empty) return;
    try {
      _applyRoom(await RoomService.submitMove(r.id, slot, row, col));
      _scheduleAiIfNeeded();
    } catch (e) {
      if (e.toString().contains('undo pending')) {
        undoMessage = '有悔棋请求待处理，先处理后才能落子';
        notifyListeners();
      }
      // 其他失败时 Realtime 会用服务端权威状态纠正。
    }
  }

  // ---------- 聊天 ----------

  Future<void> _loadChatHistory() async {
    final r = room;
    if (r == null) return;
    try {
      messages = await ChatService.history(r.id);
      _lastReadCount = messages.length;
      notifyListeners();
    } catch (_) {}
  }

  /// 发送聊天消息；内容非法或失败返回 false。
  Future<bool> sendChat(String body) async {
    final r = room;
    if (r == null) return false;
    final b = body.trim();
    if (b.isEmpty || b.length > 200) return false;
    try {
      await ChatService.send(r.id, b);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------- AI 代下（空位 AI / 托管座位） ----------

  void _scheduleAiIfNeeded() {
    final r = room;
    if (r == null || !r.isPlaying || r.winner != null) return;
    if (r.turn < 0 || r.turn > 2) return;
    if (!r.players[r.turn].isAi) return;

    final key = '${r.turn}:${r.board.join()}';
    if (key == _lastAiKey) return;
    _lastAiKey = key;

    final slot = r.turn;
    Future.delayed(const Duration(milliseconds: 450), () async {
      final cur = room;
      if (cur == null ||
          cur.turn != slot ||
          !cur.players[slot].isAi ||
          cur.winner != null) {
        return;
      }
      // 后台 isolate 计算，避免困难档卡 UI（ai.dart 为纯 Dart）
      final curBoard = List<int>.of(cur.board);
      final aiDiff = cur.aiDifficulty;
      final int idx;
      try {
        idx = await Isolate.run(
          () => GomokuAI.bestMove(curBoard, slot + 1, difficulty: aiDiff),
        );
      } catch (_) {
        return;
      }
      try {
        _applyRoom(await RoomService.submitMove(
          cur.id,
          slot,
          GameLogic.rowOf(idx),
          GameLogic.colOf(idx),
        ));
        _scheduleAiIfNeeded();
      } catch (_) {}
    });
  }

  // ---------- 掉线检测与托管 ----------

  void _checkOffline() {
    final r = room;
    if (r == null || !r.isPlaying || myUid == null) return;
    final now = DateTime.now();
    for (int i = 0; i < r.players.length; i++) {
      final p = r.players[i];
      if (p.isAi || p.uid == null || p.uid == myUid) continue;
      if (_takeOverInFlight.contains(i)) continue;
      final ls = p.lastSeen;
      if (ls == null || now.difference(ls) > _offlineAfter) {
        _takeOverInFlight.add(i);
        _takeOverAsync(i);
      }
    }
  }

  Future<void> _takeOverAsync(int slot) async {
    final r = room;
    if (r == null) {
      _takeOverInFlight.remove(slot);
      return;
    }
    try {
      await RoomService.takeOver(r.id, slot);
    } catch (_) {}
    _takeOverInFlight.remove(slot);
  }

  /// 自己的座位被托管后，网络恢复时自动恢复控制权。
  void _maybeReclaim() {
    final r = room;
    if (r == null || myUid == null) return;
    final slot = mySlot;
    if (slot < 0 || !r.players[slot].takenOver) return;
    final now = DateTime.now();
    if (_lastReclaimAt != null &&
        now.difference(_lastReclaimAt!) < _reclaimCooldown) {
      return;
    }
    _lastReclaimAt = now;
    _reclaimAsync();
  }

  Future<void> _reclaimAsync() async {
    final r = room;
    if (r == null) return;
    try {
      final rr = await RoomService.joinRoom(r.code, myName ?? '玩家');
      _applyRoom(rr);
      _scheduleAiIfNeeded();
    } catch (_) {}
  }

  // ---------- 再来一局 ----------

  Future<void> rematch() async {
    final r = room;
    if (r == null) return;
    try {
      lastIndex = null;
      _applyRoom(await RoomService.resetRoom(r.id));
      _scheduleAiIfNeeded();
    } catch (e) {
      undoMessage = '再来一局失败：${_friendlyError(e)}';
      notifyListeners();
    }
  }

  // ---------- 离开 ----------

  Future<void> leave() async {
    final r = room;
    _heartbeat?.cancel();
    _heartbeat = null;
    _countdown?.cancel();
    _countdown = null;
    remaining = null;
    await _unsubscribe();
    if (r != null) {
      try {
        await RoomService.leaveRoom(r.id);
      } catch (_) {}
    }
    await RoomPrefs.clear();
    room = null;
    messages = [];
    _lastReadCount = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _countdown?.cancel();
    _countdown = null;
    _unsubscribe();
    super.dispose();
  }
}
