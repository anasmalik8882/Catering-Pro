import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../theme/app_theme.dart';
import 'session_controller.dart';
import '../../features/auth/presentation/auth_screen.dart';
import '../../features/business/presentation/onboarding_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';

class CatererProApp extends StatelessWidget {
  const CatererProApp({super.key});
  @override
  Widget build(BuildContext context) => GetMaterialApp(
    title: 'Caterer Pro',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: const SessionGate(),
  );
}

class SessionGate extends StatelessWidget {
  const SessionGate({super.key});
  @override
  Widget build(BuildContext context) => Obx(() {
    final session = Get.find<SessionController>();
    switch (session.stage.value) {
      case SessionStage.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case SessionStage.signedOut:
        return const AuthScreen();
      case SessionStage.onboarding:
        return const OnboardingScreen();
      case SessionStage.ready:
        return const DashboardScreen();
      case SessionStage.suspended:
        return SuspendedScreen(
          message: session.errorMessage.value,
          onRetry: session.reloadSession,
          onSignOut: () => session.auth.signOut(),
        );
      case SessionStage.error:
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(session.errorMessage.value, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: session.reloadSession,
                    child: const Text('Try again'),
                  ),
                  TextButton(
                    onPressed: () => session.auth.signOut(),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        );
    }
  });
}

class SuspendedScreen extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;
  const SuspendedScreen({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.pause_circle_outline,
              size: 56,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Account suspended',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Check again')),
            TextButton(onPressed: onSignOut, child: const Text('Sign out')),
          ],
        ),
      ),
    ),
  );
}
