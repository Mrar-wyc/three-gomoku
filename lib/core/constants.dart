import 'package:flutter/material.dart';

/// 三位玩家的颜色与名称。
/// 棋盘取值：0=空，1=黑，2=白，3=红（对应座位 0/1/2）。
class GomokuPalette {
  static const List<Color> stone = [
    Colors.transparent,
    Color(0xFF1A1A1A), // 1 黑
    Color(0xFFF7F7F7), // 2 白
    Color(0xFFE53935), // 3 红
  ];

  static const List<String> name = ['', '黑方', '白方', '红方'];

  static const Color boardBg = Color(0xFFE0B684);
  static const Color gridLine = Color(0xFF5D4037);
}
