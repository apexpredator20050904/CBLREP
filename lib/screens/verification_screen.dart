import 'dart:io';
import 'package:flutter/material.dart' hide Feedback;
import 'package:image_picker/image_picker.dart';
import '../config/community.dart';
import '../core/api_service.dart';
import '../core/feedback.dart';

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
      Feedback.info(context, 'Choose a residency document first.');
      return;
    }
    setState(() => submitting = true);
    try {
      await ApiService.instance.submitVerification(
          barangay: barangay, documentType: documentType, document: document!);
      if (!mounted) return;
      await Feedback.alert(
        context,
        title: 'Verification submitted',
        message: 'Your $documentType for $barangay is now queued for admin review. '
            'You will be notified once a decision is made.',
        icon: Icons.verified_outlined,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (exception) {
      if (mounted) Feedback.error(context, exception.message, onRetry: submit);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
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
