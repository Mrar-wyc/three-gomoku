import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/ai.dart';
import '../core/game_logic.dart';
import '../models/room.dart';
import '../services/room_service.dart';
import '../services/supabase_service.dart';

class RoomController extends ChangeNotifier {
  Room? room;
  bool loading = false;
  String? error;
  String? myUid;
  RealtimeChannel? _channel;
  String? _lastAiKey;

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

  Future<bool> create(String name, int aiCount) => _run(() async {
        myUid = await SupabaseService.ensureSignedIn();
        room = await RoomService.createRoom(name, aiCount);
        await _subscribe();
        _scheduleAiIfNeeded();
      });

  Future<bool> join(String code, String name) => _run(() async {
        myUid = await SupabaseService.ensureSignedIn();
        room = await RoomService.joinRoom(code, name);
        await _subscribe();
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
        room = Room.fromJson(Map<String, dynamic>.from(rec));
        notifyListeners();
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

  Future<void> submitMove(int row, int col) async {
    final r = room;
    if (r == null) return;
    final slot = mySlot;
    if (slot < 0) return;
    if (r.turn != slot || r.players[slot].isAi) return;
    final idx = GameLogic.indexOf(row, col);
    if (r.board[idx] != GameLogic.empty) return;
    try {
      room = await RoomService.submitMove(r.id, slot, row, col);
      notifyListeners();
      _scheduleAiIfNeeded();
    } catch (_) {
      // 失败时 Realtime 会用服务端权威状态纠正。
    }
  }

  /// AI 座位轮到时，由任意在线成员计算并代下（AI 是确定性算法，结果一致；
  /// 服务端 RPC 会校验 turn，重复提交最多被拒绝一次）。
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
      final idx = GomokuAI.bestMove(cur.board, slot + 1);
      try {
        room = await RoomService.submitMove(
          cur.id,
          slot,
          GameLogic.rowOf(idx),
          GameLogic.colOf(idx),
        );
        notifyListeners();
        _scheduleAiIfNeeded();
      } catch (_) {}
    });
  }

  Future<void> leave() async {
    final r = room;
    await _unsubscribe();
    if (r != null) {
      try {
        await RoomService.leaveRoom(r.id);
      } catch (_) {}
    }
    room = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }
}
