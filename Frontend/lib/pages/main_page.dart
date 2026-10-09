import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:password_manager_app/pages/insert_item_page.dart';
import 'package:password_manager_app/pages/login_page.dart';
import 'package:password_manager_app/pages/modify_password_page.dart';
import 'package:password_manager_app/pages/show_item_page.dart';
import 'package:password_manager_app/pages/update_item_page.dart';
import 'package:password_manager_app/service/api_client_service.dart';

class DesktopScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

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
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
        _currentPage = 0;
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

  int get _totalPages {
    if (_itemsPerPage == -1 || _filteredItems.isEmpty) return 1;
    return (_filteredItems.length / _itemsPerPage).ceil();
  }

  List<String> get _pagedItems {
    final filtered = _filteredItems;
    if (_itemsPerPage == -1 || filtered.isEmpty) {
      return filtered;
    }
    
    if (_currentPage >= _totalPages) {
      _currentPage = _totalPages > 0 ? _totalPages - 1 : 0;
    }

    final startIndex = _currentPage * _itemsPerPage;
    if (startIndex >= filtered.length) {
      return [];
    }
    final endIndex = (startIndex + _itemsPerPage < filtered.length)
        ? startIndex + _itemsPerPage
        : filtered.length;
        
    return filtered.sublist(startIndex, endIndex);
  }

  void _showError(String msg) {
    if (mounted)  {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    try {
      final res = await api.sendCommand({"action": "GetItemNames"});
      if (res["success"] == true) {
        setState(() {
          _items = List<String>.from(res["item_names"] ?? []);
        });
      } else {
        _showError(res["error"] ?? "Failed to load items");
        if (ApiClient.isUnauthorizedOrSessionExpiredErrorMsg(res)) {
          if (mounted){
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
              (route) => false,
            );
          }
        }
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveOrder() async {
    try {
      final res = await api.sendCommand({
        "action": "UpdateItemOrder",
        "ordered_item_names": _items,
      });
      if (res["success"] != true) {
        _showError(res["error"] ?? "Failed to save order");
        if (ApiClient.isUnauthorizedOrSessionExpiredErrorMsg(res)) {
          if (mounted){
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
              (route) => false,
            );
          }
        }
      }
    } catch (e) {
      _showError(e.toString());
      _loadItems();
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
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
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
      } else {
        _showError(res["error"] ?? "Failed to remove item");
        if (ApiClient.isUnauthorizedOrSessionExpiredErrorMsg(res)) {
          if (mounted){
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
              (route) => false,
            );
          }
        }
      }
    } catch (e) {
      _showError(e.toString());
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
                              _currentPage = 0;
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
                  : ScrollConfiguration(
                      behavior: DesktopScrollBehavior(),
                      child:  RefreshIndicator(
                        onRefresh: _loadItems,
                        child: ReorderableListView.builder(
                          padding: const EdgeInsets.only(left: 16.0, top: 16.0, right: 16.0, bottom: 64.0),
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
            ),
            if (_itemsPerPage != -1 && _totalPages > 1)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 64.0, vertical: 10.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade800),
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ElevatedButton.icon(
                        onPressed: _currentPage > 0
                            ? () => setState(() => _currentPage--)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                        label: const Text("Previous"),
                      ),
                    ),
                    Text(
                      "Page ${_currentPage + 1} of $_totalPages",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: _currentPage < _totalPages - 1
                            ? () => setState(() => _currentPage++)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                        label: const Text("Next"),
                      ),
                    ),
                  ],
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