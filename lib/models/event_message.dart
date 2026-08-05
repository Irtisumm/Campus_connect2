import 'firestore_codecs.dart';

/// One entry in the admin ↔ host conversation attached to an event.
///
/// Unlike [Event], [EventJoining] and [EventRole], a message is **not** a
/// Firestore document: it is a nested map inside `events/{eventId}.messages`.
/// That is deliberate — the thread is small, bounded, always read together
/// with the event, and never queried on its own, so a subcollection would buy
/// nothing and cost an extra read per screen. Because there is no document
/// key, [id] is carried inside the map itself.
class EventMessage {
  final String id;
  final String senderId;

  /// 'admin' or 'student' — drives which side of the thread the bubble sits on.
  final String senderRole;
  final String message;

  /// ISO-8601 instant the message was written, kept as a string because the
  /// whole thread is a nested array and Firestore cannot index inside it
  /// anyway; ordering is done client-side on this value.
  final String timestamp;
  final String? attachmentName;

  const EventMessage({
    required this.id,
    required this.senderId,
    required this.senderRole,
    required this.message,
    required this.timestamp,
    this.attachmentName,
  });

  /// Builds an [EventMessage] from one element of the `messages` array.
  ///
  /// There is no document key to pass in: the identity travels in the map.
  factory EventMessage.fromMap(Map<String, dynamic> data) {
    return EventMessage(
      id: asString(data['id']),
      senderId: asString(data['senderId']),
      senderRole: asString(data['senderRole']).isEmpty
          ? 'student'
          : asString(data['senderRole']),
      message: asString(data['message']),
      timestamp: asString(data['timestamp']),
      attachmentName: data['attachmentName']?.toString(),
    );
  }

  /// The payload written into the `messages` array. [id] is included because a
  /// nested map has no document key of its own.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderId': senderId,
      'senderRole': senderRole,
      'message': message,
      'timestamp': timestamp,
      'attachmentName': attachmentName,
    };
  }

  EventMessage copyWith({
    String? id,
    String? senderId,
    String? senderRole,
    String? message,
    String? timestamp,
    Object? attachmentName = _sentinel,
  }) {
    return EventMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderRole: senderRole ?? this.senderRole,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      attachmentName: identical(attachmentName, _sentinel)
          ? this.attachmentName
          : attachmentName as String?,
    );
  }

  static const Object _sentinel = Object();
}
