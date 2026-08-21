import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/ai.dart';
import '../core/game_logic.dart';
import '../models/room.dart';
import '../services/room_prefs.dart';
import '../services/room_service.dart';
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

  Future<bool> create(String name, int aiCount, {String difficulty = 'medium'}) =>
      _run(() async {
        myUid = await SupabaseService.ensureSignedIn();
        myName = name;
        room = await RoomService.createRoom(name, aiCount, difficulty: difficulty);
        await RoomPrefs.save(room!.code, name);
        await _subscribe();
        _startHeartbeat();
        _scheduleAiIfNeeded();
      });

  Future<bool> join(String code, String name) => _run(() async {
        myUid = await SupabaseService.ensureSignedIn();
        myName = name;
        room = await RoomService.joinRoom(code, name);
        await RoomPrefs.save(room!.code, name);
        await _subscribe();
        _startHeartbeat();
        _scheduleAiIfNeeded();
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
        unawaited(SystemSound.play(SystemSoundType.click));
        unawaited(HapticFeedback.lightImpact());
      }
    }
    notifyListeners();
  }

  int? _findNewStone(List<int> oldBoard, List<int> newBoard) {
    for (int i = 0; i < oldBoard.length && i < newBoard.length; i++) {
      if (oldBoard[i] == GameLogic.empty && newBoard[i] != GameLogic.empty) {
        return i;
      }
    }
    return null;
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
    } catch (_) {
      // 失败时 Realtime 会用服务端权威状态纠正。
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
      final idx = GomokuAI.bestMove(cur.board, slot + 1, difficulty: cur.aiDifficulty);
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
    } catch (_) {}
  }

  // ---------- 离开 ----------

  Future<void> leave() async {
    final r = room;
    _heartbeat?.cancel();
    _heartbeat = null;
    await _unsubscribe();
    if (r != null) {
      try {
        await RoomService.leaveRoom(r.id);
      } catch (_) {}
    }
    await RoomPrefs.clear();
    room = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _unsubscribe();
    super.dispose();
  }
}
