import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import '../screens/register_screen.dart';
import '../services/auth_service.dart';
import '../services/user_record_service.dart';

/// Shown to signed-out users. Swaps between login and registration without
/// pushing routes, so AuthGate stays in control once the user signs in.
class AuthFlow extends StatefulWidget {
  const AuthFlow({
    super.key,
    required this.authService,
    required this.userRecordService,
  });

  final AuthService authService;
  final UserRecordService userRecordService;

  @override
  State<AuthFlow> createState() => _AuthFlowState();
}

class _AuthFlowState extends State<AuthFlow> {
  bool _showLogin = true;

  @override
  Widget build(BuildContext context) {
    if (_showLogin) {
      return LoginScreen(
        authService: widget.authService,
        onShowRegister: () => setState(() => _showLogin = false),
      );
    }
    return RegisterScreen(
      authService: widget.authService,
      userRecordService: widget.userRecordService,
      onShowLogin: () => setState(() => _showLogin = true),
    );
  }
}
