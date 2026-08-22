import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:three_gomoku/services/stats_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('胜局累加场次与胜场，并更新连胜', () async {
    await StatsService.record(win: true, draw: false);
    await StatsService.record(win: true, draw: false);
    final s = await StatsService.load();
    expect(s.games, 2);
    expect(s.wins, 2);
    expect(s.losses, 0);
    expect(s.draws, 0);
    expect(s.winStreak, 2);
    expect(s.lossStreak, 0);
  });

  test('负局重置连胜并累加连负', () async {
    await StatsService.record(win: true, draw: false);
    await StatsService.record(win: false, draw: false);
    await StatsService.record(win: false, draw: false);
    final s = await StatsService.load();
    expect(s.games, 3);
    expect(s.wins, 1);
    expect(s.losses, 2);
    expect(s.winStreak, 0);
    expect(s.lossStreak, 2);
  });

  test('和棋不动连胜连负', () async {
    await StatsService.record(win: true, draw: false);
    await StatsService.record(win: false, draw: true);
    final s = await StatsService.load();
    expect(s.games, 2);
    expect(s.wins, 1);
    expect(s.draws, 1);
    expect(s.winStreak, 1);
    expect(s.lossStreak, 0);
  });

  test('清零清空全部战绩', () async {
    await StatsService.record(win: true, draw: false);
    await StatsService.reset();
    final s = await StatsService.load();
    expect(s.games, 0);
    expect(s.wins, 0);
    expect(s.draws, 0);
    expect(s.winStreak, 0);
    expect(s.lossStreak, 0);
  });
}
