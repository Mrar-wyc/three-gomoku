import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/game_logic.dart';
import '../../services/moves_service.dart';
import '../widgets/board_widget.dart';

/// 联机对局复盘：回放落子历史（上一步/下一步/自动播放/拖动）。
class ReplayScreen extends StatefulWidget {
  final String roomId;

  const ReplayScreen({super.key, required this.roomId});

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  List<MoveRecord> _moves = [];
  bool _loading = true;
  String? _error;
  int _step = 0;
  Timer? _auto;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await MovesService.fetch(widget.roomId);
      if (!mounted) return;
      setState(() {
        _moves = m;
        _step = m.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<int> _boardAt(int step) {
    final b = GameLogic.newBoard();
    for (int i = 0; i < step && i < _moves.length; i++) {
      b[_moves[i].idx] = _moves[i].slot + 1;
    }
    return b;
  }

  void _toggleAuto() {
    if (_playing) {
      _auto?.cancel();
      setState(() => _playing = false);
    } else {
      setState(() => _playing = true);
      _auto = Timer.periodic(const Duration(milliseconds: 600), (_) {
        if (!mounted) return;
        if (_step >= _moves.length) {
          _auto?.cancel();
          setState(() => _playing = false);
          return;
        }
        setState(() => _step++);
      });
    }
  }

  @override
  void dispose() {
    _auto?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('复盘'), centerTitle: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('加载失败：$_error'))
              : _moves.isEmpty
                  ? const Center(child: Text('本局没有落子记录'))
                  : _build(),
    );
  }

  Widget _build() {
    final board = _boardAt(_step);
    final n = _moves.length;
    final lastIdx = _step > 0 ? _moves[_step - 1].idx : null;
    final slot = _step > 0 ? _moves[_step - 1].slot : null;

    // 终局制胜高亮
    Set<int> highlight = {};
    if (_step == n && lastIdx != null) {
      final w = GameLogic.winnerAfterMove(
          board, GameLogic.rowOf(lastIdx), GameLogic.colOf(lastIdx));
      if (w != null) {
        highlight = GameLogic.winningLineCells(board, lastIdx).toSet();
      } else if (GameLogic.isFull(board)) {
        final w2 = GameLogic.winnerByLongestLine(board);
        if (w2 != null) {
          highlight = GameLogic.longestLineCells(board, w2 + 1).toSet();
        }
      }
    }

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: BoardWidget(
              board: board,
              lastIndex: lastIdx,
              highlight: highlight,
              enabled: false,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            slot == null
                ? '起始局面'
                : '第 $_step / $n 手 · ${GomokuPalette.name[slot + 1]}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        Slider(
          value: _step.toDouble(),
          max: n.toDouble(),
          divisions: n < 1 ? 1 : n,
          label: '$_step',
          onChanged: (v) => setState(() => _step = v.round()),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.skip_previous),
              tooltip: '上一步',
              onPressed: _step > 0 ? () => setState(() => _step--) : null,
            ),
            IconButton(
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
              tooltip: _playing ? '暂停' : '自动播放',
              onPressed: _toggleAuto,
            ),
            IconButton(
              icon: const Icon(Icons.skip_next),
              tooltip: '下一步',
              onPressed: _step < n ? () => setState(() => _step++) : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
