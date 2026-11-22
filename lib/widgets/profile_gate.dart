import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/user_record_service.dart';

/// Keeps the board unreachable until `users/{uid}` holds a complete profile.
/// Listens to the document, so a profile written moments after registration
/// promotes the user automatically.
class ProfileGate extends StatefulWidget {
  const ProfileGate({
    super.key,
    required this.uid,
    required this.authService,
    required this.userRecordService,
    required this.signedInBuilder,
  });

  final String uid;
  final AuthService authService;
  final UserRecordService userRecordService;

  /// Shown once the profile is complete, with the validated record.
  final Widget Function(BuildContext context, UserRecord record)
  signedInBuilder;

  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  /// Subscribed once per uid; AuthGate keys the gate so a different user
  /// never reuses this stream.
  late final Stream<UserRecord?> _profile = widget.userRecordService.watch(
    widget.uid,
  );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserRecord?>(
      stream: _profile,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ProfileErrorScreen(
            message: friendlyFirestoreError(snapshot.error!),
            onSignOut: widget.authService.signOut,
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final record = snapshot.data;
        if (record != null && record.isComplete) {
          return widget.signedInBuilder(context, record);
        }
        // Missing document or missing fields: both need the same form.
        return CompleteProfileScreen(
          uid: widget.uid,
          authService: widget.authService,
          userRecordService: widget.userRecordService,
          initialFirstName: record?.firstName ?? '',
          initialLastName: record?.lastName ?? '',
        );
      },
    );
  }
}

/// Collects the missing profile fields and retries the Firestore write.
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({
    super.key,
    required this.uid,
    required this.authService,
    required this.userRecordService,
    this.initialFirstName = '',
    this.initialLastName = '',
  });

  final String uid;
  final AuthService authService;
  final UserRecordService userRecordService;
  final String initialFirstName;
  final String initialLastName;

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _firstNameController = TextEditingController(
    text: widget.initialFirstName,
  );
  late final _lastNameController = TextEditingController(
    text: widget.initialLastName,
  );

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await widget.userRecordService.saveProfile(
        uid: widget.uid,
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
      );
      // On success the document listener in ProfileGate takes over.
    } catch (error) {
      if (mounted) setState(() => _errorMessage = friendlyFirestoreError(error));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finish Your Profile'),
        actions: [
          IconButton(
            onPressed: _isSaving ? null : widget.authService.signOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
          ),
        ],
      ),
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
                    Icon(
                      Icons.badge_outlined,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your profile is incomplete',
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add your name to finish setting up your account.',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _firstNameController,
                      enabled: !_isSaving,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'First name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          (value ?? '').trim().isEmpty
                          ? 'Enter your first name'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _lastNameController,
                      enabled: !_isSaving,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Last name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          (value ?? '').trim().isEmpty
                          ? 'Enter your last name'
                          : null,
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
                        onPressed: _isSaving ? null : _save,
                        child: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Save Profile'),
                      ),
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

/// Shown when the profile cannot be read at all, such as permission-denied.
class ProfileErrorScreen extends StatelessWidget {
  const ProfileErrorScreen({
    super.key,
    required this.message,
    required this.onSignOut,
  });

  final String message;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Message Board')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 64,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Profile unavailable',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: onSignOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign Out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
