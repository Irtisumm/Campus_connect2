import 'package:flutter_test/flutter_test.dart';

import 'package:campus_connect/models/election_meta.dart';

void main() {
  const timeline = <ElectionTimelineEntry>[
    ElectionTimelineEntry(
      date: '2026-04-01',
      description: 'Nominations open',
      tone: 'muted',
    ),
  ];

  ElectionMeta baseMeta({String status = 'Published'}) => ElectionMeta(
        id: 'election_2026',
        title: 'Election 2026',
        allPositionsLabel: 'All Positions',
        noticeTitle: 'Notice',
        noticeBody: 'Notice body',
        aboutTitle: 'About',
        aboutBody: 'About body',
        timelineTitle: 'Timeline',
        upcomingLabel: 'Upcoming',
        positionsTitle: 'Positions',
        howToVoteTitle: 'How to Vote',
        pollingLocation: 'Main Hall',
        pollingDate: '2026-05-01',
        pollingTime: '09:00',
        positions: const <String>['President'],
        timeline: timeline,
        voteSteps: const <String>['Step one'],
        status: status,
      );

  group('ElectionMeta archive fields', () {
    test('toMap -> fromMap round-trip preserves archive fields and status', () {
      final meta = baseMeta(status: 'Archived').copyWith(
        previousStatus: 'Published',
        archivedAt: '2026-08-01T10:00:00',
        archivedBy: 'ADMIN001',
        createdAt: '2026-01-10',
      );

      final restored = ElectionMeta.fromMap(meta.id, meta.toMap());

      expect(restored.status, 'Archived');
      expect(restored.previousStatus, 'Published');
      expect(restored.archivedAt, '2026-08-01T10:00:00');
      expect(restored.archivedBy, 'ADMIN001');
      expect(restored.createdAt, '2026-01-10');
    });

    test('isArchived is true only for the Archived status', () {
      expect(baseMeta(status: 'Archived').isArchived, isTrue);
      expect(baseMeta(status: 'Published').isArchived, isFalse);
      expect(baseMeta(status: 'Pending').isArchived, isFalse);
    });

    test('fromMap without the new fields yields nulls and a default status',
        () {
      final meta = ElectionMeta.fromMap('election_2026', <String, dynamic>{
        'title': 'Election 2026',
        'allPositionsLabel': 'All Positions',
        'noticeTitle': 'Notice',
        'noticeBody': 'Notice body',
        'aboutTitle': 'About',
        'aboutBody': 'About body',
        'timelineTitle': 'Timeline',
        'upcomingLabel': 'Upcoming',
        'positionsTitle': 'Positions',
        'howToVoteTitle': 'How to Vote',
        'pollingLocation': 'Main Hall',
        'pollingDate': '2026-05-01',
        'pollingTime': '09:00',
        'positions': <String>['President'],
        'timeline': <Map<String, dynamic>>[
          {
            'date': '2026-04-01',
            'description': 'Nominations open',
            'tone': 'muted',
          },
        ],
        'voteSteps': <String>['Step one'],
      });

      expect(meta.previousStatus, isNull);
      expect(meta.archivedAt, isNull);
      expect(meta.archivedBy, isNull);
      expect(meta.createdAt, isNull);
      expect(meta.status, 'Published');
    });

    test('copyWith updates archive fields and preserves the rest', () {
      final meta = baseMeta(status: 'Published').copyWith(
        status: 'Archived',
        previousStatus: 'Published',
        archivedAt: '2026-08-01T10:00:00',
        archivedBy: 'ADMIN001',
        createdAt: '2026-01-10',
      );

      expect(meta.status, 'Archived');
      expect(meta.previousStatus, 'Published');
      expect(meta.archivedAt, '2026-08-01T10:00:00');
      expect(meta.archivedBy, 'ADMIN001');
      expect(meta.createdAt, '2026-01-10');

      // Everything not touched by copyWith stays the same.
      expect(meta.id, 'election_2026');
      expect(meta.title, 'Election 2026');
      expect(meta.positions, const <String>['President']);
      expect(meta.voteSteps, const <String>['Step one']);
      expect(meta.timeline, timeline);
      expect(meta.pollingDate, '2026-05-01');
    });
  });
}
