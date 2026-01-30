import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  String? _gender;
  String? _goal;
  String? _activityLevel;
  bool _isLoading = false;
  String? _error;

  Future<void> _register() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await http.post(
        Uri.parse(Platform.isAndroid
            ? 'http://10.0.2.2:8000/api/v1/register'
            : 'http://localhost:8000/api/v1/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': _emailController.text.trim(),
          'password': _passwordController.text.trim(),
          'name': _nameController.text.trim(),
          'age': int.tryParse(_ageController.text.trim()),
          'gender': _gender,
          'height': int.tryParse(_heightController.text.trim()),
          'weight': int.tryParse(_weightController.text.trim()),
          'goal': _goal,
          'activity_level': _activityLevel,
        }),
      );
      if (response.statusCode == 200) {
        if (!mounted) return;
        Navigator.of(context).pop();
      } else {
        final data = json.decode(response.body);
        setState(() {
          _error = data['detail'] ?? 'Kayıt başarısız';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Sunucuya bağlanılamadı';
      });
    }
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kayıt Ol')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Ad'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'E-posta'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Şifre'),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _ageController,
                decoration: const InputDecoration(labelText: 'Yaş'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _heightController,
                decoration: const InputDecoration(labelText: 'Boy (cm)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _weightController,
                decoration: const InputDecoration(labelText: 'Kilo (kg)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _gender,
                items: const [
                  DropdownMenuItem(value: 'Kadın', child: Text('Kadın')),
                  DropdownMenuItem(value: 'Erkek', child: Text('Erkek')),
                  DropdownMenuItem(value: 'Diğer', child: Text('Diğer')),
                ],
                onChanged: (value) => setState(() => _gender = value),
                decoration: const InputDecoration(labelText: 'Cinsiyet'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _goal,
                items: const [
                  DropdownMenuItem(value: 'weight_loss', child: Text('Kilo Vermek')),
                  DropdownMenuItem(value: 'maintenance', child: Text('Korumak')),
                  DropdownMenuItem(value: 'muscle_gain', child: Text('Kas Yapmak')),
                ],
                onChanged: (value) => setState(() => _goal = value),
                decoration: const InputDecoration(labelText: 'Hedefiniz'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _activityLevel,
                items: const [
                  DropdownMenuItem(value: 'sedentary', child: Text('Sedanter (Çok az hareket)')),
                  DropdownMenuItem(value: 'light', child: Text('Hafif Aktif (Haftada 1-3 gün spor)')),
                  DropdownMenuItem(value: 'moderate', child: Text('Orta Aktif (Haftada 3-5 gün spor)')),
                  DropdownMenuItem(value: 'active', child: Text('Aktif (Haftada 6-7 gün spor)')),
                  DropdownMenuItem(value: 'very_active', child: Text('Çok Aktif (Yoğun egzersiz veya fiziksel iş)')),
                ],
                onChanged: (value) => setState(() => _activityLevel = value),
                decoration: const InputDecoration(labelText: 'Aktivite Seviyesi'),
              ),
              const SizedBox(height: 24),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _register,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Kayıt Ol'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 