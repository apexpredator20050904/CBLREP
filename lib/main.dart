import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/api_service.dart';
import 'providers/app_settings_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/listings_provider.dart';
import 'providers/live_hub_provider.dart';
import 'theme/cblrep_theme.dart';
import 'widgets/cblrep_shell.dart';
import 'screens/login_screen.dart';

void main() {
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

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return auth.isAuthenticated ? const CblrepShell() : const LoginScreen();
  }
}
