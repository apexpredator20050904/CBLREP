import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';
import 'verification_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.person)), title: Text(user?.name ?? ''), subtitle: Text(user?.email ?? ''))),
        Card(child: Column(children: [
          ListTile(leading: const Icon(Icons.location_on_outlined), title: const Text('Barangay'), subtitle: Text(user?.barangay ?? '')),
          ListTile(leading: const Icon(Icons.verified_outlined), title: const Text('Verification'), subtitle: Text(user?.verificationStatus ?? 'Pending')),
          ListTile(leading: const Icon(Icons.timelapse), title: const Text('Time-bank credits'), trailing: Text('${user?.credits ?? 0}')),
        ])),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VerificationScreen())),
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Submit residency verification'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(onPressed: () async { await context.read<AuthProvider>().logout(); if (context.mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false); }, icon: const Icon(Icons.logout), label: const Text('Sign out')),
      ]),
    );
  }
}
