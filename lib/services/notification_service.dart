import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/admin_notification.dart';
import '../models/auth_result.dart';
import '../models/campus_notification.dart';
import '../models/lf_notification.dart';
import '../models/locker_notification.dart';
import '../models/user_profile.dart';
import 'lf_workflow_service.dart';
import 'locker_service.dart';
import 'user_service.dart';

/// Centralized notification emission service for Campus Connect.
///
/// Feature modules call [emit] with a [CampusNotification] and the service
/// handles everything else: deduplication, Firestore write, preference
/// resolution, and push dispatch.
///
/// ## Architecture
///
/// ```
/// Feature code
///   → NotificationService.emit(CampusNotification)
///     → dedupe check (in-memory)
///     → write to lfNotifications or lockerNotifications
///     → preference check (UserService → Firestore)
///     → push dispatch (Worker → OneSignal)
///     → return document ID
/// ```
///
/// The Firestore collections (`lfNotifications`, `lockerNotifications`)
/// remain the authoritative in-app store.  This service is a **unified
/// API layer**, not a new datastore.
class NotificationService {
  final LfWorkflowService _lfWorkflow;
  final LockerService _lockers;
  final UserService _users;

  /// Lazily resolves the `adminNotifications` collection reference.
  ///
  /// Provided as a factory so constructing this service (and AppState)
  /// never touches `FirebaseFirestore.instance` — that getter throws
  /// before `Firebase.initializeApp`, which would break every widget/unit
  /// test that builds AppState without Firebase.  The factory is only
  /// invoked when an admin-queue method actually runs (production path).
  final CollectionReference<Map<String, dynamic>> Function()?
      _adminNotificationsRef;
  CollectionReference<Map<String, dynamic>>? _adminCollectionCache;
  bool _adminCollectionResolved = false;

  /// In-memory set of recently emitted dedupe keys.  Prevents duplicate
  /// Firestore writes and duplicate pushes within a single process
  /// lifetime.  Size-limited to prevent unbounded growth.
  final Set<String> _recentDedupeKeys = {};
  static const int _maxDedupeCache = 200;

  NotificationService({
    required LfWorkflowService lfWorkflow,
    required LockerService lockers,
    required UserService users,
    CollectionReference<Map<String, dynamic>> Function()? adminNotificationsRef,
  })  : _lfWorkflow = lfWorkflow,
        _lockers = lockers,
        _users = users,
        _adminNotificationsRef = adminNotificationsRef;

  // ── Public API ────────────────────────────────────────────────────

  /// Emits a notification.
  ///
  /// 1. Validates required fields.
  /// 2. Checks the in-memory dedupe cache — if [notification.dedupeKey]
  ///    was already emitted in this process, returns the cached doc ID.
  /// 3. Writes to the appropriate Firestore collection:
  ///    - [NotificationSource.lostFound] → `lfNotifications/{id}`
  ///    - [NotificationSource.locker]    → `lockerNotifications/{id}`
  ///    - Other sources → currently unsupported (throws).
  /// 4. Reads the recipient's notification preferences.  If the
  ///    preference category is disabled, push is skipped.
  /// 5. Dispatches a OneSignal push via the Cloudflare Worker.
  ///
  /// Returns the Firestore document ID of the created notification.
  /// Failures are logged but never propagate — the notification document
  /// is the authoritative record regardless of push outcome.
  Future<String> emit(CampusNotification notification) async {
    // ── 1. Validate ──────────────────────────────────────────────
    if (notification.studentId.isEmpty) {
      throw ArgumentError('studentId must not be empty');
    }
    if (notification.recipientUid.isEmpty) {
      throw ArgumentError('recipientUid must not be empty');
    }

    // ── 2. Deduplicate ───────────────────────────────────────────
    final key = notification.dedupeKey.isNotEmpty
        ? notification.dedupeKey
        : CampusNotification.buildDedupeKey(
            source: notification.source,
            type: notification.type,
            relatedEntityId: notification.relatedEntityId,
            recipientUid: notification.recipientUid,
          );

    if (_recentDedupeKeys.contains(key)) {
      debugPrint('[Notification] DUPLICATE suppressed key=$key');
      return ''; // caller can check for empty string
    }
    _addDedupeKey(key);

    // ── 3. Write to Firestore ────────────────────────────────────
    final docId = await _writeToFirestore(notification);
    if (docId.isEmpty) return '';

    // ── 4. Check preferences ─────────────────────────────────────
    final shouldPush = await _resolvePreferences(notification);
    if (!shouldPush) {
      debugPrint('[Notification] push suppressed by preference '
          'key=${notification.preferenceCategory} '
          'uid=${notification.recipientUid}');
      return docId;
    }

    // ── 5. Dispatch push ─────────────────────────────────────────
    unawaited(_dispatchPush(notification, docId));

    return docId;
  }

  /// Dispatches a OneSignal push for an already-persisted notification
  /// document, honoring the recipient's preferences.
  ///
  /// Used when the notification document is created *outside* [emit] —
  /// e.g. `approveMatchWithNotification` writes the document inside its
  /// own atomic transaction, so this completes the delivery leg without
  /// creating a second document.
  Future<void> dispatchPush(
      CampusNotification notification, String docId) async {
    final shouldPush = await _resolvePreferences(notification);
    if (!shouldPush) {
      debugPrint('[Notification] push suppressed by preference '
          'key=${notification.preferenceCategory} '
          'uid=${notification.recipientUid}');
      return;
    }
    await _dispatchPush(notification, docId);
  }

  // ── Admin work queue ────────────────────────────────────────────

  /// Emits an admin work-queue notification into `adminNotifications`.
  ///
  /// Student *personal* notifications use [emit]; this path addresses the
  /// admin queue instead — a single cross-module store re-used by future
  /// Event/Issue/Locker/System phases via their own allowlisted types.
  /// No push is dispatched: admins consume the queue in-app (push-to-admin
  /// needs a OneSignal segment and is a future phase).
  ///
  /// Validated locally (source/type/title/body/relatedEntityId/actor
  /// non-empty); the Firestore rules re-validate attribution server-side.
  /// Deduplicated with the same in-memory cache as [emit], using a
  /// queue-wide key — the recipients are *all* administrators, so the key
  /// omits any UID by design.
  Future<String> emitAdmin(CampusNotification notification) async {
    if (notification.type.isEmpty) {
      throw ArgumentError('type must not be empty');
    }
    if (notification.title.isEmpty) {
      throw ArgumentError('title must not be empty');
    }
    if (notification.body.isEmpty) {
      throw ArgumentError('body must not be empty');
    }
    if (notification.relatedEntityId == null ||
        notification.relatedEntityId!.isEmpty) {
      throw ArgumentError('relatedEntityId must not be empty');
    }
    if (notification.studentId.isEmpty) {
      throw ArgumentError('studentId (actor) must not be empty');
    }

    final key = notification.dedupeKey.isNotEmpty
        ? notification.dedupeKey
        : CampusNotification.buildDedupeKey(
            source: notification.source,
            type: notification.type,
            relatedEntityId: notification.relatedEntityId,
            recipientUid: 'admin',
          );
    if (_recentDedupeKeys.contains(key)) {
      debugPrint('[Notification] ADMIN DUPLICATE suppressed key=$key');
      return '';
    }
    _addDedupeKey(key);

    final collection = _adminCollection();
    if (collection == null) {
      debugPrint('[Notification] admin queue unavailable — write skipped');
      return '';
    }
    final admin = AdminNotification(
      source: notification.source,
      type: notification.type,
      studentId: notification.studentId,
      title: notification.title,
      body: notification.body,
      relatedEntityId: notification.relatedEntityId!,
      relatedScreen: notification.relatedScreen,
    );
    try {
      final ref = await collection.add(admin.toCreateMap());
      debugPrint('[Notification] adminNotification created id=${ref.id} '
          'type=${notification.type} actor=${notification.studentId}');
      return ref.id;
    } on FirebaseException catch (e) {
      debugPrint('[Notification] adminNotification write failed: $e');
      return '';
    }
  }

  /// Streams the raw admin work queue (`adminNotifications`), newest
  /// first.  An empty stream when the collection reference is unavailable.
  Stream<List<AdminNotification>> watchAdminNotifications() {
    final collection = _adminCollection();
    if (collection == null) {
      return Stream.value(const <AdminNotification>[]);
    }
    return collection.orderBy('createdAt', descending: true).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => AdminNotification.fromMap(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  /// Acknowledges an admin queue item for [adminUid] *only* (array-union
  /// into `readBy`), so one admin's read never hides work from another.
  Future<void> markAdminNotificationRead(String id, String adminUid) async {
    final collection = _adminCollection();
    if (collection == null) return;
    try {
      await collection.doc(id).update(AdminNotification.readForMap(adminUid));
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Acknowledges every admin queue item not yet read by [adminUid].
  Future<void> markAllAdminNotificationsRead(String adminUid) async {
    final collection = _adminCollection();
    if (collection == null) return;
    try {
      final snapshot = await collection.get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        final readBy = (doc.data()['readBy'] as List?)
                ?.map((e) => e.toString())
                .toList(growable: false) ??
            const <String>[];
        if (!readBy.contains(adminUid)) {
          batch.update(doc.reference, AdminNotification.readForMap(adminUid));
        }
      }
      await batch.commit();
    } on FirebaseException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Resolves whether a push should be sent for [notification] based
  /// on the recipient's [UserProfile.notificationPrefs].
  ///
  /// Missing or unreadable preferences default to `true` (send push).
  Future<bool> _resolvePreferences(CampusNotification notification) async {
    try {
      final profile = await _users.fetchProfile(notification.recipientUid);
      return profile?.notificationPrefs[notification.preferenceCategory]
          ?? true;
    } catch (_) {
      // Can't read profile — default to sending.
      return true;
    }
  }

  // ── Firestore write ───────────────────────────────────────────────

  /// Writes [notification] to the correct Firestore collection based on
  /// its [NotificationSource].
  Future<String> _writeToFirestore(CampusNotification notification) async {
    switch (notification.source) {
      case NotificationSource.lostFound:
        return _writeLfNotification(notification);
      case NotificationSource.locker:
        return _writeLockerNotification(notification);
      case NotificationSource.event:
      case NotificationSource.issue:
      case NotificationSource.system:
        // Future phases will add support for these sources.
        debugPrint('[Notification] source ${notification.source.name} '
            'is not yet supported for Firestore write');
        return '';
    }
  }

  Future<String> _writeLfNotification(CampusNotification notification) async {
    try {
      final lf = LfNotification(
        studentId: notification.studentId,
        title: notification.title,
        body: notification.body,
        type: notification.type,
        relatedReportId: notification.relatedEntityId ?? '',
      );
      final docId = await _lfWorkflow.createNotification(lf);
      debugPrint('[Notification] lfNotification created id=$docId '
          'studentId=${notification.studentId} type=${notification.type}');
      return docId;
    } on Exception catch (e) {
      debugPrint('[Notification] lfNotification write failed: $e');
      return '';
    }
  }

  Future<String> _writeLockerNotification(
      CampusNotification notification) async {
    try {
      final locker = LockerNotification(
        id: '',
        studentId: notification.studentId,
        lockerId: notification.relatedEntityId ?? '',
        title: notification.title,
        body: notification.body,
        type: notification.type,
        createdAt: DateTime.now().toIso8601String(),
      );
      await _lockers.createLockerNotification(locker);
      // LockerService.createLockerNotification doesn't return doc ID
      // today — the locker module uses .add() internally.  We log the
      // creation and return a synthetic key for idempotency tracking.
      final syntheticId = notification.dedupeKey.hashCode.toRadixString(36);
      debugPrint('[Notification] lockerNotification created '
          'studentId=${notification.studentId} type=${notification.type}');
      return syntheticId;
    } on Exception catch (e) {
      debugPrint('[Notification] lockerNotification write failed: $e');
      return '';
    }
  }

  // ── Push dispatch ─────────────────────────────────────────────────

  /// Sends a OneSignal push via the Cloudflare Worker.  Async, best-effort
  /// — failures are logged but never propagated.
  Future<void> _dispatchPush(
      CampusNotification notification, String docId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('[Notification] push skipped — no current user');
        return;
      }
      final idToken = await user.getIdToken();

      // Base URL from dart-define, same as the AI matching endpoint.
      const workerBase = String.fromEnvironment(
        'AI_WORKER_URL',
        defaultValue: 'http://127.0.0.1:8787',
      );
      final uri = Uri.parse('$workerBase/notifications/ai-match');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'firebaseIdToken': idToken,
          'studentUid': notification.recipientUid,
          'notificationId': docId,
          'relatedReportId': notification.relatedEntityId ?? '',
          'title': notification.title,
          'body': notification.body,
        }),
      );

      if (response.statusCode == 200) {
        try {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final delivered = body['delivered'] as bool? ?? false;
          final recipients = body['recipients'] as int? ?? 0;
          if (delivered) {
            debugPrint('[Notification] push delivered id=$docId '
                'recipients=$recipients');
          } else {
            debugPrint('[Notification] push NO RECIPIENTS id=$docId');
          }
        } catch (_) {
          debugPrint('[Notification] push 200 (unparseable) id=$docId');
        }
      } else {
        debugPrint('[Notification] push Worker ${response.statusCode} '
            'id=$docId body=${response.body}');
      }
    } catch (e) {
      debugPrint('[Notification] push Worker unreachable: $e');
    }
  }

  // ── Admin collection access ────────────────────────────────────

  CollectionReference<Map<String, dynamic>>? _adminCollection() {
    if (_adminCollectionResolved) return _adminCollectionCache;
    _adminCollectionResolved = true;
    try {
      _adminCollectionCache = _adminNotificationsRef?.call();
    } catch (e) {
      // Firebase not initialised (e.g. a unit test that never opted into
      // the admin queue) — admin methods degrade to no-ops.
      debugPrint('[Notification] admin collection unavailable: $e');
      _adminCollectionCache = null;
    }
    return _adminCollectionCache;
  }

  // ── Deduplication ─────────────────────────────────────────────────

  void _addDedupeKey(String key) {
    _recentDedupeKeys.add(key);
    // Drop oldest entries when the cache grows too large.
    if (_recentDedupeKeys.length > _maxDedupeCache) {
      final excess = _recentDedupeKeys.length - (_maxDedupeCache ~/ 2);
      final toRemove = _recentDedupeKeys.take(excess).toList();
      _recentDedupeKeys.removeAll(toRemove);
    }
  }

  /// Clears the in-memory dedupe cache.  Useful in tests.
  @visibleForTesting
  void clearDedupeCache() {
    _recentDedupeKeys.clear();
  }

  /// The number of entries currently in the dedupe cache.
  @visibleForTesting
  int get dedupeCacheSize => _recentDedupeKeys.length;
}

// ── Navigation metadata ──────────────────────────────────────────────

/// Returns the default GoRouter route fragment for a notification of
/// the given [source] and [relatedEntityId].
///
/// Feature modules can override this with a custom [relatedScreen] in
/// the [CampusNotification] constructor when they need a non-default
/// destination.
///
/// ```
/// lostFound  + itemA1   → /lost-found/lost/itemA1
/// locker     + LK-A01   → /lockers
/// event      + evt-123  → /events/evt-123    (future)
/// issue      + iss-456  → /issues/iss-456    (future)
/// system     + (null)   → /                   (future)
/// ```
String defaultScreenForSource(NotificationSource source,
    String? relatedEntityId) {
  switch (source) {
    case NotificationSource.lostFound:
      return relatedEntityId != null && relatedEntityId.isNotEmpty
          ? '/lost-found/lost/$relatedEntityId'
          : '/lost-found/notifications';
    case NotificationSource.locker:
      return '/lockers';
    case NotificationSource.event:
      return relatedEntityId != null && relatedEntityId.isNotEmpty
          ? '/events/$relatedEntityId'
          : '/events';
    case NotificationSource.issue:
      return relatedEntityId != null && relatedEntityId.isNotEmpty
          ? '/issues/$relatedEntityId'
          : '/issues';
    case NotificationSource.system:
      return '/';
  }
}

/// Returns the [UserProfile.notificationPrefs] key for a given
/// notification source.
///
/// Used by [NotificationService._resolvePreferences] and available for
/// feature code that needs to construct the canonical preference
/// category.
String preferenceCategoryForSource(NotificationSource source) {
  switch (source) {
    case NotificationSource.lostFound:
      return 'lostFoundMatches';
    case NotificationSource.locker:
      return 'lockerReminders';
    case NotificationSource.event:
      return 'eventUpdates';
    case NotificationSource.issue:
      return 'issueStatus';
    case NotificationSource.system:
      return 'lostFoundMatches'; // system notifications have no pref toggle
  }
}
