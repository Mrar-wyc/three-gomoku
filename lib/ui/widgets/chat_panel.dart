import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../models/chat_message.dart';
import '../../state/room_controller.dart';

/// 房间聊天面板（底部弹层）：消息列表 + 输入框。
class ChatPanel extends StatefulWidget {
  final RoomController controller;

  const ChatPanel({super.key, required this.controller});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  RoomController get c => widget.controller;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await c.sendChat(body);
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      _input.clear();
      _scrollToBottom();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('发送失败（请确认仍在房间内）')),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text('房间聊天', style: Theme.of(context).textTheme.titleMedium),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: c,
              builder: (context, _) {
                final msgs = c.messages;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scroll.hasClients) {
                    _scroll.jumpTo(_scroll.position.maxScrollExtent);
                  }
                });
                if (msgs.isEmpty) {
                  return const Center(
                    child: Text(
                      '还没有消息，说点什么吧',
                      style: TextStyle(color: Colors.black38),
                    ),
                  );
                }
                final me = c.mySlot;
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: msgs.length,
                  itemBuilder: (context, i) => _bubble(msgs[i], me),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      maxLength: 200,
                      decoration: const InputDecoration(
                        hintText: '说点什么…（最多 200 字）',
                        isDense: true,
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.send),
                    onPressed: _sending ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(ChatMessage m, int meSlot) {
    final mine = m.senderSlot == meSlot;
    final color = GomokuPalette.stone[m.senderSlot + 1];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine) ...[
            _avatar(color, m.senderName),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  m.senderName,
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: mine ? const Color(0xFFE8F5E9) : const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(m.body),
                ),
              ],
            ),
          ),
          if (mine) ...[
            const SizedBox(width: 8),
            _avatar(color, m.senderName),
          ],
        ],
      ),
    );
  }

  Widget _avatar(Color color, String name) {
    final dark = color.computeLuminance() < 0.5;
    return CircleAvatar(
      radius: 12,
      backgroundColor: color,
      child: Text(
        name.isEmpty ? '?' : name.characters.first,
        style: TextStyle(
          fontSize: 11,
          color: dark ? Colors.white : Colors.black87,
        ),
      ),
    );
  }
}
