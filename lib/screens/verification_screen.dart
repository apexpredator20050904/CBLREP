import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../config/community.dart';
import '../core/api_service.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});
  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  String barangay = trinidadBarangays.first;
  String documentType = 'Barangay certificate';
  File? document;
  bool submitting = false;

  Future<void> chooseDocument() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) setState(() => document = File(picked.path));
  }

  Future<void> submit() async {
    if (document == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a residency document first.')));
      return;
    }
    setState(() => submitting = true);
    try {
      await ApiService.instance.submitVerification(barangay: barangay, documentType: documentType, document: document!);
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification submitted for admin review.'))); Navigator.pop(context); }
    } on ApiException catch (exception) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(exception.message)));
    } finally { if (mounted) setState(() => submitting = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Residency verification')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Submit a document proving your residency in Trinidad, Bohol. An administrator will review it in the Verifications panel.', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
          DropdownButtonFormField(initialValue: barangay, decoration: const InputDecoration(labelText: 'Barangay'), items: trinidadBarangays.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(), onChanged: (value) => setState(() => barangay = value!)),
          const SizedBox(height: 12),
          DropdownButtonFormField(initialValue: documentType, decoration: const InputDecoration(labelText: 'Document type'), items: const ['Barangay certificate', 'Valid ID', 'Proof of address'].map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(), onChanged: (value) => setState(() => documentType = value!)),
          const SizedBox(height: 16),
          OutlinedButton.icon(onPressed: chooseDocument, icon: const Icon(Icons.attach_file), label: Text(document == null ? 'Choose document photo' : 'Document selected')),
          const SizedBox(height: 20),
          FilledButton(onPressed: submitting ? null : submit, child: Text(submitting ? 'Submitting…' : 'Submit for review')),
        ]),
      );
}
