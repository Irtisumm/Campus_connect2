import 'package:cloud_firestore/cloud_firestore.dart';

/// Whether a document in the `items` collection is something a student lost or
/// something somebody handed in.
///
/// [wireValue] is what actually lives in Firestore — the enum is the only thing
/// the Dart side should ever compare against.
enum ItemType {
  lost('lost'),
  found('found');

  const ItemType(this.wireValue);
  final String wireValue;

  static ItemType fromWire(Object? value, {ItemType fallback = ItemType.lost}) {
    final raw = value?.toString();
    for (final type in ItemType.values) {
      if (type.wireValue == raw) return type;
    }
    return fallback;
  }
}

/// Lifecycle of a report, stored in `items/{id}.status`.
///
/// The wire values are the exact strings the existing screens already display
/// and filter on, so nothing had to be renamed to move this into Firestore.
///
/// The last three values belong to the full-workflow build (Workflows 2 and
/// 3): a found report is born `Awaiting Handover`, moves to `In Inventory`
/// when the admin confirms the physical handover, and to `Returned` when the
/// item goes back to its owner.
enum ItemStatus {
  active('Active'),
  awaitingHandover('Awaiting Handover'),
  matchedPending('Matched - Pending'),
  inInventory('In Inventory'),
  resolved('Resolved'),
  returned('Returned'),
  closed('Closed');

  const ItemStatus(this.wireValue);
  final String wireValue;

  static ItemStatus fromWire(Object? value,
      {ItemStatus fallback = ItemStatus.active}) {
    final raw = value?.toString();
    for (final status in ItemStatus.values) {
      if (status.wireValue == raw) return status;
    }
    return fallback;
  }
}

/// A document from the Firestore `items` collection.
///
/// One model covers both lost and found reports — [type] discriminates. Lost
/// report submission and My Lost Reports are served from Firestore through
/// this model; the remaining read paths are still on `DataService` and are
/// migrated in later phases.
class Item {
  /// Firestore document ID. Empty on an object that has not been written yet.
  final String id;

  final ItemType type;
  final String title;
  final String category;
  final String description;

  /// Where the item went missing. Named after the field the report form has
  /// always used rather than a generic `location`.
  final String whereLost;

  /// When the item went missing. The form has no date picker, so this is the
  /// submission moment.
  final DateTime? whenLost;

  /// Firebase Authentication UID of the reporter — the owner key the security
  /// rules match on.
  final String reportedByUid;

  /// Campus-issued Student ID (e.g. `S001`). Denormalised so the admin lists
  /// can show who reported an item without a second read.
  final String reportedByStudentId;

  final List<String> imageUrls;
  final ItemStatus status;

  /// Soft delete. Reports are hidden rather than removed so admin history and
  /// any match already made against them survive.
  final bool isDeleted;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Item({
    this.id = '',
    required this.type,
    required this.title,
    required this.category,
    required this.description,
    required this.whereLost,
    required this.reportedByUid,
    required this.reportedByStudentId,
    this.whenLost,
    this.imageUrls = const <String>[],
    this.status = ItemStatus.active,
    this.isDeleted = false,
    this.createdAt,
    this.updatedAt,
  });

  bool get isLost => type == ItemType.lost;
  bool get isFound => type == ItemType.found;

  /// `YYYY-MM-DD`, the form the existing report screens display dates in.
  String get whenLostLabel =>
      whenLost == null ? '' : whenLost!.toIso8601String().split('T').first;

  int get photoCount => imageUrls.length;

  Item copyWith({
    String? id,
    String? title,
    String? category,
    String? description,
    String? whereLost,
    DateTime? whenLost,
    List<String>? imageUrls,
    ItemStatus? status,
    bool? isDeleted,
    DateTime? updatedAt,
  }) {
    return Item(
      id: id ?? this.id,
      type: type,
      title: title ?? this.title,
      category: category ?? this.category,
      description: description ?? this.description,
      whereLost: whereLost ?? this.whereLost,
      whenLost: whenLost ?? this.whenLost,
      // Reporter identity is fixed at creation.
      reportedByUid: reportedByUid,
      reportedByStudentId: reportedByStudentId,
      imageUrls: imageUrls ?? this.imageUrls,
      status: status ?? this.status,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// The payload written when the document is first created.
  ///
  /// [id] is deliberately absent — the Firestore document key is the identity.
  Map<String, dynamic> toCreateMap() {
    return {
      'type': type.wireValue,
      'title': title,
      'category': category,
      'description': description,
      'whereLost': whereLost,
      'whenLost': whenLost == null ? null : Timestamp.fromDate(whenLost!),
      'reportedByUid': reportedByUid,
      'reportedByStudentId': reportedByStudentId,
      'imageUrls': imageUrls,
      'status': status.wireValue,
      'isDeleted': isDeleted,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// The payload written when an existing report is edited.
  ///
  /// Only the editable fields are included — `type`, `reportedByUid`,
  /// `reportedByStudentId`, and `createdAt` are deliberately absent because
  /// they are immutable (enforced by both `copyWith` and the Firestore rules).
  /// `updatedAt` is always refreshed via a server timestamp.
  Map<String, dynamic> toUpdateMap() {
    return {
      'title': title,
      'category': category,
      'description': description,
      'whereLost': whereLost,
      'imageUrls': imageUrls,
      'status': status.wireValue,
      'isDeleted': isDeleted,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory Item.fromMap(String id, Map<String, dynamic> data) {
    return Item(
      id: id,
      type: ItemType.fromWire(data['type']),
      title: data['title']?.toString() ?? '',
      category: data['category']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      whereLost: data['whereLost']?.toString() ?? '',
      whenLost: _asDate(data['whenLost']),
      reportedByUid: data['reportedByUid']?.toString() ?? '',
      reportedByStudentId: data['reportedByStudentId']?.toString() ?? '',
      imageUrls: _asStringList(data['imageUrls']),
      status: ItemStatus.fromWire(data['status']),
      isDeleted: data['isDeleted'] == true,
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
