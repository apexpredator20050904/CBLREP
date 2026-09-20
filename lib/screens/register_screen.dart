import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/community.dart';
import '../providers/auth_provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(), email = TextEditingController(), password = TextEditingController();
  String barangay = trinidadBarangays.first;

  @override
  void dispose() { name.dispose(); email.dispose(); password.dispose(); super.dispose(); }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    try {
      await context.read<AuthProvider>().register(name: name.text.trim(), email: email.text.trim(), barangay: barangay, password: password.text);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.read<AuthProvider>().error ?? 'Registration failed.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Create account')),
        body: Form(
          key: formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Full name'), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
              const SizedBox(height: 12),
              TextFormField(controller: email, decoration: const InputDecoration(labelText: 'Email'), validator: (v) => v != null && v.contains('@') ? null : 'Enter a valid email'),
              const SizedBox(height: 12),
              DropdownButtonFormField(initialValue: barangay, decoration: const InputDecoration(labelText: 'Trinidad barangay'), items: trinidadBarangays.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(), onChanged: (value) => setState(() => barangay = value!)),
              const SizedBox(height: 12),
              TextFormField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password'), validator: (v) => v != null && v.length >= 8 ? null : 'Minimum 8 characters'),
              const SizedBox(height: 20),
              FilledButton(onPressed: context.watch<AuthProvider>().loading ? null : submit, child: const Text('Register')),
            ],
          ),
        ),
      );
}
