import 'dart:async';
import 'package:flutter/material.dart';
import 'package:password_manager_app/service/api_client_service.dart';

class InsertItemPage extends StatefulWidget {
  const InsertItemPage({super.key});

  @override
  State<InsertItemPage> createState() => _InsertItemPageState();
}

class _InsertItemPageState extends State<InsertItemPage> {
  final _nameCtrl = TextEditingController();
  final List<MapEntry<TextEditingController, TextEditingController>> _fields = [];

  @override
  void initState() {
    super.initState();
    _addField("Account", "");
    _addField("Password", "");
  }

  void _addField(String key, String val) {
    setState(() {
      _fields.add(MapEntry(TextEditingController(text: key), TextEditingController(text: val)));
    });
  }

  Future<void> _confirmAndSave() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter an item name"), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Creation"),
        content: Text("Are you sure you want to add '${_nameCtrl.text}' to your vault?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
            child: const Text("CREATE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _save();
    }
  }

  Future<void> _save() async {
    final kvs = <String, String>{};
    for (var f in _fields) {
      if (f.key.text.trim().isNotEmpty) {
        kvs[f.key.text.trim()] = f.value.text;
      }
    }

    try {
      final res = await api.sendCommand({
        "action": "InsertItem",
        "item_name": _nameCtrl.text.trim(),
        "key_values": kvs,
      });

      if (res["success"] == true) {
        if (!mounted) return;
        Navigator.pop(context);
      } else {
        _showError(res["error"] ?? "Failed to insert item");
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("New Item")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: "Item Name"),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _fields.length,
                itemBuilder: (ctx, idx) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _fields[idx].key,
                            decoration: const InputDecoration(labelText: "Field Name"),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _fields[idx].value,
                            decoration: const InputDecoration(labelText: "Value"),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle, color: Colors.redAccent),
                          onPressed: () => setState(() => _fields.removeAt(idx)),
                        )
                      ],
                    ),
                  );
                },
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text("Add Custom Key-Value Field"),
              onPressed: () => _addField("", ""),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _confirmAndSave,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                child: const Text("SAVE ITEM", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }
}
