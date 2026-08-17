import 'package:flutter_test/flutter_test.dart';

import 'package:campus_connect/models/auth_result.dart';
import 'package:campus_connect/models/item.dart';
import 'package:campus_connect/models/lf_notification.dart';
import 'package:campus_connect/models/user_profile.dart';
import 'package:campus_connect/services/admin_service.dart';
import 'package:campus_connect/services/app_state.dart';
import 'package:campus_connect/services/auth_service.dart';
import 'package:campus_connect/services/lf_workflow_service.dart';
import 'package:campus_connect/services/lost_found_service.dart';
import 'package:campus_connect/services/user_service.dart';

/// A [LostFoundService] that never touches Firestore — it records the write
/// calls AppState makes so the fixed closure reasons and status transitions
/// can be asserted deterministically.
class _RecordingLostFoundService extends LostFoundService {
  final List<(String, ItemStatus)> statusCalls = [];
  final List<(String, ItemStatus, String)> statusWithReasonCalls = [];
  Item? createdItem;

  @override
  Future<void> updateStatus(String id, ItemStatus newStatus) async {
    statusCalls.add((id, newStatus));
  }

  @override
  Future<void> updateStatusWithReason(
      String id, ItemStatus newStatus, String reason) async {
    statusWithReasonCalls.add((id, newStatus, reason));
  }

  @override
  Future<Item> createItem(Item item) async {
    createdItem = item;
    return item.copyWith(id: 'new-id');
  }
}

class _RecordingLfWorkflowService extends LfWorkflowService {
  final List<String> rejectedReports = [];

  @override
  Future<void> rejectActiveMatchesForReport(String lostReportId) async {
    rejectedReports.add(lostReportId);
  }
}

/// Minimal test doubles so [AppState.retryLoadProfile] can load a known
/// profile without Firebase being initialised.
class _FakeAuthService extends AuthService {
  @override
  bool get isAvailable => true;

  @override
  String? get currentUid => 'student-uid';

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

class _ThrowingUserService extends UserService {
  @override
  bool get isAvailable => true;

  @override
  Future<UserProfile?> fetchProfile(String uid) async =>
      throw const AuthFailure('profile unavailable');
}

class _UnreadLfWorkflowService extends LfWorkflowService {
  final List<LfNotification> notifications;
  _UnreadLfWorkflowService(this.notifications);

  @override
  Stream<List<LfNotification>> watchMyLfNotifications(String studentId) =>
      Stream.value(notifications);
}

Item _lost({String title = 'Blue water bottle'}) => Item(
      id: 'r1',
      type: ItemType.lost,
      title: title,
      category: 'Bottle',
      description: 'Blue water bottle',
      whereLost: 'Canteen',
      whenLost: DateTime(2026, 8, 16),
      reportedByUid: 'student-uid',
      reportedByStudentId: 'S001',
      reportedByName: 'Alice Smith',
      closeReason: 'ADMIN_RESOLVED',
    );

void main() {
  group('Item model — reportedByName / closeReason immutability', () {
    test('toCreateMap writes reportedByName but never closeReason', () {
      final map = _lost().toCreateMap();
      expect(map['reportedByName'], 'Alice Smith');
      expect(map.containsKey('closeReason'), isFalse);
    });

    test('toUpdateMap never writes reportedByName or closeReason', () {
      final map = _lost().toUpdateMap();
      expect(map.containsKey('reportedByName'), isFalse);
      expect(map.containsKey('closeReason'), isFalse);
    });

    test('copyWith preserves reportedByName and closeReason', () {
      final updated = _lost().copyWith(title: 'New title');
      expect(updated.reportedByName, 'Alice Smith');
      expect(updated.closeReason, 'ADMIN_RESOLVED');
    });

    test('fromMap reads reportedByName and closeReason', () {
      final parsed = Item.fromMap('r1', {
        'type': 'lost',
        'title': 'Bottle',
        'reportedByName': 'Alice Smith',
        'closeReason': 'STUDENT_REQUEST_APPROVED',
      });
      expect(parsed.reportedByName, 'Alice Smith');
      expect(parsed.closeReason, 'STUDENT_REQUEST_APPROVED');
    });

    test('fromMap defaults reportedByName to empty and closeReason to null',
        () {
      final parsed = Item.fromMap('r1', {'type': 'lost', 'title': 'Bottle'});
      expect(parsed.reportedByName, '');
      expect(parsed.closeReason, isNull);
    });
  });

  group('AppState closure paths', () {
    test('requestClose transitions the report to Requested Close', () async {
      final lost = _RecordingLostFoundService();
      final state = AppState(
        lostFoundService: lost,
        lfWorkflowService: _RecordingLfWorkflowService(),
      );

      await state.requestClose('r1');

      expect(lost.statusCalls, [('r1', ItemStatus.requestedClose)]);
      expect(lost.statusWithReasonCalls, isEmpty);
    });

    test('closeReport (admin found close) transitions to Closed', () async {
      final lost = _RecordingLostFoundService();
      final state = AppState(
        lostFoundService: lost,
        lfWorkflowService: _RecordingLfWorkflowService(),
      );

      await state.closeReport('r1');

      expect(lost.statusCalls, [('r1', ItemStatus.closed)]);
    });

    test('approveCloseRequest stores STUDENT_REQUEST_APPROVED and rejects matches',
        () async {
      final lost = _RecordingLostFoundService();
      final wf = _RecordingLfWorkflowService();
      final state =
          AppState(lostFoundService: lost, lfWorkflowService: wf);

      await state.approveCloseRequest('r1');

      expect(lost.statusWithReasonCalls, [
        ('r1', ItemStatus.closed, AppState.closeReasonStudentRequestApproved),
      ]);
      expect(wf.rejectedReports, ['r1']);
    });

    test('markAsResolved stores ADMIN_RESOLVED and rejects matches', () async {
      final lost = _RecordingLostFoundService();
      final wf = _RecordingLfWorkflowService();
      final state =
          AppState(lostFoundService: lost, lfWorkflowService: wf);

      await state.markAsResolved('r1');

      expect(lost.statusWithReasonCalls, [
        ('r1', ItemStatus.closed, AppState.closeReasonAdminResolved),
      ]);
      expect(wf.rejectedReports, ['r1']);
    });
  });

  group('createReport sources the reporter name from the profile', () {
    test('ignores a client-supplied reportedByName', () async {
      final profile = UserProfile(
        uid: 'student-uid',
        studentId: 'S001',
        fullName: 'Alice Smith',
        authEmail: 'alice@campus.edu',
        email: 'alice@campus.edu',
        faculty: 'Computing',
        role: UserRole.student,
        status: AccountStatus.active,
      );
      final lost = _RecordingLostFoundService();
      final state = AppState(
        authService: _FakeAuthService(),
        userService: _FakeUserService(profile),
        adminService: _FakeAdminService(),
        lostFoundService: lost,
        lfWorkflowService: _RecordingLfWorkflowService(),
      );
      await state.retryLoadProfile();

      // A hostile form payload claiming a different name must be ignored.
      final report = Item(
        type: ItemType.lost,
        title: 'Blue water bottle',
        category: 'Bottle',
        description: 'Blue water bottle',
        whereLost: 'Canteen',
        reportedByUid: 'student-uid',
        reportedByStudentId: 'S001',
        reportedByName: 'FAKE NAME',
      );
      await state.createReport(report);

      expect(lost.createdItem!.reportedByName, 'Alice Smith');
      // The report is always born Active, never user-chosen.
      expect(lost.createdItem!.status, ItemStatus.active);
    });
  });

  group('fetchReporterName', () {
    test('returns the reporter profile fullName', () async {
      final profile = UserProfile(
        uid: 'student-uid',
        studentId: 'S001',
        fullName: 'Alice Smith',
        authEmail: 'alice@campus.edu',
        email: 'alice@campus.edu',
        faculty: 'Computing',
        role: UserRole.student,
        status: AccountStatus.active,
      );
      final state = AppState(
        authService: _FakeAuthService(),
        userService: _FakeUserService(profile),
        adminService: _FakeAdminService(),
        lostFoundService: _RecordingLostFoundService(),
        lfWorkflowService: _RecordingLfWorkflowService(),
      );

      expect(await state.fetchReporterName('student-uid'), 'Alice Smith');
    });

    test('returns null when the profile cannot be loaded', () async {
      final state = AppState(
        authService: _FakeAuthService(),
        userService: _ThrowingUserService(),
        adminService: _FakeAdminService(),
        lostFoundService: _RecordingLostFoundService(),
        lfWorkflowService: _RecordingLfWorkflowService(),
      );

      expect(await state.fetchReporterName('student-uid'), isNull);
    });

    test('returns null for an empty uid without a lookup', () async {
      final state = AppState(
        authService: _FakeAuthService(),
        userService: _ThrowingUserService(),
        adminService: _FakeAdminService(),
        lostFoundService: _RecordingLostFoundService(),
        lfWorkflowService: _RecordingLfWorkflowService(),
      );

      expect(await state.fetchReporterName(''), isNull);
    });
  });

  group('watchUnreadLfNotifications', () {
    test('counts only unread notifications', () async {
      final wf = _UnreadLfWorkflowService([
        LfNotification(
            id: 'n1', studentId: 'S001', title: 'a', body: 'b', read: false),
        LfNotification(
            id: 'n2', studentId: 'S001', title: 'c', body: 'd', read: true),
        LfNotification(
            id: 'n3', studentId: 'S001', title: 'e', body: 'f', read: false),
      ]);
      final state = AppState(
        lostFoundService: _RecordingLostFoundService(),
        lfWorkflowService: wf,
      );

      expect(await state.watchUnreadLfNotifications().first, 2);
    });

    test('reports zero once every notification is read', () async {
      final wf = _UnreadLfWorkflowService([
        LfNotification(
            id: 'n1', studentId: 'S001', title: 'a', body: 'b', read: true),
        LfNotification(
            id: 'n2', studentId: 'S001', title: 'c', body: 'd', read: true),
      ]);
      final state = AppState(
        lostFoundService: _RecordingLostFoundService(),
        lfWorkflowService: wf,
      );

      expect(await state.watchUnreadLfNotifications().first, 0);
    });
  });
}
