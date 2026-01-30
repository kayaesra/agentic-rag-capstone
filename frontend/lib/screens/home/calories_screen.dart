import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

class CaloriesScreen extends StatefulWidget {
  final int userId;
  const CaloriesScreen({super.key, required this.userId});

  @override
  State<CaloriesScreen> createState() => _CaloriesScreenState();
}

class _CaloriesScreenState extends State<CaloriesScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? macros;
  Map<String, dynamic>? todayNutrition;
  bool _isLoading = true;
  String? _error;
  late TabController _tabController;

 
  final TextEditingController _foodNameController = TextEditingController();
  final TextEditingController _proteinController = TextEditingController();
  final TextEditingController _carbsController = TextEditingController();
  final TextEditingController _fatController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    fetchAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _foodNameController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    super.dispose();
  }

  Future<void> fetchAllData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      await Future.wait([
        fetchMacros(),
        fetchTodayNutrition(),
      ]);
    } catch (e) {
      setState(() {
        _error = 'Veriler yüklenirken hata oluştu';
      });
    }
    
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> fetchMacros() async {
    try {
      final response = await http.get(
        Uri.parse(Platform.isAndroid
            ? 'http://10.0.2.2:8000/api/v1/user/${widget.userId}/macros'
            : 'http://localhost:8000/api/v1/user/${widget.userId}/macros'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          macros = data;
        });
      }
    } catch (e) {
      print('Makro bilgileri alınamadı: $e');
    }
  }

  Future<void> fetchTodayNutrition() async {
    try {
      final response = await http.get(
        Uri.parse(Platform.isAndroid
            ? 'http://10.0.2.2:8000/api/v1/nutrition/today/${widget.userId}'
            : 'http://localhost:8000/api/v1/nutrition/today/${widget.userId}'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          todayNutrition = data;
        });
      }
    } catch (e) {
      print('Günlük beslenme bilgileri alınamadı: $e');
    }
  }

  Future<void> addFood() async {
    if (_foodNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yiyecek adı girilmelidir')),
      );
      return;
    }

    final protein = double.tryParse(_proteinController.text) ?? 0;
    final carbs = double.tryParse(_carbsController.text) ?? 0;
    final fat = double.tryParse(_fatController.text) ?? 0;

    try {
      final response = await http.post(
        Uri.parse(Platform.isAndroid
            ? 'http://10.0.2.2:8000/api/v1/nutrition/add-food?user_id=${widget.userId}'
            : 'http://localhost:8000/api/v1/nutrition/add-food?user_id=${widget.userId}'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'food_name': _foodNameController.text,
          'protein_g': protein,
          'carbs_g': carbs,
          'fat_g': fat,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Beslenme kaydı eklendi (${responseData['calculated_calories'].toInt()} kcal)'),
            backgroundColor: Colors.green,
          ),
        );
        
       
        _foodNameController.clear();
        _proteinController.clear();
        _carbsController.clear();
        _fatController.clear();
        
        
        await fetchTodayNutrition();
      } else {
        throw Exception('API hatası');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata oluştu: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> deleteFood(int foodId) async {
    try {
      final response = await http.delete(
        Uri.parse(Platform.isAndroid
            ? 'http://10.0.2.2:8000/api/v1/nutrition/food/$foodId?user_id=${widget.userId}'
            : 'http://localhost:8000/api/v1/nutrition/food/$foodId?user_id=${widget.userId}'),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Beslenme kaydı silindi'), backgroundColor: Colors.green),
        );
        await fetchTodayNutrition();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Silme hatası: $e'), backgroundColor: Colors.red),
      );
    }
  }

  double calculateCalories(double protein, double carbs, double fat) {
    return (protein * 4) + (carbs * 4) + (fat * 9);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kalori & Beslenme Takibi'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Bugün', icon: Icon(Icons.today)),
            Tab(text: 'Yiyecek Ekle', icon: Icon(Icons.add_circle)),
            Tab(text: 'Hedefler', icon: Icon(Icons.track_changes)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchAllData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTodayTab(),
                    _buildAddFoodTab(),
                    _buildGoalsTab(),
                  ],
                ),
    );
  }

  Widget _buildTodayTab() {
    final daily = todayNutrition?['daily_totals'];
    final foodEntries = todayNutrition?['food_entries'] ?? [];
    
    
    final goalCalories = _safeToDouble(macros?['calories'] ?? 2000);
    final currentCalories = _safeToDouble(daily?['total_calories'] ?? 0);
    final currentProtein = _safeToDouble(daily?['total_protein_g'] ?? 0);
    final currentCarbs = _safeToDouble(daily?['total_carbs_g'] ?? 0);
    final currentFat = _safeToDouble(daily?['total_fat_g'] ?? 0);
    
    final goalProtein = _safeToDouble(macros?['protein_g'] ?? 0);
    final goalCarbs = _safeToDouble(macros?['carbs_g'] ?? 0);
    final goalFat = _safeToDouble(macros?['fat_g'] ?? 0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: currentCalories > goalCalories 
                    ? [Colors.red.shade50, Colors.red.shade100]
                    : [Colors.blue.shade50, Colors.blue.shade100],
                ),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Günlük Kalori',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (currentCalories > goalCalories)
                        Icon(Icons.warning, color: Colors.red, size: 24),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${currentCalories.toInt()} kcal', 
                           style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, 
                                          color: currentCalories > goalCalories ? Colors.red : Colors.blue)),
                      Text('/ ${goalCalories.toInt()} kcal', 
                           style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: goalCalories > 0 ? (currentCalories / goalCalories).clamp(0.0, 1.0) : 0.0,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      currentCalories > goalCalories ? Colors.red : Colors.blue,
                    ),
                    minHeight: 8,
                  ),
                  if (currentCalories > goalCalories) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Hedef aşıldı: +${(currentCalories - goalCalories).toInt()} kcal',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          
          if (daily != null) ...[
            Text('Makro Özeti', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildMacroCard('Protein', currentProtein, goalProtein, Colors.blue, 'g'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMacroCard('Karbonhidrat', currentCarbs, goalCarbs, Colors.green, 'g'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMacroCard('Yağ', currentFat, goalFat, Colors.pink, 'g'),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],

          
          Text('Bugün Tüketilen Yiyecekler', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          
          if (foodEntries.isEmpty)
            Center(
              child: Column(
                children: [
                  Icon(Icons.restaurant, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('Henüz yiyecek eklenmemiş', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => _tabController.animateTo(1),
                    child: const Text('Yiyecek Ekle'),
                  ),
                ],
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: foodEntries.length,
              itemBuilder: (context, index) {
                final food = foodEntries[index];
                return Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.orange.shade100,
                      child: Icon(Icons.restaurant, color: Colors.orange),
                    ),
                    title: Text(food['food_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      'P: ${_safeToDouble(food['protein_g']).toInt()}g • K: ${_safeToDouble(food['carbs_g']).toInt()}g • Y: ${_safeToDouble(food['fat_g']).toInt()}g',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${_safeToDouble(food['calories']).toInt()} kcal', 
                             style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => deleteFood(food['id']),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMacroCard(String title, double current, double goal, Color color, String unit) {
    final progress = goal > 0 ? (current / goal).clamp(0.0, 1.0) : 0.0;
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 8),
            Text('${current.toInt()}$unit', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('/ ${goal.toInt()}$unit', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: color.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddFoodTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Yeni Yiyecek Ekle', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  TextField(
                    controller: _foodNameController,
                    decoration: const InputDecoration(
                      labelText: 'Yiyecek Adı',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.restaurant),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _proteinController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Protein (g)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _carbsController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Karbonhidrat (g)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _fatController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Yağ (g)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Column(
                            children: [
                              Text('Hesaplanan Kalori', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                              const SizedBox(height: 4),
                              Text(
                                '${calculateCalories(
                                  double.tryParse(_proteinController.text) ?? 0,
                                  double.tryParse(_carbsController.text) ?? 0,
                                  double.tryParse(_fatController.text) ?? 0,
                                ).toInt()} kcal',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: addFood,
                      icon: const Icon(Icons.add),
                      label: const Text('Yiyecek Ekle', style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          Card(
            elevation: 2,
            color: Colors.blue.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Text('Kalori Hesaplama', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('• 1g Protein = 4 kcal', style: TextStyle(color: Colors.blue.shade600)),
                  Text('• 1g Karbonhidrat = 4 kcal', style: TextStyle(color: Colors.blue.shade600)),
                  Text('• 1g Yağ = 9 kcal', style: TextStyle(color: Colors.blue.shade600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Günlük Hedefleriniz', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          
          if (macros == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.info, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text('Hedeflerinizi görmek için profil bilgilerinizi tamamlayın'),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => Navigator.pushNamed(context, '/profile'),
                      child: const Text('Profile Git'),
                    ),
                  ],
                ),
              ),
            )
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.9,
              children: [
                _MacroCircle(
                  color: Colors.orange,
                  icon: Icons.local_fire_department,
                  label: 'Kalori',
                  value: '${macros!['calories']} kcal',
                ),
                _MacroCircle(
                  color: Colors.blue,
                  icon: Icons.fitness_center,
                  label: 'Protein',
                  value: '${macros!['protein_g']} g',
                ),
                _MacroCircle(
                  color: Colors.pink,
                  icon: Icons.opacity,
                  label: 'Yağ',
                  value: '${macros!['fat_g']} g',
                ),
                _MacroCircle(
                  color: Colors.green,
                  icon: Icons.grain,
                  label: 'Karbonhidrat',
                  value: '${macros!['carbs_g']} g',
                ),
              ],
            ),
        ],
      ),
    );
  }

  
  double _safeToDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}

class _MacroCircle extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final String value;

  const _MacroCircle({
    required this.color,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: color.withOpacity(0.15),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(height: 12),
            Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          ],
        ),
      ),
    );
  }
} 