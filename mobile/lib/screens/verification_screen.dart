import 'dart:io';
import 'package:flutter/material.dart' hide Feedback;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/community.dart';
import '../core/api_service.dart';
import '../core/feedback.dart';
import '../providers/auth_provider.dart';
import '../theme/cblrep_theme.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});
  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  @override
  void dispose() {
    purok.dispose();
    super.dispose();
  }

  String barangay = trinidadBarangays.first;
  final purok = TextEditingController();
  String documentType = 'Barangay certificate';
  File? document;
  bool submitting = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill the barangay from the member's profile when it is one of the
    // known Trinidad barangays.
    final saved = context.read<AuthProvider>().user?.barangay;
    if (saved != null && trinidadBarangays.contains(saved)) {
      barangay = saved;
    final savedPurok = context.read<AuthProvider>().user?.purokSitio;
    if (savedPurok != null && savedPurok.isNotEmpty) purok.text = savedPurok;
    }
  }

  /// Capture a fresh photo or import an existing one from the gallery.
  Future<void> chooseDocument() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (picked != null && mounted) setState(() => document = File(picked.path));
  }

  Future<void> submit() async {
    if (document == null) {
      Feedback.info(context, 'Choose or capture a residency document first.');
      return;
    }
    if (purok.text.trim().isEmpty) {
      Feedback.info(context, 'Enter your purok or sitio first.');
      return;
    }
    setState(() => submitting = true);
    try {
      await ApiService.instance.submitVerification(
          barangay: barangay, purokSitio: purok.text.trim(), documentType: documentType, document: document!);
      if (!mounted) return;
      // Pull the new `pending` status so the profile badge updates at once.
      await context.read<AuthProvider>().refreshVerification();
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
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final status = auth.user?.verificationStatus ?? 'Unverified';
    final hasPhoto = auth.user?.avatarUrl?.isNotEmpty ?? false;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Residency verification')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _StatusBanner(status: status),
        const SizedBox(height: 16),
        Text('Submit a document proving your residency in Trinidad, Bohol. An administrator will review it in the Verification queue.', style: TextStyle(color: dark ? Colors.white70 : Colors.black54)),
        // Encouraged, never required: a profile photo helps neighbours (and
        // the reviewing admin) recognise the member, but verification is about
        // the residency document.
        if (!hasPhoto)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lightbulb_outline, size: 16, color: dark ? Colors.white54 : Colors.black45),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tip: add a profile photo from your Profile page so neighbours recognise you. It is optional and not required for verification.',
                  style: TextStyle(fontSize: 11, color: dark ? Colors.white54 : Colors.black45),
                ),
              ),
            ]),
          ),
        if (status != 'Verified') ...[
          const SizedBox(height: 16),
          const _VerificationBenefits(),
        ],
        const SizedBox(height: 16),
        DropdownButtonFormField(initialValue: barangay, decoration: const InputDecoration(labelText: 'Barangay'), items: trinidadBarangays.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(), onChanged: (value) => setState(() => barangay = value!)),
        const SizedBox(height: 12),
        TextFormField(controller: purok, decoration: const InputDecoration(labelText: 'Purok / Sitio')),
        const SizedBox(height: 12),
        DropdownButtonFormField(initialValue: documentType, decoration: const InputDecoration(labelText: 'Document type'), items: const ['Barangay certificate', 'Valid ID', 'Proof of address'].map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(), onChanged: (value) => setState(() => documentType = value!)),
        const SizedBox(height: 16),
        OutlinedButton.icon(onPressed: chooseDocument, icon: const Icon(Icons.attach_file), label: Text(document == null ? 'Capture or choose document photo' : 'Document selected')),
        const SizedBox(height: 20),
        FilledButton(onPressed: submitting ? null : submit, child: Text(submitting ? 'Submitting…' : 'Submit for review')),
      ]),
    );
  }
}

/// Small status pill so the member always sees where they stand in the
/// submission → review workflow.
class _StatusBanner extends StatelessWidget {
  final String status;
  const _StatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (status) {
      'Verified' => (CblrepColors.successGreen, Icons.verified),
      'Pending' => (CblrepColors.actionOrange, Icons.hourglass_top),
      'Rejected' => (CblrepColors.dangerRed, Icons.error_outline),
      _ => (Colors.blueGrey, Icons.verified_outlined),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text('Current status: $status', style: TextStyle(fontWeight: FontWeight.bold, color: color))),
      ]),
    );
  }
}

/// What a member actually gets once an admin confirms their residency — shown
/// while they are still unverified, so the ask ("submit a document") carries a
/// visible payoff.
class _VerificationBenefits extends StatelessWidget {
  const _VerificationBenefits();

  static const List<(IconData, String)> _benefits = [
    (Icons.verified_user, 'A "Verified resident" badge on your profile and listings.'),
    (Icons.trending_up, 'Your listings are shown first in the browse feed.'),
    (Icons.all_inclusive, 'Post as many listings as you like — the unverified posting limit is lifted.'),
    (Icons.campaign_outlined, 'Barangay announcements targeted to verified residents.'),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? CblrepColors.darkCardGreen : const Color(0xFFF1FAF3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CblrepColors.successGreen.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Why get verified?', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (final (icon, text) in _benefits)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 16, color: CblrepColors.successGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(fontSize: 12, color: dark ? Colors.white70 : Colors.black54),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}
