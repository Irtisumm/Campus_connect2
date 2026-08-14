import 'firestore_codecs.dart';

/// The single published Student Elections configuration document, stored at
/// `electionMeta/election_2026`.
///
/// This replaces the hard-coded `_electionContent` constant that lived in
/// `election_info_screen.dart`. Every field the screen rendered is preserved
/// — only serialisation was added, so the widgets render identically whether
/// the data came from the const or from Firestore.
///
/// The document is world-readable to signed-in users once published, and
/// admin-only for writes — exactly the same split as `events`. There is only
/// one document per election cycle, keyed by a stable id (`election_2026`)
/// so the seeder and the admin screen can address it without a query.
class ElectionMeta {
  /// Stable document id, e.g. `election_2026`.
  final String id;

  /// Human-facing election title, e.g. `Student Elections 2026`.
  final String title;

  final String allPositionsLabel;
  final String noticeTitle;
  final String noticeBody;
  final String aboutTitle;
  final String aboutBody;
  final String timelineTitle;
  final String upcomingLabel;
  final String positionsTitle;
  final String howToVoteTitle;
  final String pollingLocation;
  final String pollingDate;
  final String pollingTime;

  /// Open positions, stored as a Firestore string array.
  final List<String> positions;

  /// Timeline entries, stored as a Firestore array of maps.
  final List<ElectionTimelineEntry> timeline;

  /// How-to-vote steps, stored as a Firestore string array.
  final List<String> voteSteps;

  /// 'Pending' or 'Published'. Admin-only transitions, mirroring `events`.
  /// 'Archived' marks the document as retired into the Admin Archive — an
  /// archived election is never hard-deleted.
  final String status;

  /// The status the election held before it was archived. Restoring an
  /// election moves it back to this status.
  final String? previousStatus;

  /// ISO-8601 timestamp of when the election was archived. Null while active.
  final String? archivedAt;

  /// Campus ID of the admin who archived the election. Null while active.
  final String? archivedBy;

  /// ISO-8601 date the document was created, stamped by the service on
  /// create. Documents that predate this field decode to null.
  final String? createdAt;

  const ElectionMeta({
    required this.id,
    required this.title,
    required this.allPositionsLabel,
    required this.noticeTitle,
    required this.noticeBody,
    required this.aboutTitle,
    required this.aboutBody,
    required this.timelineTitle,
    required this.upcomingLabel,
    required this.positionsTitle,
    required this.howToVoteTitle,
    required this.pollingLocation,
    required this.pollingDate,
    required this.pollingTime,
    required this.positions,
    required this.timeline,
    required this.voteSteps,
    this.status = 'Published',
    this.previousStatus,
    this.archivedAt,
    this.archivedBy,
    this.createdAt,
  });

  /// Builds an [ElectionMeta] from a Firestore document map.
  ///
  /// [id] is the Firestore document key — pass it explicitly when reading a
  /// snapshot (`ElectionMeta.fromMap(doc.id, doc.data())`).
  factory ElectionMeta.fromMap(String id, Map<String, dynamic> data) {
    final rawTimeline = data['timeline'];
    return ElectionMeta(
      id: id,
      title: asString(data['title']),
      allPositionsLabel: asString(data['allPositionsLabel']).isEmpty
          ? 'All Positions'
          : asString(data['allPositionsLabel']),
      noticeTitle: asString(data['noticeTitle']),
      noticeBody: asString(data['noticeBody']),
      aboutTitle: asString(data['aboutTitle']),
      aboutBody: asString(data['aboutBody']),
      timelineTitle: asString(data['timelineTitle']),
      upcomingLabel: asString(data['upcomingLabel']).isEmpty
          ? 'Upcoming'
          : asString(data['upcomingLabel']),
      positionsTitle: asString(data['positionsTitle']),
      howToVoteTitle: asString(data['howToVoteTitle']),
      pollingLocation: asString(data['pollingLocation']),
      pollingDate: asString(data['pollingDate']),
      pollingTime: asString(data['pollingTime']),
      positions: asStringList(data['positions']),
      timeline: rawTimeline is Iterable
          ? rawTimeline
              .whereType<Map>()
              .map((entry) => ElectionTimelineEntry.fromMap(
                  Map<String, dynamic>.from(entry)))
              .toList()
          : const <ElectionTimelineEntry>[],
      voteSteps: asStringList(data['voteSteps']),
      status: asString(data['status']).isEmpty
          ? 'Published'
          : asString(data['status']),
      previousStatus: asStringOrNull(data['previousStatus']),
      archivedAt: asStringOrNull(data['archivedAt']),
      archivedBy: asStringOrNull(data['archivedBy']),
      createdAt: asStringOrNull(data['createdAt']),
    );
  }

  /// The payload written when the document is created or replaced.
  ///
  /// [id] is deliberately absent — the Firestore document key is the identity.
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'allPositionsLabel': allPositionsLabel,
      'noticeTitle': noticeTitle,
      'noticeBody': noticeBody,
      'aboutTitle': aboutTitle,
      'aboutBody': aboutBody,
      'timelineTitle': timelineTitle,
      'upcomingLabel': upcomingLabel,
      'positionsTitle': positionsTitle,
      'howToVoteTitle': howToVoteTitle,
      'pollingLocation': pollingLocation,
      'pollingDate': pollingDate,
      'pollingTime': pollingTime,
      'positions': positions,
      'timeline': timeline.map((e) => e.toMap()).toList(),
      'voteSteps': voteSteps,
      'status': status,
      'previousStatus': previousStatus,
      'archivedAt': archivedAt,
      'archivedBy': archivedBy,
      'createdAt': createdAt,
    };
  }

  /// True when the election has been retired into the Admin Archive.
  bool get isArchived => status == 'Archived';

  ElectionMeta copyWith({
    String? id,
    String? title,
    String? allPositionsLabel,
    String? noticeTitle,
    String? noticeBody,
    String? aboutTitle,
    String? aboutBody,
    String? timelineTitle,
    String? upcomingLabel,
    String? positionsTitle,
    String? howToVoteTitle,
    String? pollingLocation,
    String? pollingDate,
    String? pollingTime,
    List<String>? positions,
    List<ElectionTimelineEntry>? timeline,
    List<String>? voteSteps,
    String? status,
    String? previousStatus,
    String? archivedAt,
    String? archivedBy,
    String? createdAt,
  }) {
    return ElectionMeta(
      id: id ?? this.id,
      title: title ?? this.title,
      allPositionsLabel: allPositionsLabel ?? this.allPositionsLabel,
      noticeTitle: noticeTitle ?? this.noticeTitle,
      noticeBody: noticeBody ?? this.noticeBody,
      aboutTitle: aboutTitle ?? this.aboutTitle,
      aboutBody: aboutBody ?? this.aboutBody,
      timelineTitle: timelineTitle ?? this.timelineTitle,
      upcomingLabel: upcomingLabel ?? this.upcomingLabel,
      positionsTitle: positionsTitle ?? this.positionsTitle,
      howToVoteTitle: howToVoteTitle ?? this.howToVoteTitle,
      pollingLocation: pollingLocation ?? this.pollingLocation,
      pollingDate: pollingDate ?? this.pollingDate,
      pollingTime: pollingTime ?? this.pollingTime,
      positions: positions ?? this.positions,
      timeline: timeline ?? this.timeline,
      voteSteps: voteSteps ?? this.voteSteps,
      status: status ?? this.status,
      previousStatus: previousStatus ?? this.previousStatus,
      archivedAt: archivedAt ?? this.archivedAt,
      archivedBy: archivedBy ?? this.archivedBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// One entry on the election timeline.
///
/// Stored as a map inside the `timeline` array on the [ElectionMeta] document.
/// The `tone` controls the colour the timeline widget renders — it is a plain
/// string on the wire (`'accent'`, `'current'`, `'muted'`) so the seeder and
/// the admin screen can author it without Dart enums.
class ElectionTimelineEntry {
  final String date;
  final String description;
  final String tone;

  const ElectionTimelineEntry({
    required this.date,
    required this.description,
    required this.tone,
  });

  factory ElectionTimelineEntry.fromMap(Map<String, dynamic> data) {
    return ElectionTimelineEntry(
      date: asString(data['date']),
      description: asString(data['description']),
      tone: asString(data['tone']).isEmpty
          ? 'muted'
          : asString(data['tone']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'description': description,
      'tone': tone,
    };
  }
}