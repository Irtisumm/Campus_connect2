import 'package:campus_connect/screens/events/create_event_form_state.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the pure Create Event form-state / validation layer.
///
/// No widget pumping, no I/O, no network. Paths used in fixtures are
/// synthetic and are never printed or logged (security constraint).
void main() {
  // Fixed "today" for all date arithmetic: 2026-08-14.
  final DateTime today = DateTime(2026, 8, 14);

  /// Synthetic PDF fixture — synthetic name/path only.
  PlatformFile pdfFixture({String name = 'approval_letter.pdf'}) {
    return PlatformFile(
      name: name,
      size: 2048,
      path: 'C:/synthetic/approval_letter.pdf',
    );
  }

  /// A form that passes every field validator and the 10-day rule
  /// (eventDate = today + 10). Only the event type is parameterized.
  CreateEventFormModel validForm({String eventType = 'Open'}) {
    final model = CreateEventFormModel()
      ..title = 'Hackathon 2026'
      ..category = 'Academic'
      ..eventType = eventType
      ..location = 'Block C, Lab C3-01'
      ..organizer = 'Computing Society'
      ..description = 'A hands-on coding weekend open to all students.'
      ..eventDate = DateTime(2026, 8, 24)
      ..eventTime = const TimeOfDay(hour: 9, minute: 0)
      ..approvalPdf = pdfFixture();
    return model;
  }

  group('CreateEventErrorCopy is frozen', () {
    test('every string matches the exact contract copy', () {
      expect(CreateEventErrorCopy.title, 'Event title is required');
      expect(CreateEventErrorCopy.category, 'Select a category');
      expect(CreateEventErrorCopy.eventType, 'Select an event type');
      expect(CreateEventErrorCopy.price, 'Enter valid amount');
      expect(CreateEventErrorCopy.maxParticipants, 'Enter a valid number');
      expect(
        CreateEventErrorCopy.date,
        'Pick the event date (at least 10 days from today)',
      );
      expect(CreateEventErrorCopy.time, 'Pick the start time');
      expect(CreateEventErrorCopy.location, 'Event location is required');
      expect(CreateEventErrorCopy.organizer, 'Organizer is required');
      expect(CreateEventErrorCopy.description, 'Provide a description');
      expect(
        CreateEventErrorCopy.tenDay,
        'Events must be submitted at least 10 days in advance',
      );
      expect(CreateEventErrorCopy.approvalLetter, 'Approval letter is required');
      expect(
        CreateEventErrorCopy.notLoggedIn,
        'You must be logged in to create an event',
      );
    });
  });

  group('validateEventTitle', () {
    test('empty string is invalid with exact copy', () {
      expect(validateEventTitle(''), CreateEventErrorCopy.title);
    });

    test('whitespace-only is invalid with exact copy', () {
      expect(validateEventTitle('   '), CreateEventErrorCopy.title);
    });

    test('valid title returns null', () {
      expect(validateEventTitle('Tech Talk'), isNull);
    });

    test('title with surrounding whitespace is valid after trim', () {
      expect(validateEventTitle('  Tech Talk  '), isNull);
    });

    test('exactly 100 chars is valid', () {
      expect(validateEventTitle('x' * 100), isNull);
    });

    test('101 chars is rejected (defense, same copy)', () {
      expect(validateEventTitle('x' * 101), CreateEventErrorCopy.title);
    });
  });

  group('validateCategory', () {
    test('null is invalid with exact copy', () {
      expect(validateCategory(null), CreateEventErrorCopy.category);
    });

    test('chosen value is valid', () {
      expect(validateCategory('Academic'), isNull);
      expect(validateCategory('Sport'), isNull);
      expect(validateCategory('Club'), isNull);
      expect(validateCategory('General'), isNull);
    });
  });

  group('validateEventType', () {
    test('null is invalid with exact copy', () {
      expect(validateEventType(null), CreateEventErrorCopy.eventType);
    });

    test('each of the four types is valid', () {
      expect(validateEventType('Open'), isNull);
      expect(validateEventType('Club'), isNull);
      expect(validateEventType('Club+Payment'), isNull);
      expect(validateEventType('Paid'), isNull);
    });
  });

  group('validatePrice (only for paid types)', () {
    test('blank for non-paid types is valid', () {
      expect(validatePrice(text: '', isPaid: false), isNull);
      expect(validatePrice(text: '   ', isPaid: false), isNull);
    });

    test('non-numeric for non-paid types is valid', () {
      expect(validatePrice(text: 'abc', isPaid: false), isNull);
    });

    test('blank for paid types is invalid with exact copy', () {
      expect(validatePrice(text: '', isPaid: true), CreateEventErrorCopy.price);
      expect(validatePrice(text: '  ', isPaid: true), CreateEventErrorCopy.price);
    });

    test('non-numeric for paid types is invalid with exact copy', () {
      expect(validatePrice(text: 'abc', isPaid: true), CreateEventErrorCopy.price);
      expect(validatePrice(text: '12,5', isPaid: true), CreateEventErrorCopy.price);
    });

    test('numeric for paid types is valid', () {
      expect(validatePrice(text: '0', isPaid: true), isNull);
      expect(validatePrice(text: '12.50', isPaid: true), isNull);
      expect(validatePrice(text: '  7.5  ', isPaid: true), isNull);
    });
  });

  group('validateMaxParticipants', () {
    test('empty and whitespace-only are valid (0 = unlimited)', () {
      expect(validateMaxParticipants(''), isNull);
      expect(validateMaxParticipants('   '), isNull);
    });

    test('valid integer is valid', () {
      expect(validateMaxParticipants('50'), isNull);
      expect(validateMaxParticipants('0'), isNull);
    });

    test('non-numeric present text is invalid with exact copy (defense)', () {
      expect(validateMaxParticipants('abc'), CreateEventErrorCopy.maxParticipants);
      expect(validateMaxParticipants('12.5'), CreateEventErrorCopy.maxParticipants);
    });

    test('negative text parses as int and is left to the digitsOnly formatter', () {
      // The frozen rule is literally `int.tryParse(trim) == null`; negatives
      // parse fine, so they are NOT this validator's concern — the UI's
      // `FilteringTextInputFormatter.digitsOnly` blocks them at input time.
      expect(validateMaxParticipants('-5'), isNull);
    });
  });

  group('date / time / location / organizer / description validators', () {
    test('date: null invalid, set valid', () {
      expect(validateEventDate(null), CreateEventErrorCopy.date);
      expect(validateEventDate(DateTime(2026, 8, 24)), isNull);
    });

    test('time: null invalid, set valid', () {
      expect(validateEventTime(null), CreateEventErrorCopy.time);
      expect(validateEventTime(const TimeOfDay(hour: 9, minute: 0)), isNull);
    });

    test('location: empty/whitespace invalid, set valid', () {
      expect(validateLocation(''), CreateEventErrorCopy.location);
      expect(validateLocation('   '), CreateEventErrorCopy.location);
      expect(validateLocation('Main Auditorium'), isNull);
    });

    test('organizer: empty/whitespace invalid, set valid', () {
      expect(validateOrganizer(''), CreateEventErrorCopy.organizer);
      expect(validateOrganizer('   '), CreateEventErrorCopy.organizer);
      expect(validateOrganizer('Student Council'), isNull);
    });

    test('description: empty/whitespace invalid, set valid', () {
      expect(validateDescription(''), CreateEventErrorCopy.description);
      expect(validateDescription('   '), CreateEventErrorCopy.description);
      expect(validateDescription('Join us!'), isNull);
    });
  });

  group('CreateEventFormModel defaults', () {
    test('fresh model has empty state', () {
      final model = CreateEventFormModel();
      expect(model.title, '');
      expect(model.description, '');
      expect(model.location, '');
      expect(model.organizer, '');
      expect(model.priceText, '');
      expect(model.maxParticipantsText, '');
      expect(model.category, isNull);
      expect(model.eventType, isNull);
      expect(model.clubIdRequired, isFalse);
      expect(model.eventDate, isNull);
      expect(model.eventTime, isNull);
      expect(model.approvalPdf, isNull);
      expect(model.submitting, isFalse);
      expect(model.done, isFalse);
      expect(model.isDirty, isFalse);
      expect(model.timeText, isNull);
      expect(model.isClub, isFalse);
      expect(model.isPaid, isFalse);
    });
  });

  group('isClub / isPaid matrix', () {
    test('null eventType is neither', () {
      final model = CreateEventFormModel();
      expect(model.isClub, isFalse);
      expect(model.isPaid, isFalse);
    });

    test('Open', () {
      final model = CreateEventFormModel()..eventType = 'Open';
      expect(model.isClub, isFalse);
      expect(model.isPaid, isFalse);
    });

    test('Club', () {
      final model = CreateEventFormModel()..eventType = 'Club';
      expect(model.isClub, isTrue);
      expect(model.isPaid, isFalse);
    });

    test('Club+Payment', () {
      final model = CreateEventFormModel()..eventType = 'Club+Payment';
      expect(model.isClub, isTrue);
      expect(model.isPaid, isTrue);
    });

    test('Paid', () {
      final model = CreateEventFormModel()..eventType = 'Paid';
      expect(model.isClub, isFalse);
      expect(model.isPaid, isTrue);
    });
  });

  group('timeText', () {
    test('null when no time picked', () {
      expect(CreateEventFormModel().timeText, isNull);
    });

    test('09:00 formats as "09:00 AM" (wire convention)', () {
      final model = CreateEventFormModel()
        ..eventTime = const TimeOfDay(hour: 9, minute: 0);
      expect(model.timeText, '09:00 AM');
    });

    test('14:00 formats as "02:00 PM" (wire convention)', () {
      final model = CreateEventFormModel()
        ..eventTime = const TimeOfDay(hour: 14, minute: 0);
      expect(model.timeText, '02:00 PM');
    });

    test('midnight and noon edge cases', () {
      final midnight = CreateEventFormModel()
        ..eventTime = const TimeOfDay(hour: 0, minute: 0);
      expect(midnight.timeText, '12:00 AM');
      final noon = CreateEventFormModel()
        ..eventTime = const TimeOfDay(hour: 12, minute: 0);
      expect(noon.timeText, '12:00 PM');
    });

    test('minutes are zero-padded', () {
      final model = CreateEventFormModel()
        ..eventTime = const TimeOfDay(hour: 8, minute: 5);
      expect(model.timeText, '08:05 AM');
    });
  });

  group('isDirty matrix', () {
    test('empty form is clean', () {
      expect(CreateEventFormModel().isDirty, isFalse);
    });

    test('each text field alone dirties the form', () {
      expect((CreateEventFormModel()..title = 'x').isDirty, isTrue);
      expect((CreateEventFormModel()..description = 'x').isDirty, isTrue);
      expect((CreateEventFormModel()..location = 'x').isDirty, isTrue);
      expect((CreateEventFormModel()..organizer = 'x').isDirty, isTrue);
      expect((CreateEventFormModel()..priceText = '5').isDirty, isTrue);
      expect((CreateEventFormModel()..maxParticipantsText = '50').isDirty, isTrue);
    });

    test('whitespace-only text does not dirty the form', () {
      expect((CreateEventFormModel()..title = '   ').isDirty, isFalse);
    });

    test('each dropdown choice alone dirties the form', () {
      expect((CreateEventFormModel()..category = 'Academic').isDirty, isTrue);
      expect((CreateEventFormModel()..eventType = 'Open').isDirty, isTrue);
    });

    test('date, time, and PDF each alone dirty the form', () {
      expect((CreateEventFormModel()..eventDate = DateTime(2026, 8, 24)).isDirty,
          isTrue);
      expect(
          (CreateEventFormModel()..eventTime = const TimeOfDay(hour: 9, minute: 0))
              .isDirty,
          isTrue);
      expect((CreateEventFormModel()..approvalPdf = pdfFixture()).isDirty, isTrue);
    });

    test('clubIdRequired alone does NOT dirty the form (lead decision #8)', () {
      expect((CreateEventFormModel()..clubIdRequired = true).isDirty, isFalse);
    });

    test('fully filled form is dirty', () {
      expect(validForm().isDirty, isTrue);
    });

    test('clearing fields returns to clean', () {
      final model = CreateEventFormModel()
        ..title = 'x'
        ..approvalPdf = pdfFixture();
      expect(model.isDirty, isTrue);
      model
        ..title = ''
        ..approvalPdf = null;
      expect(model.isDirty, isFalse);
    });
  });

  group('fieldErrors', () {
    test('valid form returns all-null errors with the full key set', () {
      final errors = validForm().fieldErrors();
      expect(errors.keys.toSet(), CreateEventFieldIds.naturalOrder.toSet());
      expect(errors.length, 10);
      for (final entry in errors.entries) {
        expect(entry.value, isNull, reason: '${entry.key} should be valid');
      }
    });

    test('each field id reports its own error', () {
      final model = CreateEventFormModel()
        ..category = 'Academic'
        ..eventType = 'Paid'
        ..priceText = '10';
      final errors = model.fieldErrors();
      expect(errors[CreateEventFieldIds.title], CreateEventErrorCopy.title);
      expect(errors[CreateEventFieldIds.category], isNull);
      expect(errors[CreateEventFieldIds.eventType], isNull);
      expect(errors[CreateEventFieldIds.price], isNull);
      expect(errors[CreateEventFieldIds.maxParticipants], isNull);
      expect(errors[CreateEventFieldIds.date], CreateEventErrorCopy.date);
      expect(errors[CreateEventFieldIds.time], CreateEventErrorCopy.time);
      expect(errors[CreateEventFieldIds.location], CreateEventErrorCopy.location);
      expect(errors[CreateEventFieldIds.organizer], CreateEventErrorCopy.organizer);
      expect(
        errors[CreateEventFieldIds.description],
        CreateEventErrorCopy.description,
      );
    });

    test('price error appears only for paid types', () {
      final open = validForm(eventType: 'Open');
      expect(open.fieldErrors()[CreateEventFieldIds.price], isNull);

      final paid = validForm(eventType: 'Paid')..priceText = '';
      expect(
        paid.fieldErrors()[CreateEventFieldIds.price],
        CreateEventErrorCopy.price,
      );
    });
  });

  group('firstError ordering', () {
    test('null when fully valid', () {
      expect(validForm().firstError(), isNull);
    });

    test('single error surfaces its own copy', () {
      expect(
        (validForm()..description = '').firstError(),
        CreateEventErrorCopy.description,
      );
      expect(
        (validForm()..organizer = '').firstError(),
        CreateEventErrorCopy.organizer,
      );
    });

    test('title wins over every other error', () {
      final model = CreateEventFormModel()
        ..description = ''; // and everything else also empty
      expect(model.firstError(), CreateEventErrorCopy.title);
    });

    test('natural order: category before eventType', () {
      final model = CreateEventFormModel()..title = 'x';
      expect(model.firstError(), CreateEventErrorCopy.category);
      model.category = 'Academic';
      expect(model.firstError(), CreateEventErrorCopy.eventType);
    });

    test('price before maxParticipants before date', () {
      final model = CreateEventFormModel()
        ..title = 'x'
        ..category = 'Academic'
        ..eventType = 'Club+Payment'
        ..priceText = ''
        ..maxParticipantsText = 'abc';
      expect(model.firstError(), CreateEventErrorCopy.price);
      model.priceText = '5';
      expect(model.firstError(), CreateEventErrorCopy.maxParticipants);
      model.maxParticipantsText = '';
      expect(model.firstError(), CreateEventErrorCopy.date);
    });

    test('date before time before location', () {
      final model = validForm()..eventDate = null;
      expect(model.firstError(), CreateEventErrorCopy.date);
      model.eventDate = DateTime(2026, 8, 24);
      model.eventTime = null;
      expect(model.firstError(), CreateEventErrorCopy.time);
      model.eventTime = const TimeOfDay(hour: 9, minute: 0);
      model.location = '';
      expect(model.firstError(), CreateEventErrorCopy.location);
    });

    test('organizer before description', () {
      final model = validForm()
        ..organizer = ''
        ..description = '';
      expect(model.firstError(), CreateEventErrorCopy.organizer);
    });
  });

  group('tenDayError', () {
    test('null date errors with preserved copy', () {
      expect(
        CreateEventFormModel().tenDayError(today: today),
        CreateEventErrorCopy.tenDay,
      );
    });

    test('9 days out errors', () {
      final model = CreateEventFormModel()..eventDate = DateTime(2026, 8, 23);
      expect(model.tenDayError(today: today), CreateEventErrorCopy.tenDay);
    });

    test('exactly 10 days out is allowed', () {
      final model = CreateEventFormModel()..eventDate = DateTime(2026, 8, 24);
      expect(model.tenDayError(today: today), isNull);
    });

    test('11 days out is allowed', () {
      final model = CreateEventFormModel()..eventDate = DateTime(2026, 8, 25);
      expect(model.tenDayError(today: today), isNull);
    });

    test('time-of-day components do not skew the boundary', () {
      final lateNightToday =
          CreateEventFormModel()..eventDate = DateTime(2026, 8, 24);
      expect(
        lateNightToday.tenDayError(today: DateTime(2026, 8, 14, 23, 59)),
        isNull,
      );

      final lateEventDay =
          CreateEventFormModel()..eventDate = DateTime(2026, 8, 24, 23, 59);
      expect(
        lateEventDay.tenDayError(today: DateTime(2026, 8, 14, 0, 5)),
        isNull,
      );

      final earlyEventDay =
          CreateEventFormModel()..eventDate = DateTime(2026, 8, 23, 23, 59);
      expect(
        earlyEventDay.tenDayError(today: DateTime(2026, 8, 14, 0, 5)),
        CreateEventErrorCopy.tenDay,
      );
    });
  });

  group('buildDraftEvent payload', () {
    test('mirrors the legacy submit handler field-for-field', () {
      final model = validForm()
        ..maxParticipantsText = '50'
        ..approvalPdf = pdfFixture(name: 'approval_letter.pdf');

      final event = model.buildDraftEvent(
        hostStudentId: 'S001',
        today: DateTime(2026, 8, 14, 17, 45),
      );

      expect(event.id, '');
      expect(event.title, 'Hackathon 2026');
      expect(event.category, 'Academic');
      expect(event.date, '2026-08-24');
      expect(event.time, '09:00 AM');
      expect(event.location, 'Block C, Lab C3-01');
      expect(event.organizer, 'Computing Society');
      expect(event.description,
          'A hands-on coding weekend open to all students.');
      expect(event.status, 'Pending');
      expect(event.hostStudentId, 'S001');
      expect(event.approvalLetterPath, 'C:/synthetic/approval_letter.pdf');
      expect(event.approvalLetterName, 'approval_letter.pdf');
      expect(event.hasApprovalLetter, isTrue);
      expect(event.submittedDate, '2026-08-14');
      expect(event.eventType, 'Open');
      expect(event.maxParticipants, 50);
      expect(event.coverImageUrl, isNull);
      expect(event.coverImagePublicId, isNull);
    });

    test('date is zero-padded YYYY-MM-DD', () {
      final model = validForm()..eventDate = DateTime(2026, 9, 5);
      expect(
        model
            .buildDraftEvent(hostStudentId: 'S001', today: today)
            .date,
        '2026-09-05',
      );
    });

    test('afternoon time flows through the payload', () {
      final model = validForm()
        ..eventTime = const TimeOfDay(hour: 14, minute: 0);
      expect(
        model.buildDraftEvent(hostStudentId: 'S001', today: today).time,
        '02:00 PM',
      );
    });

    test('maxParticipants: empty -> 0, "50" -> 50, whitespace -> 0', () {
      expect(
        validForm()
            .buildDraftEvent(hostStudentId: 'S001', today: today)
            .maxParticipants,
        0,
      );
      expect(
        (validForm()..maxParticipantsText = '50')
            .buildDraftEvent(hostStudentId: 'S001', today: today)
            .maxParticipants,
        50,
      );
      expect(
        (validForm()..maxParticipantsText = '   ')
            .buildDraftEvent(hostStudentId: 'S001', today: today)
            .maxParticipants,
        0,
      );
    });

    test('admin-only and roster fields use the model defaults', () {
      final event = validForm().buildDraftEvent(hostStudentId: 'S001', today: today);
      expect(event.rejectionReason, isNull);
      expect(event.revisionNotes, isNull);
      expect(event.messages, isNull);
      expect(event.revisionCount, 0);
      expect(event.qrTicketPath, isNull);
      expect(event.attendeeIds, isEmpty);
      expect(event.pendingJoiningIds, isEmpty);
    });

    for (final (String eventType, bool isPrivate, bool isPaid) in <
        (String, bool, bool)>[
      ('Open', false, false),
      ('Club', true, false),
      ('Club+Payment', true, true),
      ('Paid', false, true),
    ]) {
      test('event-type matrix: $eventType', () {
        final model = validForm(eventType: eventType)
          ..priceText = '12.50'
          ..clubIdRequired = true;
        final event =
            model.buildDraftEvent(hostStudentId: 'S001', today: today);
        expect(event.eventType, eventType);
        expect(event.isPrivate, isPrivate, reason: 'isPrivate for $eventType');
        expect(event.clubIdRequired, isPrivate,
            reason: 'clubIdRequired = isClub && toggle for $eventType');
        expect(event.isPaid, isPaid, reason: 'isPaid for $eventType');
        expect(event.price, isPaid ? 12.5 : 0.0,
            reason: 'price for $eventType');
      });
    }

    test('clubIdRequired is false when the toggle is off even for Club', () {
      final model = validForm(eventType: 'Club')..clubIdRequired = false;
      final event = model.buildDraftEvent(hostStudentId: 'S001', today: today);
      expect(event.isPrivate, isTrue);
      expect(event.clubIdRequired, isFalse);
    });

    test('blank price on a paid type falls back to 0.0 (validator blocks it)',
        () {
      final model = validForm(eventType: 'Paid')..priceText = '';
      final event = model.buildDraftEvent(hostStudentId: 'S001', today: today);
      expect(event.isPaid, isTrue);
      expect(event.price, 0.0);
    });
  });

  group('Event.toMap wire contract', () {
    const Set<String> frozenKeys = <String>{
      'title',
      'date',
      'time',
      'location',
      'category',
      'organizer',
      'description',
      'status',
      'hostStudentId',
      'approvalLetterPath',
      'approvalLetterName',
      'hasApprovalLetter',
      'rejectionReason',
      'revisionNotes',
      'messages',
      'revisionCount',
      'submittedDate',
      'eventType',
      'isPrivate',
      'clubIdRequired',
      'isPaid',
      'price',
      'maxParticipants',
      'attendeeIds',
      'pendingJoiningIds',
      'qrTicketPath',
    };

    test('payload keys match the frozen contract exactly', () {
      final map =
          validForm().buildDraftEvent(hostStudentId: 'S001', today: today).toMap();
      expect(map.keys.toSet(), frozenKeys);
    });

    test('payload contains NO id, coverImageUrl, or coverImagePublicId keys',
        () {
      final map =
          validForm().buildDraftEvent(hostStudentId: 'S001', today: today).toMap();
      expect(map.containsKey('id'), isFalse);
      expect(map.containsKey('coverImageUrl'), isFalse);
      expect(map.containsKey('coverImagePublicId'), isFalse);
    });

    test('key values mirror the built fields', () {
      final map =
          validForm().buildDraftEvent(hostStudentId: 'S001', today: today).toMap();
      expect(map['status'], 'Pending');
      expect(map['hostStudentId'], 'S001');
      expect(map['hasApprovalLetter'], true);
      expect(map['submittedDate'], '2026-08-14');
      expect(map['isPrivate'], false);
      expect(map['isPaid'], false);
      expect(map['price'], 0.0);
      expect(map['maxParticipants'], 0);
      expect(map['attendeeIds'], isEmpty);
      expect(map['pendingJoiningIds'], isEmpty);
      expect(map['revisionCount'], 0);
    });
  });

  group('evaluateSubmit priority', () {
    test('fully valid + logged in -> ready', () {
      final result =
          validForm().evaluateSubmit(today: today, loggedIn: true);
      expect(result.ready, isTrue);
      expect(result.block, SubmitBlock.ready);
      expect(result.message, isNull);
      expect(result.fieldId, isNull);
    });

    test('field error wins over 10-day, PDF, and login problems', () {
      final model = CreateEventFormModel(); // title empty, date null, no PDF
      final result = model.evaluateSubmit(today: today, loggedIn: false);
      expect(result.ready, isFalse);
      expect(result.block, SubmitBlock.fieldError);
      expect(result.message, CreateEventErrorCopy.title);
      expect(result.fieldId, CreateEventFieldIds.title);
    });

    test('field error carries its field id for scroll/focus', () {
      final result = (validForm()..location = '')
          .evaluateSubmit(today: today, loggedIn: true);
      expect(result.block, SubmitBlock.fieldError);
      expect(result.message, CreateEventErrorCopy.location);
      expect(result.fieldId, CreateEventFieldIds.location);
    });

    test('null date reports the per-field error, not the 10-day copy', () {
      final result =
          (validForm()..eventDate = null).evaluateSubmit(today: today, loggedIn: true);
      expect(result.block, SubmitBlock.fieldError);
      expect(result.message, CreateEventErrorCopy.date);
      expect(result.fieldId, CreateEventFieldIds.date);
    });

    test('paid type with blank price reports the price field error', () {
      final result = (validForm(eventType: 'Club+Payment')..priceText = '')
          .evaluateSubmit(today: today, loggedIn: true);
      expect(result.block, SubmitBlock.fieldError);
      expect(result.message, CreateEventErrorCopy.price);
      expect(result.fieldId, CreateEventFieldIds.price);
    });

    test('10-day violation beats missing PDF and login', () {
      final model = validForm()
        ..eventDate = DateTime(2026, 8, 23) // 9 days out
        ..approvalPdf = null;
      final result = model.evaluateSubmit(today: today, loggedIn: false);
      expect(result.block, SubmitBlock.tenDay);
      expect(result.message, CreateEventErrorCopy.tenDay);
      expect(result.fieldId, isNull);
    });

    test('missing PDF beats not-logged-in', () {
      final model = validForm()..approvalPdf = null;
      final result = model.evaluateSubmit(today: today, loggedIn: false);
      expect(result.block, SubmitBlock.missingPdf);
      expect(result.message, CreateEventErrorCopy.approvalLetter);
      expect(result.fieldId, isNull);
    });

    test('not-logged-in when everything else passes', () {
      final result = validForm().evaluateSubmit(today: today, loggedIn: false);
      expect(result.block, SubmitBlock.notLoggedIn);
      expect(result.message, CreateEventErrorCopy.notLoggedIn);
      expect(result.fieldId, isNull);
    });
  });

  group('ChangeNotifier behavior', () {
    test('setters notify listeners (and skip redundant notifications)', () {
      final model = CreateEventFormModel();
      var notifications = 0;
      model.addListener(() => notifications++);

      model.title = 'x';
      expect(notifications, 1);
      model.title = 'x'; // same value: no notify
      expect(notifications, 1);
      model.category = 'Academic';
      model.eventDate = DateTime(2026, 8, 24);
      model.eventTime = const TimeOfDay(hour: 9, minute: 0);
      model.approvalPdf = pdfFixture();
      model.clubIdRequired = true;
      model.submitting = true;
      model.done = true;
      expect(notifications, 8);
    });

    test('submitting and done do not affect isDirty or validation', () {
      final model = validForm()..submitting = true;
      expect(model.isDirty, isTrue);
      expect(model.firstError(), isNull);
      model.done = true;
      expect(model.isDirty, isTrue);
      expect(model.firstError(), isNull);
    });
  });
}
