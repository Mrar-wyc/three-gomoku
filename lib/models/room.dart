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
  final String aiDifficulty; // easy / medium

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
  });

  bool get isPlaying => status == 'playing';
  bool get isFinished => status == 'finished';
  bool get isDraw => isFinished && winner == null;
  bool get isBoardFull => !board.contains(GameLogic.empty);

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
    );
  }
}
