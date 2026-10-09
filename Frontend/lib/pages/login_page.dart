import 'dart:async';
import 'package:flutter/material.dart';
import 'package:password_manager_app/pages/main_page.dart';
import 'package:password_manager_app/pages/register_page.dart';
import 'package:password_manager_app/service/api_client_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _accCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  Future<void> _login() async {
    if (_accCtrl.text.isEmpty || _pwdCtrl.text.isEmpty) return;

    setState(() => _loading = true);
    try {
      await api.login(
        _accCtrl.text,
        _pwdCtrl.text,
      );

      if (mounted){
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainPage()),
        );
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    if (mounted)  {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.shield_outlined, size: 72, color: Colors.deepPurpleAccent),
                const SizedBox(height: 16),
                const Text("Password Manager", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 32),
                TextField(
                  controller: _accCtrl,
                  decoration: const InputDecoration(labelText: "Account", prefixIcon: Icon(Icons.person)),
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _loading ? null : _login(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pwdCtrl,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _loading ? null : _login(),
                  decoration: InputDecoration(
                    labelText: "Password",
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("Login", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage()));
                  },
                  child: const Text("Don't have an account? Register"),
                ),
                IconButton(
                  icon: const Icon(Icons.settings, color: Colors.grey),
                  onPressed: _showServerDialog,
                  tooltip: "Server Settings",
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showServerDialog() {
    final hCtrl = TextEditingController(text: api.host);
    final pCtrl = TextEditingController(text: api.port.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Server Settings"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: hCtrl, decoration: const InputDecoration(labelText: "IP / Host"), readOnly: ApiClient.isReleaseWeb()),
            const SizedBox(height: 12),
            TextField(controller: pCtrl, decoration: const InputDecoration(labelText: "Port"), readOnly: ApiClient.isReleaseWeb(), keyboardType: TextInputType.number,),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (!ApiClient.isReleaseWeb()) {
                final parsedPort = int.tryParse(pCtrl.text);
                if (parsedPort == null) {
                  return; 
                }
                await ApiClient.saveSettings(hCtrl.text, parsedPort);
                api.host = hCtrl.text;
                api.port = parsedPort;
                api.disconnect();
              }
              if (context.mounted) {
                Navigator.pop(ctx);
              }
            },
            child: Text(ApiClient.isReleaseWeb() ? "Close" : "Save & Reconnect"),
          )
        ],
      ),
    );
  }
}
