import 'package:firebase_auth/firebase_auth.dart';

/// All Firebase Authentication calls live here.
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  /// The signed-in user, or null when signed out.
  User? get currentUser => _auth.currentUser;

  /// Emits the user on sign-in and null on sign-out.
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Creates a new account. Throws [FirebaseAuthException] on failure.
  Future<UserCredential> register(String email, String password) async {
    return await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Signs in an existing account. Throws [FirebaseAuthException] on failure.
  Future<UserCredential> signIn(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}

/// Turns a [FirebaseAuthException] into a message that is safe to show.
String friendlyAuthError(FirebaseAuthException error) {
  switch (error.code) {
    case 'invalid-email':
      return 'That email address is not valid.';
    case 'email-already-in-use':
      return 'An account already exists for that email.';
    case 'weak-password':
      return 'Please choose a password with at least 6 characters.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'Incorrect email or password.';
    case 'user-disabled':
      return 'That account has been disabled.';
    case 'too-many-requests':
      return 'Too many attempts. Please try again later.';
    case 'network-request-failed':
      return 'No internet connection. Please try again.';
    case 'operation-not-allowed':
      return 'Email sign-in is not enabled for this app.';
    default:
      return 'Something went wrong. Please try again.';
  }
}

/// Shared email check used by the login and registration forms.
bool isValidEmail(String email) {
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());
}
