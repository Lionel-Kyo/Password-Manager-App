import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:password_manager_app/pages/update_item_page.dart';
import 'package:password_manager_app/service/api_client_service.dart';

class ShowItemPage extends StatefulWidget {
  final String itemName;
  const ShowItemPage({super.key, required this.itemName});

  @override
  State<ShowItemPage> createState() => _ShowItemPageState();
}

class _ShowItemPageState extends State<ShowItemPage> {
  Map<String, String>? _kvs;
  bool _loading = true;
  final Set<String> _unmaskedKeys = {}; // Tracks which keys are currently visible

  @override
  void initState() {
    super.initState();
    _fetchItem();
  }

  Future<void> _fetchItem() async {
    try {
      final res = await api.sendCommand({"action": "GetItem", "item_name": widget.itemName});
      if (res["success"] == true) {
        setState(() {
          _kvs = Map<String, String>.from(res["key_values"] ?? {});
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.itemName),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: "Edit Item",
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => UpdateItemPage(itemName: widget.itemName)),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ListView(
                      children: _kvs!.entries.map((entry) {
                        final isUnmasked = _unmaskedKeys.contains(entry.key);
                        final displayValue = isUnmasked ? entry.value : "••••••••";

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            title: Text(entry.key, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            subtitle: Text(
                              displayValue,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    isUnmasked ? Icons.visibility_off : Icons.visibility,
                                    color: Colors.grey,
                                  ),
                                  tooltip: isUnmasked ? "Hide Value" : "Show Value",
                                  onPressed: () {
                                    setState(() {
                                      if (isUnmasked) {
                                        _unmaskedKeys.remove(entry.key);
                                      } else {
                                        _unmaskedKeys.add(entry.key);
                                      }
                                    });
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy, color: Colors.tealAccent),
                                  tooltip: "Copy Value",
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: entry.value));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("Value copied to clipboard")),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2A2A3D)),
                      child: const Text("BACK TO MAIN PAGE", style: TextStyle(color: Colors.white)),
                    ),
                  )
                ],
              ),
            ),
    );
  }
}
