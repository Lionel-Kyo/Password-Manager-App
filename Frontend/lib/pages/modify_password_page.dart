import 'dart:async';
import 'package:flutter/material.dart';
import 'package:password_manager_app/service/api_client_service.dart';

class ModifyPasswordPage extends StatefulWidget {
  const ModifyPasswordPage({super.key});

  @override
  State<ModifyPasswordPage> createState() => _ModifyPasswordPageState();
}

class _ModifyPasswordPageState extends State<ModifyPasswordPage> {
  final _oldPwdCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _modify() async {
    if (_oldPwdCtrl.text.isEmpty || _newPwdCtrl.text.isEmpty) return;

    setState(() => _loading = true);
    try {
      final res = await api.sendCommand({
        "action": "ModifyPassword",
        "old_password": _oldPwdCtrl.text,
        "new_password": _newPwdCtrl.text,
      });

      if (res["success"] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Password updated!")),
        );
        Navigator.pop(context);
      } else {
        _showError(res["error"] ?? "Failed to update password");
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Modify Password")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              children: [
                TextField(controller: _oldPwdCtrl, obscureText: true, decoration: const InputDecoration(labelText: "Current Password")),
                const SizedBox(height: 16),
                TextField(controller: _newPwdCtrl, obscureText: true, decoration: const InputDecoration(labelText: "New Password")),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _modify,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                    child: _loading ? const CircularProgressIndicator() : const Text("Update", style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
