import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/game_logic.dart';

class BoardWidget extends StatelessWidget {
  final List<int> board;
  final int? lastIndex;
  final void Function(int row, int col)? onTap;
  final bool enabled;

  const BoardWidget({
    super.key,
    required this.board,
    this.lastIndex,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth;
          return GestureDetector(
            onTapUp: (enabled && onTap != null)
                ? (d) {
                    final p = _nearest(d.localPosition, size);
                    if (p != null) onTap!(p.$1, p.$2);
                  }
                : null,
            child: CustomPaint(
              painter: BoardPainter(board: board, lastIndex: lastIndex),
              size: Size(size, size),
            ),
          );
        },
      ),
    );
  }

  (int, int)? _nearest(Offset pos, double size) {
    final n = GameLogic.size;
    final cell = size / (n + 1);
    final col = (pos.dx / cell).round() - 1;
    final row = (pos.dy / cell).round() - 1;
    if (row < 0 || row >= n || col < 0 || col >= n) return null;
    return (row, col);
  }
}

class BoardPainter extends CustomPainter {
  final List<int> board;
  final int? lastIndex;

  BoardPainter({required this.board, this.lastIndex});

  @override
  void paint(Canvas canvas, Size size) {
    final n = GameLogic.size;
    final cell = size.width / (n + 1);

    canvas.drawRect(Offset.zero & size, Paint()..color = GomokuPalette.boardBg);

    final grid = Paint()
      ..color = GomokuPalette.gridLine
      ..strokeWidth = 1;
    for (int i = 0; i < n; i++) {
      final a = cell * (i + 1);
      canvas.drawLine(Offset(cell, a), Offset(size.width - cell, a), grid);
      canvas.drawLine(Offset(a, cell), Offset(a, size.width - cell), grid);
    }

    final star = Paint()..color = const Color(0xFF3E2723);
    const stars = [
      [3, 3], [3, 9], [3, 15],
      [9, 3], [9, 9], [9, 15],
      [15, 3], [15, 9], [15, 15],
    ];
    for (final s in stars) {
      canvas.drawCircle(
        Offset(cell * (s[1] + 1), cell * (s[0] + 1)),
        3.0,
        star,
      );
    }

    for (int idx = 0; idx < board.length; idx++) {
      final v = board[idx];
      if (v == 0) continue;
      final r = idx ~/ n;
      final c = idx % n;
      final center = Offset(cell * (c + 1), cell * (r + 1));
      final radius = cell * 0.42;

      canvas.drawCircle(
        center + const Offset(1, 1),
        radius,
        Paint()..color = Colors.black26,
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = GomokuPalette.stone[v],
      );
      if (v == 2) {
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..color = Colors.black
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
      if (idx == lastIndex) {
        canvas.drawCircle(
          center,
          radius * 0.32,
          Paint()..color = Colors.redAccent,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) => true;
}
