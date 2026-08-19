import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/auth_result.dart';
import '../models/event.dart';
import '../models/event_joining.dart';
import '../models/event_message.dart';
import '../models/event_role.dart';

/// Firestore access for the Events subsystem: the `events`, `eventJoinings`
/// and `eventRoles` collections.
///
/// Mirrors [LockerService] exactly: screens talk to [AppState], [AppState]
/// talks to this class, and nothing else touches Firestore. Every
/// [FirebaseException] is translated into an [AuthFailure] here so no Firebase
/// type — and no raw Firebase error string — ever reaches the widget tree.
///
/// This class is deliberately thin. It knows how to read and write documents
/// and how to keep two documents consistent inside a [WriteBatch]; it does not
/// decide *when* a joining may be approved or what a rejection message says.
/// That composition belongs in [AppState], exactly as it does for lockers.
class EventService {
  static const String eventsPath = 'events';
  static const String joiningsPath = 'eventJoinings';
  static const String rolesPath = 'eventRoles';

  /// The statuses an event moves through before it is published. These are the
  /// documents that appear in the admin review queue.
  static const List<String> reviewStatuses = <String>[
    'Pending',
    'Under Review',
    'Needs Revision',
  ];

  final FirebaseFirestore? _dbOrNull;

  EventService({FirebaseFirestore? firestore}) : _dbOrNull = _resolve(firestore);

  static FirebaseFirestore? _resolve(FirebaseFirestore? injected) {
    try {
      return injected ?? FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  bool get isAvailable => _dbOrNull != null;

  CollectionReference<Map<String, dynamic>> get _events =>
      _dbOrNull!.collection(eventsPath);

  CollectionReference<Map<String, dynamic>> get _joinings =>
      _dbOrNull!.collection(joiningsPath);

  CollectionReference<Map<String, dynamic>> get _roles =>
      _dbOrNull!.collection(rolesPath);

  // ── EVENTS ──────────────────────────────────────────────────────

  /// Live feed of every event, for the admin dashboard.
  ///
  /// A student caller would be rejected on the unfiltered query — rules are
  /// not filters — so students use [watchPublishedEvents] or
  /// [watchEventsForHost] instead.
  Stream<List<Event>> watchEvents() => _watchEvents();

  /// Live feed of published events, for the student browse screen. This is the
  /// only event query a student may run across all hosts, because a published
  /// event is public to signed-in users by design.
  Stream<List<Event>> watchPublishedEvents() =>
      _watchEvents(statuses: const <String>['Published']);

  /// Live feed of the admin review queue: everything not yet published,
  /// rejected or completed.
  Stream<List<Event>> watchPendingEvents() =>
      _watchEvents(statuses: reviewStatuses);

  /// Live feed of the events a given student submitted, for My Events. Covers
  /// every status — a host must see their own rejected and completed events.
  Stream<List<Event>> watchEventsForHost(String hostStudentId) =>
      _watchEvents(hostStudentId: hostStudentId);

  /// Live view of a single event by its Firestore document ID. Emits `null`
  /// when the document does not exist.
  Stream<Event?> watchEvent(String id) {
    if (!isAvailable || id.isEmpty) return Stream.value(null);
    return _events
        .doc(id)
        .snapshots()
        .map((doc) => doc.exists ? Event.fromMap(doc.id, doc.data()!) : null)
        .handleError(
          (Object error) => throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// The single query core behind every event feed.
  ///
  /// Sorting is client-side (newest submission first) so no composite
  /// Firestore index is required, matching [LockerService].
  Stream<List<Event>> _watchEvents({
    List<String>? statuses,
    String? hostStudentId,
  }) {
    if (!isAvailable) return Stream.value(const <Event>[]);
    if (hostStudentId != null && hostStudentId.isEmpty) {
      return Stream.value(const <Event>[]);
    }

    Query<Map<String, dynamic>> query = _events;
    if (hostStudentId != null) {
      query = query.where('hostStudentId', isEqualTo: hostStudentId);
    }
    if (statuses != null) {
      query = query.where('status', whereIn: statuses);
    }

    return query
        .snapshots()
        .map(_sortedEventsNewestFirst)
        .handleError(
          (Object error) => throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// Maps a snapshot to a list sorted newest-first by `submittedDate`, falling
  /// back to the event `date` for events that were never submitted for review.
  static List<Event> _sortedEventsNewestFirst(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    final events =
        snapshot.docs.map((doc) => Event.fromMap(doc.id, doc.data())).toList();
    events.sort((a, b) =>
        (b.submittedDate ?? b.date).compareTo(a.submittedDate ?? a.date));
    return events;
  }

  /// Fetches a single event by its document ID, or `null` when it does not
  /// exist.
  Future<Event?> getEvent(String id) async {
    _assertAvailable();
    try {
      final doc = await _events.doc(id).get();
      return doc.exists ? Event.fromMap(doc.id, doc.data()!) : null;
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Writes a new event and returns it with its Firestore ID.
  Future<Event> createEvent(Event event) async {
    _assertAvailable();
    try {
      final doc = await _events.add(event.toMap());
      return event.copyWith(id: doc.id);
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Overwrites an existing event. Ownership and status transitions are
  /// enforced by the security rules, not here.
  Future<void> updateEvent(Event event) async {
    _assertAvailable();
    try {
      await _events.doc(event.id).update(event.toMap());
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Clears the optional cover-image fields without changing the rest of the
  /// event document. Firestore needs an explicit delete sentinel because
  /// [Event.toMap] omits empty optional image fields.
  Future<void> clearCoverImage(String id) async {
    _assertAvailable();
    try {
      await _events.doc(id).update({
        'coverImageUrl': FieldValue.delete(),
        'coverImagePublicId': FieldValue.delete(),
      });
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Partial update of an event document — used for status transitions and
  /// single-field edits where a full overwrite would be wasteful.
  Future<void> patchEvent(String id, Map<String, dynamic> fields) async {
    _assertAvailable();
    try {
      await _events.doc(id).update(fields);
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Permanently removes an event. Only a pending event's own host, or an
  /// admin, may do this — enforced by the security rules.
  Future<void> deleteEvent(String id) async {
    _assertAvailable();
    try {
      await _events.doc(id).delete();
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  // ── COVER IMAGE UPLOAD ──────────────────────────────────────────

  /// Uploads a cover image to Firebase Storage and returns its download URL.
  ///
  /// The image is stored at `events/{eventId}/cover.jpg`. If [eventId] is
  /// empty (new event not yet created), a timestamp-based path is used.
  /// Throws [AuthFailure] on any Firebase error.
  Future<String> uploadCoverImage({
    required String eventId,
    required File imageFile,
    void Function(int sent, int total)? onProgress,
  }) async {
    try {
      final path = eventId.isEmpty
          ? 'events/temp/${DateTime.now().millisecondsSinceEpoch}_cover.jpg'
          : 'events/$eventId/cover.jpg';
      final ref = FirebaseStorage.instance.ref().child(path);
      final uploadTask = ref.putFile(imageFile);

      if (onProgress != null) {
        uploadTask.snapshotEvents.listen((taskSnapshot) {
          final total = taskSnapshot.totalBytes;
          final transferred = taskSnapshot.bytesTransferred;
          if (total > 0) onProgress(transferred, total);
        });
      }

      final snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Removes a previously uploaded cover image from Storage. Best-effort —
  /// does not throw if the file no longer exists.
  Future<void> deleteCoverImage(String coverImageUrl) async {
    if (coverImageUrl.isEmpty) return;
    try {
      await FirebaseStorage.instance.refFromURL(coverImageUrl).delete();
    } catch (_) {
      // Best-effort: ignore if already deleted or inaccessible.
    }
  }

  // ── EVENT STATUS TRANSITIONS ────────────────────────────────────
  //
  // The review lifecycle is a small, closed vocabulary. Keeping the status
  // strings in one place here means a screen can never invent a status the
  // rules do not recognise.

  /// Publishes a reviewed event. Admin only.
  Future<void> approveEvent(String id) =>
      patchEvent(id, {'status': 'Published', 'rejectionReason': null});

  /// Rejects a submission with a reason the host will see. Admin only.
  Future<void> rejectEvent(String id, String reason) =>
      patchEvent(id, {'status': 'Rejected', 'rejectionReason': reason});

  /// Marks a submission as being actively reviewed. Admin only.
  Future<void> setEventUnderReview(String id) =>
      patchEvent(id, {'status': 'Under Review'});

  /// Sends a submission back to the host with change notes. Admin only.
  Future<void> requestEventRevision(String id, String notes) =>
      patchEvent(id, {'status': 'Needs Revision', 'revisionNotes': notes});

  /// Closes out an event that has already run. Admin only.
  Future<void> markEventCompleted(String id) =>
      patchEvent(id, {'status': 'Completed'});

  /// Appends one message to the event's nested `messages` thread.
  ///
  /// Uses [FieldValue.arrayUnion] rather than a read-modify-write so two people
  /// typing at once cannot clobber each other's message.
  Future<void> addEventMessage(String eventId, EventMessage message) async {
    _assertAvailable();
    try {
      await _events.doc(eventId).update({
        'messages': FieldValue.arrayUnion([message.toMap()]),
      });
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  // ── JOININGS ────────────────────────────────────────────────────

  /// Live feed of every joining request for one event, for the host's Manage
  /// Event screen and the admin screens.
  Stream<List<EventJoining>> watchJoiningsForEvent(String eventId) =>
      _watchJoinings(eventId: eventId);

  /// Live feed of the signed-in student's own joinings across all events.
  ///
  /// The `studentId` filter is not optional for a student caller: Firestore
  /// rules are not filters, so the read rule is evaluated against every
  /// document the query would return and rejects the whole query if any
  /// document fails.
  Stream<List<EventJoining>> watchMyJoinings(String studentId) =>
      _watchJoinings(studentId: studentId);

  /// Live view of a single joining — the student's own ticket screen. Emits
  /// `null` when the document does not exist.
  Stream<EventJoining?> watchJoining(String id) {
    if (!isAvailable || id.isEmpty) return Stream.value(null);
    return _joinings
        .doc(id)
        .snapshots()
        .map((doc) => doc.exists ? EventJoining.fromMap(doc.id, doc.data()!) : null)
        .handleError(
          (Object error) => throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  Stream<List<EventJoining>> _watchJoinings({String? eventId, String? studentId}) {
    if (!isAvailable) return Stream.value(const <EventJoining>[]);
    if ((eventId != null && eventId.isEmpty) ||
        (studentId != null && studentId.isEmpty)) {
      return Stream.value(const <EventJoining>[]);
    }

    Query<Map<String, dynamic>> query = _joinings;
    if (eventId != null) {
      query = query.where('eventId', isEqualTo: eventId);
    }
    if (studentId != null) {
      query = query.where('studentId', isEqualTo: studentId);
    }

    return query
        .snapshots()
        .map((snap) {
          final joinings = snap.docs
              .map((doc) => EventJoining.fromMap(doc.id, doc.data()))
              .toList();
          joinings.sort((a, b) => b.joinedDate.compareTo(a.joinedDate));
          return joinings;
        })
        .handleError(
          (Object error) => throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// Fetches a single joining by its document ID, or `null` when it does not
  /// exist.
  Future<EventJoining?> getJoining(String id) async {
    _assertAvailable();
    try {
      final doc = await _joinings.doc(id).get();
      return doc.exists ? EventJoining.fromMap(doc.id, doc.data()!) : null;
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// The signed-in student's joining for one event, or `null` if they have not
  /// joined it. Backs the "Join" vs "View Ticket" decision on the detail
  /// screen.
  Future<EventJoining?> getJoiningForStudent(String eventId, String studentId) async {
    _assertAvailable();
    if (eventId.isEmpty || studentId.isEmpty) return null;
    try {
      final snap = await _joinings
          .where('eventId', isEqualTo: eventId)
          .where('studentId', isEqualTo: studentId)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      final doc = snap.docs.first;
      return EventJoining.fromMap(doc.id, doc.data());
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Writes a new joining request and returns it with its Firestore ID.
  Future<EventJoining> createJoining(EventJoining joining) async {
    _assertAvailable();
    try {
      final doc = await _joinings.add(joining.toMap());
      return joining.copyWith(id: doc.id);
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Partial update of a joining document — payment completion, ticket issue
  /// and attendance all go through here.
  Future<void> patchJoining(String id, Map<String, dynamic> fields) async {
    _assertAvailable();
    try {
      await _joinings.doc(id).update(fields);
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Atomically moves a joining to its decided state and keeps the event's
  /// denormalised roster in step, in a single [WriteBatch] so the two can
  /// never disagree.
  ///
  /// [joiningFields] carries the joining's partial update (status, and the
  /// ticket code when approving). The joining always leaves
  /// `pendingJoiningIds`; it enters `attendeeIds` only when [approved].
  ///
  /// Throws [AuthFailure] when [approved] is `true` but the event has already
  /// reached its participant cap — the host cannot over-approve beyond
  /// capacity.
  Future<void> decideJoining(
    String joiningId,
    String eventId,
    Map<String, dynamic> joiningFields, {
    required bool approved,
    required String studentId,
  }) async {
    _assertAvailable();
    try {
      // ── Capacity guard on approval ─────────────────────────────
      if (approved) {
        final eventDoc = await _events.doc(eventId).get();
        if (eventDoc.exists) {
          final event = Event.fromMap(eventDoc.id, eventDoc.data()!);
          if (event.isFull) {
            throw const AuthFailure('Event is at full capacity.');
          }
        }
      }

      final eventFields = <String, dynamic>{
        'pendingJoiningIds': FieldValue.arrayRemove([joiningId]),
        if (approved) 'attendeeIds': FieldValue.arrayUnion([studentId]),
      };
      final batch = _dbOrNull!.batch()
        ..update(_joinings.doc(joiningId), joiningFields)
        ..update(_events.doc(eventId), eventFields);
      await batch.commit();
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Records the new joining on the event in the same breath as it is created:
  /// a request lands in `pendingJoiningIds`, an auto-approved open join lands
  /// directly in `attendeeIds`.
  Future<void> registerJoiningOnEvent(
    String eventId,
    String joiningId,
    String studentId, {
    required bool autoApproved,
  }) async {
    _assertAvailable();
    try {
      await _events.doc(eventId).update(
        autoApproved
            ? {'attendeeIds': FieldValue.arrayUnion([studentId])}
            : {'pendingJoiningIds': FieldValue.arrayUnion([joiningId])},
      );
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Creates a joining document and registers it on the event's roster in a
  /// single [WriteBatch] so the two can never disagree. If either write fails
  /// neither lands — the student never owns an orphaned joining document.
  ///
  /// Throws [AuthFailure] with code `resource-exhausted` when the event has a
  /// participant cap and the approved attendee count has already reached it.
  /// The caller should surface a "Registration Closed" / "Event Full" message
  /// in that case rather than attempting the write.
  Future<EventJoining> createJoiningAndRegister(
    EventJoining joining, {
    required bool autoApproved,
  }) async {
    _assertAvailable();
    try {
      // ── Capacity guard ──────────────────────────────────────────
      // Only auto-approved joins consume a slot immediately; a Pending join
      // does not count toward the cap until the host approves it.
      if (autoApproved) {
        final eventDoc = await _events.doc(joining.eventId).get();
        if (eventDoc.exists) {
          final event = Event.fromMap(eventDoc.id, eventDoc.data()!);
          if (event.isFull) {
            throw const AuthFailure('Event is at full capacity.');
          }
        }
      }

      final joiningRef = _joinings.doc();
      final eventFields = autoApproved
          ? {'attendeeIds': FieldValue.arrayUnion([joining.studentId])}
          : {'pendingJoiningIds': FieldValue.arrayUnion([joiningRef.id])};
      final batch = _dbOrNull!.batch()
        ..set(joiningRef, joining.toMap())
        ..update(_events.doc(joining.eventId), eventFields);
      await batch.commit();
      return joining.copyWith(id: joiningRef.id);
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Finds the joining holding [ticketCode] for one event, or `null` when the
  /// code is unknown. This is the lookup behind the attendance scanner; the
  /// caller marks attendance with [patchJoining].
  Future<EventJoining?> findJoiningByTicketCode(String eventId, String ticketCode) async {
    _assertAvailable();
    if (eventId.isEmpty || ticketCode.isEmpty) return null;
    try {
      final snap = await _joinings
          .where('eventId', isEqualTo: eventId)
          .where('qrTicketCode', isEqualTo: ticketCode)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      final doc = snap.docs.first;
      return EventJoining.fromMap(doc.id, doc.data());
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  // ── ROLES ───────────────────────────────────────────────────────

  /// Live feed of the crew assigned to one event.
  Stream<List<EventRole>> watchRolesForEvent(String eventId) {
    if (!isAvailable || eventId.isEmpty) {
      return Stream.value(const <EventRole>[]);
    }
    return _roles
        .where('eventId', isEqualTo: eventId)
        .snapshots()
        .map((snap) {
          final roles = snap.docs
              .map((doc) => EventRole.fromMap(doc.id, doc.data()))
              .toList();
          roles.sort((a, b) => a.studentName.compareTo(b.studentName));
          return roles;
        })
        .handleError(
          (Object error) => throw AuthFailure.fromCode((error as FirebaseException).code),
          test: (Object? error) => error is FirebaseException,
        );
  }

  /// One-shot read of the crew assigned to one event, for the permission check
  /// that decides whether the signed-in user may open Manage Event.
  Future<List<EventRole>> getRolesForEvent(String eventId) async {
    _assertAvailable();
    if (eventId.isEmpty) return const <EventRole>[];
    try {
      final snap = await _roles.where('eventId', isEqualTo: eventId).get();
      return snap.docs.map((doc) => EventRole.fromMap(doc.id, doc.data())).toList();
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Assigns a crew role and returns it with its Firestore ID.
  Future<EventRole> assignRole(EventRole role) async {
    _assertAvailable();
    try {
      final doc = await _roles.add(role.toMap());
      return role.copyWith(id: doc.id);
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Revokes a crew role.
  Future<void> removeRole(String id) async {
    _assertAvailable();
    try {
      await _roles.doc(id).delete();
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  void _assertAvailable() {
    if (!isAvailable) {
      throw const AuthFailure('The database is unavailable. Please restart the app.');
    }
  }
}
