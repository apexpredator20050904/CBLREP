import 'package:flutter/material.dart' hide Feedback;
import 'package:provider/provider.dart';
import '../config/community.dart';
import '../core/feedback.dart';
import '../core/input_sanitizer.dart';
import '../providers/auth_provider.dart';
import '../theme/cblrep_theme.dart';
import '../widgets/password_field.dart';

/// Spacing tokens so every gap on the form stays consistent across screen
/// sizes and resolutions.
const _screenPadding = 20.0;
const _fieldGap = 12.0;
const _sectionGap = 20.0;

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(), email = TextEditingController(), password = TextEditingController(), confirm = TextEditingController();
  String barangay = trinidadBarangays.first;

  /// Inline error message shown just above the Register button. It is part of
  /// the scroll layout, so unlike a floating snackbar it can never overlap or
  /// cut off the bottom padding / form elements while the keyboard is open.
  String? errorMessage;

  @override
  void dispose() { name.dispose(); email.dispose(); password.dispose(); confirm.dispose(); super.dispose(); }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => errorMessage = null); // clear the banner while retrying
    try {
      await context.read<AuthProvider>().register(
            name: InputSanitizer.name(name.text),
            email: InputSanitizer.email(email.text),
            barangay: barangay,
            password: password.text,
          );
      if (mounted) {
        Feedback.success(context, 'Welcome to CBLREP, ${InputSanitizer.name(name.text)}!');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          errorMessage = context.read<AuthProvider>().error ?? 'Registration failed. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewPaddingBottom = MediaQuery.viewPaddingOf(context).bottom;
    // Select only the loading flag — the whole form no longer rebuilds for
    // any other auth-provider change.
    final authLoading = context.select<AuthProvider, bool>((p) => p.loading);
    return Scaffold(
      appBar: AppBar(title: const Text('Create account', style: TextStyle(fontSize: 16))),
      body: Form(
        key: formKey,
        child: ListView(
          // Keep breathing room at the bottom for system nav bars / gesture
          // areas so the terms text is never flush against the screen edge.
          padding: EdgeInsets.fromLTRB(_screenPadding, 16, _screenPadding, _sectionGap + viewPaddingBottom),
          children: [
            const Center(child: CblrepLogo(radius: 30)),
            const SizedBox(height: 12),
            Text('Join your neighbourhood exchange',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('Members of Trinidad, Bohol can gift, barter and lend resources.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.black54)),
            const SizedBox(height: _sectionGap),
            TextFormField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
              validator: (v) => InputSanitizer.name(v ?? '').length >= 2 ? null : 'Enter your full name',
            ),
            const SizedBox(height: _fieldGap),
            TextFormField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
              validator: (v) {
                final clean = InputSanitizer.email(v ?? '');
                if (clean.isEmpty) return 'Email is required';
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(clean)) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: _fieldGap),
            DropdownButtonFormField(
              initialValue: barangay,
              decoration: const InputDecoration(labelText: 'Trinidad barangay', prefixIcon: Icon(Icons.location_on_outlined)),
              items: trinidadBarangays.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
              onChanged: (value) => setState(() => barangay = value!),
            ),
            const SizedBox(height: _fieldGap),
            PasswordField(
              controller: password,
              label: 'Password',
              textInputAction: TextInputAction.next,
              validator: (v) => v != null && v.length >= 8 ? null : 'Minimum 8 characters',
            ),
            const SizedBox(height: _fieldGap),
            PasswordField(
              controller: confirm,
              label: 'Confirm password',
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => submit(),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Re-type your password';
                if (v != password.text) return 'Passwords do not match';
                return null;
              },
            ),
            const SizedBox(height: _sectionGap),
            // Error banner + retry sit inside the form flow, directly above
            // the Register button — no overlap with bottom padding anywhere.
            if (errorMessage != null) ...[
              _ErrorBanner(
                message: errorMessage!,
                onRetry: submit,
                onDismiss: () => setState(() => errorMessage = null),
              ),
              const SizedBox(height: _fieldGap),
            ],
            FilledButton(
              onPressed: authLoading ? null : submit,
              child: Text(authLoading ? 'Creating account…' : 'Register'),
            ),
            const SizedBox(height: 8),
            const Text(
              'By registering you agree to share resources respectfully with your '
              'barangay. CBLREP staff review new listings for community safety.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline error banner with a Retry action. Rendered inside the form flow so
/// it sits cleanly above the Register button without overlapping the bottom
/// padding or any form element, in both light and dark themes.
class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  const _ErrorBanner({required this.message, required this.onRetry, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: CblrepColors.dangerRed.withValues(alpha: dark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CblrepColors.dangerRed.withValues(alpha: 0.45)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, size: 20, color: CblrepColors.dangerRed),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, style: TextStyle(fontSize: 12, color: dark ? Colors.white : Colors.black87)),
        ),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(
            foregroundColor: CblrepColors.dangerRed,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 2),
        SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            tooltip: 'Dismiss',
            padding: EdgeInsets.zero,
            iconSize: 18,
            icon: Icon(Icons.close, color: dark ? Colors.white54 : Colors.black45),
            onPressed: onDismiss,
          ),
        ),
      ]),
    );
  }
}
