class Player {
  final int slot;
  final String? name;
  final bool isAi;
  final String? uid;
  final bool connected;
  final DateTime? lastSeen;
  final bool takenOver;

  const Player({
    required this.slot,
    this.name,
    this.isAi = false,
    this.uid,
    this.connected = false,
    this.lastSeen,
    this.takenOver = false,
  });

  bool get isEmpty => !isAi && uid == null;

  String get displayName => name ?? '空位';

  factory Player.fromJson(Map<String, dynamic> j) => Player(
        slot: j['slot'] as int? ?? 0,
        name: j['name'] as String?,
        isAi: j['is_ai'] as bool? ?? false,
        uid: j['uid'] as String?,
        connected: j['connected'] as bool? ?? false,
        lastSeen: j['last_seen'] is String
            ? DateTime.tryParse((j['last_seen'] as String).replaceFirst(' ', 'T'))
            : null,
        takenOver: j['taken_over'] as bool? ?? false,
      );
}
