import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle of a handed-over found item, stored in
/// `inventory/{id}.status`.
enum InventoryStatus {
  inInventory('In Inventory'),
  returned('Returned');

  const InventoryStatus(this.wireValue);
  final String wireValue;

  static InventoryStatus fromWire(Object? value,
      {InventoryStatus fallback = InventoryStatus.inInventory}) {
    final raw = value?.toString();
    for (final status in InventoryStatus.values) {
      if (status.wireValue == raw) return status;
    }
    return fallback;
  }
}

/// A document from the Firestore `inventory` collection.
///
/// Exactly one record is created per confirmed handover, by the admin
/// confirmation transaction. The finder may read their own records; admins
/// read and edit everything.
class InventoryItem {
  /// Firestore document ID. Empty on an object that has not been written yet.
  final String id;

  /// The found report this item came from (`items/{id}`).
  final String foundReportId;

  /// Firebase Authentication UID of the finder — the owner key the rules
  /// match on.
  final String finderUid;

  /// Campus Student ID of the finder (e.g. `S001`), denormalised for display.
  final String finderStudentId;

  final String title;
  final String category;
  final String description;

  /// Copied from the found report at handover time; never re-uploaded.
  final List<String> imageUrls;

  final InventoryStatus status;

  /// Set by the return transaction to the lost report the item went home
  /// with; `null` while the item is unclaimed.
  final String? matchedLostReportId;

  final DateTime? handedOverAt;
  final DateTime? returnedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const InventoryItem({
    this.id = '',
    required this.foundReportId,
    required this.finderUid,
    required this.finderStudentId,
    required this.title,
    required this.category,
    required this.description,
    this.imageUrls = const <String>[],
    this.status = InventoryStatus.inInventory,
    this.matchedLostReportId,
    this.handedOverAt,
    this.returnedAt,
    this.createdAt,
    this.updatedAt,
  });

  bool get isReturned => status == InventoryStatus.returned;

  InventoryItem copyWith({
    String? id,
    String? matchedLostReportId,
    InventoryStatus? status,
    DateTime? returnedAt,
    DateTime? updatedAt,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      foundReportId: foundReportId,
      finderUid: finderUid,
      finderStudentId: finderStudentId,
      title: title,
      category: category,
      description: description,
      imageUrls: imageUrls,
      status: status ?? this.status,
      matchedLostReportId: matchedLostReportId ?? this.matchedLostReportId,
      handedOverAt: handedOverAt,
      returnedAt: returnedAt ?? this.returnedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// The payload written when the record is first created (admin
  /// confirmation transaction). Born `In Inventory`.
  Map<String, dynamic> toCreateMap() {
    return {
      'foundReportId': foundReportId,
      'finderUid': finderUid,
      'finderStudentId': finderStudentId,
      'title': title,
      'category': category,
      'description': description,
      'imageUrls': imageUrls,
      'status': status.wireValue,
      'matchedLostReportId': matchedLostReportId,
      'handedOverAt': handedOverAt == null ? null : Timestamp.fromDate(handedOverAt!),
      'returnedAt': returnedAt == null ? null : Timestamp.fromDate(returnedAt!),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// The payload written when the record is edited (admin-only).
  Map<String, dynamic> toUpdateMap() {
    return {
      'status': status.wireValue,
      'matchedLostReportId': matchedLostReportId,
      'returnedAt': returnedAt == null ? null : Timestamp.fromDate(returnedAt!),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory InventoryItem.fromMap(String id, Map<String, dynamic> data) {
    return InventoryItem(
      id: id,
      foundReportId: data['foundReportId']?.toString() ?? '',
      finderUid: data['finderUid']?.toString() ?? '',
      finderStudentId: data['finderStudentId']?.toString() ?? '',
      title: data['title']?.toString() ?? '',
      category: data['category']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      imageUrls: _asStringList(data['imageUrls']),
      status: InventoryStatus.fromWire(data['status']),
      matchedLostReportId: data['matchedLostReportId']?.toString(),
      handedOverAt: _asDate(data['handedOverAt']),
      returnedAt: _asDate(data['returnedAt']),
      createdAt: _asDate(data['createdAt']),
      updatedAt: _asDate(data['updatedAt']),
    );
  }

  static List<String> _asStringList(Object? value) {
    if (value is! Iterable) return const <String>[];
    return value.map((entry) => entry.toString()).toList(growable: false);
  }

  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
