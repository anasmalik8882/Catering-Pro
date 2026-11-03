import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../domain/auth_repository.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  bool register = false;
  bool busy = false;
  String? message;
  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate() || busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final auth = Get.find<AuthRepository>();
      if (register) {
        await auth.signUp(name.text, email.text, password.text);
      } else {
        await auth.signIn(email.text, password.text);
      }
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(
        () => message = switch (error.code) {
          'invalid-credential' ||
          'wrong-password' ||
          'user-not-found' => 'Email or password is incorrect.',
          'email-already-in-use' => 'This email is already registered.',
          'weak-password' => 'Use a stronger password.',
          'invalid-email' => 'Enter a valid email address.',
          _ => error.message ?? 'Authentication failed.',
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => message = 'Unable to connect. Please try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> signInWithGoogle() async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await Get.find<AuthRepository>().signInWithGoogle();
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() => message = error.message ?? 'Google sign-in failed.');
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => message =
              'Could not sign in with Google. Verify platform configuration and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resetPassword() async {
    if (!email.text.contains('@')) {
      setState(() => message = 'Enter your email to reset your password.');
      return;
    }
    try {
      await Get.find<AuthRepository>().resetPassword(email.text);
      if (mounted) {
        setState(
          () => message =
              'If this account exists, password-reset instructions will be sent.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => message = 'Unable to request password reset.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.restaurant_menu,
                    size: 52,
                    color: Color(0xFF146B57),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Caterer Pro',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    register
                        ? 'Create your catering business account'
                        : 'Welcome back. Manage every event confidently.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),
                  if (register) ...[
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Your name'),
                      validator: (v) => (v ?? '').trim().length < 2
                          ? 'Name is required'
                          : null,
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) =>
                        (v ?? '').contains('@') ? null : 'Enter a valid email',
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                    validator: (v) => (v ?? '').length < 6
                        ? 'At least 6 characters required'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        message!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        busy
                            ? 'Please wait...'
                            : register
                            ? 'Create account'
                            : 'Sign in',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: busy ? null : signInWithGoogle,
                    icon: const Icon(Icons.account_circle_outlined),
                    label: const Text('Continue with Google'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            register = !register;
                            message = null;
                          }),
                    child: Text(
                      register
                          ? 'Already have an account? Sign in'
                          : 'New here? Create an account',
                    ),
                  ),
                  if (!register)
                    TextButton(
                      onPressed: busy ? null : resetPassword,
                      child: const Text('Forgot password?'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
