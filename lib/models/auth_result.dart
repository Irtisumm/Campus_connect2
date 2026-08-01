import 'user_profile.dart';

/// Outcome of a sign-in / registration attempt.
/// [message] is always safe to show directly to the user.
class AuthResult {
  final bool success;
  final String? message;
  final UserProfile? profile;

  const AuthResult._({required this.success, this.message, this.profile});

  const AuthResult.success({UserProfile? profile, String? message})
      : this._(success: true, profile: profile, message: message);

  const AuthResult.failure(String message) : this._(success: false, message: message);
}

/// Domain-level failure raised by the service layer.
///
/// Services translate `FirebaseAuthException` / `FirebaseException` into this
/// so Firebase types never escape into [AppState] or the widget tree.
class AuthFailure implements Exception {
  final String message;
  final String? code;

  const AuthFailure(this.message, {this.code});

  factory AuthFailure.fromCode(String code) =>
      AuthFailure(friendlyAuthMessage(code), code: code);

  @override
  String toString() => 'AuthFailure($code): $message';
}

/// Turns a Firebase error code into a message that is safe and useful to show
/// in the UI. Takes a plain string so it carries no Firebase dependency.
String friendlyAuthMessage(String code) {
  switch (code) {
    case 'email-already-in-use':
      return 'The email address is already registered.';
    case 'invalid-email':
      return 'Please enter a valid email.';
    case 'wrong-password':
      return 'Incorrect password.';
    case 'user-not-found':
      return 'No account exists with this email.';
    case 'weak-password':
      return 'Password must contain at least six characters.';
    case 'network-request-failed':
      return 'Please check your internet connection.';
    // Newer Firebase builds collapse wrong-password / user-not-found into this
    // single code when email enumeration protection is enabled.
    case 'invalid-credential':
    case 'INVALID_LOGIN_CREDENTIALS':
      return 'Incorrect email or password.';
    case 'user-disabled':
      return 'This account has been disabled.';
    case 'too-many-requests':
      return 'Too many attempts. Please try again later.';
    case 'operation-not-allowed':
      return 'Email/password sign-in is not enabled.';
    case 'requires-recent-login':
      return 'Please sign in again to complete this action.';
    case 'permission-denied':
      return 'You do not have permission to perform this action.';
    case 'unavailable':
      return 'Please check your internet connection.';
    default:
      return 'Something went wrong. Please try again.';
  }
}
