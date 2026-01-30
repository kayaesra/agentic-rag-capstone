import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'utils/theme.dart';
import 'screens/home/home_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/home/dashboard_screen.dart';
import 'dart:io';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NutriSparkAI',
      theme: AppTheme.lightTheme,
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home': (context) {
          final userId = ModalRoute.of(context)?.settings.arguments as int?;
          return HomeScreen(userId: userId ?? 0);
        },
        '/dashboard': (context) {
          final userId = ModalRoute.of(context)?.settings.arguments as int?;
          return DashboardScreen(userId: userId ?? 0);
        },
      },
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;

  Future<void> sendMessage(String message) async {
  setState(() {
    _isLoading = true;
    _messages.add({'role': 'user', 'text': message});
  });

  final url = Uri.parse(Platform.isAndroid
      ? 'http://10.0.2.2:8000/api/v1/chat'
      : 'http://localhost:8000/api/v1/chat');
  final response = await http.post(
    url,
    headers: {'Content-Type': 'application/json'},
    body: json.encode({
      'message': message,
      'user_id': 1,
    }),
  );

  String botReply = 'Bir hata oluştu.';
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    botReply = data['response'] ?? 'Yanıt alınamadı.';
  }

  setState(() {
    _messages.add({'role': 'bot', 'text': botReply});
    _isLoading = false;
  });
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Beslenme Asistanı Sohbet')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['role'] == 'user';
                return ListTile(
                  title: Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isUser ? Colors.green[100] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(msg['text'] ?? ''),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Mesajınızı yazın...',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _isLoading
                      ? null
                      : () {
                          final text = _controller.text.trim();
                          if (text.isNotEmpty) {
                            sendMessage(text);
                            _controller.clear();
                          }
                        },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}