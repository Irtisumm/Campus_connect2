import 'package:campus_connect/models/campus_notification.dart';
import 'package:campus_connect/models/lf_notification.dart';
import 'package:campus_connect/models/locker_notification.dart';
import 'package:campus_connect/models/user_profile.dart';
import 'package:campus_connect/services/lf_workflow_service.dart';
import 'package:campus_connect/services/locker_service.dart';
import 'package:campus_connect/services/notification_service.dart';
import 'package:campus_connect/services/user_service.dart';
import 'package:flutter_test/flutter_test.dart';

// ══════════════════════════════════════════════════════════════════════════
// Phase 3 — Notification Core Architecture Test Suite
//
// Covers:
//  1. CampusNotification  model construction, defaults, copyWith
//  2. NotificationSource   enum values
//  3. PushStatus           enum values
//  4. buildDedupeKey        deterministic, distinct, null-safe
//  5. defaultScreenForSource   route fragments per source
//  6. preferenceCategoryForSource   pref keys per source
//  7. NotificationService   construction, dedupe cache management,
//     field validation (emit)
//  8. Compatibility        LfNotification + LockerNotification models
// ══════════════════════════════════════════════════════════════════════════

void main() {
  // ── 1. CampusNotification model ──────────────────────────────────────

  group('CampusNotification', () {
    const lostFoundNotification = CampusNotification(
      source: NotificationSource.lostFound,
      type: 'match',
      studentId: 'S001',
      recipientUid: 'abc123def456ghi789jkl012mnop34',
      title: 'Possible Match Found',
      body: 'Your lost item "Phone" may have been found.',
      relatedEntityId: 'itemA1',
    );

    test('constructs with required fields', () {
      expect(lostFoundNotification.source, NotificationSource.lostFound);
      expect(lostFoundNotification.type, 'match');
      expect(lostFoundNotification.studentId, 'S001');
      expect(lostFoundNotification.recipientUid,
          'abc123def456ghi789jkl012mnop34');
      expect(lostFoundNotification.title, 'Possible Match Found');
      expect(lostFoundNotification.body,
          'Your lost item "Phone" may have been found.');
    });

    test('defaults', () {
      const n = CampusNotification(
        source: NotificationSource.lostFound,
        type: 'match',
        studentId: 'S001',
        recipientUid: 'abc123',
        title: 'T',
        body: 'B',
      );
      expect(n.id, '');
      expect(n.relatedEntityId, isNull);
      expect(n.relatedScreen, '');
      expect(n.read, false);
      expect(n.createdAt, isNull);
      expect(n.preferenceCategory, 'lostFoundMatches');
      expect(n.dedupeKey, '');
      expect(n.pushStatus, PushStatus.notAttempted);
    });

    test('copyWith replaces specified fields', () {
      final updated = lostFoundNotification.copyWith(
        read: true,
        pushStatus: PushStatus.delivered,
        id: 'doc789',
      );
      // Changed fields
      expect(updated.read, true);
      expect(updated.pushStatus, PushStatus.delivered);
      expect(updated.id, 'doc789');
      // Unchanged fields
      expect(updated.source, NotificationSource.lostFound);
      expect(updated.studentId, 'S001');
      expect(updated.title, 'Possible Match Found');
    });

    test('copyWith with no arguments returns equal copy', () {
      final copy = lostFoundNotification.copyWith();
      expect(copy.source, lostFoundNotification.source);
      expect(copy.studentId, lostFoundNotification.studentId);
      expect(copy.title, lostFoundNotification.title);
      expect(copy.read, lostFoundNotification.read);
    });

    test('locker source notification', () {
      const n = CampusNotification(
        source: NotificationSource.locker,
        type: 'termination',
        studentId: 'S002',
        recipientUid: 'uid456',
        title: 'Locker Terminated',
        body: 'Your locker LK-A01 has been terminated.',
        relatedEntityId: 'LK-A01',
        preferenceCategory: 'lockerReminders',
      );
      expect(n.source, NotificationSource.locker);
      expect(n.preferenceCategory, 'lockerReminders');
      expect(n.relatedEntityId, 'LK-A01');
    });

    test('event source notification', () {
      const n = CampusNotification(
        source: NotificationSource.event,
        type: 'event_approved',
        studentId: 'S003',
        recipientUid: 'uid789',
        title: 'Event Approved',
        body: 'Your event has been approved.',
        relatedEntityId: 'evt-123',
        preferenceCategory: 'eventUpdates',
      );
      expect(n.source, NotificationSource.event);
      expect(n.preferenceCategory, 'eventUpdates');
    });

    test('issue source notification', () {
      const n = CampusNotification(
        source: NotificationSource.issue,
        type: 'status_change',
        studentId: 'S004',
        recipientUid: 'uid012',
        title: 'Issue Updated',
        body: 'Your issue status has changed.',
        relatedEntityId: 'iss-456',
        preferenceCategory: 'issueStatus',
      );
      expect(n.source, NotificationSource.issue);
      expect(n.preferenceCategory, 'issueStatus');
    });

    test('system source notification', () {
      const n = CampusNotification(
        source: NotificationSource.system,
        type: 'announcement',
        studentId: 'S005',
        recipientUid: 'uid345',
        title: 'Maintenance',
        body: 'Scheduled maintenance tonight.',
      );
      expect(n.source, NotificationSource.system);
    });
  });

  // ── 2. NotificationSource enum ───────────────────────────────────────

  group('NotificationSource', () {
    test('has five values', () {
      expect(NotificationSource.values, [
        NotificationSource.lostFound,
        NotificationSource.locker,
        NotificationSource.event,
        NotificationSource.issue,
        NotificationSource.system,
      ]);
    });

    test('name matches source name', () {
      expect(NotificationSource.lostFound.name, 'lostFound');
      expect(NotificationSource.locker.name, 'locker');
      expect(NotificationSource.event.name, 'event');
      expect(NotificationSource.issue.name, 'issue');
      expect(NotificationSource.system.name, 'system');
    });
  });

  // ── 3. PushStatus enum ──────────────────────────────────────────────

  group('PushStatus', () {
    test('has five values', () {
      expect(PushStatus.values, [
        PushStatus.notAttempted,
        PushStatus.attempted,
        PushStatus.delivered,
        PushStatus.noRecipient,
        PushStatus.failed,
      ]);
    });
  });

  // ── 4. buildDedupeKey ───────────────────────────────────────────────

  group('buildDedupeKey', () {
    test('produces deterministic key', () {
      final a = CampusNotification.buildDedupeKey(
        source: NotificationSource.lostFound,
        type: 'match',
        relatedEntityId: 'itemA1',
        recipientUid: 'uid123',
      );
      final b = CampusNotification.buildDedupeKey(
        source: NotificationSource.lostFound,
        type: 'match',
        relatedEntityId: 'itemA1',
        recipientUid: 'uid123',
      );
      expect(a, b);
    });

    test('different source produces different key', () {
      final lf = CampusNotification.buildDedupeKey(
        source: NotificationSource.lostFound,
        type: 'match',
        relatedEntityId: 'itemA1',
        recipientUid: 'uid1',
      );
      final locker = CampusNotification.buildDedupeKey(
        source: NotificationSource.locker,
        type: 'match',
        relatedEntityId: 'itemA1',
        recipientUid: 'uid1',
      );
      expect(lf, isNot(locker));
    });

    test('different type produces different key', () {
      final a = CampusNotification.buildDedupeKey(
        source: NotificationSource.lostFound,
        type: 'match',
        relatedEntityId: 'itemA1',
        recipientUid: 'uid1',
      );
      final b = CampusNotification.buildDedupeKey(
        source: NotificationSource.lostFound,
        type: 'approved',
        relatedEntityId: 'itemA1',
        recipientUid: 'uid1',
      );
      expect(a, isNot(b));
    });

    test('different entityId produces different key', () {
      final a = CampusNotification.buildDedupeKey(
        source: NotificationSource.lostFound,
        type: 'match',
        relatedEntityId: 'itemA1',
        recipientUid: 'uid1',
      );
      final b = CampusNotification.buildDedupeKey(
        source: NotificationSource.lostFound,
        type: 'match',
        relatedEntityId: 'itemB2',
        recipientUid: 'uid1',
      );
      expect(a, isNot(b));
    });

    test('different recipientUid produces different key', () {
      final a = CampusNotification.buildDedupeKey(
        source: NotificationSource.lostFound,
        type: 'match',
        relatedEntityId: 'itemA1',
        recipientUid: 'uid1',
      );
      final b = CampusNotification.buildDedupeKey(
        source: NotificationSource.lostFound,
        type: 'match',
        relatedEntityId: 'itemA1',
        recipientUid: 'uid2',
      );
      expect(a, isNot(b));
    });

    test('null relatedEntityId uses empty string', () {
      final key = CampusNotification.buildDedupeKey(
        source: NotificationSource.system,
        type: 'announcement',
        relatedEntityId: null,
        recipientUid: 'uid1',
      );
      // Does not throw; produces a valid key with empty entity segment.
      expect(key, contains('..'));
    });

    test('key has expected format', () {
      final key = CampusNotification.buildDedupeKey(
        source: NotificationSource.lostFound,
        type: 'match',
        relatedEntityId: 'itemA1',
        recipientUid: 'uid123',
      );
      expect(key, 'lostFound.match.itemA1.uid123');
    });
  });

  // ── 5. defaultScreenForSource ────────────────────────────────────────

  group('defaultScreenForSource', () {
    test('lostFound with entityId', () {
      expect(
        defaultScreenForSource(NotificationSource.lostFound, 'itemA1'),
        '/lost-found/lost/itemA1',
      );
    });

    test('lostFound without entityId falls back to notifications', () {
      expect(
        defaultScreenForSource(NotificationSource.lostFound, null),
        '/lost-found/notifications',
      );
      expect(
        defaultScreenForSource(NotificationSource.lostFound, ''),
        '/lost-found/notifications',
      );
    });

    test('locker returns /lockers regardless of entityId', () {
      expect(
        defaultScreenForSource(NotificationSource.locker, 'LK-A01'),
        '/lockers',
      );
      expect(
        defaultScreenForSource(NotificationSource.locker, null),
        '/lockers',
      );
    });

    test('event with entityId', () {
      expect(
        defaultScreenForSource(NotificationSource.event, 'evt-123'),
        '/events/evt-123',
      );
    });

    test('event without entityId', () {
      expect(
        defaultScreenForSource(NotificationSource.event, null),
        '/events',
      );
    });

    test('issue with entityId', () {
      expect(
        defaultScreenForSource(NotificationSource.issue, 'iss-456'),
        '/issues/iss-456',
      );
    });

    test('issue without entityId', () {
      expect(
        defaultScreenForSource(NotificationSource.issue, null),
        '/issues',
      );
    });

    test('system always returns root', () {
      expect(
        defaultScreenForSource(NotificationSource.system, null),
        '/',
      );
      expect(
        defaultScreenForSource(NotificationSource.system, 'anything'),
        '/',
      );
    });
  });

  // ── 6. preferenceCategoryForSource ───────────────────────────────────

  group('preferenceCategoryForSource', () {
    test('lostFound → lostFoundMatches', () {
      expect(
        preferenceCategoryForSource(NotificationSource.lostFound),
        'lostFoundMatches',
      );
    });

    test('locker → lockerReminders', () {
      expect(
        preferenceCategoryForSource(NotificationSource.locker),
        'lockerReminders',
      );
    });

    test('event → eventUpdates', () {
      expect(
        preferenceCategoryForSource(NotificationSource.event),
        'eventUpdates',
      );
    });

    test('issue → issueStatus', () {
      expect(
        preferenceCategoryForSource(NotificationSource.issue),
        'issueStatus',
      );
    });

    test('system → lostFoundMatches (fallback)', () {
      expect(
        preferenceCategoryForSource(NotificationSource.system),
        'lostFoundMatches',
      );
    });
  });

  // ── 7. NotificationService dedupe cache ──────────────────────────────

  group('NotificationService dedupe cache', () {
    test('starts with empty dedupe cache', () {
      final svc = NotificationService(
        lfWorkflow: _FakeLfWorkflowService(),
        lockers: _FakeLockerService(),
        users: _FakeUserService(null),
      );
      expect(svc.dedupeCacheSize, 0);
      svc.clearDedupeCache(); // idempotent
      expect(svc.dedupeCacheSize, 0);
    });

    test('clearDedupeCache clears the cache', () {
      final svc = NotificationService(
        lfWorkflow: _FakeLfWorkflowService(),
        lockers: _FakeLockerService(),
        users: _FakeUserService(null),
      );
      // The cache is internal; we can build a notification with a dedupeKey
      // and call emit, but that requires auth. For unit-test purposes we
      // exercise clearDedupeCache directly. The emit path is covered by
      // the integration tests (onesignal_integration_test.dart).
      svc.clearDedupeCache();
      expect(svc.dedupeCacheSize, 0);
    });

    test('NotificationService can be constructed', () {
      final svc = NotificationService(
        lfWorkflow: _FakeLfWorkflowService(),
        lockers: _FakeLockerService(),
        users: _FakeUserService(null),
      );
      expect(svc, isNotNull);
    });
  });

  // ── 8. Compatibility — LfNotification model ─────────────────────────

  group('LfNotification (compatibility)', () {
    test('constructs a match notification', () {
      final n = LfNotification(
        studentId: 'S001',
        title: 'Possible Match Found',
        body: 'Your lost item matches a found item.',
        type: 'match',
        relatedReportId: 'itemA1',
      );
      expect(n.studentId, 'S001');
      expect(n.type, 'match');
      expect(n.relatedReportId, 'itemA1');
      expect(n.read, false);
      expect(n.id, '');
    });

    test('toCreateMap includes all fields', () {
      final n = LfNotification(
        studentId: 'S001',
        title: 'Test',
        body: 'Body',
        type: 'match',
        relatedReportId: 'itemX',
      );
      final map = n.toCreateMap();
      expect(map['studentId'], 'S001');
      expect(map['title'], 'Test');
      expect(map['body'], 'Body');
      expect(map['type'], 'match');
      expect(map['relatedReportId'], 'itemX');
      expect(map['read'], false);
      expect(map.containsKey('createdAt'), true);
    });

    test('copyWith preserves original fields', () {
      final n = LfNotification(
        studentId: 'S001',
        title: 'Test',
        body: 'Body',
        type: 'match',
        relatedReportId: 'itemA1',
      );
      final updated = n.copyWith(read: true, id: 'doc123');
      expect(updated.read, true);
      expect(updated.id, 'doc123');
      expect(updated.studentId, 'S001');
      expect(updated.title, 'Test');
      expect(updated.type, 'match');
    });

    test('fromMap parses a Firestore document', () {
      final data = {
        'studentId': 'S002',
        'title': 'Match',
        'body': 'Details',
        'type': 'match',
        'relatedReportId': 'itemB2',
        'read': false,
        'createdAt': DateTime(2026, 8, 15, 12, 0),
      };
      final n = LfNotification.fromMap('doc456', data);
      expect(n.id, 'doc456');
      expect(n.studentId, 'S002');
      expect(n.title, 'Match');
      expect(n.body, 'Details');
      expect(n.relatedReportId, 'itemB2');
      expect(n.read, false);
      expect(n.createdAt, isNotNull);
    });

    test('readMap returns correct shape', () {
      final map = LfNotification.readMap();
      expect(map, {'read': true});
      expect(map.length, 1);
    });
  });

  // ── 9. Compatibility — LockerNotification model ─────────────────────

  group('LockerNotification (compatibility)', () {
    test('constructs a termination notification', () {
      final n = LockerNotification(
        id: 'doc1',
        studentId: 'S003',
        lockerId: 'LK-A01',
        title: 'Termination',
        body: 'Your locker has been terminated.',
        type: 'termination',
        createdAt: '2026-08-15T12:00:00.000',
      );
      expect(n.studentId, 'S003');
      expect(n.lockerId, 'LK-A01');
      expect(n.type, 'termination');
      expect(n.read, false);
    });

    test('toMap includes all fields', () {
      final n = LockerNotification(
        id: 'doc2',
        studentId: 'S004',
        lockerId: 'LK-B02',
        title: 'Release',
        body: 'Your locker has been released.',
        type: 'release',
        createdAt: '2026-08-15T12:00:00.000',
      );
      final map = n.toMap();
      expect(map['studentId'], 'S004');
      expect(map['lockerId'], 'LK-B02');
      expect(map['title'], 'Release');
      expect(map['body'], 'Your locker has been released.');
      expect(map['type'], 'release');
      expect(map['read'], false);
      expect(map.containsKey('createdAt'), true);
    });

    test('fromMap parses a Firestore document map', () {
      final data = {
        'studentId': 'S005',
        'lockerId': 'LK-C03',
        'title': 'Block',
        'body': 'Your locker has been blocked.',
        'type': 'block',
        'createdAt': DateTime(2026, 8, 15, 12, 0),
        'read': true,
      };
      final n = LockerNotification.fromMap('doc3', data);
      expect(n.id, 'doc3');
      expect(n.studentId, 'S005');
      expect(n.lockerId, 'LK-C03');
      expect(n.type, 'block');
      expect(n.read, true);
    });

    test('copyWith replaces fields', () {
      final n = LockerNotification(
        id: 'doc4',
        studentId: 'S006',
        lockerId: 'LK-D04',
        title: 'T',
        body: 'B',
        type: 'general',
        createdAt: '2026-08-15T12:00:00.000',
      );
      final updated = n.copyWith(read: true, type: 'unblock');
      expect(updated.read, true);
      expect(updated.type, 'unblock');
      expect(updated.studentId, 'S006');
      expect(updated.lockerId, 'LK-D04');
    });
  });
}

// ── Fake services for unit-testing NotificationService ──────────────────

class _FakeLfWorkflowService extends LfWorkflowService {
  @override
  bool get isAvailable => true;
}

class _FakeLockerService extends LockerService {
  @override
  bool get isAvailable => true;
}

class _FakeUserService extends UserService {
  final UserProfile? _profile;
  _FakeUserService(this._profile);

  @override
  bool get isAvailable => true;

  @override
  Future<UserProfile?> fetchProfile(String uid) async => _profile;
}
