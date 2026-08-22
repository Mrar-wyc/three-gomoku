import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/game_logic.dart';

class BoardWidget extends StatefulWidget {
  final List<int> board;
  final int? lastIndex;
  final void Function(int row, int col)? onTap;
  final bool enabled;
  final Set<int> highlight; // 制胜连线高亮格子

  const BoardWidget({
    super.key,
    required this.board,
    this.lastIndex,
    this.onTap,
    this.enabled = true,
    this.highlight = const {},
  });

  @override
  State<BoardWidget> createState() => _BoardWidgetState();
}

class _BoardWidgetState extends State<BoardWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  int? _seenIndex;

  @override
  void didUpdateWidget(covariant BoardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lastIndex != null && widget.lastIndex != _seenIndex) {
      _seenIndex = widget.lastIndex;
      _anim.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth;
          return GestureDetector(
            onTapUp: (widget.enabled && widget.onTap != null)
                ? (d) {
                    final p = _nearest(d.localPosition, size);
                    if (p != null) widget.onTap!(p.$1, p.$2);
                  }
                : null,
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, _) => CustomPaint(
                painter: BoardPainter(
                  board: widget.board,
                  lastIndex: widget.lastIndex,
                  anim: _anim.value,
                  highlight: widget.highlight,
                ),
                size: Size(size, size),
              ),
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
  final double anim;
  final Set<int> highlight;

  BoardPainter({
    required this.board,
    this.lastIndex,
    this.anim = 1,
    this.highlight = const {},
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = GameLogic.size;
    final cell = size.width / (n + 1);
    final boardRect = Rect.fromLTWH(
      cell * 0.5,
      cell * 0.5,
      size.width - cell,
      size.width - cell,
    );

    // 木纹渐变背景
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF0DCB4), Color(0xFFD8B17D)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    // 棋盘边框
    final frame = Paint()
      ..color = const Color(0xFF5D4037)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    canvas.drawRect(boardRect, frame);

    // 网格
    final grid = Paint()
      ..color = const Color(0xFF6D4C41)
      ..strokeWidth = 1.1;
    for (int i = 0; i < n; i++) {
      final a = cell * (i + 1);
      canvas.drawLine(Offset(cell, a), Offset(size.width - cell, a), grid);
      canvas.drawLine(Offset(a, cell), Offset(a, size.width - cell), grid);
    }

    // 星位
    final star = Paint()..color = const Color(0xFF4E342E);
    const stars = [
      [3, 3], [3, 9], [3, 15],
      [9, 3], [9, 9], [9, 15],
      [15, 3], [15, 9], [15, 15],
    ];
    for (final s in stars) {
      canvas.drawCircle(
        Offset(cell * (s[1] + 1), cell * (s[0] + 1)),
        3.2,
        star,
      );
    }

    // 棋子
    for (int idx = 0; idx < board.length; idx++) {
      final v = board[idx];
      if (v == 0) continue;
      final r = idx ~/ n;
      final c = idx % n;
      final center = Offset(cell * (c + 1), cell * (r + 1));
      final isLast = idx == lastIndex;
      final double scale = isLast
          ? 0.2 + 0.8 * Curves.easeOutBack.transform(anim)
          : 1.0;
      final radius = cell * 0.42 * scale;

      // 阴影
      canvas.drawCircle(
        center + const Offset(1.2, 1.6),
        radius,
        Paint()..color = Colors.black.withValues(alpha: 0.25),
      );

      // 径向高光棋子
      final base = GomokuPalette.stone[v];
      final light = v == 1
          ? const Color(0xFF4A4A4A)
          : (v == 2 ? Colors.white : const Color(0xFFFF7A70));
      final stoneRect = Rect.fromCircle(center: center, radius: radius);
      final shade = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 0.9,
          colors: [light, base],
        ).createShader(stoneRect);
      canvas.drawCircle(center, radius, shade);

      if (v == 2) {
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..color = Colors.black26
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }

      // 最后一手标记
      if (isLast) {
        canvas.drawCircle(
          center,
          radius * 0.3,
          Paint()..color = Colors.redAccent,
        );
      }

      // 制胜连线高亮
      if (highlight.contains(idx)) {
        canvas.drawCircle(
          center,
          radius * 1.18,
          Paint()
            ..color = const Color(0xFFFF6F00)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) => true;
}
