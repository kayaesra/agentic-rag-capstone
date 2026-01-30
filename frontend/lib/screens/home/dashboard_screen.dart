import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:math';
import 'dart:io';

class DashboardScreen extends StatefulWidget {
  final int userId;
  final void Function(int)? onTabChange;
  const DashboardScreen({super.key, required this.userId, this.onTabChange});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? userName;
  int? waterCurrent;
  int? waterGoal;
  bool isLoading = true;
  double caloriesCurrent = 0;
  double caloriesGoal = 2000;
  int shoppingTotal = 0;
  int shoppingChecked = 0;
  bool hasShownCalorieWarning = false;
  static const List<String> motivationMessages = [
    "Bugün kendin için güzel bir şey yap! 🌟",
    "Küçük adımlar büyük değişimler yaratır. 🚀",
    "Sağlıklı seçimler seni hedeflerine yaklaştırır! 🥗",
    "Her gün yeni bir başlangıçtır. 💫",
    "Unutma, sen harikasın! ✨",
    "Bir bardak su, bir adım sağlık! 💧",
    "Kendine iyi bakmayı unutma! 💚",
    "Bugün birine gülümse! 😊",
    "Hedeflerine ulaşmak için sabırlı ol. 🕰️",
    "Kendini ödüllendirmeyi unutma! 🎁",
    "Her yeni gün, yeni bir fırsat! 🌅",
    "Kendine inanmaktan asla vazgeçme! 💪",
    "Zorluklar seni daha güçlü yapar. 🦾",
    "Hayat, küçük mutluluklarla güzeldir. 🌸",
    "Bugün bir adım daha ileri git! 👣",
    "Pozitif düşün, pozitif yaşa! ☀️",
    "Başarı, pes etmeyenlerindir. 🏆",
    "Kendini sevmek en büyük motivasyondur. ❤️",
    "Bugün sağlıklı bir seçim yap! 🥦",
    "Her gün bir şeye teşekkür et! 🙏",
    "Gülümsemek bulaşıcıdır, yay! 😁",
    "Enerjini iyi şeylere harca! ⚡️",
    "Kendine zaman ayırmayı unutma. 🕊️",
    "Bugün yeni bir şey dene! 🧩",
    "Hayallerin için çalışmaya devam et! 🎯",
    "Küçük değişiklikler büyük farklar yaratır. 🔄",
    "Bugün kendine bir iyilik yap! 🎈",
    "Dengeli beslen, mutlu yaşa! 🥑",
    "Her günün sonunda kendinle gurur duy! 🥇",
    "Senin için imkansız yok! 🚦",
  ];
  late List<String> selectedMotivations;
  final List<Color> motivationColors = [
    Color(0xFFFFF9C4),
    Color(0xFFB3E5FC), 
    Color(0xFFC8E6C9),
    Color(0xFFFFE0B2),
    Color(0xFFE1BEE7),
    Color(0xFFFFCDD2), 
  ];

  @override
  void initState() {
    super.initState();
    final rand = Random();
    final shuffled = List<String>.from(motivationMessages)..shuffle(rand);
    selectedMotivations = shuffled.take(3).toList();
    fetchAll();
  }

  Future<void> fetchAll() async {
    setState(() => isLoading = true);
    await Future.wait([
      fetchUserName(),
      fetchWater(),
      fetchShoppingList(),
      fetchTodayCalories(),
      fetchCalorieGoal(),
    ]);
    setState(() => isLoading = false);
    
    
    checkCalorieGoal();
  }

  Future<void> fetchUserName() async {
    try {
      final res = await http.get(Uri.parse(Platform.isAndroid
          ? 'http://10.0.2.2:8000/api/v1/user/${widget.userId}'
          : 'http://localhost:8000/api/v1/user/${widget.userId}'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          userName = data['name'] ?? null;
        });
      }
    } catch (_) {}
  }

  Future<void> fetchWater() async {
    try {
      final res = await http.get(Uri.parse(Platform.isAndroid
          ? 'http://10.0.2.2:8000/api/v1/water/today/${widget.userId}'
          : 'http://localhost:8000/api/v1/water/today/${widget.userId}'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          waterCurrent = data['amount_ml'] ?? 0;
          waterGoal = data['goal_ml'] ?? 2000;
        });
      }
    } catch (_) {
      setState(() {
        waterCurrent = 0;
        waterGoal = 2000;
      });
    }
  }

  Future<void> fetchShoppingList() async {
    final prefs = await SharedPreferences.getInstance();
    final itemsKey = 'shopping_items_user_${widget.userId}';
    final checkedKey = 'shopping_checked_user_${widget.userId}';
    final items = prefs.getStringList(itemsKey) ?? [];
    final checkedStr = prefs.getString(checkedKey);
    final checked = checkedStr != null ? List<bool>.from(json.decode(checkedStr), growable: true) : List.filled(items.length, false, growable: true);
    setState(() {
      shoppingTotal = items.length;
      shoppingChecked = checked.where((v) => v).length;
    });
  }

  Future<void> fetchTodayCalories() async {
    try {
      final res = await http.get(Uri.parse(Platform.isAndroid
          ? 'http://10.0.2.2:8000/api/v1/nutrition/today/${widget.userId}'
          : 'http://localhost:8000/api/v1/nutrition/today/${widget.userId}'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          
          var totalCalories = data['daily_totals']['total_calories'];
          if (totalCalories is int) {
            caloriesCurrent = totalCalories.toDouble();
          } else if (totalCalories is double) {
            caloriesCurrent = totalCalories;
          } else {
            caloriesCurrent = 0.0;
          }
        });
      }
    } catch (_) {
      setState(() {
        caloriesCurrent = 0.0;
      });
    }
  }

  Future<void> fetchCalorieGoal() async {
    try {
      final res = await http.get(Uri.parse(Platform.isAndroid
          ? 'http://10.0.2.2:8000/api/v1/user/${widget.userId}/macros'
          : 'http://localhost:8000/api/v1/user/${widget.userId}/macros'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          
          var calories = data['calories'];
          if (calories is int) {
            caloriesGoal = calories.toDouble();
          } else if (calories is double) {
            caloriesGoal = calories;
          } else {
            caloriesGoal = 2000.0;
          }
        });
      }
    } catch (_) {
      setState(() {
        caloriesGoal = 2000.0;
      });
    }
  }

  void checkCalorieGoal() {
    if (!hasShownCalorieWarning && caloriesCurrent > caloriesGoal) {
      hasShownCalorieWarning = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showCalorieWarningDialog();
      });
    }
  }

  void showCalorieWarningDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Text('Kalori Hedefi Aşıldı!'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Günlük kalori hedefinizi aştınız:',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Alınan Kalori:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('${caloriesCurrent.toInt()} kcal', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Hedef Kalori:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('${caloriesGoal.toInt()} kcal', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Aşım:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('+${(caloriesCurrent - caloriesGoal).toInt()} kcal', 
                             style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12),
              Text(
                '💡 Egzersiz yaparak fazla kalorileri yakabilir veya yarın daha az kalori alabilirsiniz.',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Anladım'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
               
                widget.onTabChange?.call(1);
              },
              child: Text('AI ile Konuş'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Ana Sayfa'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
            onPressed: () {
              hasShownCalorieWarning = false; 
              fetchAll();
            },
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Yardım',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('NutriSparkAI Yardım'),
                  content: const SingleChildScrollView(
                    child: Text(
                      'NutriSparkAI, sağlıklı yaşam ve beslenme takibi için geliştirilmiş bir mobil uygulamadır.\n\n'
                      '- Su ve kalori takibi yapabilir, günlük hedeflerinizi görebilirsiniz.\n'
                      '- Profilinizi güncelleyip, hedef ve aktivite seviyenizi belirleyebilirsiniz.\n'
                      '- AI destekli sohbet asistanı ile beslenme ve diyet hakkında sorular sorabilirsiniz.\n'
                      '- Alışveriş listenizi oluşturabilir ve tamamladıklarınızı işaretleyebilirsiniz.\n'
                      '- Makro ve kalori ihtiyacınızı kişisel bilgilerinize göre otomatik görebilirsiniz.\n\n'
                      'Herhangi bir sorunuz olursa destek ekibimize ulaşabilirsiniz!\n\n'
                      'Sağlıklı günler dileriz! 🥑💧🔥',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Kapat'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      userName != null ? 'Hoş geldin, $userName!' : 'Hoş geldin!',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text('Bugün de sağlıklı kalmaya devam et. 💪', style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryCard(
                            icon: Icons.water_drop,
                            color: Colors.blueAccent,
                            title: 'Su',
                            value: waterCurrent != null && waterGoal != null ? '${waterCurrent!} / ${waterGoal!} ml' : '-',
                            progress: (waterCurrent != null && waterGoal != null && waterGoal! > 0) ? waterCurrent! / waterGoal! : 0,
                            onTap: () => widget.onTabChange?.call(2),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _SummaryCard(
                            icon: Icons.local_fire_department,
                            color: caloriesCurrent > caloriesGoal ? Colors.red : Colors.redAccent,
                            title: 'Kalori',
                            value: '${caloriesCurrent.toInt()} / ${caloriesGoal.toInt()} kcal',
                            progress: (caloriesGoal > 0) ? (caloriesCurrent / caloriesGoal).clamp(0.0, 1.0) : 0,
                            onTap: () => widget.onTabChange?.call(3),
                            isOverGoal: caloriesCurrent > caloriesGoal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _SummaryCard(
                      icon: Icons.shopping_cart,
                      color: Colors.orange,
                      title: 'Alışveriş',
                      value: shoppingTotal == 0 ? 'Hiç ürün yok' : '$shoppingChecked / $shoppingTotal tamamlandı',
                      progress: shoppingTotal == 0 ? 0 : shoppingChecked / shoppingTotal,
                      onTap: () => widget.onTabChange?.call(4),
                    ),
                    const SizedBox(height: 28),
                    Column(
                      children: List.generate(3, (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Card(
                          color: motivationColors[i % motivationColors.length],
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(18.0),
                            child: Row(
                              children: [
                                const Icon(Icons.lightbulb, color: Colors.orange, size: 32),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    selectedMotivations[i],
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black87),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final double progress;
  final VoidCallback onTap;
  final bool isOverGoal;
  
  const _SummaryCard({
    required this.icon, 
    required this.color, 
    required this.title, 
    required this.value, 
    required this.progress, 
    required this.onTap,
    this.isOverGoal = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: isOverGoal ? Border.all(color: Colors.red, width: 2) : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 28),
                    const SizedBox(width: 10),
                    Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
                    if (isOverGoal) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.warning, color: Colors.red, size: 20),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: color.withOpacity(0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(isOverGoal ? Colors.red : color),
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 8),
                Text(value, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: isOverGoal ? Colors.red : null)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickAccessCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickAccessCard({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        color: color.withOpacity(0.1),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 70,
          height: 90,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
} 