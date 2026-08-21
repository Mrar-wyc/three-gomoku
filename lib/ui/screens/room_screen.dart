import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../models/room.dart';
import '../../state/room_controller.dart';
import '../widgets/board_widget.dart';
import '../widgets/player_bar.dart';

class RoomScreen extends StatefulWidget {
  final RoomController controller;

  const RoomScreen({super.key, required this.controller});

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> with WidgetsBindingObserver {
  RoomController get c => widget.controller;
  bool _prevFinished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.leave();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      c.ping();
    }
  }

  String _resultText(Room room) {
    if (room.isDraw) {
      return room.isBoardFull ? '满盘和棋（并列最长）' : '和棋！';
    }
    final name = GomokuPalette.name[room.winner! + 1];
    return room.isBoardFull ? '满盘判胜 · $name（最长连子）' : '$name 获胜！';
  }

  void _checkResult(Room? room) {
    final finished = room != null && room.isFinished;
    if (finished && !_prevFinished) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showResult(room));
    }
    _prevFinished = finished;
  }

  Future<void> _showResult(Room room) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_resultText(room)),
        content: const Text('本局结束'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              c.rematch();
            },
            child: const Text('再来一局'),
          ),
        ],
      ),
    );
  }

  Future<void> _back() async {
    final room = c.room;
    if (room != null && room.isFinished) {
      Navigator.of(context).pop();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('离开房间？'),
        content: const Text('离开后，对局中的座位将由 AI 托管。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('离开')),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final room = c.room;
        _checkResult(room);
        return Scaffold(
          appBar: AppBar(
            title: Text(room == null ? '房间' : '房间 ${room.code}'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _back,
            ),
          ),
          body: _buildBody(room),
        );
      },
    );
  }

  Widget _buildBody(Room? room) {
    if (c.loading && room == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (room == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '出错了：${c.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
          ],
        ),
      );
    }
    if (room.isPlaying || room.isFinished) return _buildGame(room);
    return _buildLobby(room);
  }

  Widget _buildLobby(Room room) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Text('房间号', style: TextStyle(fontSize: 14, color: Colors.black54)),
          const SizedBox(height: 8),
          Text(
            room.code,
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              letterSpacing: 6,
            ),
          ),
          const SizedBox(height: 8),
          const Text('把房间号发给另外两位朋友，输入即可加入', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          PlayerBar(players: _info(room)),
          const SizedBox(height: 24),
          const Text(
            '凑满 3 个座位后自动开局',
            style: TextStyle(color: Colors.black45),
          ),
        ],
      ),
    );
  }

  Widget _buildGame(Room room) {
    return Column(
      children: [
        PlayerBar(players: _info(room)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: BoardWidget(
              board: room.board,
              lastIndex: c.lastIndex,
              onTap: c.submitMove,
              enabled: c.isMyTurn,
            ),
          ),
        ),
        _statusLine(room),
      ],
    );
  }

  Widget _statusLine(Room room) {
    String text;
    if (room.isFinished) {
      text = _resultText(room);
    } else if (room.turn < 0 || room.turn > 2) {
      text = '等待中…';
    } else {
      final cur = room.players[room.turn];
      if (c.mySlot == room.turn) {
        text = '轮到你了，点击棋盘落子';
      } else if (cur.isAi) {
        text = 'AI 思考中…';
      } else {
        text = '等待 ${cur.displayName} 落子';
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          if (room.isFinished)
            FilledButton.tonal(
              onPressed: c.rematch,
              child: const Text('再来一局'),
            ),
        ],
      ),
    );
  }

  List<PlayerInfo> _info(Room room) {
    final now = DateTime.now();
    return room.players.map((p) {
      final stone = p.slot + 1;
      final String label;
      if (p.isAi) {
        label = p.takenOver ? 'AI托管' : 'AI';
      } else if (p.isEmpty) {
        label = '待加入';
      } else if (p.lastSeen != null &&
          now.difference(p.lastSeen!) < const Duration(seconds: 30)) {
        label = '在线';
      } else {
        label = '离线';
      }
      return PlayerInfo(
        name: p.isEmpty ? '空位' : p.displayName,
        stone: stone,
        isTurn: room.turn == p.slot,
        statusLabel: label,
      );
    }).toList();
  }
}
