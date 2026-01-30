import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class ShoppingListScreen extends StatefulWidget {
  final int userId;
  const ShoppingListScreen({super.key, required this.userId});

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  final TextEditingController _controller = TextEditingController();
  List<String> _items = [];
  List<bool> _checked = [];

  String get _itemsKey => 'shopping_items_user_${widget.userId}';
  String get _checkedKey => 'shopping_checked_user_${widget.userId}';

  @override
  void initState() {
    super.initState();
    _loadList();
  }

  Future<void> _loadList() async {
    final prefs = await SharedPreferences.getInstance();
    final items = prefs.getStringList(_itemsKey) ?? [];
    final checkedStr = prefs.getString(_checkedKey);
    final checked = checkedStr != null ? List<bool>.from(json.decode(checkedStr), growable: true) : List.filled(items.length, false, growable: true);
    setState(() {
      _items = items;
      _checked = checked.length == items.length ? checked : List.filled(items.length, false, growable: true);
    });
  }

  Future<void> _saveList() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_itemsKey, _items);
    await prefs.setString(_checkedKey, json.encode(_checked));
  }

  void _addItem() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _items.add(text);
        _checked.add(false);
        _controller.clear();
      });
      _saveList();
    }
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      _checked.removeAt(index);
    });
    _saveList();
  }

  void _toggleChecked(int index) {
    setState(() {
      _checked[index] = !_checked[index];
    });
    _saveList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alışveriş Listesi')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Ürün ekle...'
                    ),
                    onSubmitted: (_) => _addItem(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addItem,
                  child: const Text('Ekle'),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Text('Alışveriş Listesi:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Expanded(
              child: _items.isEmpty
                  ? const Center(child: Text('Henüz ürün eklenmedi.'))
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          leading: GestureDetector(
                            onTap: () => _toggleChecked(index),
                            child: Icon(
                              _checked[index]
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              color: _checked[index] ? Theme.of(context).colorScheme.primary : null,
                            ),
                          ),
                          title: Text(_items[index],
                              style: TextStyle(
                                decoration: _checked[index] ? TextDecoration.lineThrough : null,
                                color: _checked[index] ? Colors.grey : null,
                              )),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _removeItem(index),
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