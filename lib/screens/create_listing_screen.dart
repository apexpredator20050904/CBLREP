import 'dart:io';
import 'package:flutter/material.dart' hide Feedback;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/community.dart';
import '../core/api_service.dart';
import '../core/feedback.dart';
import '../providers/listings_provider.dart';
import '../theme/cblrep_theme.dart';

/// Post Listing — offers & needs with category, exchange mode (freecycle /
/// barter / lend), condition, barangay and camera/gallery photo upload.
class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({super.key});
  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController(), description = TextEditingController();
  String category = 'Tools';
  String type = 'offer', exchangeType = 'Lend', condition = 'Good', barangay = trinidadBarangays.first;
  File? image;
  bool saving = false;

  static const categories = ['Tools', 'Food', 'Clothing', 'Furniture', 'Electronics', 'Books', 'Skills', 'Services', 'Plants', 'Other'];

  @override
  void dispose() { title.dispose(); description.dispose(); super.dispose(); }

  Future<void> pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 80, maxWidth: 1600);
    if (picked != null) setState(() => image = File(picked.path));
  }

  void _photoSheet() {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'), onTap: () { Navigator.pop(c); pickImage(ImageSource.camera); }),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), onTap: () { Navigator.pop(c); pickImage(ImageSource.gallery); }),
          if (image != null) ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Remove photo'), onTap: () { Navigator.pop(c); setState(() => image = null); }),
        ]),
      ),
    );
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => saving = true);
    try {
      await context.read<ListingsProvider>().create(
            title: title.text.trim(),
            type: type,
            description: description.text.trim(),
            category: category,
            exchangeType: exchangeType,
            condition: condition,
            location: barangay,
            image: image,
          );
      if (!mounted) return;
      Feedback.success(context, 'Resource posted successfully.');
      Navigator.pop(context, true);
    } on ApiException catch (exception) {
      if (mounted) Feedback.error(context, exception.message, onRetry: save);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? CblrepColors.deepForest : null,
      appBar: AppBar(title: const Text('Post a resource', style: TextStyle(fontSize: 16))),
      body: Form(
        key: formKey,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'offer', label: Text('Offer'), icon: Icon(Icons.volunteer_activism)), ButtonSegment(value: 'request', label: Text('Need'), icon: Icon(Icons.help_outline))],
            selected: {type},
            onSelectionChanged: (value) => setState(() => type = value.first),
          ),
          const SizedBox(height: 12),
          TextFormField(controller: title, decoration: const InputDecoration(labelText: 'Title'), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
          const SizedBox(height: 12),
          TextFormField(controller: description, maxLines: 4, decoration: const InputDecoration(labelText: 'Description (what, why, pickup notes)')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: categories.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
            onChanged: (value) => setState(() => category = value ?? category),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField(
            initialValue: exchangeType,
            decoration: const InputDecoration(labelText: 'Exchange mode'),
            items: const [DropdownMenuItem(value: 'Freecycle', child: Text('Freecycle — free gifting')), DropdownMenuItem(value: 'Barter', child: Text('Barter — direct swap')), DropdownMenuItem(value: 'Lend', child: Text('Lend — temporary, scheduled return'))],
            onChanged: (value) => setState(() => exchangeType = value!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField(
            initialValue: condition,
            decoration: const InputDecoration(labelText: 'Condition'),
            items: const ['New', 'Good', 'Needs repair'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
            onChanged: (value) => setState(() => condition = value!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField(
            initialValue: barangay,
            decoration: const InputDecoration(labelText: 'Trinidad barangay'),
            items: trinidadBarangays.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
            onChanged: (value) => setState(() => barangay = value!),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _photoSheet,
            child: Container(
              height: 150,
              decoration: BoxDecoration(color: dark ? CblrepColors.fieldGreen : const Color(0xFFEFE9DA), borderRadius: BorderRadius.circular(12), border: Border.all(color: dark ? Colors.white12 : Colors.black12)),
              child: image == null
                  ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo_outlined, size: 30), SizedBox(height: 6), Text('Add item photo (camera or gallery)', style: TextStyle(fontSize: 11))])
                  : ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(image!, fit: BoxFit.cover, width: double.infinity)),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: saving ? null : save, child: Text(saving ? 'Posting…' : 'Post resource')),
        ]),
      ),
    );
  }
}
