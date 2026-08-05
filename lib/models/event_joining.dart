import 'firestore_codecs.dart';

/// One student's registration for one event — a document in `eventJoinings`.
///
/// This is the owner-scoped half of the Events schema. The event document is
/// readable by every signed-in user, so anything that identifies a particular
/// student (their name, course, club ID, payment state and above all their
/// [qrTicketCode]) lives here instead, behind an ownership rule. The ticket
/// code is the entry credential: if it were denormalised onto the event, any
/// signed-in student could read a stranger's ticket — the same class of leak
/// the locker `digitalCode` fix closed.
class EventJoining {
  final String id;
  final String eventId;

  /// The owner. Every read rule on this collection keys off this field.
  final String studentId;

  final String name;
  final String courseName;

  /// Club membership number, required only when the event sets
  /// `clubIdRequired`.
  final String? clubId;

  /// 'Pending' → 'Approved' / 'Rejected'. Open events skip straight to
  /// 'Approved'; club and paid events wait for the host.
  final String status;

  /// `null` for a free event, otherwise 'Pending' or 'Completed'.
  final String? paymentStatus;

  /// The entry credential, issued once the joining is approved (and paid for).
  /// Never denormalised onto the event document.
  final String? qrTicketCode;

  final String joinedDate;
  final bool hasAttended;

  const EventJoining({
    required this.id,
    required this.eventId,
    required this.studentId,
    required this.name,
    required this.courseName,
    this.clubId,
    this.status = 'Pending',
    this.paymentStatus,
    this.qrTicketCode,
    required this.joinedDate,
    this.hasAttended = false,
  });

  /// Builds an [EventJoining] from a Firestore document map.
  ///
  /// [id] is the Firestore document key — pass it explicitly when reading a
  /// snapshot (`EventJoining.fromMap(doc.id, doc.data())`).
  factory EventJoining.fromMap(String id, Map<String, dynamic> data) {
    return EventJoining(
      id: id,
      eventId: asString(data['eventId']),
      studentId: asString(data['studentId']),
      name: asString(data['name']),
      courseName: asString(data['courseName']),
      clubId: data['clubId']?.toString(),
      status: asString(data['status']).isEmpty ? 'Pending' : asString(data['status']),
      paymentStatus: data['paymentStatus']?.toString(),
      qrTicketCode: data['qrTicketCode']?.toString(),
      joinedDate: asString(data['joinedDate']),
      hasAttended: asBool(data['hasAttended']),
    );
  }

  /// The payload written to the document.
  ///
  /// [id] is deliberately absent — the Firestore document key is the identity.
  Map<String, dynamic> toMap() {
    return {
      'eventId': eventId,
      'studentId': studentId,
      'name': name,
      'courseName': courseName,
      'clubId': clubId,
      'status': status,
      'paymentStatus': paymentStatus,
      'qrTicketCode': qrTicketCode,
      'joinedDate': joinedDate,
      'hasAttended': hasAttended,
    };
  }

  EventJoining copyWith({
    String? id,
    String? eventId,
    String? studentId,
    String? name,
    String? courseName,
    Object? clubId = _sentinel,
    String? status,
    Object? paymentStatus = _sentinel,
    Object? qrTicketCode = _sentinel,
    String? joinedDate,
    bool? hasAttended,
  }) {
    return EventJoining(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      studentId: studentId ?? this.studentId,
      name: name ?? this.name,
      courseName: courseName ?? this.courseName,
      clubId: identical(clubId, _sentinel) ? this.clubId : clubId as String?,
      status: status ?? this.status,
      paymentStatus: identical(paymentStatus, _sentinel) ? this.paymentStatus : paymentStatus as String?,
      qrTicketCode: identical(qrTicketCode, _sentinel) ? this.qrTicketCode : qrTicketCode as String?,
      joinedDate: joinedDate ?? this.joinedDate,
      hasAttended: hasAttended ?? this.hasAttended,
    );
  }

  static const Object _sentinel = Object();
}
