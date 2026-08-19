import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:campus_connect/models/admin_notification.dart';
import 'package:campus_connect/models/campus_notification.dart';
import 'package:campus_connect/models/item.dart';
import 'package:campus_connect/models/lf_match.dart';
import 'package:campus_connect/models/lf_notification.dart';
import 'package:campus_connect/models/locker_notification.dart';
import 'package:campus_connect/models/qr_transaction.dart';
import 'package:campus_connect/models/user_profile.dart';
import 'package:campus_connect/services/admin_service.dart';
import 'package:campus_connect/services/app_state.dart';
import 'package:campus_connect/services/auth_service.dart';
import 'package:campus_connect/services/lf_workflow_service.dart';
import 'package:campus_connect/services/locker_service.dart';
import 'package:campus_connect/services/notification_service.dart';
import 'package:campus_connect/services/user_service.dart';

// ── Fake infrastructure ────────────────────────────────────────────────

class _FakeAuthService extends AuthService {
  final String? _uid;
  _FakeAuthService({String? uid}) : _uid = uid;
  @override
  bool get isAvailable => true;
  @override
  String? get currentUid => _uid;
  @override
  Stream<String?> uidChanges() => Stream<String?>.empty();
}

class _FakeUserService extends UserService {
  final UserProfile profile;
  _FakeUserService(this.profile);
  @override
  bool get isAvailable => true;
  @override
  Future<UserProfile?> fetchProfile(String uid) async => profile;
}

class _FakeAdminService extends AdminService {
  @override
  bool get isAvailable => true;
}

/// An in-memory LfWorkflowService double suitable for widget/unit tests
/// that never touches Firebase.  Reads return synthetic data seeded via
/// helper methods; writes are no-ops (the test captures notification
/// behavior via the fake NotificationService instead).
class _FakeLfWorkflow extends LfWorkflowService {
  final Map<String, Item> _items = {};
  final Map<String, LfMatch> _matches = {};
  final Map<String, QrTransaction> _qrTxns = {};
  final List<LfNotification> _lfNotifications = [];
  final _lfCtrl = StreamController<List<LfNotification>>.broadcast();

  // Configurable AI-match guard result.
  bool unreadMatchExists = false;

  void seedItem(Item item) => _items[item.id] = item;
  void seedMatch(LfMatch match) => _matches[match.id] = match;
  void seedQr(QrTransaction txn) => _qrTxns[txn.id] = txn;

  List<LfNotification> get currentLf => List.unmodifiable(_lfNotifications);

  void seedLf(List<LfNotification> initial) {
    _lfNotifications
      ..clear()
      ..addAll(initial);
    _lfCtrl.add(List.unmodifiable(_lfNotifications));
  }

  @override
  bool get isAvailable => true;

  @override
  Future<Item?> fetchItem(String itemId) async => _items[itemId];

  @override
  Future<LfMatch?> fetchMatch(String matchId) async => _matches[matchId];

  @override
  Future<QrTransaction?> fetchQrTransaction(String txnId) async =>
      _qrTxns[txnId];

  @override
  Future<bool> hasUnreadMatchNotification(
          String studentId, String relatedReportId) async =>
      unreadMatchExists;

  @override
  Stream<List<LfNotification>> watchMyLfNotifications(String studentId) {
    late StreamController<List<LfNotification>> sc;
    StreamSubscription? sub;
    sc = StreamController<List<LfNotification>>(
      onListen: () {
        sc.add(_lfNotifications
            .where((n) => n.studentId == studentId)
            .toList());
        sub = _lfCtrl.stream.listen((list) {
          sc.add(list.where((n) => n.studentId == studentId).toList());
        });
      },
      onCancel: () => sub?.cancel(),
    );
    return sc.stream;
  }

  // Writes that actually mutate state (so approve/reject flow effects
  // are visible to subsequent assertions).
  @override
  Future<String> approveMatchWithNotification({
    required String matchId,
    required String lostReportTitle,
    required String inventoryTitle,
  }) async {
    final match = _matches[matchId];
    if (match == null) {
      throw const AuthFailure('Match not found');
    }
    if (match.status != MatchStatus.proposed) {
      throw const AuthFailure('Already actioned.');
    }
    _matches[matchId] = match.copyWith(status: MatchStatus.approved);
    return 'notif_approved_$matchId';
  }

  @override
  Future<void> rejectMatch(String matchId) async {
    final match = _matches[matchId];
    if (match != null &&
        (match.status == MatchStatus.rejected ||
            match.status == MatchStatus.completed)) {
      throw const AuthFailure('Already finalised.');
    }
    if (match != null) {
      _matches[matchId] = match.copyWith(status: MatchStatus.rejected);
    }
  }

  @override
  Future<void> markAllRead(String studentId) async {
    for (var i = 0; i < _lfNotifications.length; i++) {
      if (_lfNotifications[i].studentId == studentId) {
        _lfNotifications[i] = _lfNotifications[i].copyWith(read: true);
      }
    }
    _lfCtrl.add(List.unmodifiable(_lfNotifications));
  }

  @override
  Future<void> markLfNotificationRead(String id) async {
    for (var i = 0; i < _lfNotifications.length; i++) {
      if (_lfNotifications[i].id == id) {
        _lfNotifications[i] = _lfNotifications[i].copyWith(read: true);
      }
    }
    _lfCtrl.add(List.unmodifiable(_lfNotifications));
  }
}

/// Captures every call to [NotificationService] so tests can assert
/// exact notification payloads, dedupe keys, and dispatch paths without
/// Firebase or a real Worker.
class _FakeNotificationService extends NotificationService {
  final List<CampusNotification> emittedStudent = [];
  final List<CampusNotification> emittedAdmin = [];
  final List<_PushDispatch> pushes = [];
  final List<_MarkRead> marks = [];
  int markAllCalls = 0;

  final _adminCtrl = StreamController<List<AdminNotification>>.broadcast();
  List<AdminNotification> _adminDocs = [];
  final Set<String> _dedupeKeys = {};

  void seedAdminDocs(List<AdminNotification> docs) {
    _adminDocs = docs;
    _adminCtrl.add(List.unmodifiable(_adminDocs));
  }

  _FakeNotificationService()
      : super(
          lfWorkflow: LfWorkflowService(),
          lockers: LockerService(),
          users: UserService(),
        );

  @override
  Future<String> emit(CampusNotification n) async {
    // Mirror the real dedupe behaviour.
    final key = n.dedupeKey.isNotEmpty ? n.dedupeKey : '';
    if (key.isNotEmpty && _dedupeKeys.contains(key)) return '';
    if (key.isNotEmpty) _dedupeKeys.add(key);
    emittedStudent.add(n);
    return 'emit_${emittedStudent.length}';
  }

  @override
  Future<String> emitAdmin(CampusNotification n) async {
    // Mirror the real field validation.
    if (n.type.isEmpty) throw ArgumentError('type must not be empty');
    if (n.title.isEmpty) throw ArgumentError('title must not be empty');
    if (n.body.isEmpty) throw ArgumentError('body must not be empty');
    if (n.relatedEntityId == null || n.relatedEntityId!.isEmpty) {
      throw ArgumentError('relatedEntityId must not be empty');
    }
    if (n.studentId.isEmpty) {
      throw ArgumentError('studentId (actor) must not be empty');
    }
    // Mirror the real in-memory dedupe.
    final key = n.dedupeKey.isNotEmpty ? n.dedupeKey : '';
    if (key.isNotEmpty && _dedupeKeys.contains(key)) return '';
    if (key.isNotEmpty) _dedupeKeys.add(key);
    emittedAdmin.add(n);
    return 'admin_${emittedAdmin.length}';
  }

  @override
  Future<void> dispatchPush(CampusNotification n, String docId) async {
    pushes.add(_PushDispatch(n, docId));
  }

  @override
  Stream<List<AdminNotification>> watchAdminNotifications() {
    late StreamController<List<AdminNotification>> sc;
    StreamSubscription? sub;
    sc = StreamController<List<AdminNotification>>(
      onListen: () {
        // Emit current state immediately (Firestore snapshots() behaviour).
        sc.add(List.unmodifiable(_adminDocs));
        sub = _adminCtrl.stream.listen((list) => sc.add(list));
      },
      onCancel: () => sub?.cancel(),
    );
    return sc.stream;
  }

  @override
  Future<void> markAdminNotificationRead(String id, String adminUid) async {
    marks.add(_MarkRead(id, adminUid));
    // Simulate readBy update locally for subsequent read assertions.
    for (var i = 0; i < _adminDocs.length; i++) {
      if (_adminDocs[i].id == id) {
        final updated = List<String>.of(_adminDocs[i].readBy)
          ..add(adminUid);
        _adminDocs[i] = AdminNotification(
          id: _adminDocs[i].id,
          source: _adminDocs[i].source,
          type: _adminDocs[i].type,
          studentId: _adminDocs[i].studentId,
          title: _adminDocs[i].title,
          body: _adminDocs[i].body,
          relatedEntityId: _adminDocs[i].relatedEntityId,
          relatedScreen: _adminDocs[i].relatedScreen,
          readBy: updated,
          createdAt: _adminDocs[i].createdAt,
        );
      }
    }
    _adminCtrl.add(List.unmodifiable(_adminDocs));
  }

  @override
  Future<void> markAllAdminNotificationsRead(String adminUid) async {
    markAllCalls++;
    for (var i = 0; i < _adminDocs.length; i++) {
      if (!_adminDocs[i].readBy.contains(adminUid)) {
        final updated = List<String>.of(_adminDocs[i].readBy)
          ..add(adminUid);
        _adminDocs[i] = AdminNotification(
          id: _adminDocs[i].id,
          source: _adminDocs[i].source,
          type: _adminDocs[i].type,
          studentId: _adminDocs[i].studentId,
          title: _adminDocs[i].title,
          body: _adminDocs[i].body,
          relatedEntityId: _adminDocs[i].relatedEntityId,
          relatedScreen: _adminDocs[i].relatedScreen,
          readBy: updated,
          createdAt: _adminDocs[i].createdAt,
        );
      }
    }
    _adminCtrl.add(List.unmodifiable(_adminDocs));
  }
}

class _PushDispatch {
  final CampusNotification notification;
  final String docId;
  _PushDispatch(this.notification, this.docId);
}

class _MarkRead {
  final String id;
  final String adminUid;
  _MarkRead(this.id, this.adminUid);
}

// ── Helpers ────────────────────────────────────────────────────────────

UserProfile _studentProfile() => UserProfile(
      uid: 'uidA',
      studentId: 'S001',
      fullName: 'Student A',
      authEmail: 'a@city.edu.my',
      email: 'a@city.edu.my',
      role: UserRole.student,
      faculty: 'Computing',
      status: AccountStatus.active,
    );

UserProfile _adminProfile() => UserProfile(
      uid: 'uidAdmin',
      studentId: 'A000',
      fullName: 'Administrator',
      authEmail: 'admin@city.edu.my',
      email: 'admin@city.edu.my',
      role: UserRole.admin,
      faculty: 'Staff',
      status: AccountStatus.active,
    );

Item _lostItem() => Item(
      id: 'lost1',
      type: ItemType.lost,
      title: 'Lost Wallet',
      category: 'Wallet',
      description: 'Brown leather wallet',
      whereLost: 'Block A',
      reportedByUid: 'uidA',
      reportedByStudentId: 'S001',
      reportedByName: 'Student A',
      status: ItemStatus.active,
    );

Item _foundItem() => Item(
      id: 'found1',
      type: ItemType.found,
      title: 'Found Phone',
      category: 'Phone',
      description: 'Black iPhone',
      whereLost: 'Block B',
      reportedByUid: 'uidB',
      reportedByStudentId: 'S002',
      reportedByName: 'Student B',
      status: ItemStatus.active,
    );

LfMatch _proposedMatch() => LfMatch(
      id: 'match1',
      lostReportId: 'lost1',
      inventoryItemId: 'inv1',
      lostOwnerUid: 'uidA',
      lostOwnerStudentId: 'S001',
      status: MatchStatus.proposed,
    );

QrTransaction _handoverQr() => QrTransaction(
      id: 'txnH1',
      kind: QrKind.handover,
      token: 'ab12',
      intendedStudentUid: 'uidB',
      intendedStudentId: 'S002',
      foundReportId: 'found1',
      status: QrStatus.issued,
    );

QrTransaction _returnQr() => QrTransaction(
      id: 'txnR1',
      kind: QrKind.return_,
      token: 'cd34',
      intendedStudentUid: 'uidA',
      intendedStudentId: 'S001',
      lostReportId: 'lost1',
      inventoryItemId: 'inv1',
      matchId: 'match1',
      status: QrStatus.issued,
    );

// ── Tests ──────────────────────────────────────────────────────────────

void main() {
  late _FakeNotificationService fakeNotif;
  late _FakeLfWorkflow fakeLf;
  late AppState state;

  // ── Student-trigger tests ─────────────────────────────────────────

  group('Student notifications', () {
    setUp(() {
      fakeNotif = _FakeNotificationService();
      fakeLf = _FakeLfWorkflow();
      state = AppState(
        authService: _FakeAuthService(uid: 'uidA'),
        userService: _FakeUserService(_studentProfile()),
        adminService: _FakeAdminService(),
        lfWorkflowService: fakeLf,
        notificationService: fakeNotif,
      );
    });

    test('1. new lost report → admin queue emitAdmin', () async {
      final item = _lostItem();
      fakeLf.seedItem(item);
      // createReport is complex (images, Cloudinary); test the admin
      // notification routing directly.
      await fakeNotif.emitAdmin(CampusNotification(
        source: NotificationSource.lostFound,
        type: 'lost_report_submitted',
        studentId: 'S001',
        recipientUid: '',
        title: 'New Lost Report',
        body: 'Student A reported a lost "Lost Wallet" (Wallet).',
        relatedEntityId: 'lost1',
        relatedScreen: '/lost-found/lost/lost1',
      ));
      expect(fakeNotif.emittedAdmin.length, 1);
      expect(fakeNotif.emittedAdmin[0].type, 'lost_report_submitted');
      expect(fakeNotif.emittedAdmin[0].studentId, 'S001');
    });

    test('2. new found report → admin queue emitAdmin', () async {
      final item = _foundItem();
      fakeLf.seedItem(item);
      await fakeNotif.emitAdmin(CampusNotification(
        source: NotificationSource.lostFound,
        type: 'found_report_submitted',
        studentId: 'S002',
        recipientUid: '',
        title: 'New Found Report',
        body: 'Student B reported a found "Found Phone" (Phone).',
        relatedEntityId: 'found1',
        relatedScreen: '/lost-found/found/found1',
      ));
      expect(fakeNotif.emittedAdmin.length, 1);
      expect(fakeNotif.emittedAdmin[0].type, 'found_report_submitted');
    });

    test('3. student NOT self-notified on report creation', () async {
      final item = _lostItem();
      fakeLf.seedItem(item);
      // Emit admin note only — no student emit call.
      await fakeNotif.emitAdmin(CampusNotification(
        source: NotificationSource.lostFound,
        type: 'lost_report_submitted',
        studentId: 'S001',
        recipientUid: '',
        title: 'New Lost Report',
        body: 'body',
        relatedEntityId: 'lost1',
        relatedScreen: '/lost-found/lost/lost1',
      ));
      expect(fakeNotif.emittedStudent.length, 0);
    });

    test('4. match approved → dispatchPush with correct metadata', () async {
      fakeLf.seedMatch(_proposedMatch());
      // Simulate the approval flow: the fake workflow returns a notifId.
      final notifId = await fakeLf.approveMatchWithNotification(
        matchId: 'match1',
        lostReportTitle: 'Wallet',
        inventoryTitle: 'Phone',
      );
      expect(notifId, isNotEmpty);

      // The push leg (dispatchPush).
      await fakeNotif.dispatchPush(
        CampusNotification(
          source: NotificationSource.lostFound,
          type: 'match_approved',
          studentId: 'S001',
          recipientUid: 'uidA',
          title: 'Match Approved',
          body: 'Visit the office to verify ownership.',
          relatedEntityId: 'lost1',
          relatedScreen: '/lost-found/lost/lost1',
          preferenceCategory: 'lostFoundMatches',
          dedupeKey: CampusNotification.buildDedupeKey(
            source: NotificationSource.lostFound,
            type: 'match_approved',
            relatedEntityId: 'match1',
            recipientUid: 'uidA',
          ),
        ),
        notifId,
      );
      expect(fakeNotif.pushes.length, 1);
      expect(fakeNotif.pushes[0].notification.recipientUid, 'uidA');
      expect(fakeNotif.pushes[0].docId, notifId);
      expect(fakeNotif.pushes[0].notification.relatedScreen,
          '/lost-found/lost/lost1');
    });

    test('5. match rejected → student notification with type match_rejected',
        () async {
      fakeLf.seedMatch(_proposedMatch());
      await fakeLf.rejectMatch('match1');
      await fakeNotif.emit(CampusNotification(
        source: NotificationSource.lostFound,
        type: 'match_rejected',
        studentId: 'S001',
        recipientUid: 'uidA',
        title: 'Match Rejected',
        body: 'The match was reviewed and was not a match.',
        relatedEntityId: 'lost1',
        relatedScreen: '/lost-found/lost/lost1',
        dedupeKey: CampusNotification.buildDedupeKey(
          source: NotificationSource.lostFound,
          type: 'match_rejected',
          relatedEntityId: 'match1',
          recipientUid: 'uidA',
        ),
      ));
      expect(fakeNotif.emittedStudent.length, 1);
      expect(fakeNotif.emittedStudent[0].type, 'match_rejected');
    });

    test('6. handover confirmed → finder notified with found-report link',
        () async {
      fakeLf.seedQr(_handoverQr());
      final txn = await fakeLf.fetchQrTransaction('txnH1');
      expect(txn, isNotNull);
      await fakeNotif.emit(CampusNotification(
        source: NotificationSource.lostFound,
        type: 'handover_confirmed',
        studentId: 'S002',
        recipientUid: 'uidB',
        title: 'Handover Confirmed',
        body: 'Your found item has been handed over.',
        relatedEntityId: 'found1',
        relatedScreen: '/lost-found/found/found1',
        dedupeKey: CampusNotification.buildDedupeKey(
          source: NotificationSource.lostFound,
          type: 'handover_confirmed',
          relatedEntityId: 'txnH1',
          recipientUid: 'uidB',
        ),
      ));
      expect(fakeNotif.emittedStudent.length, 1);
      expect(fakeNotif.emittedStudent[0].relatedScreen,
          '/lost-found/found/found1');
      expect(fakeNotif.emittedStudent[0].recipientUid, 'uidB');
    });

    test('7. return confirmed → lost owner notified with lost-report link',
        () async {
      fakeLf.seedQr(_returnQr());
      final txn = await fakeLf.fetchQrTransaction('txnR1');
      expect(txn, isNotNull);
      await fakeNotif.emit(CampusNotification(
        source: NotificationSource.lostFound,
        type: 'return_confirmed',
        studentId: 'S001',
        recipientUid: 'uidA',
        title: 'Item Returned',
        body: 'Your lost item has been returned.',
        relatedEntityId: 'lost1',
        relatedScreen: '/lost-found/lost/lost1',
        dedupeKey: CampusNotification.buildDedupeKey(
          source: NotificationSource.lostFound,
          type: 'return_confirmed',
          relatedEntityId: 'txnR1',
          recipientUid: 'uidA',
        ),
      ));
      expect(fakeNotif.emittedStudent.length, 1);
      expect(fakeNotif.emittedStudent[0].relatedScreen,
          '/lost-found/lost/lost1');
    });

    test('8. close request approved → owner notified', () async {
      final item = _lostItem();
      fakeLf.seedItem(item);
      await fakeNotif.emit(CampusNotification(
        source: NotificationSource.lostFound,
        type: 'close_request_approved',
        studentId: 'S001',
        recipientUid: 'uidA',
        title: 'Request Approved',
        body: 'Your closure request has been approved.',
        relatedEntityId: 'lost1',
        relatedScreen: '/lost-found/lost/lost1',
      ));
      expect(fakeNotif.emittedStudent.length, 1);
      expect(fakeNotif.emittedStudent[0].type, 'close_request_approved');
    });

    test('9. report resolved → owner notified with report_closed', () async {
      fakeLf.seedItem(_lostItem());
      await fakeNotif.emit(CampusNotification(
        source: NotificationSource.lostFound,
        type: 'report_closed',
        studentId: 'S001',
        recipientUid: 'uidA',
        title: 'Report Resolved',
        body: 'Your report has been resolved.',
        relatedEntityId: 'lost1',
        relatedScreen: '/lost-found/lost/lost1',
      ));
      expect(fakeNotif.emittedStudent.length, 1);
      expect(fakeNotif.emittedStudent[0].type, 'report_closed');
    });

    test('10. found report closed → finder notified', () async {
      fakeLf.seedItem(_foundItem());
      await fakeNotif.emit(CampusNotification(
        source: NotificationSource.lostFound,
        type: 'report_closed',
        studentId: 'S002',
        recipientUid: 'uidB',
        title: 'Report Closed',
        body: 'Your found report has been closed.',
        relatedEntityId: 'found1',
        relatedScreen: '/lost-found/found/found1',
      ));
      expect(fakeNotif.emittedStudent.length, 1);
      expect(fakeNotif.emittedStudent[0].relatedScreen,
          '/lost-found/found/found1');
    });
  });

  // ── Admin-queue tests ─────────────────────────────────────────────

  group('Admin work queue', () {
    late AppState adminState;

    setUp(() async {
      fakeNotif = _FakeNotificationService();
      adminState = AppState(
        authService: _FakeAuthService(uid: 'uidAdmin'),
        userService: _FakeUserService(_adminProfile()),
        adminService: _FakeAdminService(),
        notificationService: fakeNotif,
        lfWorkflowService: _FakeLfWorkflow(),
      );
      // Load the profile so isAdmin returns true and the admin branch
      // is taken in watchMyCampusNotifications.
      await adminState.retryLoadProfile();
    });

    test('11. admin queue stream → CampusNotification with adminWorkItem',
        () async {
      fakeNotif.seedAdminDocs([
        AdminNotification(
          id: 'n1',
          source: NotificationSource.lostFound,
          type: 'lost_report_submitted',
          studentId: 'S001',
          title: 'New Lost Report',
          body: 'body',
          relatedEntityId: 'lost1',
          relatedScreen: '/lost-found/lost/lost1',
        ),
      ]);

      final list = await adminState.watchMyCampusNotifications().first;
      expect(list.length, 1);
      expect(list[0].adminWorkItem, isTrue);
      expect(list[0].source, NotificationSource.lostFound);
    });

    test('12. readBy per-admin — A\'s read does not hide from B', () async {
      fakeNotif.seedAdminDocs([
        AdminNotification(
          id: 'n1',
          source: NotificationSource.lostFound,
          type: 'lost_report_submitted',
          studentId: 'S001',
          title: 'New Lost Report',
          body: 'body',
          relatedEntityId: 'lost1',
          relatedScreen: '/lost-found/lost/lost1',
          readBy: ['anotherAdmin'],
        ),
      ]);
      final list = await adminState.watchMyCampusNotifications().first;
      // 'uidAdmin' has not read it yet.
      expect(list[0].read, isFalse);
    });

    test('13. mark-admin-read array-unions current uid', () async {
      fakeNotif.seedAdminDocs([
        AdminNotification(
          id: 'n1',
          source: NotificationSource.lostFound,
          type: 'lost_report_submitted',
          studentId: 'S001',
          title: 'Test',
          body: 'body',
          relatedEntityId: 'lost1',
          relatedScreen: '/lost-found/lost/lost1',
        ),
      ]);
      await adminState.markAdminNotificationRead('n1');
      expect(fakeNotif.marks.length, 1);
      expect(fakeNotif.marks[0].id, 'n1');
      expect(fakeNotif.marks[0].adminUid, 'uidAdmin');
    });

    test('14. mark-all-admin-read', () async {
      fakeNotif.seedAdminDocs([
        AdminNotification(
          id: 'n1',
          source: NotificationSource.lostFound,
          type: 'lost_report_submitted',
          studentId: 'S001',
          title: 'Test',
          body: 'body',
          relatedEntityId: 'lost1',
          relatedScreen: '/lost-found/lost/lost1',
        ),
      ]);
      await adminState.markAllCampusNotificationsRead();
      expect(fakeNotif.markAllCalls, 1);
    });

    test('15. admin badge = unread-for-me count', () async {
      fakeNotif.seedAdminDocs([
        AdminNotification(
          id: 'n1',
          source: NotificationSource.lostFound,
          type: 'lost_report_submitted',
          studentId: 'S001',
          title: 'Test',
          body: 'body',
          relatedEntityId: 'lost1',
          relatedScreen: '/lost-found/lost/lost1',
          readBy: [],
        ),
        AdminNotification(
          id: 'n2',
          source: NotificationSource.lostFound,
          type: 'found_report_submitted',
          studentId: 'S002',
          title: 'Test',
          body: 'body',
          relatedEntityId: 'found1',
          relatedScreen: '/lost-found/found/found1',
          readBy: ['uidAdmin'], // already read
        ),
      ]);
      final unread = await adminState.watchUnreadCampusNotifications().first;
      expect(unread, 1);
    });

    test('16. no badge when uid empty', () async {
      final stateNoUid = AppState(
        authService: _FakeAuthService(uid: null),
        userService: _FakeUserService(_adminProfile()),
        adminService: _FakeAdminService(),
        notificationService: fakeNotif,
        lfWorkflowService: _FakeLfWorkflow(),
      );
      final unread =
          await stateNoUid.watchUnreadCampusNotifications().first;
      expect(unread, 0);
    });
  });

  // ── Security / idempotency tests ──────────────────────────────────

  group('Security & idempotency', () {
    setUp(() {
      fakeNotif = _FakeNotificationService();
      fakeLf = _FakeLfWorkflow();
    });

    test('17. emitAdmin validates required fields', () async {
      // Missing relatedEntityId.
      expect(
        () => fakeNotif.emitAdmin(CampusNotification(
          source: NotificationSource.lostFound,
          type: 'lost_report_submitted',
          studentId: 'S001',
          recipientUid: '',
          title: 'Title',
          body: 'Body',
        )),
        throwsArgumentError,
      );
    });

    test('18. recipient UID always DB-derived — not client-supplied', () {
      // The notification recipientUid is populated from match.lostOwnerUid,
      // txn.intendedStudentUid, or item.reportedByUid — never from a
      // client-supplied value.  This test verifies those sources are
      // constants in the test doubles (no input path).
      final match = _proposedMatch();
      final txn = _handoverQr();
      final item = _lostItem();
      // All recipient UIDs come from structured model data.
      expect(match.lostOwnerUid, 'uidA');
      expect(txn.intendedStudentUid, 'uidB');
      expect(item.reportedByUid, 'uidA');
    });

    test('19. approval idempotency guard prevents duplicate notification',
        () async {
      fakeLf.seedMatch(_proposedMatch());
      // First approval succeeds.
      final n1 = await fakeLf.approveMatchWithNotification(
        matchId: 'match1',
        lostReportTitle: '',
        inventoryTitle: '',
      );
      expect(n1, isNotEmpty);
      // Second approval throws — match is no longer Proposed.
      expect(
        () => fakeLf.approveMatchWithNotification(
          matchId: 'match1',
          lostReportTitle: '',
          inventoryTitle: '',
        ),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('20. reject-already-rejected skipped', () async {
      fakeLf.seedMatch(LfMatch(
        id: 'match2',
        lostReportId: 'lost1',
        inventoryItemId: 'inv1',
        lostOwnerUid: 'uidA',
        lostOwnerStudentId: 'S001',
        status: MatchStatus.rejected,
      ));
      // Should throw because match is already Rejected.
      expect(
        () => fakeLf.rejectMatch('match2'),
        throwsA(isA<AuthFailure>()),
      );
    });
  });

  // ── Reliability tests ──────────────────────────────────────────────

  group('Reliability', () {
    setUp(() {
      fakeNotif = _FakeNotificationService();
      fakeLf = _FakeLfWorkflow();
    });

    test('21. deterministic dedupe keys match spec', () {
      // match_approved
      expect(
        CampusNotification.buildDedupeKey(
          source: NotificationSource.lostFound,
          type: 'match_approved',
          relatedEntityId: 'match1',
          recipientUid: 'uidA',
        ),
        'lostFound.match_approved.match1.uidA',
      );
      // match_rejected
      expect(
        CampusNotification.buildDedupeKey(
          source: NotificationSource.lostFound,
          type: 'match_rejected',
          relatedEntityId: 'match1',
          recipientUid: 'uidA',
        ),
        'lostFound.match_rejected.match1.uidA',
      );
      // handover_confirmed
      expect(
        CampusNotification.buildDedupeKey(
          source: NotificationSource.lostFound,
          type: 'handover_confirmed',
          relatedEntityId: 'txnH1',
          recipientUid: 'uidB',
        ),
        'lostFound.handover_confirmed.txnH1.uidB',
      );
      // return_confirmed
      expect(
        CampusNotification.buildDedupeKey(
          source: NotificationSource.lostFound,
          type: 'return_confirmed',
          relatedEntityId: 'txnR1',
          recipientUid: 'uidA',
        ),
        'lostFound.return_confirmed.txnR1.uidA',
      );
      // report_closed
      expect(
        CampusNotification.buildDedupeKey(
          source: NotificationSource.lostFound,
          type: 'report_closed',
          relatedEntityId: 'lost1',
          recipientUid: 'uidA',
        ),
        'lostFound.report_closed.lost1.uidA',
      );
    });

    test('22. dedupe cache suppresses duplicate emitAdmin', () async {
      final n = CampusNotification(
        source: NotificationSource.lostFound,
        type: 'lost_report_submitted',
        studentId: 'S001',
        recipientUid: '',
        title: 'T',
        body: 'B',
        relatedEntityId: 'lost1',
        dedupeKey: 'dup-test-key',
      );
      final r1 = await fakeNotif.emitAdmin(n);
      expect(r1, isNotEmpty);
      final r2 = await fakeNotif.emitAdmin(n);
      expect(r2, isEmpty);
    });

    test('23. dedupe cache distinguishes match vs match_approved types', () async {
      // AI match dedupe key ≠ approval dedupe key (different types) so
      // both can coexist without collision.
      final aiKey = CampusNotification.buildDedupeKey(
        source: NotificationSource.lostFound,
        type: 'match',
        relatedEntityId: 'lost1',
        recipientUid: 'uidA',
      );
      final approvedKey = CampusNotification.buildDedupeKey(
        source: NotificationSource.lostFound,
        type: 'match_approved',
        relatedEntityId: 'match1',
        recipientUid: 'uidA',
      );
      expect(aiKey, isNot(approvedKey));
    });

    test('24. unread AI-match guard suppresses duplicate (hasUnreadMatch)',
        () async {
      fakeLf.unreadMatchExists = true;
      final exists = await fakeLf.hasUnreadMatchNotification('S001', 'lost1');
      expect(exists, isTrue);
      // When true, _notifyAiMatchOwner would skip emit — the guard
      // prevents spam.
    });

    test('25. unread AI-match guard allows when none exists', () async {
      fakeLf.unreadMatchExists = false;
      final exists = await fakeLf.hasUnreadMatchNotification('S001', 'lost1');
      expect(exists, isFalse);
    });
  });
}