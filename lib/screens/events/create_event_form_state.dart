import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/event.dart';

/// ── Create Event form state + validation ─────────────────────────
///
/// Pure, unit-testable layer behind the redesigned `CreateEventScreen`
/// (route `/events/create`). Owns NO `BuildContext`, performs NO I/O,
/// makes NO service/provider/network calls — the screen (Agent 4) does
/// all of that and drives this model.
///
/// Contract it implements (frozen in `docs/create_event_redesign_handoff.md`):
/// - Exact validator copy per field (see [CreateEventErrorCopy]).
/// - 10-day submission rule: picker `firstDate = today + 10 days` AND a
///   submit-time re-check with the preserved toast copy.
/// - Mandatory approval-letter PDF: only its local `path` and `name` are
///   carried on the payload; the file itself is never uploaded or read.
/// - Payload built by [CreateEventFormModel.buildDraftEvent] mirrors the
///   legacy submit handler (`events_screens.dart:1567–1590`) byte-for-byte,
///   including `status: 'Pending'`, `hasApprovalLetter: true`, cover-image
///   fields `null`, and every model default (`rejectionReason`, `messages`,
///   `revisionCount`, `qrTicketPath`, `attendeeIds`, `pendingJoiningIds`).
///
/// Security: never log file paths or file contents anywhere in this layer;
/// tests use synthetic names only.

/// Wire display-string format for the picked event date (`'2026-09-01'`).
/// Locale-independent; identical to the legacy picker's manual padding.
final DateFormat createEventDateFormat = DateFormat('yyyy-MM-dd');

/// Wire display-string format for the picked start time (`'09:00 AM'`,
/// `'02:00 PM'`). `hh` (not `h`) is deliberate: the frozen convention in
/// `lib/data/mock_data.dart` uses a zero-padded hour. Locale pinned to
/// `en_US` for determinism (the app never sets `Intl.defaultLocale`).
final DateFormat createEventTimeFormat = DateFormat('hh:mm a', 'en_US');

/// Exact user-facing error copy. Every string below is frozen — tests
/// assert against these values character-for-character.
abstract final class CreateEventErrorCopy {
  CreateEventErrorCopy._();

  static const String title = 'Event title is required';
  static const String category = 'Select a category';
  static const String eventType = 'Select an event type';
  static const String price = 'Enter valid amount';
  static const String maxParticipants = 'Enter a valid number';
  static const String date = 'Pick the event date (at least 10 days from today)';
  static const String time = 'Pick the start time';
  static const String location = 'Event location is required';
  static const String organizer = 'Organizer is required';
  static const String description = 'Provide a description';

  /// Preserved toast copy for the submit-time 10-day re-check.
  static const String tenDay = 'Events must be submitted at least 10 days in advance';

  /// Rendered on the upload card after a failed submit (lead decision #10).
  static const String approvalLetter = 'Approval letter is required';

  /// Preserved pre-write guard copy (auth).
  static const String notLoggedIn = 'You must be logged in to create an event';
}

/// Stable ids for the per-field error map. The screen keys its scroll-to /
/// focus-to behavior off these strings.
abstract final class CreateEventFieldIds {
  CreateEventFieldIds._();

  static const String title = 'title';
  static const String category = 'category';
  static const String eventType = 'eventType';
  static const String price = 'price';
  static const String maxParticipants = 'maxParticipants';
  static const String date = 'date';
  static const String time = 'time';
  static const String location = 'location';
  static const String organizer = 'organizer';
  static const String description = 'description';

  /// Natural top-to-bottom order used by [CreateEventFormModel.firstError]
  /// and [CreateEventFormModel.evaluateSubmit].
  static const List<String> naturalOrder = <String>[
    title,
    category,
    eventType,
    price,
    maxParticipants,
    date,
    time,
    location,
    organizer,
    description,
  ];
}

// ── Pure validators ───────────────────────────────────────────────
// Each returns `null` when valid, otherwise the exact frozen copy.
// Deliberately free of the model so every rule is testable in isolation.

String? validateEventTitle(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return CreateEventErrorCopy.title;
  // Defense: the UI caps input at 100 chars (lead decision #4). The wire
  // contract has no length rule, so an overlong value fails with the same
  // copy rather than producing a distinct message.
  if (trimmed.length > 100) return CreateEventErrorCopy.title;
  return null;
}

String? validateCategory(String? value) =>
    value == null ? CreateEventErrorCopy.category : null;

String? validateEventType(String? value) =>
    value == null ? CreateEventErrorCopy.eventType : null;

/// Price is only validated for paid event types (`Club+Payment` / `Paid`).
String? validatePrice({required String text, required bool isPaid}) {
  if (!isPaid) return null;
  if (text.trim().isEmpty || double.tryParse(text.trim()) == null) {
    return CreateEventErrorCopy.price;
  }
  return null;
}

/// Defense rule: empty/whitespace is fine (0 = unlimited at submit), but a
/// non-empty value must parse as an integer. With `digitsOnly` input this
/// is near-unreachable (lead decision #5).
String? validateMaxParticipants(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  if (int.tryParse(trimmed) == null) return CreateEventErrorCopy.maxParticipants;
  return null;
}

String? validateEventDate(DateTime? date) =>
    date == null ? CreateEventErrorCopy.date : null;

String? validateEventTime(TimeOfDay? time) =>
    time == null ? CreateEventErrorCopy.time : null;

String? validateLocation(String text) =>
    text.trim().isEmpty ? CreateEventErrorCopy.location : null;

String? validateOrganizer(String text) =>
    text.trim().isEmpty ? CreateEventErrorCopy.organizer : null;

String? validateDescription(String text) =>
    text.trim().isEmpty ? CreateEventErrorCopy.description : null;

/// What blocked a submit, in evaluation priority order.
enum SubmitBlock {
  /// A per-field validation error (see [SubmitEvaluation.fieldId]).
  fieldError,

  /// The 10-day business-rule re-check failed.
  tenDay,

  /// No approval-letter PDF selected.
  missingPdf,

  /// `loggedIn` was false.
  notLoggedIn,

  /// Nothing blocked — the screen may build the draft and call
  /// `AppState.createEvent`.
  ready,
}

/// Pure result of [CreateEventFormModel.evaluateSubmit].
class SubmitEvaluation {
  const SubmitEvaluation._(this.block, {this.message, this.fieldId});

  /// Which check failed (or [SubmitBlock.ready]).
  final SubmitBlock block;

  /// Error copy to surface — toast for [SubmitBlock.tenDay] /
  /// [SubmitBlock.notLoggedIn], inline card error for [SubmitBlock.fieldError]
  /// / [SubmitBlock.missingPdf]. `null` when [ready].
  final String? message;

  /// The [CreateEventFieldIds] id of the offending field when [block] is
  /// [SubmitBlock.fieldError] (for scroll-into-view + focus). `null` otherwise.
  final String? fieldId;

  bool get ready => block == SubmitBlock.ready;

  @override
  String toString() => 'SubmitEvaluation(${block.name}, message: $message, '
      'fieldId: $fieldId)';
}

/// Plain typed form state for the Create Event screen.
///
/// The screen owns `TextEditingController`s (listening to this model or
/// syncing into it on change), pickers, the PDF `FilePicker` call, and the
/// actual `AppState.createEvent(...)` submission. This model only stores,
/// validates, and builds the payload.
class CreateEventFormModel extends ChangeNotifier {
  String _title = '';
  String _description = '';
  String _location = '';
  String _organizer = '';
  String _priceText = '';
  String _maxParticipantsText = '';
  String? _category;
  String? _eventType;
  bool _clubIdRequired = false;
  DateTime? _eventDate;
  TimeOfDay? _eventTime;
  PlatformFile? _approvalPdf;
  bool _submitting = false;
  bool _done = false;

  String get title => _title;
  set title(String value) {
    if (value == _title) return;
    _title = value;
    notifyListeners();
  }

  String get description => _description;
  set description(String value) {
    if (value == _description) return;
    _description = value;
    notifyListeners();
  }

  String get location => _location;
  set location(String value) {
    if (value == _location) return;
    _location = value;
    notifyListeners();
  }

  String get organizer => _organizer;
  set organizer(String value) {
    if (value == _organizer) return;
    _organizer = value;
    notifyListeners();
  }

  String get priceText => _priceText;
  set priceText(String value) {
    if (value == _priceText) return;
    _priceText = value;
    notifyListeners();
  }

  String get maxParticipantsText => _maxParticipantsText;
  set maxParticipantsText(String value) {
    if (value == _maxParticipantsText) return;
    _maxParticipantsText = value;
    notifyListeners();
  }

  String? get category => _category;
  set category(String? value) {
    if (value == _category) return;
    _category = value;
    notifyListeners();
  }

  String? get eventType => _eventType;
  set eventType(String? value) {
    if (value == _eventType) return;
    _eventType = value;
    notifyListeners();
  }

  /// Club-ID toggle (only shown for `Club` / `Club+Payment`). Note: toggling
  /// it alone does NOT mark the form dirty (lead decision #8's exact
  /// `_isDirty` definition excludes it).
  bool get clubIdRequired => _clubIdRequired;
  set clubIdRequired(bool value) {
    if (value == _clubIdRequired) return;
    _clubIdRequired = value;
    notifyListeners();
  }

  DateTime? get eventDate => _eventDate;
  set eventDate(DateTime? value) {
    if (value == _eventDate) return;
    _eventDate = value;
    notifyListeners();
  }

  TimeOfDay? get eventTime => _eventTime;
  set eventTime(TimeOfDay? value) {
    if (value == _eventTime) return;
    _eventTime = value;
    notifyListeners();
  }

  PlatformFile? get approvalPdf => _approvalPdf;
  set approvalPdf(PlatformFile? value) {
    if (value == _approvalPdf) return;
    _approvalPdf = value;
    notifyListeners();
  }

  /// Duplicate-submit guard; the screen flips it true before `await` and
  /// false when the write settles (success flips `done` instead).
  bool get submitting => _submitting;
  set submitting(bool value) {
    if (value == _submitting) return;
    _submitting = value;
    notifyListeners();
  }

  /// Inline-success branch of the screen (preserved behavior).
  bool get done => _done;
  set done(bool value) {
    if (value == _done) return;
    _done = value;
    notifyListeners();
  }

  /// `eventType ∈ {Club, Club+Payment}` — drives `isPrivate` and the
  /// Club-ID card's visibility.
  bool get isClub =>
      _eventType == 'Club' || _eventType == 'Club+Payment';

  /// `eventType ∈ {Club+Payment, Paid}` — drives the price card's
  /// visibility and the payload `price`.
  bool get isPaid =>
      _eventType == 'Club+Payment' || _eventType == 'Paid';

  /// Wire display string for the picked time (`'09:00 AM'`, `'02:00 PM'`),
  /// or `null` while unset. Matches the app convention verified against
  /// `lib/data/mock_data.dart`.
  String? get timeText {
    final time = _eventTime;
    if (time == null) return null;
    return createEventTimeFormat.format(
      DateTime(2000, 1, 1, time.hour, time.minute),
    );
  }

  /// True when any text field is non-empty (after trim), any dropdown is
  /// chosen, a date/time is picked, or a PDF is selected. Exact lead
  /// decision #8 definition — `clubIdRequired` alone does not dirty the form.
  bool get isDirty =>
      _title.trim().isNotEmpty ||
      _description.trim().isNotEmpty ||
      _location.trim().isNotEmpty ||
      _organizer.trim().isNotEmpty ||
      _priceText.trim().isNotEmpty ||
      _maxParticipantsText.trim().isNotEmpty ||
      _category != null ||
      _eventType != null ||
      _eventDate != null ||
      _eventTime != null ||
      _approvalPdf != null;

  /// Per-field validation results keyed by [CreateEventFieldIds]. Every id
  /// is always present; `null` = valid.
  Map<String, String?> fieldErrors() {
    return <String, String?>{
      CreateEventFieldIds.title: validateEventTitle(_title),
      CreateEventFieldIds.category: validateCategory(_category),
      CreateEventFieldIds.eventType: validateEventType(_eventType),
      CreateEventFieldIds.price:
          validatePrice(text: _priceText, isPaid: isPaid),
      CreateEventFieldIds.maxParticipants:
          validateMaxParticipants(_maxParticipantsText),
      CreateEventFieldIds.date: validateEventDate(_eventDate),
      CreateEventFieldIds.time: validateEventTime(_eventTime),
      CreateEventFieldIds.location: validateLocation(_location),
      CreateEventFieldIds.organizer: validateOrganizer(_organizer),
      CreateEventFieldIds.description: validateDescription(_description),
    };
  }

  /// First non-null error in the natural top-to-bottom order
  /// (title → category → eventType → price → maxParticipants → date → time →
  /// location → organizer → description), or `null` when every field is valid.
  String? firstError() {
    final errors = fieldErrors();
    for (final id in CreateEventFieldIds.naturalOrder) {
      final message = errors[id];
      if (message != null) return message;
    }
    return null;
  }

  /// Submit-time business-rule re-check with the EXACT preserved copy.
  ///
  /// Returns [CreateEventErrorCopy.tenDay] when [eventDate] is null or falls
  /// before `today + 10 days`; else `null`. Both sides are normalized to
  /// date-only before comparing, so time-of-day components cannot skew the
  /// boundary. The picker separately enforces `firstDate = today + 10 days` —
  /// this is the final guard (lead decision #9).
  String? tenDayError({required DateTime today}) {
    final date = _eventDate;
    if (date == null) return CreateEventErrorCopy.tenDay;
    final eventDay = DateTime(date.year, date.month, date.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    // `day + 10` (not `add(Duration(days: 10))`) keeps the arithmetic on the
    // calendar, immune to DST edge cases.
    final minDay = DateTime(todayDay.year, todayDay.month, todayDay.day + 10);
    if (eventDay.isBefore(minDay)) return CreateEventErrorCopy.tenDay;
    return null;
  }

  /// Pure submit state machine, in priority order:
  /// 1. first field error (carries its field id for scroll/focus),
  /// 2. the 10-day re-check,
  /// 3. missing approval-letter PDF,
  /// 4. not logged in,
  /// 5. ready.
  ///
  /// The screen performs the actual `await appState.createEvent(...)` only
  /// when this returns [SubmitBlock.ready].
  SubmitEvaluation evaluateSubmit({
    required DateTime today,
    required bool loggedIn,
  }) {
    final errors = fieldErrors();
    for (final id in CreateEventFieldIds.naturalOrder) {
      final message = errors[id];
      if (message != null) {
        return SubmitEvaluation._(
          SubmitBlock.fieldError,
          message: message,
          fieldId: id,
        );
      }
    }
    final tenDay = tenDayError(today: today);
    if (tenDay != null) {
      return SubmitEvaluation._(SubmitBlock.tenDay, message: tenDay);
    }
    if (_approvalPdf == null) {
      return const SubmitEvaluation._(
        SubmitBlock.missingPdf,
        message: CreateEventErrorCopy.approvalLetter,
      );
    }
    if (!loggedIn) {
      return const SubmitEvaluation._(
        SubmitBlock.notLoggedIn,
        message: CreateEventErrorCopy.notLoggedIn,
      );
    }
    return const SubmitEvaluation._(SubmitBlock.ready);
  }

  /// Builds the submission payload, mirroring the legacy submit handler
  /// (`events_screens.dart:1567–1590`) so the wire contract is identical.
  ///
  /// Preconditions (enforced by [evaluateSubmit] — call only when ready):
  /// [eventDate], [eventType], [category] and [approvalPdf] non-null; the
  /// `!`s below fail loudly on contract misuse instead of writing a silent
  /// empty value.
  ///
  /// Security: [Event.approvalLetterPath] carries the local device path —
  /// never log it, display it, or write it anywhere except the payload.
  ///
  /// [coverImageUrl] and [coverImagePublicId] are optional: when the screen
  /// has uploaded a cover image to Cloudinary before calling this, it passes
  /// the result here; otherwise both stay `null` and are omitted from the
  /// wire payload.
  Event buildDraftEvent({
    required String hostStudentId,
    required DateTime today,
    String? coverImageUrl,
    String? coverImagePublicId,
  }) {
    // Fails loudly on contract misuse (evaluateSubmit gates this path).
    final pdf = approvalPdf!;
    final date = eventDate;
    return Event(
      id: '',
      title: _title,
      category: category!,
      date: date == null ? '' : createEventDateFormat.format(date),
      time: timeText ?? '',
      location: _location,
      organizer: _organizer,
      description: _description,
      status: 'Pending',
      hostStudentId: hostStudentId,
      approvalLetterPath: pdf.path,
      approvalLetterName: pdf.name,
      hasApprovalLetter: true,
      // Explicit model defaults — byte-identical to the legacy handler which
      // omitted them, and keeps `toMap` output on the frozen key list.
      rejectionReason: null,
      revisionNotes: null,
      messages: null,
      revisionCount: 0,
      submittedDate: createEventDateFormat.format(today),
      eventType: eventType!,
      isPrivate: isClub,
      clubIdRequired: isClub && _clubIdRequired,
      isPaid: isPaid,
      price: isPaid ? double.tryParse(_priceText) ?? 0.0 : 0.0,
      maxParticipants: int.tryParse(_maxParticipantsText.trim()) ?? 0,
      attendeeIds: const <String>[],
      pendingJoiningIds: const <String>[],
      qrTicketPath: null,
      // Cover image: passed in by the screen after Cloudinary upload, or
      // `null` when no image was selected. `Event.toMap` omits nulls, so
      // the wire payload stays on the frozen key set when none is provided.
      coverImageUrl: coverImageUrl,
      coverImagePublicId: coverImagePublicId,
    );
  }
}
