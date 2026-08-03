/// Shared decoders for Firestore wire values.
///
/// Every model that reads a document has to cope with the same three problems:
/// a field may be missing, it may hold a type the app did not write (a document
/// authored by hand in the console, or by an older build), and Firestore's own
/// types are not Dart's. These helpers are the single answer to all three, so
/// `Item`, `UserProfile` and every model added later decode identically.
///
/// They live in `models/` rather than `services/` on purpose: models must not
/// depend on the service layer, and services already depend on models.
///
/// Every helper is total — it returns a sensible empty value instead of
/// throwing, because a single malformed field must never take down a screen.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore timestamps as `DateTime?`.
///
/// Accepts a [Timestamp] (what the server writes), a [DateTime] (what a local
/// pending write reflects back before the server resolves it) and an ISO-8601
/// [String] (documents seeded before the field was a real timestamp). Anything
/// else — including a `null` from a `serverTimestamp()` that has not resolved
/// yet — decodes to `null`, which callers already treat as "unknown".
DateTime? asDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

/// A Firestore array as `List<String>`.
///
/// A missing or non-array field decodes to the empty list rather than throwing,
/// so a document written without the field renders as "no entries".
List<String> asStringList(Object? value) {
  if (value is! Iterable) return const <String>[];
  return value.map((entry) => entry.toString()).toList(growable: false);
}

/// A Firestore value as a plain [String], with `null` becoming `''`.
///
/// Mirrors the `data['field']?.toString() ?? ''` written at nearly every field
/// site in the models.
String asString(Object? value) => value?.toString() ?? '';

/// A Firestore value as a [bool].
///
/// Only a literal `true` is true: a missing flag is false, which is what every
/// boolean field in the schema (`isDeleted`) wants as its default.
bool asBool(Object? value) => value == true;

/// A [DateTime] as the value to write, or `null` when there is nothing to
/// write. Domain dates are stored as real [Timestamp]s so Firestore can range
/// query them; only audit fields use `FieldValue.serverTimestamp()`.
Timestamp? toTimestamp(DateTime? value) =>
    value == null ? null : Timestamp.fromDate(value);
