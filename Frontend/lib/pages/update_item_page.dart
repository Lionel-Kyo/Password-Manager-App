import 'dart:async';
import 'package:flutter/material.dart';
import 'package:password_manager_app/pages/show_item_page.dart';
import 'package:password_manager_app/service/api_client_service.dart';

class UpdateItemPage extends StatefulWidget {
  final String itemName;
  const UpdateItemPage({super.key, required this.itemName});

  @override
  State<UpdateItemPage> createState() => _UpdateItemPageState();
}

class _UpdateItemPageState extends State<UpdateItemPage> {
  final List<MapEntry<TextEditingController, TextEditingController>> _fields = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchItem();
  }

  Future<void> _fetchItem() async {
    try {
      final res = await api.sendCommand({"action": "GetItem", "item_name": widget.itemName});
      if (res["success"] == true) {
        final kvs = Map<String, String>.from(res["key_values"] ?? {});
        setState(() {
          _fields.clear();
          kvs.forEach((k, v) {
            _fields.add(MapEntry(TextEditingController(text: k), TextEditingController(text: v)));
          });
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmAndUpdate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Update"),
        content: Text("Are you sure you want to save changes to '${widget.itemName}'?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
            child: const Text("UPDATE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _update();
    }
  }

  Future<void> _update() async {
    final kvs = <String, String>{};
    for (var f in _fields) {
      if (f.key.text.trim().isNotEmpty) {
        kvs[f.key.text.trim()] = f.value.text;
      }
    }

    try {
      final res = await api.sendCommand({
        "action": "UpdateItem",
        "item_name": widget.itemName,
        "key_values": kvs,
      });

      if (res["success"] == true) {
        if (!mounted) return;
        Navigator.pop(context);
      } else {
        _showError(res["error"] ?? "Failed to update item");
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
      appBar: AppBar(
        title: Text("Edit ${widget.itemName}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.visibility),
            tooltip: "View Mode",
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => ShowItemPage(itemName: widget.itemName)),
              );
            },
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
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
                                  decoration: const InputDecoration(labelText: "Key"),
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
                    label: const Text("Add Field"),
                    onPressed: () => setState(() => _fields.add(MapEntry(TextEditingController(), TextEditingController()))),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _confirmAndUpdate,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                      child: const Text("UPDATE ITEM", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ),
            ),
    );
  }
}
