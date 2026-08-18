import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:campus_connect/services/admin_service.dart';
import 'package:campus_connect/services/app_state.dart';
import 'package:campus_connect/services/auth_service.dart';
import 'package:campus_connect/services/data_service.dart';
import 'package:campus_connect/services/locker_service.dart';
import 'package:campus_connect/services/user_service.dart';

// ── Fake infrastructure ──────────────────────────────────────────

/// Minimal [AuthService] double so [AppState] can load a profile without
/// Firebase being initialised. Mirrors the pattern in
/// `lf_close_request_test.dart`.
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

/// An [LfWorkflowService] whose notification list lives in memory and is
/// re-emitted on every mutation — the same snapshot semantics Firestore
/// `snapshots()` provides, but synchronous and deterministic.
///
/// Each [watch*] call returns a fresh single-subscription stream that
/// immediately emits the current filtered state (via [onListen]) and then
/// forwards every future mutation from the shared broadcast controller.
class _StatefulLf extends LfWorkflowService {
  List<LfNotification> _lf = [];
  final _ctrl = StreamController<List<LfNotification>>.broadcast();

  List<LfNotification> get currentLf => List.unmodifiable(_lf);

  void seedLf(List<LfNotification> initial) {
    _lf = List.of(initial);
    _emit();
  }

  void _emit() => _ctrl.add(List.unmodifiable(_lf));

  Stream<List<LfNotification>> _filteredStream(String studentId) {
    late StreamController<List<LfNotification>> sc;
    StreamSubscription? sub;
    sc = StreamController<List<LfNotification>>(
      onListen: () {
        sc.add(_lf.where((n) => n.studentId == studentId).toList());
        sub = _ctrl.stream.listen((list) {
          sc.add(list.where((n) => n.studentId == studentId).toList());
        });
      },
      onCancel: () => sub?.cancel(),
    );
    return sc.stream;
  }

  @override
  Stream<List<LfNotification>> watchMyLfNotifications(String studentId) =>
      _filteredStream(studentId);

  @override
  Stream<List<LfNotification>> watchAllLfNotifications() {
    late StreamController<List<LfNotification>> sc;
    StreamSubscription? sub;
    sc = StreamController<List<LfNotification>>(
      onListen: () {
        sc.add(List.unmodifiable(_lf));
        sub = _ctrl.stream.listen(sc.add);
      },
      onCancel: () => sub?.cancel(),
    );
    return sc.stream;
  }

  @override
  Future<void> markLfNotificationRead(String id) async {
    _lf = _lf
        .map((n) => n.id == id ? n.copyWith(read: true) : n)
        .toList();
    _emit();
  }

  @override
  Future<void> markAllRead(String studentId) async {
    _lf = _lf
        .map((n) => (n.studentId == studentId && !n.read)
            ? n.copyWith(read: true)
            : n)
        .toList();
    _emit();
  }

  @override
  Future<String> createNotification(LfNotification notification) async {
    final id = 'lf-${_lf.length + 1}';
    _lf = [..._lf, notification.copyWith(id: id)];
    _emit();
    return id;
  }

  void dispose() => _ctrl.close();
}

/// Same in-memory snapshot pattern for [LockerService].
class _StatefulLocker extends LockerService {
  List<LockerNotification> _ln = [];
  final _ctrl = StreamController<List<LockerNotification>>.broadcast();

  List<LockerNotification> get currentLocker => List.unmodifiable(_ln);

  void seedLocker(List<LockerNotification> initial) {
    _ln = List.of(initial);
    _emit();
  }

  void _emit() => _ctrl.add(List.unmodifiable(_ln));

  Stream<List<LockerNotification>> _filteredStream(String studentId) {
    late StreamController<List<LockerNotification>> sc;
    StreamSubscription? sub;
    sc = StreamController<List<LockerNotification>>(
      onListen: () {
        sc.add(_ln.where((n) => n.studentId == studentId).toList());
        sub = _ctrl.stream.listen((list) {
          sc.add(list.where((n) => n.studentId == studentId).toList());
        });
      },
      onCancel: () => sub?.cancel(),
    );
    return sc.stream;
  }

  @override
  Stream<List<LockerNotification>> watchMyLockerNotifications(
          String studentId) =>
      _filteredStream(studentId);

  @override
  Stream<List<LockerNotification>> watchAllLockerNotifications() {
    late StreamController<List<LockerNotification>> sc;
    StreamSubscription? sub;
    sc = StreamController<List<LockerNotification>>(
      onListen: () {
        sc.add(List.unmodifiable(_ln));
        sub = _ctrl.stream.listen(sc.add);
      },
      onCancel: () => sub?.cancel(),
    );
    return sc.stream;
  }

  @override
  Future<void> markNotificationRead(String id) async {
    _ln = _ln
        .map((n) => n.id == id ? n.copyWith(read: true) : n)
        .toList();
    _emit();
  }

  @override
  Future<void> markAllRead(String studentId) async {
    _ln = _ln
        .map((n) => (n.studentId == studentId && !n.read)
            ? n.copyWith(read: true)
            : n)
        .toList();
    _emit();
  }

  @override
  Future<LockerNotification> createLockerNotification(
      LockerNotification notification) async {
    final id = 'locker-${_ln.length + 1}';
    final withId = notification.copyWith(id: id);
    _ln = [..._ln, withId];
    _emit();
    return withId;
  }

  void dispose() => _ctrl.close();
}

// ── Test profiles ─────────────────────────────────────────────────

final _student = UserProfile(
  uid: 'student-uid',
  studentId: 'S001',
  fullName: 'Alice Smith',
  authEmail: 'alice@campus.edu',
  email: 'alice@campus.edu',
  faculty: 'Computing',
  role: UserRole.student,
  status: AccountStatus.active,
);

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

/// Builds an [AppState] wired to the given fake services and loads the
/// student profile so [AppState.userId] resolves to `S001`.
Future<AppState> _studentState({
  _StatefulLf? lf,
  _StatefulLocker? locker,
}) async {
  final state = AppState(
    authService: _FakeAuthService(uid: 'student-uid'),
    userService: _FakeUserService(_student),
    adminService: _FakeAdminService(),
    lfWorkflowService: lf ?? _StatefulLf(),
    lockerService: locker ?? _StatefulLocker(),
  );
  await state.retryLoadProfile();
  return state;
}

/// Builds an [AppState] wired to the given fake services and loads the
/// admin profile so [AppState.isAdmin] is `true`.
Future<AppState> _adminState({
  _StatefulLf? lf,
  _StatefulLocker? locker,
}) async {
  final state = AppState(
    authService: _FakeAuthService(uid: 'admin-uid'),
    userService: _FakeUserService(_admin),
    adminService: _FakeAdminService(),
    lfWorkflowService: lf ?? _StatefulLf(),
    lockerService: locker ?? _StatefulLocker(),
  );
  await state.retryLoadProfile();
  return state;
}

LfNotification _lfNotif({
  String id = 'n1',
  String studentId = 'S001',
  bool read = false,
  String relatedReportId = 'lost-1',
}) =>
    LfNotification(
      id: id,
      studentId: studentId,
      title: 'Match found',
      body: 'A match was found for your lost report.',
      relatedReportId: relatedReportId,
      read: read,
    );

LockerNotification _lockerNotif({
  String id = 'ln1',
  String studentId = 'S001',
  bool read = false,
}) =>
    LockerNotification(
      id: id,
      studentId: studentId,
      lockerId: 'LK-A01',
      title: 'Locker update',
      body: 'Your locker agreement has been updated.',
      type: 'termination',
      createdAt: DateTime(2026, 8, 16).toIso8601String(),
      read: read,
    );

/// Pumps the microtask queue so the [onListen] initial emissions are
/// delivered to listeners before assertions run.
Future<void> _pump() => Future<void>.delayed(Duration.zero);

// ── Tests ─────────────────────────────────────────────────────────

void main() {
  group('1-2. L&F read state persistence', () {
    test('marking a notification read persists across stream rebuild',
        () async {
      final lf = _StatefulLf();
      lf.seedLf([_lfNotif(id: 'n1', read: false)]);
      final state = await _studentState(lf: lf);

      final emissions = <List<LfNotification>>[];
      final sub = state.watchMyLfNotifications().listen(emissions.add);
      await _pump();

      // Initial snapshot: n1 is unread.
      expect(emissions, hasLength(greaterThanOrEqualTo(1)));
      expect(emissions.last.singleWhere((n) => n.id == 'n1').read, isFalse);

      // Mark read — the fake re-emits, simulating a fresh Firestore snapshot.
      await state.markLfNotificationRead('n1');
      await _pump();

      expect(emissions.last.singleWhere((n) => n.id == 'n1').read, isTrue);

      await sub.cancel();
    });

    test('read state survives an app-restart simulation', () async {
      // Service A — the "first session."
      final lfA = _StatefulLf();
      lfA.seedLf([_lfNotif(id: 'n1', read: false)]);
      final stateA = await _studentState(lf: lfA);

      await stateA.markLfNotificationRead('n1');

      // Simulate a cold start: a fresh service reads from the same
      // "Firestore" (the post-mutation list).  The notification must still
      // be read.
      final lfB = _StatefulLf();
      lfB.seedLf(lfA.currentLf);
      final stateB = await _studentState(lf: lfB);

      final rows = await stateB.watchMyLfNotifications().first;
      expect(rows.singleWhere((n) => n.id == 'n1').read, isTrue);
    });
  });

  group('3. Locker read state persistence', () {
    test('marking a locker notification read persists', () async {
      final locker = _StatefulLocker();
      locker.seedLocker([_lockerNotif(id: 'ln1', read: false)]);
      final state = await _studentState(locker: locker);

      final emissions = <List<LockerNotification>>[];
      final sub = state.watchMyLockerNotifications().listen(emissions.add);
      await _pump();

      expect(emissions.last.singleWhere((n) => n.id == 'ln1').read, isFalse);

      await state.markLockerNotificationRead('ln1');
      await _pump();

      expect(emissions.last.singleWhere((n) => n.id == 'ln1').read, isTrue);

      await sub.cancel();
    });
  });

  group('4-7. Badge count', () {
    test('badge is 0 when both collections are empty', () async {
      final state = await _studentState();

      final lfCount = await state.watchUnreadLfNotifications().first;
      final lockerCount = await state.watchUnreadLockerNotifications().first;

      expect(lfCount + lockerCount, 0);
    });

    test('badge counts unread L&F notifications', () async {
      final lf = _StatefulLf();
      lf.seedLf([
        _lfNotif(id: 'n1', read: false),
        _lfNotif(id: 'n2', read: true),
        _lfNotif(id: 'n3', read: false),
      ]);
      final state = await _studentState(lf: lf);

      final lfCount = await state.watchUnreadLfNotifications().first;
      final lockerCount = await state.watchUnreadLockerNotifications().first;

      expect(lfCount, 2);
      expect(lockerCount, 0);
      expect(lfCount + lockerCount, 2);
    });

    test('badge counts unread locker notifications', () async {
      final locker = _StatefulLocker();
      locker.seedLocker([
        _lockerNotif(id: 'ln1', read: false),
        _lockerNotif(id: 'ln2', read: true),
      ]);
      final state = await _studentState(locker: locker);

      final lfCount = await state.watchUnreadLfNotifications().first;
      final lockerCount = await state.watchUnreadLockerNotifications().first;

      expect(lfCount, 0);
      expect(lockerCount, 1);
      expect(lfCount + lockerCount, 1);
    });

    test('badge combines L&F and locker unread correctly', () async {
      final lf = _StatefulLf();
      lf.seedLf([
        _lfNotif(id: 'n1', read: false),
        _lfNotif(id: 'n2', read: false),
      ]);
      final locker = _StatefulLocker();
      locker.seedLocker([
        _lockerNotif(id: 'ln1', read: false),
        _lockerNotif(id: 'ln2', read: true),
        _lockerNotif(id: 'ln3', read: false),
      ]);
      final state = await _studentState(lf: lf, locker: locker);

      final lfCount = await state.watchUnreadLfNotifications().first;
      final lockerCount = await state.watchUnreadLockerNotifications().first;

      expect(lfCount, 2);
      expect(lockerCount, 2);
      expect(lfCount + lockerCount, 4);
    });
  });

  group('8. Legacy DataService mock does not affect the badge', () {
    test('DataService notifications leave the Firestore-based badge at 0',
        () async {
      // Populate the legacy mock DataService with unread notifications.
      final data = DataService();
      data.addNotification('mock event', 'personal');
      data.addNotification('mock issue', 'personal');

      // The badge now reads only from the Firestore-backed streams, so the
      // DataService mock must not contribute.
      final state = await _studentState();

      final lfCount = await state.watchUnreadLfNotifications().first;
      final lockerCount = await state.watchUnreadLockerNotifications().first;

      expect(lfCount + lockerCount, 0);
    });
  });

  group('9. Mark-all-read clears the unread count', () {
    test('markAllLfNotificationsRead clears L&F unread', () async {
      final lf = _StatefulLf();
      lf.seedLf([
        _lfNotif(id: 'n1', read: false),
        _lfNotif(id: 'n2', read: false),
      ]);
      final state = await _studentState(lf: lf);

      final before = await state.watchUnreadLfNotifications().first;
      expect(before, 2);

      final ok = await state.markAllLfNotificationsRead();
      expect(ok, isTrue);

      final after = await state.watchUnreadLfNotifications().first;
      expect(after, 0);
    });

    test('markAllLockerNotificationsRead clears locker unread', () async {
      final locker = _StatefulLocker();
      locker.seedLocker([
        _lockerNotif(id: 'ln1', read: false),
        _lockerNotif(id: 'ln2', read: false),
      ]);
      final state = await _studentState(locker: locker);

      final before = await state.watchUnreadLockerNotifications().first;
      expect(before, 2);

      final ok = await state.markAllLockerNotificationsRead();
      expect(ok, isTrue);

      final after = await state.watchUnreadLockerNotifications().first;
      expect(after, 0);
    });
  });

  group("10. User cannot affect another user's notifications", () {
    test('markAllRead only touches the caller\'s own notifications', () async {
      final lf = _StatefulLf();
      lf.seedLf([
        _lfNotif(id: 'n1', studentId: 'S001', read: false),
        _lfNotif(id: 'n2', studentId: 'S002', read: false),
        _lfNotif(id: 'n3', studentId: 'S001', read: false),
      ]);

      // S001 marks all their own notifications read.
      final state = await _studentState(lf: lf);
      await state.markAllLfNotificationsRead();

      // S001's notifications are now read.
      final mine = await state.watchMyLfNotifications().first;
      expect(mine.every((n) => n.read), isTrue);

      // S002's notifications are untouched.
      final theirs = await lf.watchMyLfNotifications('S002').first;
      expect(theirs.every((n) => !n.read), isTrue);
    });

    test('locker markAllRead only touches the caller\'s own', () async {
      final locker = _StatefulLocker();
      locker.seedLocker([
        _lockerNotif(id: 'ln1', studentId: 'S001', read: false),
        _lockerNotif(id: 'ln2', studentId: 'S002', read: false),
      ]);

      final state = await _studentState(locker: locker);
      await state.markAllLockerNotificationsRead();

      final mine = await state.watchMyLockerNotifications().first;
      expect(mine.every((n) => n.read), isTrue);

      final theirs = await locker.watchMyLockerNotifications('S002').first;
      expect(theirs.every((n) => !n.read), isTrue);
    });
  });

  group('11. Admin-created notification flow still works', () {
    test('createNotification makes a new L&F notification visible to the owner',
        () async {
      final lf = _StatefulLf();
      final state = await _studentState(lf: lf);

      // Admin creates a notification for S001 (rules allow admin-create).
      final id = await lf.createNotification(
        _lfNotif(id: '', studentId: 'S001', read: false),
      );

      expect(id, isNotEmpty);

      // The recipient now sees it in their feed.
      final rows = await state.watchMyLfNotifications().first;
      expect(rows.any((n) => n.id == id), isTrue);
      expect(rows.firstWhere((n) => n.id == id).read, isFalse);
    });

    test('admin watchAllLfNotifications shows every student\'s notifications',
        () async {
      final lf = _StatefulLf();
      lf.seedLf([
        _lfNotif(id: 'n1', studentId: 'S001'),
        _lfNotif(id: 'n2', studentId: 'S002'),
      ]);
      final state = await _adminState(lf: lf);

      final all = await state.watchAllLfNotifications().first;
      expect(all, hasLength(2));
    });
  });

  group('12. Deep-link behavior preserved', () {
    test('tapping a notification marks it read and exposes the report id',
        () async {
      final lf = _StatefulLf();
      lf.seedLf([
        _lfNotif(id: 'n1', read: false, relatedReportId: 'lost-42'),
      ]);
      final state = await _studentState(lf: lf);

      // The screen's _onRowTap does two things: mark read, then navigate.
      // We verify both halves at the state/model level.
      final before = await state.watchMyLfNotifications().first;
      final row = before.singleWhere((n) => n.id == 'n1');
      expect(row.read, isFalse);
      expect(row.relatedReportId, 'lost-42');

      // Mark read (the first half of _onRowTap).
      final ok = await state.markLfNotificationRead('n1');
      expect(ok, isTrue);

      // The notification is now read and still carries the deep-link target.
      final after = await state.watchMyLfNotifications().first;
      final updated = after.singleWhere((n) => n.id == 'n1');
      expect(updated.read, isTrue);
      expect(updated.relatedReportId, 'lost-42');
    });

    test('notifications without a related report do not deep-link', () async {
      final lf = _StatefulLf();
      lf.seedLf([
        _lfNotif(id: 'n1', relatedReportId: ''),
      ]);
      final state = await _studentState(lf: lf);

      final rows = await state.watchMyLfNotifications().first;
      expect(rows.singleWhere((n) => n.id == 'n1').relatedReportId, isEmpty);
    });
  });
}
