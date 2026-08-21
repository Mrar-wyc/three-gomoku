import 'package:shared_preferences/shared_preferences.dart';

class Stats {
  final int games;
  final int wins;
  final int draws;

  const Stats({this.games = 0, this.wins = 0, this.draws = 0});

  int get losses => games - wins - draws;
}

/// 联机战绩（本机记录）。
class StatsService {
  static const _gamesKey = 'stat_games';
  static const _winsKey = 'stat_wins';
  static const _drawsKey = 'stat_draws';

  static Future<Stats> load() async {
    final p = await SharedPreferences.getInstance();
    return Stats(
      games: p.getInt(_gamesKey) ?? 0,
      wins: p.getInt(_winsKey) ?? 0,
      draws: p.getInt(_drawsKey) ?? 0,
    );
  }

  /// 记录一局结果（负场由 games − wins − draws 推算，无需单独存储）。
  static Future<void> record({required bool win, required bool draw}) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_gamesKey, (p.getInt(_gamesKey) ?? 0) + 1);
    if (win) {
      await p.setInt(_winsKey, (p.getInt(_winsKey) ?? 0) + 1);
    }
    if (draw) {
      await p.setInt(_drawsKey, (p.getInt(_drawsKey) ?? 0) + 1);
    }
  }
}
