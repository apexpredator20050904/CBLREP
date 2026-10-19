import 'package:flutter/material.dart' hide Feedback;
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/login_screen.dart';
import 'feedback.dart';

/// Ensures there is a signed-in member before an action that needs one.
///
/// The public listing feed does not need a session, so most screens are
/// reachable signed out — and a session can also die mid-run. Any action
/// that needs a member asks first instead of sending a request that can
/// only answer 401 and putting the raw server string ("Unauthenticated.")
/// in front of the member.
///
/// [action] names what the member was trying to do, so the prompt reads
/// naturally ("Sign in to report this listing.").
///
/// Resolves true when a session is available. Otherwise it offers the
/// sign-in form and resolves false: the form replaces the whole stack with a
/// fresh dashboard, so nothing may continue afterwards.
Future<bool> ensureSignedIn(BuildContext context, String action) async {
  if (context.read<AuthProvider>().isAuthenticated) return true;
  if (!context.mounted) return false;

  final goToSignIn = await Feedback.confirm(
    context,
    title: 'Sign in required',
    message: 'Sign in to $action.',
    confirmLabel: 'Sign in',
  );
  if (!goToSignIn || !context.mounted) return false;

  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const LoginScreen()),
  );
  return false;
}
