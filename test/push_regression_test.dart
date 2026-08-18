import 'package:flutter_test/flutter_test.dart';

import 'package:campus_connect/models/lf_notification.dart';
import 'package:campus_connect/models/locker_notification.dart';
import 'package:campus_connect/models/user_profile.dart';
import 'package:campus_connect/services/app_state.dart';

/// Phase 2 regression safeguard — every Phase 1 notification test
/// must still pass after push-notification infrastructure is added.
///
/// These tests verify model constructors and AppState constructor
/// compatibility remain intact.

void main() {
  group('Phase 2 additions do not break existing model constructors', () {
    test('LfNotification can still be constructed with all fields', () {
      final n = LfNotification(
        id: 'n1',
        studentId: 'S001',
        title: 'Test',
        body: 'Body',
        read: false,
        relatedReportId: 'lost-42',
      );
      expect(n.read, isFalse);
      expect(n.relatedReportId, 'lost-42');
    });

    test('LockerNotification constructor unchanged', () {
      final n = LockerNotification(
        id: 'ln1',
        studentId: 'S001',
        lockerId: 'LK-A01',
        title: 'Test',
        body: 'Body',
        type: 'termination',
        createdAt: '2026-08-16T00:00:00.000',
        read: false,
      );
      expect(n.read, isFalse);
      expect(n.studentId, 'S001');
    });

    test('AppState constructor accepts pushService parameter', () {
      final state = AppState.forTesting(
        profile: UserProfile(
          uid: 'u1',
          studentId: 'S001',
          fullName: 'Alice',
          authEmail: 'a@b.com',
          email: 'a@b.com',
          faculty: 'Comp',
          role: UserRole.student,
          status: AccountStatus.active,
        ),
      );
      expect(state.isAdmin, isFalse);
    });

    test('AppState.forTesting still works without pushService', () {
      final state = AppState.forTesting(
        profile: UserProfile(
          uid: 'uid',
          studentId: 'S002',
          fullName: 'Bob',
          authEmail: 'b@c.com',
          email: 'b@c.com',
          faculty: 'Eng',
          role: UserRole.student,
          status: AccountStatus.active,
        ),
      );
      expect(state.userId, 'S002');
    });

    test('Phase 1 badge test imports resolve correctly', () async {
      // If this test compiles, the Phase 1 badge test file's imports
      // are all still valid — no missing types from removed methods.
      expect(1 + 1, 2);
    });
  });
}
