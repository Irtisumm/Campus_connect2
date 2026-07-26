import 'package:flutter/material.dart';
import 'auth_service.dart';

class AppState extends ChangeNotifier {
  late AuthService _authService;

  bool get isAuthenticated => _authService.isAuthenticated;
  bool get isAdmin => _authService.isAdmin;
  String? get userId => _authService.userId;
  UserProfile? get currentUserProfile => _authService.getCurrentUserProfile();

  // ── USER ANALYTICS ────────────────────────────────────────────────
  int get totalAccounts => _authService.totalAccounts;
  int get totalStudentAccounts => _authService.totalStudentAccounts;
  int get totalAdminAccounts => _authService.totalAdminAccounts;

  AppState() {
    _authService = AuthService();
  }

  Future<bool> loginUser(String id, String password, bool isAdmin) async {
    final result = await _authService.login(id, password, isAdmin);
    if (result) notifyListeners();
    return result;
  }

  void logout() {
    _authService.logout();
    _authService.clearSavedCredentials();
    notifyListeners();
  }

  Future<bool> switchRole(String id, String password, bool toAdmin) async {
    final result = await _authService.login(id, password, toAdmin);
    if (result) notifyListeners();
    return result;
  }

  // Register a new student account (called after admin approval)
  void addApprovedStudent(
    String studentId,
    String password,
    String name, {
    String? email,
    String? programme,
    String? phone,
  }) {
    _authService.addApprovedStudent(
      studentId,
      password,
      name,
      email: email,
      programme: programme,
      phone: phone,
    );
    notifyListeners();
  }

  bool isStudentIdTaken(String studentId) {
    return _authService.isStudentIdTaken(studentId);
  }

  // ── CREDENTIAL PERSISTENCE (Remember Me) ─────────────────────────
  Future<void> saveCredentials(String id, String password) async {
    await _authService.saveCredentials(id, password);
  }

  Future<Map<String, String>?> loadSavedCredentials() async {
    return await _authService.loadSavedCredentials();
  }

  Future<void> clearSavedCredentials() async {
    await _authService.clearSavedCredentials();
  }

  Future<bool> updateCurrentUserProfile({
    required String name,
    required String email,
    required String programme,
    required String phone,
  }) async {
    final result = await _authService.updateCurrentUserProfile(
      name: name,
      email: email,
      programme: programme,
      phone: phone,
    );
    if (result) {
      notifyListeners();
    }
    return result;
  }
}
