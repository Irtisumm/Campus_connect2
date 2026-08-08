import 'event_message.dart';
import 'firestore_codecs.dart';

/// A campus event, stored as one document in the `events` collection.
///
/// The document is the whole event: the submission, its approval state, the
/// admin ↔ host conversation (`messages`, a nested array — see [EventMessage])
/// and the joining configuration. Who may join, and whether they have paid,
/// lives on the separate `eventJoinings` documents so a student's own
/// registration can be owner-scoped by the security rules; the event document
/// itself is world-readable to signed-in users once published.
///
/// Field shapes are unchanged from the pre-Firestore model — this migration
/// moved the storage, not the schema. Dates and times stay display strings
/// (`'2025-03-15'`, `'10:00 AM'`) because that is exactly what the screens
/// render and what the admin types; nothing range-queries them.
class Event {
  final String id;
  final String title;
  final String date;
  final String time;
  final String location;
  final String category;
  final String organizer;
  final String description;

  /// 'Pending' → 'Under Review' → 'Needs Revision' / 'Rejected' / 'Published'
  /// → 'Completed'. Admin-only transitions are enforced by the security rules.
  final String status;

  /// The student who submitted the event, or `null` for an admin-created one.
  /// This is the ownership field the rules key off for edit/delete.
  final String? hostStudentId;

  final String? approvalLetterPath;
  final String? approvalLetterName;
  final bool hasApprovalLetter;
  final String? rejectionReason;
  final String? revisionNotes;

  /// The admin ↔ host thread, nested in the document. `null` and `[]` both
  /// mean "no messages"; `null` is preserved so an untouched event does not
  /// gain a field it never had.
  final List<EventMessage>? messages;

  final int revisionCount;
  final String? submittedDate;

  /// 'Open', 'Club', 'Club+Payment' or 'Paid' — the joining flow selector.
  final String eventType;
  final bool isPrivate;
  final bool clubIdRequired;
  final bool isPaid;
  final double price;

  /// Maximum number of approved participants the event can hold. `0` means
  /// no limit. When the approved attendee count reaches this value the join
  /// button is disabled and further registrations are refused in every layer.
  final int maxParticipants;

  /// Students whose joining was approved. Denormalised onto the event so the
  /// browse screen can show the attendee count without reading every joining.
  final List<String> attendeeIds;

  /// Joining documents still awaiting host approval.
  final List<String> pendingJoiningIds;

  final String? qrTicketPath;

  /// Optional cover image URL (Cloudinary secure URL). When non-null
  /// and non-empty, screens display this image instead of the generated
  /// category-gradient placeholder. Backward-compatible: existing events
  /// that predate this field will have `null` and show the placeholder.
  final String? coverImageUrl;

  /// Cloudinary public ID for the cover image. Used later for replacing
  /// or deleting the image via the Cloudinary API. `null` when no cover
  /// image has been uploaded.
  final String? coverImagePublicId;

  /// `true` when a participant cap is set and the approved attendee count has
  /// reached it. `maxParticipants` of `0` means unlimited, so this is always
  /// `false` in that case.
  bool get isFull =>
      maxParticipants > 0 && attendeeIds.length >= maxParticipants;

  /// Remaining slots before the cap is hit. `null` when there is no limit.
  int? get availableSlots =>
      maxParticipants > 0 ? maxParticipants - attendeeIds.length : null;

  const Event({
    required this.id,
    required this.title,
    required this.date,
    required this.time,
    required this.location,
    required this.category,
    required this.organizer,
    required this.description,
    required this.status,
    this.hostStudentId,
    this.approvalLetterPath,
    this.approvalLetterName,
    this.hasApprovalLetter = false,
    this.rejectionReason,
    this.revisionNotes,
    this.messages,
    this.revisionCount = 0,
    this.submittedDate,
    this.eventType = 'Open',
    this.isPrivate = false,
    this.clubIdRequired = false,
    this.isPaid = false,
    this.price = 0.0,
    this.maxParticipants = 0,
    this.attendeeIds = const [],
    this.pendingJoiningIds = const [],
    this.qrTicketPath,
    this.coverImageUrl,
    this.coverImagePublicId,
  });

  /// Builds an [Event] from a Firestore document map.
  ///
  /// [id] is the Firestore document key — pass it explicitly when reading a
  /// snapshot (`Event.fromMap(doc.id, doc.data())`).
  factory Event.fromMap(String id, Map<String, dynamic> data) {
    final rawMessages = data['messages'];
    return Event(
      id: id,
      title: asString(data['title']),
      date: asString(data['date']),
      time: asString(data['time']),
      location: asString(data['location']),
      category: asString(data['category']),
      organizer: asString(data['organizer']),
      description: asString(data['description']),
      status: asString(data['status']).isEmpty ? 'Pending' : asString(data['status']),
      hostStudentId: data['hostStudentId']?.toString(),
      approvalLetterPath: data['approvalLetterPath']?.toString(),
      approvalLetterName: data['approvalLetterName']?.toString(),
      hasApprovalLetter: asBool(data['hasApprovalLetter']),
      rejectionReason: data['rejectionReason']?.toString(),
      revisionNotes: data['revisionNotes']?.toString(),
      messages: rawMessages is Iterable
          ? rawMessages
              .whereType<Map>()
              .map((entry) => EventMessage.fromMap(Map<String, dynamic>.from(entry)))
              .toList()
          : null,
      revisionCount: (data['revisionCount'] as num?)?.toInt() ?? 0,
      submittedDate: data['submittedDate']?.toString(),
      eventType: asString(data['eventType']).isEmpty ? 'Open' : asString(data['eventType']),
      isPrivate: asBool(data['isPrivate']),
      clubIdRequired: asBool(data['clubIdRequired']),
      isPaid: asBool(data['isPaid']),
      price: (data['price'] as num?)?.toDouble() ?? 0.0,
      maxParticipants: (data['maxParticipants'] as num?)?.toInt() ?? 0,
      attendeeIds: asStringList(data['attendeeIds']),
      pendingJoiningIds: asStringList(data['pendingJoiningIds']),
      qrTicketPath: data['qrTicketPath']?.toString(),
      coverImageUrl: data['coverImageUrl']?.toString(),
      coverImagePublicId: data['coverImagePublicId']?.toString(),
    );
  }

  /// The payload written to the document.
  ///
  /// [id] is deliberately absent — the Firestore document key is the identity.
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'date': date,
      'time': time,
      'location': location,
      'category': category,
      'organizer': organizer,
      'description': description,
      'status': status,
      'hostStudentId': hostStudentId,
      'approvalLetterPath': approvalLetterPath,
      'approvalLetterName': approvalLetterName,
      'hasApprovalLetter': hasApprovalLetter,
      'rejectionReason': rejectionReason,
      'revisionNotes': revisionNotes,
      'messages': messages?.map((m) => m.toMap()).toList(),
      'revisionCount': revisionCount,
      'submittedDate': submittedDate,
      'eventType': eventType,
      'isPrivate': isPrivate,
      'clubIdRequired': clubIdRequired,
      'isPaid': isPaid,
      'price': price,
      'maxParticipants': maxParticipants,
      'attendeeIds': attendeeIds,
      'pendingJoiningIds': pendingJoiningIds,
      'qrTicketPath': qrTicketPath,
      if (coverImageUrl != null && coverImageUrl!.isNotEmpty)
        'coverImageUrl': coverImageUrl,
      if (coverImagePublicId != null && coverImagePublicId!.isNotEmpty)
        'coverImagePublicId': coverImagePublicId,
    };
  }

  Event copyWith({
    String? id,
    String? title,
    String? date,
    String? time,
    String? location,
    String? category,
    String? organizer,
    String? description,
    String? status,
    Object? hostStudentId = _sentinel,
    Object? approvalLetterPath = _sentinel,
    Object? approvalLetterName = _sentinel,
    bool? hasApprovalLetter,
    Object? rejectionReason = _sentinel,
    Object? revisionNotes = _sentinel,
    Object? messages = _sentinel,
    int? revisionCount,
    Object? submittedDate = _sentinel,
    String? eventType,
    bool? isPrivate,
    bool? clubIdRequired,
    bool? isPaid,
    double? price,
    int? maxParticipants,
    List<String>? attendeeIds,
    List<String>? pendingJoiningIds,
    Object? qrTicketPath = _sentinel,
    Object? coverImageUrl = _sentinel,
    Object? coverImagePublicId = _sentinel,
  }) {
    return Event(
      id: id ?? this.id,
      title: title ?? this.title,
      date: date ?? this.date,
      time: time ?? this.time,
      location: location ?? this.location,
      category: category ?? this.category,
      organizer: organizer ?? this.organizer,
      description: description ?? this.description,
      status: status ?? this.status,
      hostStudentId: identical(hostStudentId, _sentinel) ? this.hostStudentId : hostStudentId as String?,
      approvalLetterPath: identical(approvalLetterPath, _sentinel) ? this.approvalLetterPath : approvalLetterPath as String?,
      approvalLetterName: identical(approvalLetterName, _sentinel) ? this.approvalLetterName : approvalLetterName as String?,
      hasApprovalLetter: hasApprovalLetter ?? this.hasApprovalLetter,
      rejectionReason: identical(rejectionReason, _sentinel) ? this.rejectionReason : rejectionReason as String?,
      revisionNotes: identical(revisionNotes, _sentinel) ? this.revisionNotes : revisionNotes as String?,
      messages: identical(messages, _sentinel) ? this.messages : messages as List<EventMessage>?,
      revisionCount: revisionCount ?? this.revisionCount,
      submittedDate: identical(submittedDate, _sentinel) ? this.submittedDate : submittedDate as String?,
      eventType: eventType ?? this.eventType,
      isPrivate: isPrivate ?? this.isPrivate,
      clubIdRequired: clubIdRequired ?? this.clubIdRequired,
      isPaid: isPaid ?? this.isPaid,
      price: price ?? this.price,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      attendeeIds: attendeeIds ?? this.attendeeIds,
      pendingJoiningIds: pendingJoiningIds ?? this.pendingJoiningIds,
      qrTicketPath: identical(qrTicketPath, _sentinel) ? this.qrTicketPath : qrTicketPath as String?,
      coverImageUrl: identical(coverImageUrl, _sentinel) ? this.coverImageUrl : coverImageUrl as String?,
      coverImagePublicId: identical(coverImagePublicId, _sentinel) ? this.coverImagePublicId : coverImagePublicId as String?,
    );
  }

  static const Object _sentinel = Object();
}
