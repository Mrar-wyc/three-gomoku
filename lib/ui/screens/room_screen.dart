import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../core/game_logic.dart';
import '../../models/room.dart';
import '../../state/room_controller.dart';
import 'replay_screen.dart';
import '../widgets/board_widget.dart';
import '../widgets/chat_panel.dart';
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
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ReplayScreen(roomId: room.id)),
              );
            },
            child: const Text('复盘'),
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

  bool _prevUndoVoteShown = false;

  /// pending 升起且我是投票者 → 弹同意窗（只弹一次）。
  void _checkUndo() {
    final voteNeeded = c.iAmUndoVoter;
    if (voteNeeded && !_prevUndoVoteShown) {
      _prevUndoVoteShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && c.iAmUndoVoter) _showUndoDialog();
      });
    }
    if (!voteNeeded) _prevUndoVoteShown = false;
  }

  Future<void> _showUndoDialog() async {
    final r = c.room;
    if (r == null || !mounted) return;
    final requester = (r.undoSenderSlot != null && r.undoSenderSlot! >= 0 && r.undoSenderSlot! <= 2)
        ? r.players[r.undoSenderSlot!].displayName
        : '某玩家';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('悔棋请求'),
        content: Text('「$requester」想悔棋（撤销他刚下的最后一步），是否同意？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('拒绝')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('同意')),
        ],
      ),
    );
    if (ok == null || !mounted) return;
    await c.respondUndo(ok);
  }

  /// pending 横幅：发起者显示等待+取消；投票者/其他显示提示。
  Widget _undoBanner() {
    final r = c.room;
    final requester = (r != null && r.undoSenderSlot != null && r.undoSenderSlot! >= 0 && r.undoSenderSlot! <= 2)
        ? r.players[r.undoSenderSlot!].displayName
        : '某玩家';
    final String text;
    if (c.iAmUndoRequester) {
      text = '等待其他玩家同意悔棋…（30 秒内有效）';
    } else if (c.iAmUndoVoter) {
      text = '$requester 请求悔棋，请选择同意或拒绝';
    } else {
      text = '$requester 请求悔棋（等待投票）';
    }
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF8E1),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.history, size: 16, color: Colors.orange),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13)),
          ),
          if (c.iAmUndoRequester)
            TextButton(onPressed: c.cancelUndo, child: const Text('取消')),
        ],
      ),
    );
  }

  void _openChat() {
    c.markChatRead();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChatPanel(controller: c),
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
        _checkUndo();
        final msg = c.timeoutMessage ?? c.undoMessage;
        if (msg != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || (c.timeoutMessage == null && c.undoMessage == null)) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
            c.clearTimeoutMessage();
            c.clearUndoMessage();
          });
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(room == null ? '房间' : '房间 ${room.code}'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _back,
            ),
            actions: [
              IconButton(
                icon: Badge.count(
                  count: c.unreadChatCount,
                  isLabelVisible: c.unreadChatCount > 0,
                  child: const Icon(Icons.chat_bubble_outline),
                ),
                tooltip: '房间聊天',
                onPressed: _openChat,
              ),
            ],
          ),
          body: Column(
            children: [
              if (c.undoPending) _undoBanner(),
              Expanded(child: _buildBody(room)),
            ],
          ),
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
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制房间号'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: room.code));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('房间号已复制，去微信发给朋友吧')),
              );
            },
          ),
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
              highlight: _winHighlight(room),
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
          if (c.canRequestUndo)
            TextButton.icon(
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('悔棋'),
              onPressed: c.requestUndo,
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

  /// 终局制胜连线高亮（5 连胜或满盘最长连子）。
  Set<int> _winHighlight(Room room) {
    if (!room.isFinished || room.winner == null) return {};
    final lastIdx = c.lastIndex;
    if (lastIdx != null) {
      final w = GameLogic.winnerAfterMove(
          room.board, GameLogic.rowOf(lastIdx), GameLogic.colOf(lastIdx));
      if (w != null) {
        return GameLogic.winningLineCells(room.board, lastIdx).toSet();
      }
    }
    if (room.isBoardFull) {
      return GameLogic.longestLineCells(room.board, room.winner! + 1).toSet();
    }
    return {};
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
        remaining: (!p.isAi && room.turn == p.slot) ? c.remaining : null,
      );
    }).toList();
  }
}
