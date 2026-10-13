import 'package:flutter/material.dart' hide Feedback;
import 'package:provider/provider.dart';
import '../config/community.dart';
import '../core/feedback.dart';
import '../core/input_sanitizer.dart';
import '../core/session_prefs.dart';
import '../providers/auth_provider.dart';
import '../theme/cblrep_theme.dart';
import '../widgets/cblrep_shell.dart';
import '../widgets/password_field.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final formKey = GlobalKey<FormState>();

  /// Initial state of the "Remember me" box; replaced with the member's
  /// saved preference (and their e-mail, if the last sign-in was remembered)
  /// as soon as the preferences load.
  bool rememberMe = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final remember = await SessionPrefs.rememberPreference();
    final savedEmail = await SessionPrefs.rememberedEmail();
    if (!mounted) return;
    setState(() {
      rememberMe = remember;
      if (savedEmail != null && savedEmail.isNotEmpty && email.text.isEmpty) {
        email.text = savedEmail;
      }
    });
  }

  @override
  void dispose() { email.dispose(); password.dispose(); super.dispose(); }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final auth = context.read<AuthProvider>();
    // The banner is dismissed once a new attempt starts, so a failed retry
    // does not leave stale "session ended" text above the form.
    if (auth.sessionExpired) auth.clearSessionExpiredNotice();
    try {
      await auth.login(email.text, password.text, rememberMe: rememberMe);
      if (!mounted) return;
      Feedback.success(context, 'Signed in. Welcome back!');
      // Replace the whole auth stack: a signed-in member lands on the
      // dashboard immediately and Back can never return to the login screen.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const CblrepShell()),
        (route) => false,
      );
    } catch (_) {
      if (mounted) {
        Feedback.error(
          context,
          context.read<AuthProvider>().error ?? 'Login failed. Please try again.',
          onRetry: submit,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: dark ? const [Color(0xFF2E5339), Color(0xFF142B1D)] : const [Color(0xFFF5EFE2), Color(0xFFE8DCC3)]),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: formKey,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // Why the member is back here after a session that looked
                  // signed in: say it, don't leave them guessing.
                  if (context.watch<AuthProvider>().sessionExpired)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: CblrepColors.actionOrange.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: CblrepColors.actionOrange.withValues(alpha: 0.5)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.info_outline,
                              size: 18, color: CblrepColors.actionOrange),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Your session ended. Please sign in again.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: dark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  const Center(child: CblrepLogo(radius: 44, padding: 3)),
                  const SizedBox(height: 14),
                  Text('CBLREP', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26, letterSpacing: 3, color: dark ? Colors.white : CblrepColors.brandGreen)),
                  const Text('Community-Based Local Resources Exchange Portal', textAlign: TextAlign.center, style: TextStyle(fontSize: 11)),
                  Text(communityName, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: dark ? Colors.white60 : Colors.black54)),
                  const SizedBox(height: 28),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('Welcome back', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: dark ? Colors.white : Colors.black)),
                        Text('Sign in to swap resources with neighbours.', style: TextStyle(fontSize: 11, color: dark ? Colors.white70 : Colors.black54)),
                        const SizedBox(height: 14),
                        TextFormField(controller: email, keyboardType: TextInputType.emailAddress, autocorrect: false, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)), validator: (value) { final clean = InputSanitizer.email(value ?? ''); if (clean.isEmpty) return 'Email is required'; if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(clean)) return 'Enter a valid email'; return null; }),
                        const SizedBox(height: 12),
                        PasswordField(controller: password, label: 'Password', textInputAction: TextInputAction.done, onSubmitted: (_) => submit(), validator: (value) => value != null && value.isNotEmpty ? null : 'Password is required'),
                        // Remember me (left) shares the row with
                        // "Forgot password?" (right): the box decides whether
                        // this session survives an app restart.
                        Row(children: [
                          Checkbox(
                            value: rememberMe,
                            onChanged: (value) =>
                                setState(() => rememberMe = value ?? false),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          Text(
                            'Remember me',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: dark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ForgotPasswordScreen(email: InputSanitizer.email(email.text)))),
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(0, 32), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                            child: const Text('Forgot password?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        FilledButton(onPressed: context.watch<AuthProvider>().loading ? null : submit, child: Text(context.watch<AuthProvider>().loading ? 'Signing in…' : 'Sign in')),
                        TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())), child: const Text('Create a member account')),
                        const SizedBox(height: 4),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.lock_outline, size: 11, color: Colors.black38),
                          const SizedBox(width: 4),
                          Text('Your session is secured with encrypted storage.', style: TextStyle(fontSize: 9.5, color: dark ? Colors.white38 : Colors.black38)),
                        ]),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
