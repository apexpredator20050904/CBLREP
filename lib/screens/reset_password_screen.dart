import 'package:flutter/material.dart' hide Feedback;
import '../core/api_service.dart';
import '../core/feedback.dart';
import '../theme/cblrep_theme.dart';
import '../widgets/password_field.dart';

/// Step 2 of password recovery — redeem the mailed code for a new password.
class ResetPasswordScreen extends StatefulWidget {
  final String email;

  /// Populated only by a debug backend (MAIL_MAILER=log) so the flow can be
  /// exercised without a real inbox; always null in production.
  final String? suggestedCode;

  const ResetPasswordScreen({super.key, required this.email, this.suggestedCode});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController code =
      TextEditingController(text: widget.suggestedCode ?? '');
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool saving = false;

  @override
  void dispose() {
    code.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => saving = true);
    try {
      final result = await ApiService.instance.resetPassword(
        email: widget.email,
        code: code.text,
        password: password.text,
        passwordConfirmation: confirm.text,
      );
      if (!mounted) return;
      await Feedback.alert(
        context,
        title: 'Password updated',
        message: '${result['message'] ?? 'You can now sign in with your new password.'}\n\n'
            'For your security every other device has been signed out.',
        icon: Icons.lock_reset,
      );
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (exception) {
      if (mounted) Feedback.error(context, exception.message, onRetry: submit);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? CblrepColors.deepForest : null,
      appBar: AppBar(title: const Text('Set a new password', style: TextStyle(fontSize: 16))),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Center(child: CblrepLogo(radius: 30)),
            const SizedBox(height: 14),
            Text('Enter the code we sent to\n${widget.email}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 18),
            if (widget.suggestedCode != null)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CblrepColors.goldHighlight.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(children: [
                  Icon(Icons.developer_mode, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Local debug build: the backend returned the code inline '
                      'because MAIL_MAILER=log. It is pre-filled below.',
                      style: TextStyle(fontSize: 10.5),
                    ),
                  ),
                ]),
              ),
            TextFormField(
              controller: code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(letterSpacing: 8, fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                labelText: '6-digit reset code',
                prefixIcon: Icon(Icons.pin_outlined),
                counterText: '',
              ),
              validator: (value) {
                final clean = (value ?? '').trim();
                if (clean.isEmpty) return 'Enter the code from your e-mail';
                if (!RegExp(r'^\d{6}$').hasMatch(clean)) return 'The code is 6 digits';
                return null;
              },
            ),
            const SizedBox(height: 14),
            PasswordField(
              controller: password,
              label: 'New password',
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.isEmpty) return 'Choose a new password';
                if (value.length < 8) return 'Minimum 8 characters';
                return null;
              },
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: confirm,
              label: 'Confirm new password',
              validator: (value) {
                if (value == null || value.isEmpty) return 'Re-type the new password';
                if (value != password.text) return 'Passwords do not match';
                return null;
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 46,
              child: FilledButton.icon(
                onPressed: saving ? null : submit,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.lock_reset, size: 18),
                label: Text(saving ? 'Updating…' : 'Update password'),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Choosing a new password here signs out every other device.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }
}
