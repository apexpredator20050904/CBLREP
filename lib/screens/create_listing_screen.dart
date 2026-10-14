import 'dart:io';
import 'package:flutter/material.dart' hide Feedback;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/community.dart';
import '../core/api_service.dart';
import '../core/feedback.dart';
import '../providers/listings_provider.dart';
import '../theme/cblrep_theme.dart';

/// Post Listing — offers & needs with category, condition, barangay and
/// camera/gallery photo upload. CBLREP runs on direct bartering only, so a
/// listing carries no exchange-mode field.
class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({super.key});
  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController(), description = TextEditingController(), purok = TextEditingController();
  final price = TextEditingController();
  // The return side of a barter — what the member hopes to receive. Ignored
  // for free/paid listings, which have no return side.
  final wanted = TextEditingController();
  String category = 'Tools';
  String type = 'offer', condition = 'Good', barangay = trinidadBarangays.first;
  // Flexible compensation: free | barter | paid.
  String compensation = 'barter';
  File? image;
  bool saving = false;

  static const categories = ['Tools', 'Food', 'Clothing', 'Furniture', 'Electronics', 'Books', 'Skills', 'Services', 'Plants', 'Other'];

  static const _compensationCopy = {
    'free': 'Free sharing — you are giving this away at no cost.',
    'barter': 'Barter — a neighbour offers an item or skill in return.',
    'paid': 'Paid — set a price and neighbours can inquire to buy.',
  };

  @override
  void dispose() { title.dispose(); description.dispose(); purok.dispose(); price.dispose(); wanted.dispose(); super.dispose(); }

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
            condition: condition,
            location: '$barangay, ${purok.text.trim()}',
            barangay: barangay,
            purokSitio: purok.text.trim(),
            // Only a paid listing carries a price; free/barter send none.
            compensationType: compensation,
            price: compensation == 'paid' ? double.tryParse(price.text.trim()) : null,
            wantedItem: compensation == 'barter' ? wanted.text.trim() : null,
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
            // isExpanded bounds the button to the field width so a long category
            // name cannot overflow the form on a narrow phone.
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category'),
            items: categories
                .map((value) => DropdownMenuItem(
                      value: value,
                      child: Text(value, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (value) => setState(() => category = value ?? category),
          ),
          const SizedBox(height: 12),
          // How the member wants to share: Free, Barter or Paid. This is the
          // flexible-compensation choice the whole portal is built around.
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'free', label: Text('Free'), icon: Icon(Icons.card_giftcard)),
              ButtonSegment(value: 'barter', label: Text('Barter'), icon: Icon(Icons.swap_horiz)),
              ButtonSegment(value: 'paid', label: Text('Paid'), icon: Icon(Icons.sell_outlined)),
            ],
            selected: {compensation},
            onSelectionChanged: (value) => setState(() => compensation = value.first),
          ),
          const SizedBox(height: 8),
          _CompensationNotice(type: compensation, copy: _compensationCopy[compensation]!),
          // Barter only: the poster's own return wish. Naming it up front is
          // what lets a neighbour offer the right thing instead of guessing —
          // the mirror of the "Make a trade offer" sheet on the other side.
          if (compensation == 'barter') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: wanted,
              maxLength: 160,
              decoration: const InputDecoration(
                labelText: 'In return, I would like (optional)',
                helperText: 'e.g. 5 kg of rice, or an hour of plumbing help',
              ),
            ),
          ],
          if (compensation == 'paid') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Price (₱)', prefixText: '₱ '),
              validator: (v) {
                if (compensation != 'paid') return null;
                final parsed = double.tryParse((v ?? '').trim());
                if (parsed == null) return 'Enter a price';
                if (parsed <= 0) return 'Price must be greater than zero';
                return null;
              },
            ),
          ],
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
          TextFormField(
            controller: purok,
            decoration: const InputDecoration(labelText: 'Purok / Sitio'),
            validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'Enter the purok or sitio';
                if (!t.startsWith('Purok') && !t.startsWith('Sitio')) return 'Use a format like "Purok 3" or "Sitio Name"';
                return null;
              },
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

/// Read-only banner describing the selected sharing mode. Colour-coded so the
/// three compensation types read as clearly on the form as they do on a card.
class _CompensationNotice extends StatelessWidget {
  final String type;
  final String copy;
  const _CompensationNotice({required this.type, required this.copy});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (Color accent, IconData icon) = switch (type) {
      'free' => (CblrepColors.compFree, Icons.card_giftcard),
      'paid' => (CblrepColors.compPaid, Icons.sell_outlined),
      _ => (CblrepColors.compBarter, Icons.swap_horiz),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? CblrepColors.darkCardGreen : const Color(0xFFEFE9DA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dark ? Colors.white12 : Colors.black12),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(copy, style: const TextStyle(fontSize: 11, height: 1.35)),
        ),
      ]),
    );
  }
}
