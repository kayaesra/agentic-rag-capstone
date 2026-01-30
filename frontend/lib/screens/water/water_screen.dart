import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

class WaterScreen extends StatefulWidget {
  final int userId;
  const WaterScreen({super.key, required this.userId});

  @override
  State<WaterScreen> createState() => _WaterScreenState();
}

class _WaterScreenState extends State<WaterScreen> {
  int _todayAmount = 0;
  int _goal = 2000;
  bool _isLoading = true;
  List<Map<String, dynamic>> _history = [];
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _goalController = TextEditingController();
  int _glasses = 0;
  int _glassSize = 200;

  @override
  void initState() {
    super.initState();
    fetchToday();
    fetchHistory();
  }

  Future<void> fetchToday() async {
    setState(() => _isLoading = true);
    final res = await http.get(Uri.parse(Platform.isAndroid
        ? 'http://10.0.2.2:8000/api/v1/water/today/${widget.userId}'
        : 'http://localhost:8000/api/v1/water/today/${widget.userId}'));
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      setState(() {
        _todayAmount = data['amount_ml'] ?? 0;
        _goal = data['goal_ml'] ?? 2000;
        _glasses = data['glasses'] ?? 0;
        _glassSize = data['glass_size'] ?? 200;
        _goalController.text = _goal.toString();
      });
    }
    setState(() => _isLoading = false);
  }

  Future<void> fetchHistory() async {
    final res = await http.get(Uri.parse(Platform.isAndroid
        ? 'http://10.0.2.2:8000/api/v1/water/history/${widget.userId}'
        : 'http://localhost:8000/api/v1/water/history/${widget.userId}'));
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      setState(() {
        _history = List<Map<String, dynamic>>.from(data);
      });
    }
  }

  Future<void> addWater() async {
    final amount = int.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) return;
    await http.post(
      Uri.parse(Platform.isAndroid
          ? 'http://10.0.2.2:8000/api/v1/water/add?user_id=${widget.userId}'
          : 'http://localhost:8000/api/v1/water/add?user_id=${widget.userId}'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'amount_ml': amount}),
    );
    _amountController.clear();
    await fetchToday();
    await fetchHistory();
  }

  Future<void> updateGoal() async {
    final goal = int.tryParse(_goalController.text.trim());
    if (goal == null || goal <= 0) return;
    await http.put(
      Uri.parse(Platform.isAndroid
          ? 'http://10.0.2.2:8000/api/v1/water/goal/${widget.userId}?goal_ml=$goal'
          : 'http://localhost:8000/api/v1/water/goal/${widget.userId}?goal_ml=$goal'),
    );
    await fetchToday();
    await fetchHistory();
  }

  Future<void> addGlass() async {
    await http.post(
      Uri.parse(Platform.isAndroid
          ? 'http://10.0.2.2:8000/api/v1/water/add-glass?user_id=${widget.userId}'
          : 'http://localhost:8000/api/v1/water/add-glass?user_id=${widget.userId}'),
    );
    await fetchToday();
    await fetchHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Su Takibi')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 18),
                  if (_todayAmount >= _goal)
                    Card(
                      color: Colors.green[50],
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.emoji_events, color: Colors.green, size: 32),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Tebrikler! Günlük su hedefini başardın 🎉',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.water_drop, color: Theme.of(context).colorScheme.primary, size: 36),
                              const SizedBox(width: 8),
                              Text(
                                '$_todayAmount / $_goal ml',
                                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('$_glasses bardak (${_glassSize} ml)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: (_todayAmount / _goal).clamp(0.0, 1.0),
                              minHeight: 18,
                              backgroundColor: Colors.grey[200],
                              color: _todayAmount >= _goal ? Colors.green : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: addGlass,
                            icon: const Icon(Icons.local_drink, size: 28),
                            label: Text('${_glassSize} ml Bardak', style: const TextStyle(fontSize: 18)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _goalController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Günlük Hedef (ml)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton(
                            onPressed: updateGoal,
                            child: const Text('Hedefi Güncelle'),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Geçmiş Su Tüketimi', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _history.isEmpty
                        ? const Center(child: Text('Kayıt yok'))
                        : ListView.builder(
                            itemCount: _history.length,
                            itemBuilder: (context, i) {
                              final log = _history[i];
                              final date = DateTime.tryParse(log['date'] ?? '') ?? DateTime.now();
                              final formattedDate = '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
                              return Card(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  leading: const Icon(Icons.water_drop, color: Colors.blueAccent),
                                  title: Text('${log['amount_ml']} ml', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text('Hedef: ${log['goal_ml']} ml'),
                                  trailing: Text(formattedDate, style: const TextStyle(fontSize: 13)),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
} 