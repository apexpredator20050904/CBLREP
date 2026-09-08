import 'package:flutter/material.dart';

class PostResourceDialog extends StatefulWidget {
  const PostResourceDialog({super.key});

  @override
  State<PostResourceDialog> createState() => _PostResourceDialogState();
}

class _PostResourceDialogState extends State<PostResourceDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _postedByController = TextEditingController(text: 'Zaki S.');
  String _selectedBrgy = 'Brgy 2';

  final List<String> _barangays = ['Brgy 1', 'Brgy 2', 'Brgy 3', 'Brgy 14'];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E3A27),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'POST A NEW RESOURCE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: _inputDecoration('Item / Resource Name'),
                validator: (value) =>
                value == null || value.trim().isEmpty ? 'Please enter a title' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _postedByController,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: _inputDecoration('Your Name'),
                validator: (value) =>
                value == null || value.trim().isEmpty ? 'Please enter your name' : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _selectedBrgy,
                dropdownColor: const Color(0xFF1E3A27),
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: _inputDecoration('Select Barangay'),
                items: _barangays.map((brgy) {
                  return DropdownMenuItem(
                    value: brgy,
                    child: Text(brgy, style: const TextStyle(color: Colors.white)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedBrgy = val);
                },
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white38),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('CANCEL', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD9822B),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          Navigator.pop(context, {
                            'title': _titleController.text.trim().toUpperCase(),
                            'postedBy': _postedByController.text.trim(),
                            'brgy': _selectedBrgy,
                          });
                        }
                      },
                      child: const Text('SUBMIT', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70, fontSize: 11),
      filled: true,
      fillColor: const Color(0xFF2E5339),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide.none,
      ),
    );
  }
}