import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/auth_result.dart';
import '../models/payment.dart';

/// Firestore access for the `payments` collection and the demo payment
/// gateway logic.
///
/// Mirrors [LockerService]: screens talk to this class (via [AppState]) and
/// never to Firestore directly, and every [FirebaseException] is translated
/// into an [AuthFailure] here so no Firebase type ever reaches the widget
/// tree.
///
/// The demo gateway simulates a card payment with a 1.5-second delay and
/// recognises three test card numbers:
///   - `4242 4242 4242 4242` → success
///   - `4000 0000 0000 0002` → card declined
///   - `4000 0000 0000 9995` → insufficient funds
/// Any other valid 16-digit card number also succeeds (demo mode). The full
/// card number and CVV are NEVER stored — only the last 4 digits are
/// persisted on the [Payment] document.
class PaymentService {
  static const String paymentsPath = 'payments';

  final FirebaseFirestore? _dbOrNull;

  PaymentService({FirebaseFirestore? firestore})
      : _dbOrNull = _resolve(firestore);

  static FirebaseFirestore? _resolve(FirebaseFirestore? injected) {
    try {
      return injected ?? FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  bool get isAvailable => _dbOrNull != null;

  CollectionReference<Map<String, dynamic>> get _payments =>
      _dbOrNull!.collection(paymentsPath);

  // ── DEMO PAYMENT GATEWAY ────────────────────────────────────────

  /// Runs the demo payment gateway for a card transaction and, on success,
  /// writes a `payments` document.
  ///
  /// [cardNumber] must be a 16-digit string (spaces are stripped). [cardCvv]
  /// is used for the simulation only and is NEVER stored. [amount], [deposit],
  /// [monthlyRent], [durationMonths], [lockerId], [studentId], and
  /// [bookingId] are recorded on the payment document.
  ///
  /// Returns a [PaymentResult.success] with the created [Payment] on success,
  /// or a [PaymentResult.failure] with a user-safe message on decline /
  /// insufficient funds / network error.
  Future<PaymentResult> processPayment({
    required String cardNumber,
    required String cardCvv,
    required double amount,
    required double deposit,
    required double monthlyRent,
    required int durationMonths,
    required String lockerId,
    required String studentId,
    required String bookingId,
  }) async {
    final cleaned = cardNumber.replaceAll(RegExp(r'\s'), '');
    if (cleaned.length != 16 || !RegExp(r'^\d{16}$').hasMatch(cleaned)) {
      return const PaymentResult.failure(
          'Invalid card number. Please enter a valid 16-digit card number.');
    }
    if (cardCvv.length < 3) {
      return const PaymentResult.failure(
          'Invalid CVV. Please enter the 3-digit security code.');
    }

    // Simulate gateway processing delay.
    await Future.delayed(const Duration(milliseconds: 1500));

    // Demo gateway test-card routing.
    final declined = cleaned == '4000000000000002';
    final insufficient = cleaned == '4000000000009995';
    if (declined) {
      return const PaymentResult.failure(
          'Your card was declined. Please try a different card.');
    }
    if (insufficient) {
      return const PaymentResult.failure(
          'Insufficient funds. Please try a different card.');
    }

    // Success — build the payment document.
    final now = DateTime.now();
    final transactionId =
        'TXN-${now.millisecondsSinceEpoch}-${now.microsecond.toString().padLeft(6, '0')}';
    final receiptNumber =
        'RCP-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.millisecond.toString().padLeft(3, '0')}';
    final cardLast4 = cleaned.substring(12);

    final payment = Payment(
      id: '',
      bookingId: bookingId,
      studentId: studentId,
      lockerId: lockerId,
      amount: amount,
      deposit: deposit,
      monthlyRent: monthlyRent,
      durationMonths: durationMonths,
      paymentMethod: 'Card',
      cardLast4: cardLast4,
      transactionId: transactionId,
      receiptNumber: receiptNumber,
      paymentStatus: 'Completed',
      paidAt: now.toIso8601String(),
    );

    if (!isAvailable) {
      // No Firestore — return the payment object without persisting so the
      // booking flow can still proceed in offline/demo mode.
      return PaymentResult.success(payment.copyWith(id: 'demo-${now.millisecond}'));
    }

    try {
      final doc = await _payments.add(payment.toMap());
      return PaymentResult.success(payment.copyWith(id: doc.id));
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  // ── READS ───────────────────────────────────────────────────────

  /// Live feed of the signed-in student's own payments, newest first.
  Stream<List<Payment>> watchMyPayments(String studentId) {
    if (!isAvailable || studentId.isEmpty) {
      return Stream.value(const <Payment>[]);
    }
    return _payments
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map((snap) {
          final payments = snap.docs
              .map((doc) => Payment.fromMap(doc.id, doc.data()))
              .toList();
          payments.sort((a, b) => b.paidAt.compareTo(a.paidAt));
          return payments;
        })
        .handleError(
          (Object error) =>
              throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// Live feed of every payment across all students, for the admin screens.
  Stream<List<Payment>> watchAllPayments() {
    if (!isAvailable) return Stream.value(const <Payment>[]);
    return _payments.snapshots().map((snap) {
      final payments = snap.docs
          .map((doc) => Payment.fromMap(doc.id, doc.data()))
          .toList();
      payments.sort((a, b) => b.paidAt.compareTo(a.paidAt));
      return payments;
    }).handleError(
      (Object error) =>
          throw AuthFailure.fromCode((error as FirebaseException).code),
      test: (Object? error) => error is FirebaseException,
    );
  }

  /// Fetches the payment for a given booking ID, or `null` when none exists.
  Future<Payment?> getPaymentForBooking(String bookingId) async {
    if (!isAvailable || bookingId.isEmpty) return null;
    try {
      final snap = await _payments
          .where('bookingId', isEqualTo: bookingId)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return Payment.fromMap(snap.docs.first.id, snap.docs.first.data());
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  // ── UPDATES ─────────────────────────────────────────────────────

  /// Updates a payment's status (e.g. to 'Refund Pending' when a booking is
  /// rejected). Admin-only by Firestore rules.
  Future<void> updatePaymentStatus(String paymentId, String status) async {
    if (!isAvailable) return;
    try {
      await _payments.doc(paymentId).update({'paymentStatus': status});
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }
}
