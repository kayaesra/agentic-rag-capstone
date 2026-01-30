import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

class ProfileScreen extends StatefulWidget {
  final int userId;
  const ProfileScreen({super.key, required this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? userData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    fetchUserData();
  }

  Future<void> fetchUserData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await http.get(
        Uri.parse(Platform.isAndroid
            ? 'http://10.0.2.2:8000/api/v1/user/${widget.userId}'
            : 'http://localhost:8000/api/v1/user/${widget.userId}'),
      );
      if (response.statusCode == 200) {
        setState(() {
          userData = json.decode(response.body);
        });
      } else {
        setState(() {
          _error = 'Kullanıcı bilgileri alınamadı';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Sunucuya bağlanılamadı';
      });
    }
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Profilim'), actions: [
        if (userData != null)
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _showEditDialog(context),
          ),
      ]),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : userData == null
                  ? const Center(child: Text('Kullanıcı verisi yok'))
                  : Center(
                      child: Card(
                        elevation: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        child: Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(minHeight: 600),
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius: 40,
                                backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                                child: Icon(Icons.person, size: 48, color: theme.colorScheme.primary),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                userData!["name"] ?? "-",
                                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(userData!["email"] ?? "-", style: theme.textTheme.bodyMedium),
                              const Divider(height: 32, thickness: 1),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _ProfileInfoTile(
                                    icon: Icons.cake,
                                    label: "Yaş",
                                    value: userData!["age"]?.toString() ?? "-",
                                  ),
                                  _ProfileInfoTile(
                                    icon: Icons.wc,
                                    label: "Cinsiyet",
                                    value: userData!["gender"] ?? "-",
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _ProfileInfoTile(
                                    icon: Icons.height,
                                    label: "Boy (cm)",
                                    value: userData!["height"]?.toString() ?? "-",
                                  ),
                                  _ProfileInfoTile(
                                    icon: Icons.monitor_weight,
                                    label: "Kilo (kg)",
                                    value: userData!["weight"]?.toString() ?? "-",
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _ProfileInfoTile(
                                    icon: Icons.flag,
                                    label: "Hedef",
                                    value: _goalLabel(userData!["goal"]),
                                  ),
                                  _ProfileInfoTile(
                                    icon: Icons.directions_run,
                                    label: "Aktivite",
                                    value: _activityLabel(userData!["activity_level"]),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                                },
                                icon: const Icon(Icons.logout),
                                label: const Text('Çıkış Yap'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(48),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _showChangePasswordDialog,
                                icon: const Icon(Icons.lock_reset),
                                label: const Text('Şifre Değiştir'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final nameController = TextEditingController(text: userData?["name"] ?? "");
    final ageController = TextEditingController(text: userData?["age"]?.toString() ?? "");
    final gender = userData?["gender"] ?? "";
    final heightController = TextEditingController(text: userData?["height"]?.toString() ?? "");
    final weightController = TextEditingController(text: userData?["weight"]?.toString() ?? "");
    String? selectedGender = gender;
    String? selectedGoal = userData?["goal"];
    String? selectedActivity = userData?["activity_level"];
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: const Text('Profili Düzenle'),
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 350),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Ad'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ageController,
                    decoration: const InputDecoration(labelText: 'Yaş'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedGender,
                    items: const [
                      DropdownMenuItem(value: 'Kadın', child: Text('Kadın')),
                      DropdownMenuItem(value: 'Erkek', child: Text('Erkek')),
                      DropdownMenuItem(value: 'Diğer', child: Text('Diğer')),
                    ],
                    onChanged: (value) => selectedGender = value,
                    decoration: const InputDecoration(labelText: 'Cinsiyet'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: heightController,
                    decoration: const InputDecoration(labelText: 'Boy (cm)'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: weightController,
                    decoration: const InputDecoration(labelText: 'Kilo (kg)'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedGoal,
                    items: const [
                      DropdownMenuItem(value: 'weight_loss', child: Text('Kilo Vermek')),
                      DropdownMenuItem(value: 'maintenance', child: Text('Korumak')),
                      DropdownMenuItem(value: 'muscle_gain', child: Text('Kas Yapmak')),
                    ],
                    onChanged: (value) => selectedGoal = value,
                    decoration: const InputDecoration(labelText: 'Hedef'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedActivity,
                    items: const [
                      DropdownMenuItem(value: 'sedentary', child: Text('Sedanter (Çok az hareket)')),
                      DropdownMenuItem(value: 'light', child: Text('Hafif Aktif (Haftada 1-3 gün spor)')),
                      DropdownMenuItem(value: 'moderate', child: Text('Orta Aktif (Haftada 3-5 gün spor)')),
                      DropdownMenuItem(value: 'active', child: Text('Aktif (Haftada 6-7 gün spor)')),
                      DropdownMenuItem(value: 'very_active', child: Text('Çok Aktif (Yoğun egzersiz veya fiziksel iş)')),
                    ],
                    onChanged: (value) => selectedActivity = value,
                    decoration: const InputDecoration(labelText: 'Aktivite Seviyesi'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _updateProfile(
                  name: nameController.text.trim(),
                  age: int.tryParse(ageController.text.trim()),
                  gender: selectedGender,
                  height: int.tryParse(heightController.text.trim()),
                  weight: int.tryParse(weightController.text.trim()),
                  goal: selectedGoal,
                  activityLevel: selectedActivity,
                );
                if (mounted) Navigator.of(context).pop();
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateProfile({String? name, int? age, String? gender, int? height, int? weight, String? goal, String? activityLevel}) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.put(
        Uri.parse(Platform.isAndroid
            ? 'http://10.0.2.2:8000/api/v1/user/${widget.userId}'
            : 'http://localhost:8000/api/v1/user/${widget.userId}'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
          'age': age,
          'gender': gender,
          'height': height,
          'weight': weight,
          'goal': goal,
          'activity_level': activityLevel,
        }),
      );
      if (response.statusCode == 200) {
        await fetchUserData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil güncellenemedi')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sunucuya bağlanılamadı')),
      );
    }
    setState(() => _isLoading = false);
  }

  void _showChangePasswordDialog() {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: const Text('Şifre Değiştir'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldPasswordController,
                decoration: const InputDecoration(labelText: 'Mevcut Şifre'),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPasswordController,
                decoration: const InputDecoration(labelText: 'Yeni Şifre'),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _changePassword(
                  oldPassword: oldPasswordController.text.trim(),
                  newPassword: newPasswordController.text.trim(),
                );
                if (mounted) Navigator.of(context).pop();
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _changePassword({required String oldPassword, required String newPassword}) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse(Platform.isAndroid
            ? 'http://10.0.2.2:8000/api/v1/user/${widget.userId}/change-password'
            : 'http://localhost:8000/api/v1/user/${widget.userId}/change-password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'old_password': oldPassword,
          'new_password': newPassword,
        }),
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Şifre başarıyla değiştirildi.')),
        );
      } else {
        final data = json.decode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['detail'] ?? 'Şifre değiştirilemedi.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sunucuya bağlanılamadı')),
      );
    }
    setState(() => _isLoading = false);
  }

  String _goalLabel(String? goal) {
    switch (goal) {
      case 'weight_loss':
        return 'Kilo Vermek';
      case 'maintenance':
        return 'Korumak';
      case 'muscle_gain':
        return 'Kas Yapmak';
      default:
        return '-';
    }
  }

  String _activityLabel(String? activity) {
    switch (activity) {
      case 'sedentary':
        return 'Sedanter';
      case 'light':
        return 'Hafif Aktif';
      case 'moderate':
        return 'Orta Aktif';
      case 'active':
        return 'Aktif';
      case 'very_active':
        return 'Çok Aktif';
      default:
        return '-';
    }
  }
}

class _ProfileInfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _ProfileInfoTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 28),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
} 