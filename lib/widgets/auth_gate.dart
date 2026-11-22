import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/board_screen.dart';
import '../services/auth_service.dart';
import '../services/board_service.dart';
import '../services/user_record_service.dart';
import 'auth_flow.dart';
import 'profile_gate.dart';

/// Watches the authentication state and shows the matching screen. Signed-in
/// users pass through [ProfileGate], which checks the Firestore user record
/// before the protected screen is shown.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    this.authService,
    this.userRecordService,
    this.boardService,
    this.authState,
  });

  /// Test-only overrides. When null, the real services are used.
  final AuthService? authService;
  final UserRecordService? userRecordService;
  final BoardService? boardService;
  final Stream<User?>? authState;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthService _authService = widget.authService ?? AuthService();
  late final UserRecordService _userRecordService =
      widget.userRecordService ?? UserRecordService();
  late final BoardService _boardService =
      widget.boardService ?? BoardService(authService: _authService);

  /// Created once so the gate does not resubscribe on every rebuild.
  late final Stream<User?> _authState =
      widget.authState ?? _authService.authStateChanges();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authState,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _AuthMessage(
            icon: Icons.error_outline,
            title: 'Sign-in is unavailable',
            message: 'Something went wrong. Please restart the app.',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) {
          return AuthFlow(
            authService: _authService,
            userRecordService: _userRecordService,
          );
        }
        return ProfileGate(
          // Keyed by uid so a different user never reuses profile state.
          key: ValueKey(user.uid),
          uid: user.uid,
          authService: _authService,
          userRecordService: _userRecordService,
          signedInBuilder: (context, record) => BoardScreen(
            author: record,
            authService: _authService,
            boardService: _boardService,
          ),
        );
      },
    );
  }
}

class _AuthMessage extends StatelessWidget {
  const _AuthMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Message Board')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
