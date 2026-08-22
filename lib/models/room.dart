import '../core/game_logic.dart';
import 'player.dart';

class Room {
  final String id;
  final String code;
  final String hostId;
  final List<Player> players; // 固定 3 个座位
  final List<int> board; // 长度 361
  final int turn; // 当前回合座位 0/1/2，-1 表示已结束
  final String status; // waiting / playing / finished
  final int? winner; // 胜者座位 0/1/2；null = 未定或和棋
  final String aiDifficulty; // easy / medium / hard
  final int? turnTimeoutSec; // 每步限时秒数；null = 不限时
  final DateTime? moveDeadline; // 当前回合截止时间；null = 不适用
  final int? lastMoveSlot; // 最后一步的座位（悔棋按钮可见性）
  final int? undoSenderSlot; // 待同意悔棋的发起座位
  final List<String> undoAccepts; // 已同意悔棋的成员 uid
  final DateTime? undoExpiresAt; // 同意期限

  const Room({
    required this.id,
    required this.code,
    required this.hostId,
    required this.players,
    required this.board,
    required this.turn,
    required this.status,
    this.winner,
    this.aiDifficulty = 'medium',
    this.turnTimeoutSec,
    this.moveDeadline,
    this.lastMoveSlot,
    this.undoSenderSlot,
    this.undoAccepts = const [],
    this.undoExpiresAt,
  });

  bool get isPlaying => status == 'playing';
  bool get isFinished => status == 'finished';
  bool get isDraw => isFinished && winner == null;
  bool get isBoardFull => !board.contains(GameLogic.empty);
  bool get undoPending => undoSenderSlot != null;

  factory Room.fromJson(Map<String, dynamic> j) {
    final playersRaw = (j['players'] as List? ?? const []);
    final players = playersRaw
        .map((e) => Player.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    while (players.length < 3) {
      players.add(Player(slot: players.length));
    }

    final boardStr = j['board'] as String? ?? '';
    final board = boardStr.isEmpty
        ? GameLogic.newBoard()
        : GameLogic.boardFromString(boardStr);

    return Room(
      id: j['id'] as String,
      code: j['code'] as String,
      hostId: j['host_id'] as String,
      players: players,
      board: board,
      turn: j['turn'] as int? ?? 0,
      status: j['status'] as String? ?? 'waiting',
      winner: j['winner'] as int?,
      aiDifficulty: j['ai_difficulty'] as String? ?? 'medium',
      turnTimeoutSec: j['turn_timeout_sec'] as int?,
      moveDeadline: _parseTs(j['move_deadline']),
      lastMoveSlot: j['last_move_slot'] as int?,
      undoSenderSlot: j['undo_slot'] as int?,
      undoAccepts: (j['undo_accepts'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      undoExpiresAt: _parseTs(j['undo_expires_at']),
    );
  }

  static DateTime? _parseTs(dynamic v) {
    if (v is! String) return null;
    try {
      // Postgres 返回 "2025-01-01 12:00:00+00"，需补 T 才能被 DateTime.parse 接受
      return DateTime.parse(v.replaceFirst(' ', 'T'));
    } catch (_) {
      return null;
    }
  }
}
