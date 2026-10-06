import 'dart:async';
import 'package:flutter/material.dart';
import 'package:password_manager_app/service/api_client_service.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _accCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _register() async {
    if (_accCtrl.text.isEmpty || _pwdCtrl.text.isEmpty) return;

    setState(() => _loading = true);
    try {
      final res = await api.sendCommand({
        "action": "Register",
        "account": _accCtrl.text,
        "password": _pwdCtrl.text,
      });

      if (res["success"] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Account created successfully! Please login.")),
        );
        Navigator.pop(context);
      } else {
        _showError(res["error"] ?? "Registration failed");
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
      appBar: AppBar(title: const Text("Create Account")),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              children: [
                TextField(controller: _accCtrl, decoration: const InputDecoration(labelText: "Account")),
                const SizedBox(height: 16),
                TextField(controller: _pwdCtrl, obscureText: true, decoration: const InputDecoration(labelText: "Password")),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _register,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent),
                    child: _loading
                        ? const CircularProgressIndicator()
                        : const Text("REGISTER", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
