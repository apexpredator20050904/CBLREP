import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../config/community.dart';
import '../core/api_service.dart';

class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({super.key});
  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController(), description = TextEditingController(), category = TextEditingController(text: 'General');
  String type = 'offer', exchangeType = 'Lend', condition = 'Good', barangay = trinidadBarangays.first;
  File? image;
  bool saving = false;

  @override
  void dispose() { title.dispose(); description.dispose(); category.dispose(); super.dispose(); }

  Future<void> pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) setState(() => image = File(picked.path));
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await ApiService.instance.createListing(title: title.text.trim(), type: type, description: description.text.trim(), category: category.text.trim(), exchangeType: exchangeType, condition: condition, location: barangay, image: image);
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Resource posted successfully.'))); Navigator.pop(context); }
    } on ApiException catch (exception) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(exception.message)));
    } finally { if (mounted) setState(() => saving = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Post a resource')),
        body: Form(
          key: formKey,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            SegmentedButton<String>(segments: const [ButtonSegment(value: 'offer', label: Text('Offer'), icon: Icon(Icons.volunteer_activism)), ButtonSegment(value: 'request', label: Text('Need'), icon: Icon(Icons.help_outline))], selected: {type}, onSelectionChanged: (value) => setState(() => type = value.first)),
            const SizedBox(height: 12),
            TextFormField(controller: title, decoration: const InputDecoration(labelText: 'Title'), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
            const SizedBox(height: 12),
            TextFormField(controller: description, maxLines: 4, decoration: const InputDecoration(labelText: 'Description')),
            const SizedBox(height: 12),
            TextFormField(controller: category, decoration: const InputDecoration(labelText: 'Category')),
            const SizedBox(height: 12),
            DropdownButtonFormField(initialValue: exchangeType, decoration: const InputDecoration(labelText: 'Exchange mode'), items: const ['Freecycle', 'Barter', 'Lend'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(), onChanged: (value) => setState(() => exchangeType = value!)),
            const SizedBox(height: 12),
            DropdownButtonFormField(initialValue: condition, decoration: const InputDecoration(labelText: 'Condition'), items: const ['New', 'Good', 'Needs repair'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(), onChanged: (value) => setState(() => condition = value!)),
            const SizedBox(height: 12),
            DropdownButtonFormField(initialValue: barangay, decoration: const InputDecoration(labelText: 'Trinidad barangay'), items: trinidadBarangays.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(), onChanged: (value) => setState(() => barangay = value!)),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: pickImage, icon: const Icon(Icons.photo_library_outlined), label: Text(image == null ? 'Add item photo' : 'Photo selected')),
            const SizedBox(height: 20),
            FilledButton(onPressed: saving ? null : save, child: Text(saving ? 'Posting…' : 'Post resource')),
          ]),
        ),
      );
}
