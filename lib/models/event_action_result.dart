/// The outcome of an event workflow operation that may fail for a *business*
/// reason the UI must surface to the user — not a Firestore error, but a rule
/// violation such as "payment not completed" or "attendance already recorded".
///
/// [success] is `true` when the operation completed; [message] carries the
/// user-facing explanation when it did not. A successful result may also
/// carry a [message] (e.g. "Entry verified").
///
/// This is deliberately separate from [AuthFailure], which represents a
/// transport/storage failure and is caught inside [AppState]. This type
/// travels from [AppState] to the screen so the screen can show the exact
/// reason a workflow step was refused.
class EventActionResult {
  final bool success;
  final String? message;

  const EventActionResult._({required this.success, this.message});

  const EventActionResult.success([String? message])
      : this._(success: true, message: message);

  const EventActionResult.failure(String message)
      : this._(success: false, message: message);
}
