import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/community.dart';
import '../providers/auth_provider.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final formKey = GlobalKey<FormState>();

  @override
  void dispose() { email.dispose(); password.dispose(); super.dispose(); }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    try {
      await context.read<AuthProvider>().login(email.text, password.text);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.read<AuthProvider>().error ?? 'Login failed.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.eco, size: 68, color: Color(0xFF1B3B22)),
                    const SizedBox(height: 12),
                    Text('CBLRE', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF1B3B22))),
                    Text(communityName, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
                    const SizedBox(height: 32),
                    TextFormField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)), validator: (value) => value != null && value.contains('@') ? null : 'Enter a valid email'),
                    const SizedBox(height: 12),
                    TextFormField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)), validator: (value) => value != null && value.length >= 8 ? null : 'Minimum 8 characters'),
                    const SizedBox(height: 20),
                    FilledButton(onPressed: context.watch<AuthProvider>().loading ? null : submit, child: const Text('Sign in')),
                    TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())), child: const Text('Create a member account')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
