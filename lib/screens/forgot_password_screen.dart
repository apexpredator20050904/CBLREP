import 'package:flutter/material.dart' hide Feedback;
import '../config/community.dart';
import '../core/api_service.dart';
import '../core/feedback.dart';
import '../core/input_sanitizer.dart';
import '../theme/cblrep_theme.dart';
import 'reset_password_screen.dart';

/// Step 1 of password recovery — ask the backend to e-mail a reset code.
class ForgotPasswordScreen extends StatefulWidget {
  /// Pre-fills the field when the member tapped "Forgot password?" on login.
  final String email;

  const ForgotPasswordScreen({super.key, this.email = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController email = TextEditingController(text: widget.email);
  bool sending = false;

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (!formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => sending = true);
    try {
      final result = await ApiService.instance.requestPasswordReset(email.text);
      if (!mounted) return;
      Feedback.success(context, '${result['message'] ?? 'Reset code sent.'}');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResetPasswordScreen(
            email: InputSanitizer.email(email.text),
            // Only populated by a local debug backend; null in production.
            suggestedCode: result['dev_code'] as String?,
          ),
        ),
      );
    } on ApiException catch (exception) {
      if (mounted) {
        Feedback.error(context, exception.message, onRetry: send);
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? CblrepColors.deepForest : null,
      appBar: AppBar(title: const Text('Forgot password', style: TextStyle(fontSize: 16))),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Center(child: CblrepLogo(radius: 34)),
            const SizedBox(height: 16),
            Text('Reset your password',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text(
              'Enter the e-mail address registered to your CBLREP account and we will '
              'send a 6-digit code to set a new password.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => send(),
              decoration: const InputDecoration(
                labelText: 'Registered e-mail',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (value) {
                final clean = InputSanitizer.email(value ?? '');
                if (clean.isEmpty) return 'E-mail is required';
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(clean)) {
                  return 'Enter a valid e-mail address';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 46,
              child: FilledButton.icon(
                onPressed: sending ? null : send,
                icon: sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_outlined, size: 18),
                label: Text(sending ? 'Sending code…' : 'Send reset code'),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Codes expire after 15 minutes and can only be used once. '
              'CBLREP never e-mails a link that asks for your password.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: dark ? Colors.white38 : Colors.black45),
            ),
            const SizedBox(height: 6),
            Text(communityName,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: dark ? Colors.white38 : Colors.black38)),
          ],
        ),
      ),
    );
  }
}
