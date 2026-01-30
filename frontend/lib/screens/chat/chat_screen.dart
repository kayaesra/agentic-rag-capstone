import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/quick_reply_buttons.dart';
import 'package:flutter/rendering.dart';
import 'dart:io';

class ChatScreen extends StatefulWidget {
  final int userId;
  final int sessionId;
  const ChatScreen({super.key, required this.userId, required this.sessionId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;
  bool _historyLoaded = false;
  final ScrollController _scrollController = ScrollController();

  final List<String> _quickReplies = [
    'Günlük kalori ihtiyacım nedir?',
    'Su tüketimimi nasıl artırabilirim?',
    'Protein açısından zengin besinler nelerdir?',
    'Sağlıklı atıştırmalık önerileri',
  ];

  @override
  void initState() {
    super.initState();
    fetchHistory();
  }

  Future<void> fetchHistory() async {
    setState(() => _isLoading = true);
    final res = await http.get(Uri.parse(Platform.isAndroid
        ? 'http://10.0.2.2:8000/api/v1/chat/history/${widget.sessionId}'
        : 'http://localhost:8000/api/v1/chat/history/${widget.sessionId}'));
    if (res.statusCode == 200) {
      final data = json.decode(res.body) as List;
      setState(() {
        _messages.clear();
        for (final msg in data) {
          _messages.add({'role': msg['role'], 'text': msg['text']});
        }
        _historyLoaded = true;
        _isLoading = false;
      });
      _scrollToBottom();
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asistan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: fetchHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return MessageBubble(
                  message: message['text'],
                  isUser: message['role'] == 'user',
                ).animate().fadeIn().slideX();
              },
            ),
          ),
          if (_messages.isEmpty && !_isLoading)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.chat_bubble_outline,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Merhaba! Size nasıl yardımcı olabilirim?',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 24),
                  QuickReplyButtons(
                    replies: _quickReplies,
                    onTap: (reply) {
                      _controller.text = reply;
                      sendMessage(reply);
                    },
                  ),
                ],
              ),
            ),
          if (_isLoading) const LinearProgressIndicator(),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Mesajınızı yazın...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                      ),
                      maxLines: null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            final text = _controller.text.trim();
                            if (text.isNotEmpty) {
                              sendMessage(text);
                              _controller.clear();
                            }
                          },
                    child: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> sendMessage(String message) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _messages.add({
        'role': 'user',
        'text': message,
        'timestamp': DateTime.now(),
      });
    });

    try {
      final response = await http.post(
        Uri.parse(Platform.isAndroid
            ? 'http://10.0.2.2:8000/api/v1/chat'
            : 'http://localhost:8000/api/v1/chat'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'session_id': widget.sessionId,
          'user_id': widget.userId,
          'message': message,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (!mounted) return;
        setState(() {
          _messages.add({
            'role': 'bot',
            'text': data['response'],
            'timestamp': DateTime.now(),
          });
        });
      } else {
        throw Exception('Failed to send message');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error:  ${e.toString()}')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }
} 