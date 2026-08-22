import 'package:shared_preferences/shared_preferences.dart';

class Stats {
  final int games;
  final int wins;
  final int draws;
  final int winStreak;
  final int lossStreak;

  const Stats({
    this.games = 0,
    this.wins = 0,
    this.draws = 0,
    this.winStreak = 0,
    this.lossStreak = 0,
  });

  int get losses => games - wins - draws;
  double get winRate => games == 0 ? 0 : wins / games;
}

/// 联机战绩（本机记录）。
class StatsService {
  static const _gamesKey = 'stat_games';
  static const _winsKey = 'stat_wins';
  static const _drawsKey = 'stat_draws';
  static const _winStreakKey = 'stat_win_streak';
  static const _lossStreakKey = 'stat_loss_streak';

  static Future<Stats> load() async {
    final p = await SharedPreferences.getInstance();
    return Stats(
      games: p.getInt(_gamesKey) ?? 0,
      wins: p.getInt(_winsKey) ?? 0,
      draws: p.getInt(_drawsKey) ?? 0,
      winStreak: p.getInt(_winStreakKey) ?? 0,
      lossStreak: p.getInt(_lossStreakKey) ?? 0,
    );
  }

  /// 记录一局结果（负场由 games − wins − draws 推算；和棋不动连胜/连负）。
  static Future<void> record({required bool win, required bool draw}) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_gamesKey, (p.getInt(_gamesKey) ?? 0) + 1);
    if (win) {
      await p.setInt(_winsKey, (p.getInt(_winsKey) ?? 0) + 1);
      await p.setInt(_winStreakKey, (p.getInt(_winStreakKey) ?? 0) + 1);
      await p.setInt(_lossStreakKey, 0);
    } else if (draw) {
      await p.setInt(_drawsKey, (p.getInt(_drawsKey) ?? 0) + 1);
    } else {
      await p.setInt(_lossStreakKey, (p.getInt(_lossStreakKey) ?? 0) + 1);
      await p.setInt(_winStreakKey, 0);
    }
  }

  /// 清零全部战绩。
  static Future<void> reset() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_gamesKey);
    await p.remove(_winsKey);
    await p.remove(_drawsKey);
    await p.remove(_winStreakKey);
    await p.remove(_lossStreakKey);
  }
}
