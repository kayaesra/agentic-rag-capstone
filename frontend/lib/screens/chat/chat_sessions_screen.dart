import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'chat_screen.dart';
import 'dart:io';

class ChatSessionsScreen extends StatefulWidget {
  final int userId;
  const ChatSessionsScreen({super.key, required this.userId});

  @override
  State<ChatSessionsScreen> createState() => _ChatSessionsScreenState();
}

class _ChatSessionsScreenState extends State<ChatSessionsScreen> {
  List<Map<String, dynamic>> sessions = [];

  @override
  void initState() {
    super.initState();
    fetchSessions();
  }

  Future<void> fetchSessions() async {
    final res = await http.get(Uri.parse(Platform.isAndroid
        ? 'http://10.0.2.2:8000/api/v1/chat/sessions/${widget.userId}'
        : 'http://localhost:8000/api/v1/chat/sessions/${widget.userId}'));
    if (res.statusCode == 200) {
      setState(() {
        sessions = List<Map<String, dynamic>>.from(json.decode(res.body));
      });
    }
  }

  Future<void> createNewSession() async {
    final res = await http.post(
      Uri.parse(Platform.isAndroid
          ? 'http://10.0.2.2:8000/api/v1/chat/session?user_id=${widget.userId}'
          : 'http://localhost:8000/api/v1/chat/session?user_id=${widget.userId}'),
    );
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(userId: widget.userId, sessionId: data['session_id']),
        ),
      );
    }
  }

  Future<void> deleteSession(int sessionId) async {
    final res = await http.delete(
      Uri.parse(Platform.isAndroid
          ? 'http://10.0.2.2:8000/api/v1/chat/session/$sessionId'
          : 'http://localhost:8000/api/v1/chat/session/$sessionId'),
    );
    if (res.statusCode == 200) {
      setState(() {
        sessions.removeWhere((s) => s['session_id'] == sessionId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sohbet silindi')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sohbet silinemedi')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sohbetlerim')),
      floatingActionButton: FloatingActionButton(
        onPressed: createNewSession,
        child: const Icon(Icons.add),
        tooltip: 'Yeni Sohbet',
      ),
      body: ListView.builder(
        itemCount: sessions.length,
        itemBuilder: (context, index) {
          final session = sessions[index];
          return ListTile(
            title: Text(session['session_name'] ?? 'Sohbet'),
            subtitle: Text(session['created_at'] ?? ''),
            trailing: IconButton(
              icon: Icon(Icons.delete, color: Colors.red),
              onPressed: () => deleteSession(session['session_id']),
              tooltip: 'Sohbeti Sil',
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(userId: widget.userId, sessionId: session['session_id']),
                ),
              );
            },
          );
        },
      ),
    );
  }
} 