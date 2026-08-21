import 'package:flutter/material.dart';

import 'ui/screens/home_screen.dart';

class GomokuApp extends StatelessWidget {
  const GomokuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '三人五子棋',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8D6E63)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
