import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserProfile {
  final String userId;
  final String role; // 'student' | 'admin'
  final String name;
  final String email;
  final String programme;
  final String phone;

  const UserProfile({
    required this.userId,
    required this.role,
    required this.name,
    required this.email,
    required this.programme,
    required this.phone,
  });

  UserProfile copyWith({
    String? name,
    String? email,
    String? programme,
    String? phone,
  }) {
    return UserProfile(
      userId: userId,
      role: role,
      name: name ?? this.name,
      email: email ?? this.email,
      programme: programme ?? this.programme,
      phone: phone ?? this.phone,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'role': role,
      'name': name,
      'email': email,
      'programme': programme,
      'phone': phone,
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['userId']?.toString() ?? '',
      role: json['role']?.toString() ?? 'student',
      name: json['name']?.toString() ?? 'User',
      email: json['email']?.toString() ?? '',
      programme: json['programme']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
    );
  }
}

class AuthService extends ChangeNotifier {
  static const _profilePrefsKey = 'user_profile_overrides_v1';

  bool _isAuthenticated = false;
  bool _isAdmin = false;
  String? _userId;
  String? _userName;
  bool _profilesLoaded = false;

  bool get isAuthenticated => _isAuthenticated;
  bool get isAdmin => _isAdmin;
  String? get userId => _userId;
  String? get userName => _userName;

  // Student accounts (can be expanded via registration approval)
  final Map<String, Map<String, String>> _studentAccounts = {
    'S001': {'password': 'pass123', 'name': 'Ahmad Rizwan'},
    'S002': {'password': 'pass123', 'name': 'Fatima Hassan'},
    'S003': {'password': 'pass123', 'name': 'Mohammad Ali'},
  };

  static const _adminAccounts = {
    'ADMIN001': {'password': 'admin123', 'name': 'Admin Panel'},
    'ADMIN002': {'password': 'admin123', 'name': 'Manager Account'},
  };

  final Map<String, UserProfile> _studentProfiles = {
    'S001': const UserProfile(
      userId: 'S001',
      role: 'student',
      name: 'Ahmad Rizwan',
      email: 's001@student.city.edu.my',
      programme: 'Faculty of Engineering',
      phone: '',
    ),
    'S002': const UserProfile(
      userId: 'S002',
      role: 'student',
      name: 'Fatima Hassan',
      email: 's002@student.city.edu.my',
      programme: 'Faculty of Business',
      phone: '',
    ),
    'S003': const UserProfile(
      userId: 'S003',
      role: 'student',
      name: 'Mohammad Ali',
      email: 's003@student.city.edu.my',
      programme: 'Faculty of Computing',
      phone: '',
    ),
  };

  final Map<String, UserProfile> _adminProfiles = {
    'ADMIN001': const UserProfile(
      userId: 'ADMIN001',
      role: 'admin',
      name: 'Admin Panel',
      email: 'admin001@city.edu.my',
      programme: 'Campus Operations',
      phone: '',
    ),
    'ADMIN002': const UserProfile(
      userId: 'ADMIN002',
      role: 'admin',
      name: 'Manager Account',
      email: 'admin002@city.edu.my',
      programme: 'Campus Operations',
      phone: '',
    ),
  };

  // User analytics
  int get totalStudentAccounts => _studentAccounts.length;
  int get totalAdminAccounts => _adminAccounts.length;
  int get totalAccounts => totalStudentAccounts + totalAdminAccounts;

  Future<void> _ensureProfilesLoaded() async {
    if (_profilesLoaded) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilePrefsKey);
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        decoded.forEach((id, value) {
          if (value is Map<String, dynamic>) {
            final profile = UserProfile.fromJson(value);
            if (profile.role == 'admin') {
              _adminProfiles[id] = profile;
            } else {
              _studentProfiles[id] = profile;
            }
          }
        });
      }
    }
    _profilesLoaded = true;
  }

  Future<void> _persistProfiles() async {
    final merged = <String, dynamic>{};
    for (final entry in _studentProfiles.entries) {
      merged[entry.key] = entry.value.toJson();
    }
    for (final entry in _adminProfiles.entries) {
      merged[entry.key] = entry.value.toJson();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profilePrefsKey, jsonEncode(merged));
  }

  Future<bool> login(String id, String password, bool isAdminLogin) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));
    await _ensureProfilesLoaded();

    final accounts = isAdminLogin ? _adminAccounts : _studentAccounts;
    final account = accounts[id];

    if (account == null || account['password'] != password) {
      return false;
    }

    _isAuthenticated = true;
    _isAdmin = isAdminLogin;
    _userId = id;
    _userName = account['name'];
    notifyListeners();
    return true;
  }

  void logout() {
    _isAuthenticated = false;
    _isAdmin = false;
    _userId = null;
    _userName = null;
    notifyListeners();
  }

  void switchRole(String id, String password, bool toAdmin) async {
    logout();
    await Future.delayed(const Duration(milliseconds: 300));
    await login(id, password, toAdmin);
  }

  // Register a new student account (after admin approval, the account gets added)
  void addApprovedStudent(
    String studentId,
    String password,
    String name, {
    String? email,
    String? programme,
    String? phone,
  }) {
    _studentAccounts[studentId] = {'password': password, 'name': name};
    _studentProfiles[studentId] = UserProfile(
      userId: studentId,
      role: 'student',
      name: name,
      email: email ?? '${studentId.toLowerCase()}@student.city.edu.my',
      programme: programme ?? 'General Studies',
      phone: phone ?? '',
    );
    _persistProfiles();
    notifyListeners();
  }

  UserProfile? getCurrentUserProfile() {
    if (_userId == null) return null;
    if (_isAdmin) {
      return _adminProfiles[_userId!];
    }
    return _studentProfiles[_userId!];
  }

  Future<bool> updateCurrentUserProfile({
    required String name,
    required String email,
    required String programme,
    required String phone,
  }) async {
    if (_userId == null) return false;
    await _ensureProfilesLoaded();

    final existing = getCurrentUserProfile();
    if (existing == null) return false;

    final updated = existing.copyWith(
      name: name.trim(),
      email: email.trim(),
      programme: programme.trim(),
      phone: phone.trim(),
    );

    if (_isAdmin) {
      _adminProfiles[_userId!] = updated;
    } else {
      _studentProfiles[_userId!] = updated;
      final account = _studentAccounts[_userId!];
      if (account != null) {
        account['name'] = updated.name;
      }
    }

    _userName = updated.name;
    await _persistProfiles();
    notifyListeners();
    return true;
  }

  // Check if a student ID is already taken
  bool isStudentIdTaken(String studentId) {
    return _studentAccounts.containsKey(studentId);
  }

  // Credential persistence (Remember Me)
  Future<void> saveCredentials(String id, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_user_id', id);
    await prefs.setString('saved_password', password);
    await prefs.setBool('remember_me', true);
  }

  Future<Map<String, String>?> loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool('remember_me') ?? false;
    if (!remember) return null;
    final id = prefs.getString('saved_user_id');
    final pass = prefs.getString('saved_password');
    if (id != null && pass != null) return {'id': id, 'password': pass};
    return null;
  }

  Future<void> clearSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_user_id');
    await prefs.remove('saved_password');
    await prefs.setBool('remember_me', false);
  }
}
