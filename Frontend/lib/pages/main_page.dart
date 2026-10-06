import 'dart:async';
import 'package:flutter/material.dart';
import 'package:password_manager_app/pages/insert_item_page.dart';
import 'package:password_manager_app/pages/login_page.dart';
import 'package:password_manager_app/pages/modify_password_page.dart';
import 'package:password_manager_app/pages/show_item_page.dart';
import 'package:password_manager_app/pages/update_item_page.dart';
import 'package:password_manager_app/service/api_client_service.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  List<String> _items = [];
  bool _loading = false;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  int _itemsPerPage = 100;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
    _loadItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _filteredItems {
    if (_searchQuery.isEmpty) return _items;
    return _items.where((item) => item.toLowerCase().contains(_searchQuery)).toList();
  }

  List<String> get _pagedItems {
    final filtered = _filteredItems;
    if (_itemsPerPage == -1 || filtered.length <= _itemsPerPage) {
      return filtered;
    }
    return filtered.sublist(0, _itemsPerPage);
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    try {
      final res = await api.sendCommand({"action": "GetItemNames"});
      if (res["success"] == true) {
        setState(() {
          _items = List<String>.from(res["item_names"] ?? []);
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

  Future<void> _saveOrder() async {
    try {
      await api.sendCommand({
        "action": "UpdateItemOrder",
        "ordered_item_names": _items,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save item order: $e"), backgroundColor: Colors.redAccent),
        );
      }
      _loadItems(); // Rollback/reload on failure
    }
  }

  void _onReorderItem(int oldIndex, int newIndex) {
    setState(() {
      final String item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
    _saveOrder();
  }

  Future<void> _confirmAndRemoveItem(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Deletion"),
        content: Text("Are you sure you want to delete '$name'? This action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text("DELETE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _removeItem(name);
    }
  }

  Future<void> _removeItem(String name) async {
    try {
      final res = await api.sendCommand({"action": "RemoveItem", "item_name": name});
      if (res["success"] == true) {
        _loadItems();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = _pagedItems;
    final totalFilteredCount = _filteredItems.length;
    // Disable reordering if searching or viewing a limited subset (to avoid tracking index mismatches with the main list)
    final bool canReorder = !_isSearching && _searchQuery.isEmpty && _itemsPerPage == -1;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: "Search items...",
                  hintStyle: TextStyle(color: Colors.white60),
                  border: InputBorder.none,
                ),
              )
            : const Text("Items"),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            tooltip: _isSearching ? "Clear Search" : "Search Items",
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.key),
            tooltip: "Modify Password",
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ModifyPasswordPage())),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              api.logout();
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
            },
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Showing ${visibleItems.length} of $totalFilteredCount items",
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      Row(
                        children: [
                          const Text("Show: ", style: TextStyle(fontSize: 13)),
                          DropdownButton<int>(
                            value: _itemsPerPage,
                            items: const [
                              DropdownMenuItem(value: 10, child: Text("10")),
                              DropdownMenuItem(value: 30, child: Text("30")),
                              DropdownMenuItem(value: 50, child: Text("50")),
                              DropdownMenuItem(value: 100, child: Text("100")),
                              DropdownMenuItem(value: -1, child: Text("All")),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _itemsPerPage = value;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: visibleItems.isEmpty
                      ? Center(
                          child: Text(
                            _searchQuery.isNotEmpty ? "No matching items found." : "No items stored in vault.",
                            style: const TextStyle(color: Colors.grey),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadItems,
                          child: ReorderableListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: visibleItems.length,
                            buildDefaultDragHandles: false,
                            onReorderItem: canReorder ? _onReorderItem : null,
                            itemBuilder: (ctx, idx) {
                              final name = visibleItems[idx];

                              return Card(
                                key: ValueKey(name),
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ListTile(
                                  title: Text(
                                    name,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.visibility,
                                          color: Colors.tealAccent,
                                        ),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => ShowItemPage(itemName: name),
                                            ),
                                          );
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.edit,
                                          color: Colors.deepPurpleAccent,
                                        ),
                                        onPressed: () async {
                                          await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => UpdateItemPage(itemName: name),
                                            ),
                                          );
                                          _loadItems();
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete,
                                          color: Colors.redAccent,
                                        ),
                                        onPressed: () => _confirmAndRemoveItem(name),
                                      ),

                                      if (canReorder)
                                        ReorderableDragStartListener(
                                          index: idx,
                                          child: const Padding(
                                            padding: EdgeInsets.only(left: 8),
                                            child: Icon(
                                              Icons.drag_handle,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.deepPurpleAccent,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const InsertItemPage()));
          _loadItems();
        },
      ),
    );
  }
}