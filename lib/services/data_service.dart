import 'dart:math';
import 'package:flutter/material.dart';
import '../data/mock_data.dart' hide Notification;
import '../data/mock_data.dart' as mockdata show Notification;

class DataService extends ChangeNotifier {
  // Lists - mutable instead of const
  late List<LostReport> myLostReports;
  late List<FoundReport> myFoundReports;
  late List<AdminLostReport> allLostReports;
  late List<LfMatch> matches;
  late List<Issue> myIssues;
  late List<Issue> allIssues;
  late Map<String, List<IssueHistory>> issueHistory;
  late List<EventJoining> eventJoiningRequests; // Track all joining requests
  late List<Event> allEvents;
  late List<Event> pendingEvents; // Events waiting for approval
  late List<Candidate> candidates;
  late List<Locker> lockers;
  late List<LockerBooking> myBookings;
  late List<LockerIssue> lockerIssues;
  late Map<String, List<LockerHistory>> lockerHistory;
  late List<mockdata.Notification> notifications;
  final List<EventRole> eventRoles = [];

  DataService() {
    _initializeData();
  }

  void _initializeData() {
    myLostReports = List.from(MockData.myLostReports);
    myFoundReports = List.from(MockData.myFoundReports);
    allLostReports = List.from(MockData.allLostReports);
    matches = List.from(MockData.matches);
    myIssues = List.from(MockData.myIssues);
    allIssues = List.from(MockData.allIssues);
    allEvents = List.from(MockData.events);  // Pre-populate with published events
    pendingEvents = [];
    candidates = List.from(MockData.candidates);
    lockers = List.from(MockData.lockers);
    myBookings = List.from(MockData.myBookings);
    lockerIssues = List.from(MockData.lockerIssues);
    lockerHistory = Map.from(MockData.lockerHistory.map((k, v) => MapEntry(k, List<LockerHistory>.from(v))));
    notifications = List.from(MockData.notifications);

    // Initialize mutable issueHistory from mock data
    issueHistory = Map.from(MockData.issueHistory.map((k, v) => MapEntry(k, List<IssueHistory>.from(v))));

    // Create history entries for all issues if they don't already exist
    for (final issue in myIssues) {
      if (!issueHistory.containsKey(issue.id)) {
        issueHistory[issue.id] = [
          IssueHistory(date: issue.createdDate, from: null, to: issue.status, note: 'Issue submitted by student.'),
        ];
      }
    }
    for (final issue in allIssues) {
      if (!issueHistory.containsKey(issue.id)) {
        issueHistory[issue.id] = [
          IssueHistory(date: issue.createdDate, from: null, to: issue.status, note: 'Issue submitted by student.'),
        ];
      }
    }

    // Initialize event joining requests
    eventJoiningRequests = [];
  }

  // ── LOST & FOUND ────────────────────────────────────────────────
  void addLostReport(LostReport report) {
    myLostReports.add(report);
    allLostReports.add(AdminLostReport(
      id: report.id,
      studentId: 'S001',
      title: report.title,
      category: report.category,
      whereLost: report.whereLost,
      status: report.status,
      createdDate: report.whenLost,
    ));
    // Public notification (no sensitive details)
    _addNotification('A lost item has been reported', 'public', source: 'lost_found');
    // Private notification to admin with details
    _addNotification(
      'New lost report: ${report.id}',
      'private',
      detailText: '${report.title} - ${report.category}, ${report.whereLost}',
      visibility: 'admin',
      source: 'lost_found',
    );
    notifyListeners();
  }

  void addFoundReport(FoundReport report) {
    myFoundReports.add(report);
    // Public notification (no sensitive details)
    _addNotification('A found item has been reported', 'public', source: 'lost_found');
    // Private notification to admin
    _addNotification(
      'New found report: ${report.id}',
      'private',
      detailText: '${report.category} found at ${report.whereFound}. Description: ${report.description}',
      visibility: 'admin',
      source: 'lost_found',
    );
    // Run smart matching engine
    _checkForMatches(report);
    notifyListeners();
  }

  void updateLostReportStatus(String id, String newStatus) {
    final index = myLostReports.indexWhere((r) => r.id == id);
    if (index != -1) {
      myLostReports[index] = LostReport(
        id: myLostReports[index].id,
        title: myLostReports[index].title,
        category: myLostReports[index].category,
        whereLost: myLostReports[index].whereLost,
        whenLost: myLostReports[index].whenLost,
        status: newStatus,
        description: myLostReports[index].description,
        photos: myLostReports[index].photos,
        matchStatus: myLostReports[index].matchStatus,
      );
    }
    // Also update allLostReports (admin list)
    final adminIndex = allLostReports.indexWhere((r) => r.id == id);
    if (adminIndex != -1) {
      final r = allLostReports[adminIndex];
      allLostReports[adminIndex] = AdminLostReport(
        id: r.id, studentId: r.studentId, title: r.title,
        category: r.category, whereLost: r.whereLost,
        status: newStatus, createdDate: r.createdDate,
        aiScore: r.aiScore, matchedFoundId: r.matchedFoundId,
      );
    }
    notifyListeners();
  }

  void updateAdminLostReportStatus(String id, String newStatus) {
    final index = allLostReports.indexWhere((r) => r.id == id);
    if (index != -1) {
      final r = allLostReports[index];
      allLostReports[index] = AdminLostReport(
        id: r.id, studentId: r.studentId, title: r.title,
        category: r.category, whereLost: r.whereLost,
        status: newStatus, createdDate: r.createdDate,
        aiScore: r.aiScore, matchedFoundId: r.matchedFoundId,
      );
    }
    // Also sync student's myLostReports
    final myIndex = myLostReports.indexWhere((r) => r.id == id);
    if (myIndex != -1) {
      final r = myLostReports[myIndex];
      myLostReports[myIndex] = LostReport(
        id: r.id, title: r.title, category: r.category,
        whereLost: r.whereLost, whenLost: r.whenLost,
        status: newStatus, description: r.description,
        photos: r.photos, matchStatus: r.matchStatus,
      );
    }
    _addNotification('Lost report $id status updated to $newStatus', 'personal');
    notifyListeners();
  }

  void updateFoundReportStatus(String id, String newStatus) {
    final index = myFoundReports.indexWhere((r) => r.id == id);
    if (index != -1) {
      final r = myFoundReports[index];
      myFoundReports[index] = FoundReport(
        id: r.id, description: r.description, category: r.category,
        whereFound: r.whereFound, whenFound: r.whenFound,
        status: newStatus, photos: r.photos,
        handoverStatus: r.handoverStatus, qrCode: r.qrCode, qrScanned: r.qrScanned,
        handoverStep: r.handoverStep,
      );
    }
    _addNotification('Found report $id status updated to $newStatus', 'personal');
    notifyListeners();
  }

  // ── QR Code: Admin generates one-time QR for found item receive ──
  String generateReceiveQR(String foundReportId) {
    final code = 'RCV-$foundReportId-${Random().nextInt(999999).toString().padLeft(6, '0')}';
    final index = myFoundReports.indexWhere((r) => r.id == foundReportId);
    if (index != -1) {
      final r = myFoundReports[index];
      myFoundReports[index] = FoundReport(
        id: r.id, description: r.description, category: r.category,
        whereFound: r.whereFound, whenFound: r.whenFound,
        status: r.status, photos: r.photos,
        handoverStatus: 'Pending Handover', qrCode: code, qrScanned: false,
        handoverStep: 3,
      );
    }
    notifyListeners();
    return code;
  }

  // Student scans QR code to confirm handover
  bool scanReceiveQR(String foundReportId, String qrCode) {
    final index = myFoundReports.indexWhere((r) => r.id == foundReportId);
    if (index != -1) {
      final r = myFoundReports[index];
      if (r.qrCode == qrCode && !r.qrScanned) {
        myFoundReports[index] = FoundReport(
          id: r.id, description: r.description, category: r.category,
          whereFound: r.whereFound, whenFound: r.whenFound,
          status: 'Received', photos: r.photos,
          handoverStatus: 'Handed Over', qrCode: r.qrCode, qrScanned: true,
          handoverStep: 5,
        );
        _addNotification('An item handover has been confirmed successfully.', 'personal');
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  // Admin generates handover QR (for claiming student)
  String generateHandoverQR(String foundReportId) {
    final code = 'HND-$foundReportId-${Random().nextInt(999999).toString().padLeft(6, '0')}';
    final index = myFoundReports.indexWhere((r) => r.id == foundReportId);
    if (index != -1) {
      final r = myFoundReports[index];
      myFoundReports[index] = FoundReport(
        id: r.id, description: r.description, category: r.category,
        whereFound: r.whereFound, whenFound: r.whenFound,
        status: 'Claiming', photos: r.photos,
        handoverStatus: 'Claiming', qrCode: code, qrScanned: false,
        handoverStep: r.handoverStep,
      );
    }
    _addNotification('A handover QR has been generated for a found item', 'admin');
    notifyListeners();
    return code;
  }

  void completeHandover(String foundReportId) {
    final index = myFoundReports.indexWhere((r) => r.id == foundReportId);
    if (index != -1) {
      final r = myFoundReports[index];
      myFoundReports[index] = FoundReport(
        id: r.id, description: r.description, category: r.category,
        whereFound: r.whereFound, whenFound: r.whenFound,
        status: 'Resolved', photos: r.photos,
        handoverStatus: 'Claimed', qrCode: null, qrScanned: true,
        handoverStep: 5,
      );
    }
    _addNotification('A found item has been claimed and resolved.', 'personal');
    notifyListeners();
  }

  // ── ISSUES ──────────────────────────────────────────────────────
  void reportIssue(Issue issue) {
    myIssues.add(issue);
    allIssues.add(issue);

    // Create initial history entry for the new issue
    issueHistory[issue.id] = [
      IssueHistory(date: issue.createdDate, from: null, to: issue.status, note: 'Issue submitted by student.'),
    ];

    _addNotification(
      'A new campus issue has been reported',
      'admin',
    );
    notifyListeners();
  }

  void updateIssueStatus(String id, String newStatus) {
    // Get the old status before updating
    final oldStatus = allIssues.firstWhere((i) => i.id == id, orElse: () => const Issue(
      id: '', title: '', category: '', location: '',
      status: '', createdDate: '', updatedDate: '', description: ''
    )).status;

    // Update in allIssues (admin list)
    final index = allIssues.indexWhere((i) => i.id == id);
    if (index != -1) {
      allIssues[index] = Issue(
        id: allIssues[index].id,
        title: allIssues[index].title,
        category: allIssues[index].category,
        location: allIssues[index].location,
        status: newStatus,
        createdDate: allIssues[index].createdDate,
        updatedDate: DateTime.now().toString().split('.')[0],
        description: allIssues[index].description,
        studentId: allIssues[index].studentId,
        imagePaths: allIssues[index].imagePaths,
      );
    }
    // ALSO sync to myIssues (student view) - BUG FIX
    final myIndex = myIssues.indexWhere((i) => i.id == id);
    if (myIndex != -1) {
      myIssues[myIndex] = Issue(
        id: myIssues[myIndex].id,
        title: myIssues[myIndex].title,
        category: myIssues[myIndex].category,
        location: myIssues[myIndex].location,
        status: newStatus,
        createdDate: myIssues[myIndex].createdDate,
        updatedDate: DateTime.now().toString().split('.')[0],
        description: myIssues[myIndex].description,
        studentId: myIssues[myIndex].studentId,
        imagePaths: myIssues[myIndex].imagePaths,
      );
    }

    // Add history entry for status change (only if status actually changed)
    if (oldStatus != newStatus && oldStatus.isNotEmpty) {
      final hist = issueHistory[id] ?? [];
      hist.add(IssueHistory(
        date: DateTime.now().toString().split('.')[0],
        from: oldStatus,
        to: newStatus,
        note: null,
      ));
      issueHistory[id] = hist;
    }

    _addNotification('Issue $id status updated to $newStatus', 'personal');
    notifyListeners();
  }

  void deleteIssue(String id) {
    allIssues.removeWhere((i) => i.id == id);
    myIssues.removeWhere((i) => i.id == id);
    _addNotification('Issue $id has been deleted.', 'admin');
    notifyListeners();
  }

  /// Force a UI rebuild — useful for pull-to-refresh
  void refresh() => notifyListeners();

  // ── EVENTS ──────────────────────────────────────────────────────
  Event _copyEvent(
    Event e, {
    String? title,
    String? date,
    String? time,
    String? location,
    String? category,
    String? organizer,
    String? description,
    String? status,
    String? hostStudentId,
    String? approvalLetterPath,
    String? approvalLetterName,
    bool? hasApprovalLetter,
    String? rejectionReason,
    String? revisionNotes,
    List<EventMessage>? messages,
    int? revisionCount,
    String? submittedDate,
    String? eventType,
    bool? isPrivate,
    bool? clubIdRequired,
    bool? isPaid,
    double? price,
    List<String>? attendeeIds,
    List<String>? pendingJoiningIds,
    String? qrTicketPath,
  }) {
    return Event(
      id: e.id,
      title: title ?? e.title,
      date: date ?? e.date,
      time: time ?? e.time,
      location: location ?? e.location,
      category: category ?? e.category,
      organizer: organizer ?? e.organizer,
      description: description ?? e.description,
      status: status ?? e.status,
      hostStudentId: hostStudentId ?? e.hostStudentId,
      approvalLetterPath: approvalLetterPath ?? e.approvalLetterPath,
      approvalLetterName: approvalLetterName ?? e.approvalLetterName,
      hasApprovalLetter: hasApprovalLetter ?? e.hasApprovalLetter,
      rejectionReason: rejectionReason ?? e.rejectionReason,
      revisionNotes: revisionNotes ?? e.revisionNotes,
      messages: messages ?? e.messages,
      revisionCount: revisionCount ?? e.revisionCount,
      submittedDate: submittedDate ?? e.submittedDate,
      eventType: eventType ?? e.eventType,
      isPrivate: isPrivate ?? e.isPrivate,
      clubIdRequired: clubIdRequired ?? e.clubIdRequired,
      isPaid: isPaid ?? e.isPaid,
      price: price ?? e.price,
      attendeeIds: attendeeIds ?? e.attendeeIds,
      pendingJoiningIds: pendingJoiningIds ?? e.pendingJoiningIds,
      qrTicketPath: qrTicketPath ?? e.qrTicketPath,
    );
  }

  /// Check if user has permission to access a file (role-based access control)
  bool canAccessFilePath(String? filePath, String? userId, bool isAdmin, String? eventCreatorId) {
    if (filePath == null || filePath.isEmpty) return false;

    // Admins can always access files
    if (isAdmin) return true;

    // Students can only access their own files
    if (userId != null && eventCreatorId != null && userId == eventCreatorId) return true;

    // Otherwise, deny access
    return false;
  }

  Event? getEventById(String id) {
    final pendingIndex = pendingEvents.indexWhere((e) => e.id == id);
    if (pendingIndex != -1) return pendingEvents[pendingIndex];
    final publishedIndex = allEvents.indexWhere((e) => e.id == id);
    if (publishedIndex != -1) return allEvents[publishedIndex];
    return null;
  }

  List<Event> getEventsForHost(String? hostStudentId) {
    if (hostStudentId == null || hostStudentId.isEmpty) {
      return [];
    }

    // Collect events from both pending and published, ensuring no duplicates
    final eventMap = <String, Event>{};

    // Add pending events
    for (final e in pendingEvents) {
      if (e.hostStudentId != null && e.hostStudentId == hostStudentId) {
        eventMap[e.id] = e;
      }
    }

    // Add published events (will overwrite pending if same ID, which is correct)
    for (final e in allEvents) {
      if (e.hostStudentId != null && e.hostStudentId == hostStudentId) {
        eventMap[e.id] = e;
      }
    }

    return eventMap.values.toList();
  }

  void createEvent(Event event) {
    // Ensure hostStudentId is set, otherwise event won't appear in getEventsForHost
    if (event.hostStudentId == null || event.hostStudentId!.isEmpty) {
      throw ArgumentError('hostStudentId must be set when creating an event');
    }

    final created = _copyEvent(
      event,
      status: event.status.isEmpty ? 'Pending' : event.status,
      submittedDate: DateTime.now().toString().split(' ')[0],
      messages: event.messages ?? const [],
    );
    pendingEvents.add(created);
    _addNotification('A new event has been submitted', 'public', source: 'events');
    _addNotification(
      'New event submission: ${created.title}',
      'private',
      detailText:
          'Event ${created.id} submitted by ${created.organizer}. Date: ${created.date}, Location: ${created.location}.',
      visibility: 'admin',
      source: 'events',
      relatedId: created.id,
      relatedScreen: 'admin-event-pending',
    );
    notifyListeners();
  }

  void approveEvent(String id) {
    final index = pendingEvents.indexWhere((e) => e.id == id);
    if (index == -1) return;
    final event = pendingEvents[index];

    final approved = _copyEvent(event, status: 'Published');
    allEvents.removeWhere((e) => e.id == event.id);
    allEvents.add(approved);
    pendingEvents.removeAt(index);

    _addNotification('An event has been approved', 'public', source: 'events');
    _addNotification(
      'Your event has been approved',
      'private',
      detailText: 'Event "${event.title}" is approved and published.',
      targetUserId: event.hostStudentId,
      source: 'events',
      relatedId: event.id,
      relatedScreen: 'event-detail',
    );
    notifyListeners();
  }

  void setEventUnderReview(String id) {
    final index = pendingEvents.indexWhere((e) => e.id == id);
    if (index == -1) return;
    final event = pendingEvents[index];
    pendingEvents[index] = _copyEvent(event, status: 'Under Review');

    _addNotification(
      'Your event is now under review',
      'private',
      detailText: 'Event "${event.title}" is currently being reviewed by admin.',
      targetUserId: event.hostStudentId,
      source: 'events',
      relatedId: event.id,
      relatedScreen: 'my-event-detail',
    );
    notifyListeners();
  }

  void requestEventRevision(String id, String revisionNotes) {
    final index = pendingEvents.indexWhere((e) => e.id == id);
    if (index == -1) return;
    final event = pendingEvents[index];
    pendingEvents[index] = _copyEvent(
      event,
      status: 'Needs Revision',
      revisionNotes: revisionNotes,
      rejectionReason: null,
    );

    _addNotification(
      'Your event needs changes',
      'private',
      detailText: revisionNotes,
      targetUserId: event.hostStudentId,
      source: 'events',
      relatedId: event.id,
      relatedScreen: 'my-event-detail',
    );
    notifyListeners();
  }

  void rejectEvent(String id, {String reason = ''}) {
    final index = pendingEvents.indexWhere((e) => e.id == id);
    if (index == -1) return;
    final event = pendingEvents[index];
    pendingEvents[index] = _copyEvent(
      event,
      status: 'Rejected',
      rejectionReason: reason.isEmpty ? 'Not specified' : reason,
    );

    _addNotification(
      'Your event has been rejected',
      'private',
      detailText: reason.isEmpty ? 'Please contact admin for details.' : reason,
      targetUserId: event.hostStudentId,
      source: 'events',
      relatedId: event.id,
      relatedScreen: 'my-event-detail',
    );
    notifyListeners();
  }

  bool resubmitEvent(String id, Event updatedEvent) {
    final index = pendingEvents.indexWhere((e) => e.id == id);
    if (index == -1) return false;
    final current = pendingEvents[index];
    pendingEvents[index] = _copyEvent(
      current,
      title: updatedEvent.title,
      date: updatedEvent.date,
      time: updatedEvent.time,
      location: updatedEvent.location,
      category: updatedEvent.category,
      organizer: updatedEvent.organizer,
      description: updatedEvent.description,
      status: 'Pending',
      approvalLetterPath: updatedEvent.approvalLetterPath ?? current.approvalLetterPath,
      approvalLetterName: updatedEvent.approvalLetterName ?? current.approvalLetterName,
      hasApprovalLetter: updatedEvent.hasApprovalLetter || current.hasApprovalLetter,
      rejectionReason: null,
      revisionNotes: null,
      revisionCount: current.revisionCount + 1,
      submittedDate: DateTime.now().toString().split(' ')[0],
    );
    _addNotification(
      'Event has been resubmitted',
      'private',
      detailText: 'Event "${current.title}" has been resubmitted and is pending review.',
      visibility: 'admin',
      source: 'events',
      relatedId: current.id,
      relatedScreen: 'admin-event-pending',
    );
    notifyListeners();
    return true;
  }

  bool updateEventDetails(String id, Event updatedEvent) {
    var index = pendingEvents.indexWhere((e) => e.id == id);
    if (index != -1) {
      final current = pendingEvents[index];
      pendingEvents[index] = _copyEvent(
        current,
        title: updatedEvent.title,
        date: updatedEvent.date,
        time: updatedEvent.time,
        location: updatedEvent.location,
        category: updatedEvent.category,
        organizer: updatedEvent.organizer,
        description: updatedEvent.description,
      );
      notifyListeners();
      return true;
    }
    index = allEvents.indexWhere((e) => e.id == id);
    if (index != -1) {
      final current = allEvents[index];
      allEvents[index] = _copyEvent(
        current,
        title: updatedEvent.title,
        date: updatedEvent.date,
        time: updatedEvent.time,
        location: updatedEvent.location,
        category: updatedEvent.category,
        organizer: updatedEvent.organizer,
        description: updatedEvent.description,
      );
      notifyListeners();
      return true;
    }
    return false;
  }

  void markEventCompleted(String id) {
    final index = allEvents.indexWhere((e) => e.id == id);
    if (index != -1) {
      final e = allEvents[index];
      allEvents[index] = _copyEvent(e, status: 'Completed');
      _addNotification(
        'Event "${e.title}" has been marked as completed.',
        'private',
        visibility: 'admin',
        source: 'events',
      );
      notifyListeners();
    }
  }

  void deleteEvent(String id) {
    final event = allEvents.firstWhere((e) => e.id == id, orElse: () =>
      const Event(id:'',title:'',date:'',time:'',location:'',category:'',organizer:'',description:'',status:''));
    allEvents.removeWhere((e) => e.id == id);
    pendingEvents.removeWhere((e) => e.id == id);
    if (event.title.isNotEmpty) {
      _addNotification(
        'Event "${event.title}" has been deleted.',
        'private',
        visibility: 'admin',
        source: 'events',
      );
    }
    notifyListeners();
  }

  // ── EVENT JOINING SYSTEM ────────────────────────────────────
  /// Request to join an event (for private/club events or paid events)
  EventJoining requestJoinEvent(String eventId, String studentId, String name, String courseName, {String? clubId}) {
    final joining = EventJoining(
      id: 'EJ-${DateTime.now().millisecondsSinceEpoch}',
      eventId: eventId,
      studentId: studentId,
      name: name,
      courseName: courseName,
      clubId: clubId,
      status: 'Pending',
      joinedDate: DateTime.now().toString().split(' ')[0],
    );
    eventJoiningRequests.add(joining);

    // Find the event and add to pending requests
    final eventIndex = allEvents.indexWhere((e) => e.id == eventId);
    if (eventIndex != -1) {
      final ev = allEvents[eventIndex];
      allEvents[eventIndex] = Event(
        id: ev.id, title: ev.title, date: ev.date, time: ev.time,
        location: ev.location, category: ev.category, organizer: ev.organizer,
        description: ev.description, status: ev.status, hostStudentId: ev.hostStudentId,
        approvalLetterPath: ev.approvalLetterPath, approvalLetterName: ev.approvalLetterName,
        hasApprovalLetter: ev.hasApprovalLetter, rejectionReason: ev.rejectionReason,
        revisionNotes: ev.revisionNotes, messages: ev.messages, revisionCount: ev.revisionCount,
        submittedDate: ev.submittedDate, isPrivate: ev.isPrivate, clubIdRequired: ev.clubIdRequired,
        isPaid: ev.isPaid, price: ev.price, attendeeIds: ev.attendeeIds,
        pendingJoiningIds: [...ev.pendingJoiningIds, joining.id], qrTicketPath: ev.qrTicketPath,
      );
    }

    _addNotification('New joining request for event', 'admin',
      detailText: 'Student $studentId ($name) requested to join an event.',
      source: 'events');
    notifyListeners();
    return joining;
  }

  /// Direct join for open (non-private) free events
  bool quickJoinEvent(String eventId, String studentId, String name, String courseName) {
    final event = allEvents.firstWhere((e) => e.id == eventId, orElse: () => const Event(
      id: '', title: '', date: '', time: '', location: '',
      category: '', organizer: '', description: '', status: ''
    ));

    if (event.id.isEmpty) return false;

    // Can only quick join if open and free
    if (event.isPrivate || event.isPaid) return false;

    // Generate QR code for free event
    final qrCode = _generateQRCode(eventId, studentId);

    // Create joining record
    final joining = EventJoining(
      id: 'EJ-${DateTime.now().millisecondsSinceEpoch}',
      eventId: eventId,
      studentId: studentId,
      name: name,
      courseName: courseName,
      status: 'Approved',
      paymentStatus: 'Completed',
      qrTicketCode: qrCode,
      joinedDate: DateTime.now().toString().split(' ')[0],
    );
    eventJoiningRequests.add(joining);

    // Add to attendees
    final eventIndex = allEvents.indexWhere((e) => e.id == eventId);
    if (eventIndex != -1) {
      final ev = allEvents[eventIndex];
      allEvents[eventIndex] = Event(
        id: ev.id, title: ev.title, date: ev.date, time: ev.time,
        location: ev.location, category: ev.category, organizer: ev.organizer,
        description: ev.description, status: ev.status, hostStudentId: ev.hostStudentId,
        approvalLetterPath: ev.approvalLetterPath, approvalLetterName: ev.approvalLetterName,
        hasApprovalLetter: ev.hasApprovalLetter, rejectionReason: ev.rejectionReason,
        revisionNotes: ev.revisionNotes, messages: ev.messages, revisionCount: ev.revisionCount,
        submittedDate: ev.submittedDate, isPrivate: ev.isPrivate, clubIdRequired: ev.clubIdRequired,
        isPaid: ev.isPaid, price: ev.price, attendeeIds: [...ev.attendeeIds, studentId],
        pendingJoiningIds: ev.pendingJoiningIds, qrTicketPath: ev.qrTicketPath,
      );
    }

    _addNotification('Successfully joined event "${event.title}"', 'private',
      targetUserId: studentId, detailText: 'Your QR ticket has been generated.',
      source: 'events');
    notifyListeners();
    return true;
  }

  /// Complete payment and generate QR code for paid events
  bool completePaymentAndJoin(String joiningId, double amountPaid) {
    final joinIndex = eventJoiningRequests.indexWhere((j) => j.id == joiningId);
    if (joinIndex == -1) return false;

    final joining = eventJoiningRequests[joinIndex];
    final event = allEvents.firstWhere((e) => e.id == joining.eventId, orElse: () => const Event(
      id: '', title: '', date: '', time: '', location: '',
      category: '', organizer: '', description: '', status: ''
    ));

    if (event.id.isEmpty || !event.isPaid || amountPaid < event.price) return false;

    // Generate QR code
    final qrCode = _generateQRCode(event.id, joining.studentId);

    // Update joining record
    eventJoiningRequests[joinIndex] = EventJoining(
      id: joining.id, eventId: joining.eventId, studentId: joining.studentId,
      name: joining.name, courseName: joining.courseName, clubId: joining.clubId,
      status: 'Approved', paymentStatus: 'Completed', qrTicketCode: qrCode,
      joinedDate: joining.joinedDate,
    );

    // Add to attendees
    final eventIndex = allEvents.indexWhere((e) => e.id == event.id);
    if (eventIndex != -1) {
      final ev = allEvents[eventIndex];
      allEvents[eventIndex] = Event(
        id: ev.id, title: ev.title, date: ev.date, time: ev.time,
        location: ev.location, category: ev.category, organizer: ev.organizer,
        description: ev.description, status: ev.status, hostStudentId: ev.hostStudentId,
        approvalLetterPath: ev.approvalLetterPath, approvalLetterName: ev.approvalLetterName,
        hasApprovalLetter: ev.hasApprovalLetter, rejectionReason: ev.rejectionReason,
        revisionNotes: ev.revisionNotes, messages: ev.messages, revisionCount: ev.revisionCount,
        submittedDate: ev.submittedDate, isPrivate: ev.isPrivate, clubIdRequired: ev.clubIdRequired,
        isPaid: ev.isPaid, price: ev.price, attendeeIds: [...ev.attendeeIds, joining.studentId],
        pendingJoiningIds: ev.pendingJoiningIds, qrTicketPath: ev.qrTicketPath,
      );
    }

    _addNotification('Payment successful! Your ticket is ready', 'private',
      targetUserId: joining.studentId, detailText: 'QR code has been generated for ${event.title}.',
      source: 'events');
    notifyListeners();
    return true;
  }

  /// Approve a joining request (for private events or requests)
  void approveEventJoining(String joiningId) {
    final joinIndex = eventJoiningRequests.indexWhere((j) => j.id == joiningId);
    if (joinIndex == -1) return;

    final joining = eventJoiningRequests[joinIndex];
    final event = allEvents.firstWhere((e) => e.id == joining.eventId, orElse: () => const Event(
      id: '', title: '', date: '', time: '', location: '',
      category: '', organizer: '', description: '', status: ''
    ));

    if (event.id.isEmpty) return;

    // Generate QR code for approved request
    final qrCode = _generateQRCode(event.id, joining.studentId);

    // Update joining status
    eventJoiningRequests[joinIndex] = EventJoining(
      id: joining.id, eventId: joining.eventId, studentId: joining.studentId,
      name: joining.name, courseName: joining.courseName, clubId: joining.clubId,
      status: 'Approved', paymentStatus: event.isPaid ? null : 'Completed',
      qrTicketCode: event.isPaid ? null : qrCode, joinedDate: joining.joinedDate,
    );

    // If free event, add to attendees
    if (!event.isPaid) {
      final eventIndex = allEvents.indexWhere((e) => e.id == event.id);
      if (eventIndex != -1) {
        final ev = allEvents[eventIndex];
        final updatedPending = List<String>.from(ev.pendingJoiningIds)..remove(joiningId);
        allEvents[eventIndex] = Event(
          id: ev.id, title: ev.title, date: ev.date, time: ev.time,
          location: ev.location, category: ev.category, organizer: ev.organizer,
          description: ev.description, status: ev.status, hostStudentId: ev.hostStudentId,
          approvalLetterPath: ev.approvalLetterPath, approvalLetterName: ev.approvalLetterName,
          hasApprovalLetter: ev.hasApprovalLetter, rejectionReason: ev.rejectionReason,
          revisionNotes: ev.revisionNotes, messages: ev.messages, revisionCount: ev.revisionCount,
          submittedDate: ev.submittedDate, isPrivate: ev.isPrivate, clubIdRequired: ev.clubIdRequired,
          isPaid: ev.isPaid, price: ev.price, attendeeIds: [...ev.attendeeIds, joining.studentId],
          pendingJoiningIds: updatedPending, qrTicketPath: ev.qrTicketPath,
        );
      }
    }

    _addNotification('Your joining request was approved!', 'private',
      targetUserId: joining.studentId, detailText: 'You have been approved to join "${event.title}".',
      source: 'events');
    notifyListeners();
  }

  /// Reject a joining request
  void rejectEventJoining(String joiningId, {String reason = ''}) {
    final joinIndex = eventJoiningRequests.indexWhere((j) => j.id == joiningId);
    if (joinIndex == -1) return;

    final joining = eventJoiningRequests[joinIndex];
    final event = allEvents.firstWhere((e) => e.id == joining.eventId, orElse: () => const Event(
      id: '', title: '', date: '', time: '', location: '',
      category: '', organizer: '', description: '', status: ''
    ));

    // Update joining status to rejected
    eventJoiningRequests[joinIndex] = EventJoining(
      id: joining.id, eventId: joining.eventId, studentId: joining.studentId,
      name: joining.name, courseName: joining.courseName, clubId: joining.clubId,
      status: 'Rejected', joinedDate: joining.joinedDate,
    );

    // Remove from pending
    final eventIndex = allEvents.indexWhere((e) => e.id == event.id);
    if (eventIndex != -1 && event.id.isNotEmpty) {
      final ev = allEvents[eventIndex];
      final updatedPending = List<String>.from(ev.pendingJoiningIds)..remove(joiningId);
      allEvents[eventIndex] = Event(
        id: ev.id, title: ev.title, date: ev.date, time: ev.time,
        location: ev.location, category: ev.category, organizer: ev.organizer,
        description: ev.description, status: ev.status, hostStudentId: ev.hostStudentId,
        approvalLetterPath: ev.approvalLetterPath, approvalLetterName: ev.approvalLetterName,
        hasApprovalLetter: ev.hasApprovalLetter, rejectionReason: ev.rejectionReason,
        revisionNotes: ev.revisionNotes, messages: ev.messages, revisionCount: ev.revisionCount,
        submittedDate: ev.submittedDate, isPrivate: ev.isPrivate, clubIdRequired: ev.clubIdRequired,
        isPaid: ev.isPaid, price: ev.price, attendeeIds: ev.attendeeIds,
        pendingJoiningIds: updatedPending, qrTicketPath: ev.qrTicketPath,
      );
    }

    _addNotification('Your joining request was rejected', 'private',
      targetUserId: joining.studentId, detailText: reason.isNotEmpty ? reason : 'Your request does not meet the requirements.',
      source: 'events');
    notifyListeners();
  }

  /// Generate QR code for event ticket
  String _generateQRCode(String eventId, String studentId) {
    return 'QR-$eventId-$studentId-${Random().nextInt(999999).toString().padLeft(6, '0')}';
  }

  /// Get ALL joining records for an event (for host management — includes Pending, Approved, Rejected)
  List<EventJoining> getJoiningRequestsForEvent(String eventId) {
    return eventJoiningRequests.where((j) => j.eventId == eventId).toList();
  }

  /// Get the approved joining record for a specific student in an event
  EventJoining? getJoiningRecord(String eventId, String studentId) {
    try {
      return eventJoiningRequests.firstWhere(
        (j) => j.eventId == eventId && j.studentId == studentId && j.status == 'Approved',
      );
    } catch (_) {
      return null;
    }
  }

  /// Get a joining record by its own ID (used to fetch updated record after payment)
  EventJoining? getJoiningById(String joiningId) {
    try {
      return eventJoiningRequests.firstWhere((j) => j.id == joiningId);
    } catch (_) {
      return null;
    }
  }

  // ── Event Role Management ────────────────────────────────────────

  /// Get all roles assigned for an event
  List<EventRole> getRolesForEvent(String eventId) =>
      eventRoles.where((r) => r.eventId == eventId).toList();

  /// Assign a role to a team member (replaces existing role for same student)
  void assignRole({
    required String eventId,
    required String studentId,
    required String studentName,
    required String role,
    required List<String> permissions,
  }) {
    eventRoles.removeWhere((r) => r.eventId == eventId && r.studentId == studentId);
    eventRoles.add(EventRole(
      id: 'ER-${DateTime.now().millisecondsSinceEpoch}',
      eventId: eventId,
      studentId: studentId,
      studentName: studentName,
      role: role,
      permissions: List.from(permissions),
    ));
    notifyListeners();
  }

  /// Remove a role by its ID
  void removeRole(String roleId) {
    eventRoles.removeWhere((r) => r.id == roleId);
    notifyListeners();
  }

  /// Check if a user can perform a specific action on an event
  bool canPerformAction(String eventId, String userId, String action) {
    final event = getEventById(eventId);
    if (event?.hostStudentId == userId) return true;
    try {
      final role = eventRoles.firstWhere(
        (r) => r.eventId == eventId && r.studentId == userId,
      );
      return role.permissions.contains(action);
    } catch (_) {
      return false;
    }
  }

  /// Get approved attendees for an event
  List<EventJoining> getEventAttendees(String eventId) {
    return eventJoiningRequests.where((j) => j.eventId == eventId && j.status == 'Approved').toList();
  }

  /// Verify QR code and mark participant as attended
  bool verifyAndMarkAttendance(String eventId, String qrCode) {
    final index = eventJoiningRequests.indexWhere(
      (j) => j.eventId == eventId && j.qrTicketCode == qrCode && j.status == 'Approved'
    );
    if (index != -1) {
      final j = eventJoiningRequests[index];
      if (j.hasAttended) return true; // Already attended
      
      eventJoiningRequests[index] = EventJoining(
        id: j.id, eventId: j.eventId, studentId: j.studentId,
        name: j.name, courseName: j.courseName, clubId: j.clubId,
        status: j.status, paymentStatus: j.paymentStatus, 
        qrTicketCode: j.qrTicketCode, joinedDate: j.joinedDate,
        hasAttended: true,
      );
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Manually toggle an attendee's check-in status
  void toggleManualAttendance(String joiningId) {
    final index = eventJoiningRequests.indexWhere((j) => j.id == joiningId);
    if (index != -1) {
      final j = eventJoiningRequests[index];
      eventJoiningRequests[index] = EventJoining(
        id: j.id, eventId: j.eventId, studentId: j.studentId,
        name: j.name, courseName: j.courseName, clubId: j.clubId,
        status: j.status, paymentStatus: j.paymentStatus, 
        qrTicketCode: j.qrTicketCode, joinedDate: j.joinedDate,
        hasAttended: !j.hasAttended,
      );
      notifyListeners();
    }
  }

  /// Get user's joined events
  List<EventJoining> getUserJoinedEvents(String studentId) {
    return eventJoiningRequests.where((j) => j.studentId == studentId && j.status == 'Approved').toList();
  }

  void updateEventStatus(String id, String newStatus) {
    final index = allEvents.indexWhere((e) => e.id == id);
    if (index != -1) {
      final e = allEvents[index];
      allEvents[index] = _copyEvent(e, status: newStatus);
      _addNotification(
        'Event "${e.title}" status changed to $newStatus.',
        'private',
        visibility: 'admin',
        source: 'events',
      );
      notifyListeners();
    }
  }

  void sendEventNotice(String id, String message) {
    final event = getEventById(id);
    if (event == null) return;
    _addNotification(
      'Notice for event "${event.title}"',
      'private',
      detailText: message,
      targetUserId: event.hostStudentId,
      source: 'events',
      relatedId: id,
      relatedScreen: 'my-event-detail',
    );
    notifyListeners();
  }

  void addEventMessage(
    String eventId,
    String senderId,
    String senderRole,
    String message,
  ) {
    final msg = EventMessage(
      id: 'EM-${DateTime.now().millisecondsSinceEpoch}',
      senderId: senderId,
      senderRole: senderRole,
      message: message,
      timestamp: DateTime.now().toString().split('.')[0],
    );

    var index = pendingEvents.indexWhere((e) => e.id == eventId);
    if (index != -1) {
      final event = pendingEvents[index];
      final messages = <EventMessage>[
        ...(event.messages ?? const <EventMessage>[]),
        msg,
      ];
      pendingEvents[index] = _copyEvent(event, messages: messages);

      if (senderRole == 'admin') {
        _addNotification(
          'Admin sent you a message about your event',
          'private',
          detailText: message,
          targetUserId: event.hostStudentId,
          source: 'events',
          relatedId: event.id,
          relatedScreen: 'my-event-detail',
        );
      } else {
        _addNotification(
          'Student replied about event ${event.id}',
          'private',
          detailText: message,
          visibility: 'admin',
          source: 'events',
          relatedId: event.id,
          relatedScreen: 'admin-event-pending',
        );
      }
      notifyListeners();
      return;
    }

    index = allEvents.indexWhere((e) => e.id == eventId);
    if (index == -1) return;
    final event = allEvents[index];
    allEvents[index] = _copyEvent(
      event,
      messages: <EventMessage>[
        ...(event.messages ?? const <EventMessage>[]),
        msg,
      ],
    );
    notifyListeners();
  }

  // ── QR CODE GENERATION ───────────────────────────────────────────────
  /// Generate QR ticket code for event joining
  String generateQRTicketCode(String eventId, String studentId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(9999);
    return 'QR-$eventId-$studentId-$timestamp-$random';
  }

  /// Get or generate QR code for an event joining
  String getOrGenerateQRCode(String joinId, String eventId, String studentId) {
    final joining = eventJoiningRequests.firstWhere(
      (j) => j.id == joinId,
      orElse: () => const EventJoining(
        id: '',
        eventId: '',
        studentId: '',
        name: '',
        courseName: '',
        joinedDate: '',
      ),
    );

    if (joining.id.isNotEmpty && joining.qrTicketCode != null && joining.qrTicketCode!.isNotEmpty) {
      return joining.qrTicketCode!;
    }

    return generateQRTicketCode(eventId, studentId);
  }

  // ── NOTIFICATIONS ───────────────────────────────────────────────
  void _addNotification(
    String message,
    String type, {
    String? detailText,
    String visibility = 'all',
    String? targetUserId,
    String? relatedScreen,
    String? relatedId,
    String source = 'system',
  }) {
    final newNotif = mockdata.Notification(
      id: 'N${notifications.length + 1}',
      type: type,
      visibility: visibility,
      text: message,
      detailText: detailText,
      time: DateTime.now().toString().split('.')[0],
      read: false,
      targetUserId: targetUserId,
      relatedScreen: relatedScreen,
      relatedId: relatedId,
      source: source,
    );
    notifications.insert(0, newNotif);
    notifyListeners();
  }

  void addNotification(String message, String type) {
    _addNotification(message, type);
  }

  // ── LOCKERS ──────────────────────────────────────────────────────
  void bookLocker(String lockerId, {int durationMonths = 6}) {
    final lockerIndex = lockers.indexWhere((l) => l.id == lockerId);
    if (lockerIndex == -1) return;

    // Check max 1 locker per student
    if (myBookings.any((b) => b.status == 'Active' || b.status == 'Pending Pickup')) {
      return; // Already has a locker
    }

    final lk = lockers[lockerIndex];
    final now = DateTime.now();
    final endDate = DateTime(now.year, now.month + durationMonths, now.day);
    final daysLeft = endDate.difference(now).inDays;
    // amountDueToday = deposit + totalRentalCost (matches LockerPricing)
    final deposit = lk.deposit;
    final monthlyRent = lk.monthlyRent;
    final totalPaid = deposit + (monthlyRent * durationMonths);

    // SECURITY: the digital-lock code is never stored on the locker record —
    // it belongs to the owner-scoped booking only.
    // Update locker status
    lockers[lockerIndex] = Locker(
      id: lk.id, location: lk.location, status: 'Pending Pickup',
      studentId: 'S001',
      startDate: now.toString().split(' ')[0],
      endDate: endDate.toString().split(' ')[0],
      daysLeft: daysLeft,
      lockType: lk.lockType,
      monthlyRent: monthlyRent,
      deposit: deposit,
    );

    // Create booking
    final booking = LockerBooking(
      id: 'BK-${DateTime.now().millisecondsSinceEpoch}',
      lockerId: lk.id,
      location: lk.location,
      startDate: now.toString().split(' ')[0],
      endDate: endDate.toString().split(' ')[0],
      status: 'Pending Pickup',
      daysLeft: daysLeft,
      durationMonths: durationMonths,
      monthlyRent: monthlyRent,
      deposit: deposit,
      totalPaid: totalPaid,
    );
    myBookings.add(booking);

    // Add history
    _addLockerHistory(lk.id, 'Booked by student', 'system', 'Student self-booking. Duration: $durationMonths months. Paid: RM${totalPaid.toStringAsFixed(0)}');
    _addNotification(
      'Locker ${lk.id} booked successfully',
      'private',
      detailText:
          'Duration: $durationMonths months. Total: RM${totalPaid.toStringAsFixed(0)} (RM$deposit deposit + RM${(monthlyRent * durationMonths).toStringAsFixed(0)} rental).',
      targetUserId: 'S001',
      source: 'lockers',
    );
    if (lk.lockType == 'key') {
      _addNotification(
        'Locker key pickup required',
        'private',
        detailText: 'Locker ${lk.id} is pending key collection. Generate collection QR when student visits.',
        visibility: 'admin',
        source: 'lockers',
      );
    }
    notifyListeners();
  }

  void releaseBooking(String bookingId) {
    requestLockerRelease(bookingId);
  }

  bool requestLockerExtension(String bookingId, int additionalMonths) {
    final index = myBookings.indexWhere((b) => b.id == bookingId);
    if (index == -1 || additionalMonths <= 0) return false;
    final b = myBookings[index];
    if (b.daysLeft > 30) return false;

    DateTime end;
    try {
      end = DateTime.parse(b.endDate);
    } catch (_) {
      return false;
    }
    final newEnd = DateTime(end.year, end.month + additionalMonths, end.day);
    final today = DateTime.now();
    final newDaysLeft = newEnd.difference(DateTime(today.year, today.month, today.day)).inDays;
    final additionalCost = b.monthlyRent * additionalMonths;

    myBookings[index] = LockerBooking(
      id: b.id,
      lockerId: b.lockerId,
      location: b.location,
      startDate: b.startDate,
      endDate: newEnd.toString().split(' ')[0],
      status: b.status,
      daysLeft: newDaysLeft,
      durationMonths: b.durationMonths + additionalMonths,
      monthlyRent: b.monthlyRent,
      deposit: b.deposit,
      totalPaid: b.totalPaid + additionalCost,
      keyCollectionQR: b.keyCollectionQR,
      keyCollected: b.keyCollected,
      keyCollectionDate: b.keyCollectionDate,
      keyReturnQR: b.keyReturnQR,
      keyReturned: b.keyReturned,
      keyReturnDate: b.keyReturnDate,
      releaseStatus: b.releaseStatus,
    );

    final lockerIndex = lockers.indexWhere((l) => l.id == b.lockerId);
    if (lockerIndex != -1) {
      final lk = lockers[lockerIndex];
      lockers[lockerIndex] = Locker(
        id: lk.id,
        location: lk.location,
        status: lk.status,
        studentId: lk.studentId,
        startDate: lk.startDate,
        endDate: newEnd.toString().split(' ')[0],
        daysLeft: newDaysLeft,
        lockType: lk.lockType,
        monthlyRent: lk.monthlyRent,
        deposit: lk.deposit,
        depositRefunded: lk.depositRefunded,
      );
    }

    _addLockerHistory(
      b.lockerId,
      'Rental extended',
      'system',
      'Extended by $additionalMonths month(s). Additional payment: RM${additionalCost.toStringAsFixed(0)}',
    );
    _addNotification(
      'Locker extension successful',
      'private',
      detailText:
          'Locker ${b.lockerId} extended by $additionalMonths month(s). New end date: ${newEnd.toString().split(' ')[0]}.',
      targetUserId: 'S001',
      source: 'lockers',
    );
    notifyListeners();
    return true;
  }

  void reportLockerIssue(String lockerId, String description, int photoCount) {
    final issue = LockerIssue(
      id: 'LI-${DateTime.now().millisecondsSinceEpoch}',
      lockerId: lockerId,
      studentId: 'S001',
      description: description,
      status: 'Reported',
      photoCount: photoCount,
      reportedDate: DateTime.now().toString().split('.')[0],
    );
    lockerIssues.insert(0, issue);

    _addLockerHistory(lockerId, 'Issue reported', 'system', description);
    _addNotification(
      'Locker issue reported',
      'private',
      detailText: 'Issue reported for locker $lockerId: $description',
      visibility: 'admin',
      source: 'lockers',
    );
    _addNotification(
      'Your locker issue has been submitted',
      'private',
      detailText:
          'Issue for locker $lockerId has been submitted. Admin will review it shortly.',
      targetUserId: 'S001',
      source: 'lockers',
    );
    notifyListeners();
  }

  // ── LOCKER ADMIN ACTIONS ─────────────────────────────────────────
  void updateLockerStatus(String lockerId, String newStatus) {
    final index = lockers.indexWhere((l) => l.id == lockerId);
    if (index == -1) return;
    final lk = lockers[index];

    lockers[index] = Locker(
      id: lk.id, location: lk.location, status: newStatus,
      studentId: newStatus == 'Available' || newStatus == 'Blocked' ? null : lk.studentId,
      startDate: lk.startDate,
      endDate: lk.endDate,
      daysLeft: lk.daysLeft,
      lockType: lk.lockType,
      monthlyRent: lk.monthlyRent,
      deposit: lk.deposit,
      depositRefunded: lk.depositRefunded,
    );

    _addLockerHistory(lockerId, 'Status changed to $newStatus', 'ADMIN', 'Admin updated locker status');
    _addNotification(
      'Locker $lockerId status updated to $newStatus.',
      'private',
      visibility: 'admin',
      source: 'lockers',
    );
    notifyListeners();
  }

  void terminateLocker(String lockerId) {
    final index = lockers.indexWhere((l) => l.id == lockerId);
    if (index == -1) return;
    final lk = lockers[index];

    // Remove booking if exists
    myBookings.removeWhere((b) => b.lockerId == lockerId);

    lockers[index] = Locker(
      id: lk.id, location: lk.location, status: 'Available',
      lockType: lk.lockType,
    );

    _addLockerHistory(lockerId, 'Agreement terminated', 'ADMIN', 'Admin terminated locker agreement. Deposit forfeited.');
    if (lk.studentId != null) {
      _addNotification(
        'Your locker $lockerId agreement has been terminated by admin. Deposit forfeited.',
        'private',
        targetUserId: 'S001',
        source: 'lockers',
      );
    }
    _addNotification(
      'Locker $lockerId terminated.',
      'private',
      visibility: 'admin',
      source: 'lockers',
    );
    notifyListeners();
  }

  void blockLocker(String lockerId, {String? reason}) {
    final index = lockers.indexWhere((l) => l.id == lockerId);
    if (index == -1) return;
    final lk = lockers[index];

    // Remove booking if exists
    myBookings.removeWhere((b) => b.lockerId == lockerId);

    lockers[index] = Locker(
      id: lk.id, location: lk.location, status: 'Blocked',
      lockType: lk.lockType,
    );

    _addLockerHistory(lockerId, 'Locker blocked', 'ADMIN', reason ?? 'Admin blocked locker');
    _addNotification(
      'Locker $lockerId has been blocked.',
      'private',
      visibility: 'admin',
      source: 'lockers',
    );
    notifyListeners();
  }

  void releaseLockerAdmin(String lockerId) {
    final index = lockers.indexWhere((l) => l.id == lockerId);
    if (index == -1) return;
    final lk = lockers[index];

    // Remove booking if exists
    myBookings.removeWhere((b) => b.lockerId == lockerId);

    lockers[index] = Locker(
      id: lk.id, location: lk.location, status: 'Available',
      lockType: lk.lockType,
    );

    _addLockerHistory(lockerId, 'Locker released', 'ADMIN', 'Admin released locker. Made available.');
    _addNotification(
      'Locker $lockerId has been released and is now available.',
      'private',
      visibility: 'admin',
      source: 'lockers',
    );
    notifyListeners();
  }

  void sendLockerNotice(String lockerId, String message) {
    final lk = lockers.firstWhere((l) => l.id == lockerId, orElse: () =>
      const Locker(id: '', location: '', status: ''));
    if (lk.studentId != null) {
      _addNotification(
        'Notice for locker $lockerId',
        'private',
        detailText: message,
        targetUserId: 'S001',
        source: 'lockers',
      );
      _addLockerHistory(lockerId, 'Notice sent to student', 'ADMIN', message);
      notifyListeners();
    }
  }

  void _addLockerHistory(String lockerId, String action, String staffId, String? reason) {
    final list = lockerHistory[lockerId] ?? [];
    list.add(LockerHistory(
      action: action,
      staffId: staffId,
      timestamp: DateTime.now().toString().split('.')[0],
      reason: reason,
    ));
    lockerHistory[lockerId] = list;
  }

  // ── LOCKER QR CODE SYSTEM ────────────────────────────────────────
  // Admin generates QR for key collection
  String generateLockerCollectionQR(String bookingId) {
    return generateKeyCollectionQR(bookingId);
  }

  String generateKeyCollectionQR(String bookingId) {
    final code =
        'KEY-COL-$bookingId-${Random().nextInt(999999).toString().padLeft(6, '0')}';
    final index = myBookings.indexWhere((b) => b.id == bookingId);
    if (index == -1) return code;
    final b = myBookings[index];

    myBookings[index] = LockerBooking(
      id: b.id,
      lockerId: b.lockerId,
      location: b.location,
      startDate: b.startDate,
      endDate: b.endDate,
      status: b.status,
      daysLeft: b.daysLeft,
      durationMonths: b.durationMonths,
      monthlyRent: b.monthlyRent,
      deposit: b.deposit,
      totalPaid: b.totalPaid,
      keyCollectionQR: code,
      keyCollected: b.keyCollected,
      keyCollectionDate: b.keyCollectionDate,
      keyReturnQR: b.keyReturnQR,
      keyReturned: b.keyReturned,
      keyReturnDate: b.keyReturnDate,
      releaseStatus: b.releaseStatus,
    );
    _addLockerHistory(
      b.lockerId,
      'Key collection QR generated',
      'ADMIN',
      'QR code ready for student to scan',
    );
    _addNotification(
      'Key collection QR is ready',
      'private',
      detailText:
          'Please scan the QR code at admin office to collect key for locker ${b.lockerId}.',
      targetUserId: lockers
          .firstWhere(
            (l) => l.id == b.lockerId,
            orElse: () => const Locker(id: '', location: '', status: ''),
          )
          .studentId ??
          'S001',
      source: 'lockers',
    );
    notifyListeners();
    return code;
  }

  // Student scans QR to collect keys
  bool scanLockerCollectionQR(String bookingId, String qrCode) {
    return scanKeyCollectionQR(bookingId, qrCode);
  }

  bool scanKeyCollectionQR(String bookingId, String qrCode) {
    final index = myBookings.indexWhere((b) => b.id == bookingId);
    if (index == -1) return false;
    final b = myBookings[index];
    if (b.keyCollectionQR != qrCode || b.keyCollected) return false;

    myBookings[index] = LockerBooking(
      id: b.id,
      lockerId: b.lockerId,
      location: b.location,
      startDate: b.startDate,
      endDate: b.endDate,
      status: 'Active',
      daysLeft: b.daysLeft,
      durationMonths: b.durationMonths,
      monthlyRent: b.monthlyRent,
      deposit: b.deposit,
      totalPaid: b.totalPaid,
      keyCollectionQR: b.keyCollectionQR,
      keyCollected: true,
      keyCollectionDate: DateTime.now().toString().split('.')[0],
      keyReturnQR: b.keyReturnQR,
      keyReturned: b.keyReturned,
      keyReturnDate: b.keyReturnDate,
      releaseStatus: b.releaseStatus,
    );

    final lockerIndex = lockers.indexWhere((l) => l.id == b.lockerId);
    if (lockerIndex != -1) {
      final lk = lockers[lockerIndex];
      lockers[lockerIndex] = Locker(
        id: lk.id,
        location: lk.location,
        status: 'Active',
        studentId: lk.studentId,
        startDate: lk.startDate,
        endDate: lk.endDate,
        daysLeft: lk.daysLeft,
        lockType: lk.lockType,
        monthlyRent: lk.monthlyRent,
        deposit: lk.deposit,
        depositRefunded: lk.depositRefunded,
      );
    }
    _addLockerHistory(
      b.lockerId,
      'Key collected - QR verified',
      'system',
      'Student scanned QR and collected key',
    );
    _addNotification(
      'Key collection confirmed',
      'private',
      detailText: 'You have collected the key for locker ${b.lockerId}.',
      targetUserId: lockers
          .firstWhere(
            (l) => l.id == b.lockerId,
            orElse: () => const Locker(id: '', location: '', status: ''),
          )
          .studentId ??
          'S001',
      source: 'lockers',
    );
    notifyListeners();
    return true;
  }

  // Admin generates QR for key return
  String generateLockerReturnQR(String bookingId) {
    return generateKeyReturnQR(bookingId);
  }

  String generateKeyReturnQR(String bookingId) {
    final code =
        'KEY-RET-$bookingId-${Random().nextInt(999999).toString().padLeft(6, '0')}';
    final index = myBookings.indexWhere((b) => b.id == bookingId);
    if (index == -1) return code;
    final b = myBookings[index];
    if (b.releaseStatus != 'Requested') {
      return b.keyReturnQR ?? code;
    }
    myBookings[index] = LockerBooking(
      id: b.id,
      lockerId: b.lockerId,
      location: b.location,
      startDate: b.startDate,
      endDate: b.endDate,
      status: b.status,
      daysLeft: b.daysLeft,
      durationMonths: b.durationMonths,
      monthlyRent: b.monthlyRent,
      deposit: b.deposit,
      totalPaid: b.totalPaid,
      keyCollectionQR: b.keyCollectionQR,
      keyCollected: b.keyCollected,
      keyCollectionDate: b.keyCollectionDate,
      keyReturnQR: code,
      keyReturned: false,
      keyReturnDate: b.keyReturnDate,
      releaseStatus: 'Pending Return',
    );
    _addLockerHistory(
      b.lockerId,
      'Key return QR generated',
      'ADMIN',
      'QR code ready for student to scan',
    );
    _addNotification(
      'Return QR code is ready',
      'private',
      detailText:
          'Please scan the QR code at admin office to confirm key return for locker ${b.lockerId}.',
      targetUserId: lockers
          .firstWhere(
            (l) => l.id == b.lockerId,
            orElse: () => const Locker(id: '', location: '', status: ''),
          )
          .studentId ??
          'S001',
      source: 'lockers',
    );
    notifyListeners();
    return code;
  }

  // Student scans QR to return keys
  bool scanLockerReturnQR(String bookingId, String qrCode) {
    return scanKeyReturnQR(bookingId, qrCode);
  }

  bool scanKeyReturnQR(String bookingId, String qrCode) {
    final index = myBookings.indexWhere((b) => b.id == bookingId);
    if (index == -1) return false;
    final b = myBookings[index];
    if (b.releaseStatus != 'Pending Return') return false;
    if (b.keyReturnQR != qrCode || b.keyReturned) return false;

    myBookings[index] = LockerBooking(
      id: b.id,
      lockerId: b.lockerId,
      location: b.location,
      startDate: b.startDate,
      endDate: b.endDate,
      status: b.status,
      daysLeft: b.daysLeft,
      durationMonths: b.durationMonths,
      monthlyRent: b.monthlyRent,
      deposit: b.deposit,
      totalPaid: b.totalPaid,
      keyCollectionQR: b.keyCollectionQR,
      keyCollected: b.keyCollected,
      keyCollectionDate: b.keyCollectionDate,
      keyReturnQR: b.keyReturnQR,
      keyReturned: true,
      keyReturnDate: DateTime.now().toString().split('.')[0],
      releaseStatus: 'Returned',
    );

    _addLockerHistory(
      b.lockerId,
      'Key returned - QR verified',
      'system',
      'Student scanned return QR and returned key',
    );
    _addNotification(
      'Key returned successfully',
      'private',
      detailText: 'Key returned for locker ${b.lockerId}. Awaiting admin approval.',
      targetUserId: lockers
          .firstWhere(
            (l) => l.id == b.lockerId,
            orElse: () => const Locker(id: '', location: '', status: ''),
          )
          .studentId ??
          'S001',
      source: 'lockers',
    );
    _addNotification(
      'Key returned for locker ${b.lockerId}',
      'private',
      detailText: 'Student completed return QR. Approve release to finish process.',
      visibility: 'admin',
      source: 'lockers',
    );
    notifyListeners();
    return true;
  }

  // ── STUDENT REGISTRATION ─────────────────────────────────────────
  void requestLockerRelease(String bookingId) {
    final index = myBookings.indexWhere((b) => b.id == bookingId);
    if (index == -1) return;
    final b = myBookings[index];
    if (b.releaseStatus != null && b.releaseStatus != 'Completed') return;

    final locker = lockers.firstWhere(
      (l) => l.id == b.lockerId,
      orElse: () => const Locker(id: '', location: '', status: ''),
    );
    final studentTarget = locker.studentId ?? 'S001';

    myBookings[index] = LockerBooking(
      id: b.id,
      lockerId: b.lockerId,
      location: b.location,
      startDate: b.startDate,
      endDate: b.endDate,
      status: 'Release Requested',
      daysLeft: b.daysLeft,
      durationMonths: b.durationMonths,
      monthlyRent: b.monthlyRent,
      deposit: b.deposit,
      totalPaid: b.totalPaid,
      keyCollectionQR: b.keyCollectionQR,
      keyCollected: b.keyCollected,
      keyCollectionDate: b.keyCollectionDate,
      keyReturnQR: b.keyReturnQR,
      keyReturned: b.keyReturned,
      keyReturnDate: b.keyReturnDate,
      releaseStatus: 'Requested',
    );

    _addLockerHistory(
      b.lockerId,
      'Release requested',
      'system',
      'Student requested locker release',
    );
    _addNotification(
      'Locker release requested',
      'private',
      detailText:
          'Student requested release for locker ${b.lockerId}. Generate return QR when they visit.',
      visibility: 'admin',
      source: 'lockers',
    );
    _addNotification(
      'Release request submitted',
      'private',
      detailText:
          'Your request to release locker ${b.lockerId} has been submitted. Please return your key at admin office.',
      targetUserId: studentTarget,
      source: 'lockers',
    );
    notifyListeners();
  }

  void approveLockerRelease(String bookingId) {
    final index = myBookings.indexWhere((b) => b.id == bookingId);
    if (index == -1) return;
    final b = myBookings[index];

    final lockerIndex = lockers.indexWhere((l) => l.id == b.lockerId);
    if (lockerIndex == -1) return;
    final locker = lockers[lockerIndex];
    final requiresKeyReturn = locker.lockType == 'key';
    if (requiresKeyReturn && (b.releaseStatus != 'Returned' || !b.keyReturned)) return;
    if (!requiresKeyReturn && b.releaseStatus != 'Requested' && b.releaseStatus != 'Returned') return;

    final studentTarget =
        lockers[lockerIndex].studentId ?? 'S001';
    lockers[lockerIndex] = Locker(
      id: locker.id,
      location: locker.location,
      status: 'Available',
      lockType: locker.lockType,
      depositRefunded: true,
    );

    myBookings.removeAt(index);
    _addLockerHistory(
      b.lockerId,
      'Locker released - Admin approved',
      'ADMIN',
      'Release approved. Deposit: RM${b.deposit.toStringAsFixed(0)} refunded.',
    );
    _addNotification(
      'Locker release completed',
      'private',
      detailText:
          'Your locker ${b.lockerId} has been released. Deposit of RM${b.deposit.toStringAsFixed(0)} will be refunded.',
      targetUserId: studentTarget,
      source: 'lockers',
    );
    _addNotification(
      'Locker ${b.lockerId} release approved',
      'private',
      detailText: 'Release finalized after key return verification. Locker is now available.',
      visibility: 'admin',
      source: 'lockers',
    );
    notifyListeners();
  }

  /// Raises the admin notification for a new sign-up. The registration record
  /// itself lives in Firestore (`users`), not here — this only restores the
  /// in-app badge that the mock flow used to produce.
  void notifyNewRegistration(String name, String studentId) {
    _addNotification('New student registration: $name ($studentId)', 'admin');
    notifyListeners();
  }

  // ── SMART MATCHING ENGINE: Auto-match found items with lost reports ──
  void _checkForMatches(FoundReport foundReport) {
    for (int i = 0; i < myLostReports.length; i++) {
      final lost = myLostReports[i];
      if (lost.status != 'Active') continue;

      int score = 0;

      // Category match (40 points)
      if (lost.category.toLowerCase() == foundReport.category.toLowerCase()) {
        score += 40;
      }

      // Location proximity (30 points)
      if (_isLocationNearby(lost.whereLost, foundReport.whereFound)) {
        score += 30;
      }

      // Keyword overlap (30 points)
      final lostWords = _extractKeywords(lost.description);
      final foundWords = _extractKeywords(foundReport.description);
      final overlap = lostWords.intersection(foundWords);
      if (overlap.isNotEmpty) {
        score += (30 * overlap.length / lostWords.length).round().clamp(0, 30);
      }

      if (score >= 40) {
        // Create match record
        final match = LfMatch(
          id: 'M-${matches.length + 1}',
          lostId: lost.id,
          foundId: foundReport.id,
          score: score,
          status: 'Pending',
          notes: 'Auto-matched: ${lost.category} found in ${foundReport.whereFound}',
        );
        matches.add(match);

        // Update lost report matchStatus
        myLostReports[i] = LostReport(
          id: lost.id, title: lost.title, category: lost.category,
          whereLost: lost.whereLost, whenLost: lost.whenLost,
          status: lost.status, description: lost.description,
          photos: lost.photos,
          matchStatus: 'A possible match has been found! Score: $score%',
        );

        // Private notification to student (lost item reporter)
        _addNotification(
          'Your lost item may have been found!',
          'private',
          detailText: 'A ${foundReport.category} matching your report ${lost.id} was found in ${foundReport.whereFound}. Match confidence: $score%. Please check your report or visit the Lost & Found office.',
          targetUserId: 'S001', // In production, use the actual reporter's student ID
          relatedScreen: 'lost-detail',
          relatedId: lost.id,
          source: 'lost_found',
        );

        // Private notification to admin
        _addNotification(
          'Smart match found: ${lost.id} <-> ${foundReport.id}',
          'private',
          detailText: 'Category: ${lost.category}, Score: $score%. Review the match in admin panel.',
          visibility: 'admin',
          relatedScreen: 'match-detail',
          relatedId: match.id,
          source: 'lost_found',
        );
      }
    }
  }

  bool _isLocationNearby(String loc1, String loc2) {
    final block1 = loc1.split(',').first.trim().toLowerCase();
    final block2 = loc2.split(',').first.trim().toLowerCase();
    return block1 == block2;
  }

  Set<String> _extractKeywords(String text) {
    final stopWords = {'the','a','an','is','was','in','on','at','to','for','of','and','with','has','my'};
    return text.toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
      .split(RegExp(r'\s+'))
      .where((w) => w.length > 2 && !stopWords.contains(w))
      .toSet();
  }

  // ── HANDOVER STEP TRACKING ──
  void updateHandoverStep(String foundReportId, int step) {
    final index = myFoundReports.indexWhere((r) => r.id == foundReportId);
    if (index != -1) {
      final r = myFoundReports[index];
      myFoundReports[index] = FoundReport(
        id: r.id, description: r.description, category: r.category,
        whereFound: r.whereFound, whenFound: r.whenFound,
        status: r.status, photos: r.photos,
        handoverStatus: r.handoverStatus, qrCode: r.qrCode, qrScanned: r.qrScanned,
        handoverStep: step,
      );
      notifyListeners();
    }
  }
}
