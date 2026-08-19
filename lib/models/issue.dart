import 'package:cloud_firestore/cloud_firestore.dart';

/// A document from the Firestore `issues` collection.
///
/// Moved out of `lib/data/mock_data.dart` and made Firestore-ready via
/// [Issue.fromMap] / [Issue.toMap]. Every field the mock model exposed is
/// preserved — only serialisation was added, nothing was renamed or dropped.
///
/// `createdDate` / `updatedDate` stay as ISO-8601 strings on the Dart side so
/// the existing screens keep formatting them exactly as before; the Firestore
/// documents store real [Timestamp]s, converted both ways here.
class Issue {
  /// Firestore document ID. Empty on an object that has not been written yet.
  final String id;
  final String title;
  final String category;
  final String location;
  final String status;
  final String createdDate;
  final String updatedDate;
  final String description;

  /// Campus-issued Student ID of the reporter (e.g. `S001`). Null on the
  /// student-side mock rows; populated once issues are written to Firestore.
  final String? studentId;

  final List<String> imagePaths;

  const Issue({
    required this.id,
    required this.title,
    required this.category,
    required this.location,
    required this.status,
    required this.createdDate,
    required this.updatedDate,
    required this.description,
    this.studentId,
    this.imagePaths = const [],
  });

  /// Builds an [Issue] from a Firestore document map.
  ///
  /// [id] is the Firestore document key — pass it explicitly when reading a
  /// snapshot (`Issue.fromMap(doc.id, doc.data())`).
  factory Issue.fromMap(String id, Map<String, dynamic> data) {
    return Issue(
      id: id,
      title: data['title']?.toString() ?? '',
      category: data['category']?.toString() ?? '',
      location: data['location']?.toString() ?? '',
      // A missing status is malformed data, not a newly submitted issue.
      // Keeping it empty prevents the dashboard from silently counting a
      // broken document as `New`; valid creates are pinned to `New` by the
      // Firestore rules and by AppState.createIssue().
      status: data['status']?.toString() ?? '',
      createdDate: _asIso(data['createdDate']),
      updatedDate: _asIso(data['updatedDate']),
      description: data['description']?.toString() ?? '',
      studentId: data['studentId']?.toString(),
      imagePaths: _asStringList(data['imagePaths']),
    );
  }

  /// The payload written when the document is first created.
  ///
  /// [id] is deliberately absent — the Firestore document key is the identity.
  /// Dates are stored as [Timestamp]s so range queries and ordering work.
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'category': category,
      'location': location,
      'status': status,
      'createdDate': _toTimestamp(createdDate),
      'updatedDate': _toTimestamp(updatedDate),
      'description': description,
      'studentId': studentId,
      'imagePaths': imagePaths,
    };
  }

  Issue copyWith({
    String? id,
    String? title,
    String? category,
    String? location,
    String? status,
    String? createdDate,
    String? updatedDate,
    String? description,
    String? studentId,
    List<String>? imagePaths,
  }) {
    return Issue(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      location: location ?? this.location,
      status: status ?? this.status,
      createdDate: createdDate ?? this.createdDate,
      updatedDate: updatedDate ?? this.updatedDate,
      description: description ?? this.description,
      studentId: studentId ?? this.studentId,
      imagePaths: imagePaths ?? this.imagePaths,
    );
  }

  static List<String> _asStringList(Object? value) {
    if (value is! Iterable) return const <String>[];
    return value.map((entry) => entry.toString()).toList(growable: false);
  }

  /// Firestore stores [Timestamp]s; the Dart side keeps ISO-8601 strings.
  static String _asIso(Object? value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is String) return value;
    return DateTime.now().toIso8601String();
  }

  static Object _toTimestamp(String value) {
    final parsed = DateTime.tryParse(value);
    return parsed == null
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(parsed);
  }
}

/// One status-transition entry in an issue's history.
///
/// Moved out of `lib/data/mock_data.dart` unchanged apart from the added
/// [IssueHistory.fromMap] / [IssueHistory.toMap] serialisation.
class IssueHistory {
  final String date;
  final String to;
  final String? from;
  final String? note;

  const IssueHistory({
    required this.date,
    required this.to,
    this.from,
    this.note,
  });

  factory IssueHistory.fromMap(Map<String, dynamic> data) {
    return IssueHistory(
      date: Issue._asIso(data['date']),
      to: data['to']?.toString() ?? '',
      from: data['from']?.toString(),
      note: data['note']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': Issue._toTimestamp(date),
      'to': to,
      'from': from,
      'note': note,
    };
  }
}
