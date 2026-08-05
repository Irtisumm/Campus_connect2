import '../models/locker.dart';
import '../models/locker_booking.dart';

/// Single source of truth for every monetary value in the Locker module.
///
/// Every screen — Booking, Payment Summary, Card Payment, Receipt, My Locker,
/// Extension dialog, and Admin — must derive its displayed amounts from this
/// class so that identical inputs always produce identical outputs.
///
/// The class is intentionally a pure value object: it holds [deposit],
/// [monthlyRent], and [durationMonths], and exposes every derived amount via
/// getters.  No Firestore calls, no side-effects.
class LockerPricing {
  final double deposit;
  final double monthlyRent;
  final int durationMonths;

  const LockerPricing({
    required this.deposit,
    required this.monthlyRent,
    required this.durationMonths,
  });

  /// Build from a [Locker] document (Firestore `lockers/{id}`) and the
  /// user-selected duration.
  factory LockerPricing.fromLocker(Locker locker, int durationMonths) =>
      LockerPricing(
        deposit: locker.deposit,
        monthlyRent: locker.monthlyRent,
        durationMonths: durationMonths,
      );

  /// Build from a persisted [LockerBooking] document.  Used by My Locker,
  /// Extension dialog, and Admin screens where the locker document may no
  /// longer be available but the booking carries the pricing snapshot.
  factory LockerPricing.fromBooking(LockerBooking booking) => LockerPricing(
        deposit: booking.deposit,
        monthlyRent: booking.monthlyRent,
        durationMonths: booking.durationMonths,
      );

  /// Total rent for the full rental period (excludes deposit).
  ///   `monthlyRent × durationMonths`
  double get totalRentalCost => monthlyRent * durationMonths;

  /// Amount charged to the card today: deposit + total rental cost.
  /// The student pays the FULL rental amount plus the refundable deposit
  /// upfront — no monthly billing.
  ///   `deposit + totalRentalCost`
  double get amountDueToday => deposit + totalRentalCost;

  /// Full financial commitment for the entire rental period.  Because the
  /// full rental is paid upfront, this equals [amountDueToday].
  ///   `amountDueToday`
  double get totalCommitment => amountDueToday;

  /// Cost of extending the rental by [months] additional months.
  ///   `monthlyRent × months`
  double extensionCost(int months) => monthlyRent * months;

  /// Returns a copy with a different [durationMonths].
  LockerPricing copyWithDurationMonths(int newDuration) =>
      LockerPricing(deposit: deposit, monthlyRent: monthlyRent, durationMonths: newDuration);

  /// Human-readable rental-info string for notice boxes, generated from the
  /// actual pricing data instead of a hardcoded string.
  String get rentalInfoText =>
      'Locker rentals: 2-12 months, RM${monthlyRent.toStringAsFixed(0)}/month + '
      'RM${deposit.toStringAsFixed(0)} refundable deposit. '
      'Tap an available locker to book.';
}
