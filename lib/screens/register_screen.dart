import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/user_record_service.dart';

/// Account creation. Registration is only finished once the Firestore user
/// record has been written, so both steps happen here.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.authService,
    required this.userRecordService,
    required this.onShowLogin,
  });

  final AuthService authService;
  final UserRecordService userRecordService;
  final VoidCallback onShowLogin;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  /// Set once the Firebase account exists, so a retry after a failed profile
  /// write never creates a second account.
  String? _createdUid;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading || !_formKey.currentState!.validate()) return;

    // Captured before the first await. Registration signs the new user in,
    // which makes AuthGate rebuild and dispose this screen, so the controllers
    // cannot be read once the asynchronous work is under way.
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text;
    final password = _passwordController.text;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      var uid = _createdUid;
      if (uid == null) {
        final credential = await widget.authService.register(email, password);
        uid = credential.user?.uid;
        if (uid == null) {
          if (mounted) {
            setState(
              () => _errorMessage = 'Something went wrong. Please try again.',
            );
          }
          return;
        }
        _createdUid = uid;
      }

      // Registration is not complete until this write succeeds. This future
      // keeps running even if the screen has already been disposed.
      await widget.userRecordService.saveProfile(
        uid: uid,
        firstName: firstName,
        lastName: lastName,
      );
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _errorMessage = friendlyAuthError(error));
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = friendlyFirestoreError(error));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _validateName(String? value, String field) {
    if ((value ?? '').trim().isEmpty) return 'Enter your $field';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _firstNameController,
                      enabled: !_isLoading,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'First name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => _validateName(value, 'first name'),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _lastNameController,
                      enabled: !_isLoading,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Last name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => _validateName(value, 'last name'),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      enabled: !_isLoading && _createdUid == null,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final email = (value ?? '').trim();
                        if (email.isEmpty) return 'Enter your email';
                        if (!isValidEmail(email)) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      enabled: !_isLoading && _createdUid == null,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final password = value ?? '';
                        if (password.isEmpty) return 'Enter a password';
                        if (password.length < 6) {
                          return 'Use at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmPasswordController,
                      enabled: !_isLoading && _createdUid == null,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm password',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if ((value ?? '').isEmpty) {
                          return 'Confirm your password';
                        }
                        if (value != _passwordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: theme.colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isLoading ? null : _submit,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _createdUid == null
                                    ? 'Register'
                                    : 'Retry Profile Setup',
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _isLoading ? null : widget.onShowLogin,
                      child: const Text('I already have an account'),
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
}
