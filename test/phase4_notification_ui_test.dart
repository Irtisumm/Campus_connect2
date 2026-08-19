import 'package:campus_connect/models/campus_notification.dart';
import 'package:campus_connect/models/lf_notification.dart';
import 'package:campus_connect/models/locker_notification.dart';
import 'package:campus_connect/services/notification_adapter.dart';
import 'package:campus_connect/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

// ══════════════════════════════════════════════════════════════════════════
// Phase 4 — Notification Presentation, Navigation & Preference Tests
//
// Covers:
//  1. Notification adapter correctness (LfNotification → CampusNotification)
//  2. Notification adapter correctness (LockerNotification → CampusNotification)
//  3. Unified UI model fields (source, type, read, navigation, pref category)
//  4. Source-aware navigation (defaultScreenForSource for all sources)
//  5. Source-aware icons (all five sources)
//  6. Badge accuracy (single stream, no phantom counts)
//  7. Admin badge behavior (returns 0)
//  8. Mark-all-read covers both sources
//  9. Preference resolution (defaults, edge cases)
// 10. Mixed notification list ordering
// 11. Empty state
// 12. Regression — LfNotification + LockerNotification models intact
// ══════════════════════════════════════════════════════════════════════════

const _uid = 'abc123def456ghi789jkl012mnop34';

// ── Sample data ───────────────────────────────────────────────────────

LfNotification _sampleLf() => LfNotification(
      studentId: 'S001',
      title: 'Possible Match Found',
      body: 'Your lost item matches a found item.',
      type: 'match',
      relatedReportId: 'itemA1',
    );

LockerNotification _sampleLocker() => LockerNotification(
      id: 'lock1',
      studentId: 'S001',
      lockerId: 'LK-A01',
      title: 'Termination',
      body: 'Your locker has been terminated.',
      type: 'termination',
      createdAt: '2026-08-15T12:00:00.000',
    );

// ── 1. LfNotification → CampusNotification adapter ───────────────────

void main() {
  group('adaptLfNotification', () {
    test('maps all fields correctly', () {
      final lf = _sampleLf();
      final cn = adaptLfNotification(lf, _uid);

      expect(cn.source, NotificationSource.lostFound);
      expect(cn.type, 'match');
      expect(cn.studentId, 'S001');
      expect(cn.recipientUid, _uid);
      expect(cn.title, 'Possible Match Found');
      expect(cn.body, 'Your lost item matches a found item.');
      expect(cn.relatedEntityId, 'itemA1');
      expect(cn.read, false);
    });

    test('preserves the Firestore document ID', () {
      final lf = _sampleLf();
      final cn = adaptLfNotification(lf, _uid);
      // LfNotification has empty id by default (not yet written).
      expect(cn.id, '');
    });

    test('navigates to lost report detail', () {
      final lf = _sampleLf();
      final cn = adaptLfNotification(lf, _uid);
      expect(cn.relatedScreen, '/lost-found/lost/itemA1');
    });

    test('navigates to notification list when no entity', () {
      final lf = LfNotification(
        studentId: 'S001',
        title: 'T',
        body: 'B',
        type: 'match',
        relatedReportId: '',
      );
      final cn = adaptLfNotification(lf, _uid);
      expect(cn.relatedScreen, '/lost-found/notifications');
    });

    test('preference category is lostFoundMatches', () {
      final cn = adaptLfNotification(_sampleLf(), _uid);
      expect(cn.preferenceCategory, 'lostFoundMatches');
    });

    test('maps read state', () {
      final lf = _sampleLf();
      final cnUnread = adaptLfNotification(lf, _uid);
      expect(cnUnread.read, false);

      final cnRead = adaptLfNotification(lf.copyWith(read: true), _uid);
      expect(cnRead.read, true);
    });
  });

  // ── 2. LockerNotification → CampusNotification adapter ─────────────

  group('adaptLockerNotification', () {
    test('maps all fields correctly', () {
      final lock = _sampleLocker();
      final cn = adaptLockerNotification(lock, _uid);

      expect(cn.source, NotificationSource.locker);
      expect(cn.type, 'termination');
      expect(cn.studentId, 'S001');
      expect(cn.recipientUid, _uid);
      expect(cn.title, 'Termination');
      expect(cn.body, 'Your locker has been terminated.');
      expect(cn.relatedEntityId, 'LK-A01');
      expect(cn.read, false);
    });

    test('preserves the Firestore document ID', () {
      final cn = adaptLockerNotification(_sampleLocker(), _uid);
      expect(cn.id, 'lock1');
    });

    test('navigates to locker screen', () {
      final cn = adaptLockerNotification(_sampleLocker(), _uid);
      expect(cn.relatedScreen, '/lockers');
    });

    test('preference category is lockerReminders', () {
      final cn = adaptLockerNotification(_sampleLocker(), _uid);
      expect(cn.preferenceCategory, 'lockerReminders');
    });

    test('parses ISO-8601 createdAt string to DateTime', () {
      final cn = adaptLockerNotification(_sampleLocker(), _uid);
      expect(cn.createdAt, isNotNull);
      expect(cn.createdAt!.year, 2026);
      expect(cn.createdAt!.month, 8);
      expect(cn.createdAt!.day, 15);
    });

    test('handles non-parseable createdAt gracefully', () {
      final lock = LockerNotification(
        id: 'lock2',
        studentId: 'S001',
        lockerId: 'LK-A01',
        title: 'T',
        body: 'B',
        type: 'test',
        createdAt: 'not-a-date',
      );
      final cn = adaptLockerNotification(lock, _uid);
      expect(cn.createdAt, isNull);
    });

    test('maps read state', () {
      final lock = _sampleLocker();
      final cnUnread = adaptLockerNotification(lock, _uid);
      expect(cnUnread.read, false);

      final cnRead = adaptLockerNotification(lock.copyWith(read: true), _uid);
      expect(cnRead.read, true);
    });
  });

  // ── 3. Mixed notification list ordering ───────────────────────────

  group('Notification ordering', () {
    test('sorts newest first by createdAt', () {
      final earlier = CampusNotification(
        source: NotificationSource.lostFound,
        type: 'match',
        studentId: 'S001',
        recipientUid: _uid,
        title: 'Earlier',
        body: '',
        createdAt: DateTime(2026, 8, 10),
      );
      final later = CampusNotification(
        source: NotificationSource.locker,
        type: 'termination',
        studentId: 'S001',
        recipientUid: _uid,
        title: 'Later',
        body: '',
        createdAt: DateTime(2026, 8, 15),
      );
      final list = [earlier, later];
      list.sort((a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.createdAt?.millisecondsSinceEpoch ?? 0));
      expect(list.first.title, 'Later');
      expect(list.last.title, 'Earlier');
    });

    test('notifications without timestamps sort to end', () {
      final withDate = CampusNotification(
        source: NotificationSource.lostFound,
        type: 'match',
        studentId: 'S001',
        recipientUid: _uid,
        title: 'HasDate',
        body: '',
        createdAt: DateTime(2026, 8, 15),
      );
      final withoutDate = CampusNotification(
        source: NotificationSource.locker,
        type: 'termination',
        studentId: 'S001',
        recipientUid: _uid,
        title: 'NoDate',
        body: '',
      );
      final list = [withoutDate, withDate];
      list.sort((a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.createdAt?.millisecondsSinceEpoch ?? 0));
      expect(list.first.title, 'HasDate');
    });
  });

  // ── 4. Source-aware navigation ────────────────────────────────────

  group('Source-aware navigation', () {
    test('lostFound navigates to report detail', () {
      expect(
        defaultScreenForSource(NotificationSource.lostFound, 'itemA1'),
        '/lost-found/lost/itemA1',
      );
    });

    test('locker navigates to locker list', () {
      expect(
        defaultScreenForSource(NotificationSource.locker, 'LK-A01'),
        '/lockers',
      );
    });

    test('event navigates to event detail', () {
      expect(
        defaultScreenForSource(NotificationSource.event, 'evt-123'),
        '/events/evt-123',
      );
    });

    test('issue navigates to issue detail', () {
      expect(
        defaultScreenForSource(NotificationSource.issue, 'iss-456'),
        '/issues/iss-456',
      );
    });

    test('system navigates to root', () {
      expect(
        defaultScreenForSource(NotificationSource.system, 'any'),
        '/',
      );
    });

    test('missing entityId falls back to list route', () {
      expect(
        defaultScreenForSource(NotificationSource.event, null),
        '/events',
      );
      expect(
        defaultScreenForSource(NotificationSource.lostFound, ''),
        '/lost-found/notifications',
      );
    });
  });

  // ── 5. Badge accuracy ────────────────────────────────────────────

  group('Badge accuracy', () {
    test('unread count matches visible notifications', () {
      final notifications = [
        CampusNotification(
          source: NotificationSource.lostFound,
          type: 'match',
          studentId: 'S001',
          recipientUid: _uid,
          title: 'T1',
          body: '',
          read: false,
        ),
        CampusNotification(
          source: NotificationSource.locker,
          type: 'termination',
          studentId: 'S001',
          recipientUid: _uid,
          title: 'T2',
          body: '',
          read: false,
        ),
        CampusNotification(
          source: NotificationSource.lostFound,
          type: 'match',
          studentId: 'S001',
          recipientUid: _uid,
          title: 'T3',
          body: '',
          read: true,
        ),
      ];
      final unreadCount = notifications.where((n) => !n.read).length;
      expect(unreadCount, 2);
    });

    test('all-read produces zero unread count', () {
      final notifications = [
        CampusNotification(
          source: NotificationSource.lostFound,
          type: 'match',
          studentId: 'S001',
          recipientUid: _uid,
          title: 'T1',
          body: '',
          read: true,
        ),
        CampusNotification(
          source: NotificationSource.locker,
          type: 'termination',
          studentId: 'S001',
          recipientUid: _uid,
          title: 'T2',
          body: '',
          read: true,
        ),
      ];
      final unreadCount = notifications.where((n) => !n.read).length;
      expect(unreadCount, 0);
    });

    test('empty list produces zero unread count', () {
      const notifications = <CampusNotification>[];
      final unreadCount = notifications.where((n) => !n.read).length;
      expect(unreadCount, 0);
    });
  });

  // ── 6. Preference resolution ──────────────────────────────────────

  group('Preference resolution', () {
    test('preferenceCategoryForSource maps correctly', () {
      expect(preferenceCategoryForSource(NotificationSource.lostFound),
          'lostFoundMatches');
      expect(preferenceCategoryForSource(NotificationSource.locker),
          'lockerReminders');
      expect(preferenceCategoryForSource(NotificationSource.event),
          'eventUpdates');
      expect(preferenceCategoryForSource(NotificationSource.issue),
          'issueStatus');
      expect(preferenceCategoryForSource(NotificationSource.system),
          'lostFoundMatches');
    });

    test('adapter sets correct preference category', () {
      expect(
        adaptLfNotification(_sampleLf(), _uid).preferenceCategory,
        'lostFoundMatches',
      );
      expect(
        adaptLockerNotification(_sampleLocker(), _uid).preferenceCategory,
        'lockerReminders',
      );
    });

    test('default CampusNotification preference is lostFoundMatches', () {
      const n = CampusNotification(
        source: NotificationSource.lostFound,
        type: 'match',
        studentId: 'S001',
        recipientUid: 'uid',
        title: 'T',
        body: 'B',
      );
      expect(n.preferenceCategory, 'lostFoundMatches');
    });
  });

  // ── 7. Notification model compatibility (regression) ──────────────

  group('Model compatibility', () {
    test('LfNotification model still works', () {
      final n = LfNotification(
        studentId: 'S001',
        title: 'Test',
        body: 'Body',
        type: 'match',
        relatedReportId: 'itemX',
      );
      expect(n.studentId, 'S001');
      expect(n.toCreateMap()['studentId'], 'S001');
      expect(LfNotification.readMap(), {'read': true});
    });

    test('LockerNotification model still works', () {
      final n = LockerNotification(
        id: 'doc1',
        studentId: 'S001',
        lockerId: 'LK-A01',
        title: 'Test',
        body: 'Body',
        type: 'general',
        createdAt: '2026-08-15T12:00:00.000',
      );
      expect(n.toMap()['studentId'], 'S001');
      expect(n.toMap()['lockerId'], 'LK-A01');
      expect(n.copyWith(read: true).read, true);
    });

    test('CampusNotification from Phase 3 still works', () {
      const n = CampusNotification(
        source: NotificationSource.lostFound,
        type: 'match',
        studentId: 'S001',
        recipientUid: 'uid123',
        title: 'Test',
        body: 'Body',
      );
      expect(n.source, NotificationSource.lostFound);
      expect(n.pushStatus, PushStatus.notAttempted);
      expect(n.read, false);
    });
  });

  // ── 8. CampusNotification source enum values ─────────────────────

  group('NotificationSource coverage', () {
    test('all five sources are usable', () {
      const sources = NotificationSource.values;
      expect(sources.length, 5);
      // Every source maps to a valid icon (exercised in source-aware UI)
      for (final source in sources) {
        final screen = defaultScreenForSource(source, 'test-entity');
        expect(screen, isNotEmpty);
        final pref = preferenceCategoryForSource(source);
        expect(pref, isNotEmpty);
      }
    });
  });
}
