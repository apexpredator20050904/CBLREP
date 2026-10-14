import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/api_service.dart';
import 'core/push_service.dart';
import 'providers/app_settings_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/listings_provider.dart';
import 'providers/live_hub_provider.dart';
import 'theme/cblrep_theme.dart';
import 'widgets/cblrep_shell.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Push notifications are an enhancement over the in-app 10s poll. If Firebase
  // is misconfigured (missing google-services.json, a device without Google Play
  // services, …) the app must still launch and work via polling, so every step
  // here fails soft.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(cblrepBackgroundMessageHandler);
    await PushService.instance.init(ApiService.instance);
  } catch (error) {
    debugPrint('[CBLREP] push notifications unavailable: $error');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppSettingsProvider()..load()),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(ApiService.instance)..restore(),
        ),
        ChangeNotifierProvider(create: (_) => ListingsProvider(ApiService.instance)),
        ChangeNotifierProvider(create: (_) => LiveHubProvider(ApiService.instance)),
        ChangeNotifierProvider(create: (_) => ChatProvider(ApiService.instance)),
      ],
      child: Consumer<AppSettingsProvider>(
        builder: (context, settings, _) => MaterialApp(
          title: 'CBLREP',
          debugShowCheckedModeBanner: false,
          theme: CblrepTheme.lightCream,
          darkTheme: CblrepTheme.darkGreen,
          themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
          home: const AuthGate(),
        ),
      ),
    );
  }
}

/// Launch gate: shows a spinner while the stored session is restored, then
/// either the dashboard (valid saved session) or the login screen. Sign-in,
/// sign-up and sign-out navigate imperatively with `pushAndRemoveUntil`, so
/// this gate only decides the very first screen of an app launch.
///
/// A failed restore (usually "can't reach the server") renders an explicit
/// error card with a retry button rather than an endless spinner or a blank
/// screen.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.loading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/logo.png',
                width: 140,
                height: 140,
              ),
              const SizedBox(height: 20),
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(
                'Connecting to the CBLREP server…',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    final failure = auth.restoreError;
    if (failure != null && !auth.isAuthenticated) {
      return _RestoreFailed(message: failure, onRetry: auth.retryRestore);
    }

    return auth.isAuthenticated ? const CblrepShell() : const LoginScreen();
  }
}

/// Shown when the app cannot validate the saved session because the API is
/// unreachable. Offering both "retry" and "continue as guest" means a member
/// is never trapped by a backend outage.
class _RestoreFailed extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _RestoreFailed({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(Icons.cloud_off, size: 36, color: scheme.onErrorContainer),
                ),
                const SizedBox(height: 16),
                Text(
                  "Can't reach the server",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    // Explicit, intentional reset of the restore attempt so the
                    // gate falls through to the login form.
                    context.read<AuthProvider>().dismissRestoreError();
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (_) => false,
                    );
                  },
                  child: const Text('Continue to sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
