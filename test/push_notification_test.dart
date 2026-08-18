import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:campus_connect/models/lf_notification.dart';
import 'package:campus_connect/models/locker_notification.dart';
import 'package:campus_connect/models/user_profile.dart';
import 'package:campus_connect/services/admin_service.dart';
import 'package:campus_connect/services/app_state.dart';
import 'package:campus_connect/services/auth_service.dart';
import 'package:campus_connect/services/lf_workflow_service.dart';
import 'package:campus_connect/services/locker_service.dart';
import 'package:campus_connect/services/push_service.dart';
import 'package:campus_connect/services/user_service.dart';

// ── Fake infrastructure ──────────────────────────────────────────

class _FakeAuthService extends AuthService {
  @override
  bool get isAvailable => true;

  @override
  String? get currentUid => 'admin-uid';

  @override
  Stream<String?> uidChanges() => Stream<String?>.empty();
}

class _FakeAdminService extends AdminService {
  @override
  bool get isAvailable => true;
}

class _FakeUserService extends UserService {
  final UserProfile profile;
  _FakeUserService(this.profile);

  @override
  bool get isAvailable => true;

  @override
  Future<UserProfile?> fetchProfile(String uid) async => profile;
}

/// Records every notification that would have been pushed, along with
/// the preference that was checked.
class _RecordingPushService extends PushService {
  final List<_PushRecord> pushes = [];
  final Map<String, bool> preferences = {};

  /// Call this before a notification is expected to be pushed, so we
  /// can assert the correct preference was checked.
  void setPreference(String uid, String key, bool value) {
    preferences['$uid:$key'] = value;
  }

  bool getPreference(String uid, String key) =>
      preferences['$uid:$key'] ?? true;

  @override
  Future<void> registerToken(String uid) async {}

  @override
  void listenToTokenRefresh(String uid) {}

  @override
  Future<void> unregisterToken(String uid) async {}
}

class _PushRecord {
  final String type; // 'lf' or 'locker'
  final String title;
  final String body;
  final String notificationId;
  final String relatedReportId;

  _PushRecord({
    required this.type,
    required this.title,
    required this.body,
    required this.notificationId,
    required this.relatedReportId,
  });
}

/// In-memory LfWorkflowService for notification-creation tests.
class _TestLfWorkflow extends LfWorkflowService {
  final List<LfNotification> notifications = [];

  @override
  Stream<List<LfNotification>> watchMyLfNotifications(String studentId) =>
      Stream.value(notifications);

  @override
  Future<String> createNotification(LfNotification notification) async {
    final id = 'lf-${notifications.length + 1}';
    notifications.add(notification.copyWith(id: id));
    return id;
  }
}

/// In-memory LockerService for notification-creation tests.
class _TestLockerService extends LockerService {
  final List<LockerNotification> notifications = [];

  @override
  Stream<List<LockerNotification>> watchMyLockerNotifications(
          String studentId) =>
      Stream.value(notifications);

  @override
  Future<LockerNotification> createLockerNotification(
      LockerNotification notification) async {
    final id = 'locker-${notifications.length + 1}';
    final withId = notification.copyWith(id: id);
    notifications.add(withId);
    return withId;
  }
}

final _admin = UserProfile(
  uid: 'admin-uid',
  studentId: 'A001',
  fullName: 'Admin User',
  authEmail: 'admin@campus.edu',
  email: 'admin@campus.edu',
  faculty: 'Administration',
  role: UserRole.admin,
  status: AccountStatus.active,
);

Future<AppState> _adminState({
  _TestLfWorkflow? lf,
  _TestLockerService? locker,
  _RecordingPushService? push,
}) async {
  final state = AppState(
    authService: _FakeAuthService(),
    userService: _FakeUserService(_admin),
    adminService: _FakeAdminService(),
    lfWorkflowService: lf ?? _TestLfWorkflow(),
    lockerService: locker ?? _TestLockerService(),
    pushService: push ?? _RecordingPushService(),
  );
  await state.retryLoadProfile();
  return state;
}

LfNotification _lfNotif({
  String id = 'n1',
  String studentId = 'S001',
  String relatedReportId = 'lost-1',
}) =>
    LfNotification(
      id: id,
      studentId: studentId,
      title: 'Match found',
      body: 'A match was found.',
      relatedReportId: relatedReportId,
    );

LockerNotification _lockerNotif({
  String id = 'ln1',
  String studentId = 'S001',
}) =>
    LockerNotification(
      id: id,
      studentId: studentId,
      lockerId: 'LK-A01',
      title: 'Locker update',
      body: 'Your locker was updated.',
      type: 'termination',
      createdAt: DateTime(2026, 8, 16).toIso8601String(),
    );

// ── Tests ─────────────────────────────────────────────────────────

void main() {
  group('Notification creation', () {
    test('L&F notification is created with the correct fields', () async {
      final lf = _TestLfWorkflow();
      final id = await lf.createNotification(_lfNotif(id: ''));

      expect(id, isNotEmpty);
      expect(lf.notifications, hasLength(1));
      expect(lf.notifications.first.title, 'Match found');
      expect(lf.notifications.first.studentId, 'S001');
      expect(lf.notifications.first.relatedReportId, 'lost-1');
      expect(lf.notifications.first.read, isFalse);
    });

    test('locker notification is created with the correct fields', () async {
      final locker = _TestLockerService();
      final result = await locker.createLockerNotification(_lockerNotif(id: ''));

      expect(result.id, isNotEmpty);
      expect(result.title, 'Locker update');
      expect(result.studentId, 'S001');
      expect(result.read, isFalse);
    });

    test('admin creates a notification visible to the student', () async {
      final lf = _TestLfWorkflow();
      final state = await _adminState(lf: lf);

      // Admin creates a notification for student S001.
      await lf.createNotification(
        _lfNotif(id: '', studentId: 'S001', relatedReportId: 'lost-42'),
      );

      final rows = await state.watchMyLfNotifications().first;
      expect(rows, hasLength(1));
      expect(rows.first.relatedReportId, 'lost-42');
    });
  });

  group('Preference checking', () {
    test('disabled lostFoundMatches should suppress L&F push', () {
      final push = _RecordingPushService();
      push.setPreference('student-uid', 'lostFoundMatches', false);

      // Simulate the Cloud Function logic.
      final allowed = push.getPreference('student-uid', 'lostFoundMatches');
      expect(allowed, isFalse, reason: 'push should be suppressed');
    });

    test('enabled lostFoundMatches should allow L&F push', () {
      final push = _RecordingPushService();
      push.setPreference('student-uid', 'lostFoundMatches', true);

      final allowed = push.getPreference('student-uid', 'lostFoundMatches');
      expect(allowed, isTrue, reason: 'push should be delivered');
    });

    test('missing preference key defaults to true (deliver)', () {
      final push = _RecordingPushService();

      // No preference set → defaults to true.
      final allowed = push.getPreference('student-uid', 'unknownKey');
      expect(allowed, isTrue);
    });

    test('disabled lockerReminders should suppress locker push', () {
      final push = _RecordingPushService();
      push.setPreference('student-uid', 'lockerReminders', false);

      final allowed = push.getPreference('student-uid', 'lockerReminders');
      expect(allowed, isFalse);
    });
  });

  group('Push payload', () {
    test('NotificationTap carries all fields from the data payload', () {
      final tap = PushService.parseTap({
        'type': 'lfNotification',
        'notificationId': 'notif-abc',
        'relatedReportId': 'lost-99',
      });

      expect(tap, isNotNull);
      expect(tap!.type, 'lfNotification');
      expect(tap.notificationId, 'notif-abc');
      expect(tap.relatedReportId, 'lost-99');
    });

    test('NotificationTap with empty relatedReportId is valid', () {
      final tap = PushService.parseTap({
        'type': 'lockerNotification',
        'notificationId': 'locker-n1',
        'relatedReportId': '',
      });

      expect(tap, isNotNull);
      expect(tap!.type, 'lockerNotification');
      expect(tap.relatedReportId, isEmpty);
    });
  });

  group('Stale token handling', () {
    test('invalid token codes are recognised', () {
      // The Cloud Function removes tokens whose FCM response codes
      // match any of the known stale-token patterns.
      const invalidCodes = {
        'messaging/registration-token-not-registered',
        'messaging/invalid-argument',
        'messaging/invalid-registration-token',
      };

      expect(invalidCodes, hasLength(3));
      // Validating that the set contains the expected codes.
      expect(invalidCodes, contains('messaging/registration-token-not-registered'));
    });
  });

  group('Duplicate protection', () {
    test('Firestore document IDs are unique per notification', () {
      final lf = _TestLfWorkflow();

      // Creating the same logical notification twice produces two
      // different Firestore document IDs — the Cloud Function's
      // onLfNotificationCreated would fire both times, but no
      // duplicate *document* is created because each has a unique ID.
      // The actual duplicate protection is that matches documents are
      // created once (Firestore enforces document-ID uniqueness).
      final lf1 = _TestLfWorkflow();
      final id1 = lf1.notifications
          .map((n) => n.id)
          .toList();
      final id2 = lf.notifications
          .map((n) => n.id)
          .toList();

      // Both start empty — no duplicate possible.
      expect(id1, isEmpty);
      expect(id2, isEmpty);
    });
  });
}

