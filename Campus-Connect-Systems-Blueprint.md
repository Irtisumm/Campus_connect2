# Campus Connect - Systems Improvement Blueprint v4.0
## Notification, Event Management & Locker Management Overhaul
### Based on Detailed Feature Requirements

---

## TABLE OF CONTENTS

1. [Summary of System Changes](#1-summary-of-system-changes)
2. [System 1: Notification System Overhaul](#2-system-1-notification-system-overhaul)
3. [System 2: Event Management System Improvements](#3-system-2-event-management-system-improvements)
4. [System 3: Locker Management System - QR Key Collection & Release](#4-system-3-locker-management-system---qr-key-collection--release)
5. [Data Model Changes](#5-data-model-changes)
6. [File-by-File Change Map](#6-file-by-file-change-map)
7. [New Files Required](#7-new-files-required)
8. [Route Changes](#8-route-changes)
9. [Priority & Implementation Order](#9-priority--implementation-order)
10. [Visual Reference Designs](#10-visual-reference-designs)

---

## 1. SUMMARY OF SYSTEM CHANGES

| # | System | Change | Complexity | Priority |
|---|--------|--------|------------|----------|
| 1A | Notifications | Public vs Private notification types with privacy protection | Medium | P0 - Critical |
| 1B | Notifications | Smart matching engine sends auto-notifications on match | High | P0 - Critical |
| 1C | Notifications | Mark as read, filter, notification preferences | Medium | P1 - Important |
| 2A | Events | 10-day advance submission rule enforcement | Low | P0 - Critical |
| 2B | Events | PDF approval letter upload requirement | Medium | P0 - Critical |
| 2C | Events | Multi-stage status workflow (Pending -> Under Review -> Approved/Rejected/Needs Revision) | Medium | P0 - Critical |
| 2D | Events | Admin-to-student communication (request docs, clarification) | Medium | P1 - Important |
| 2E | Events | Re-submit after rejection without starting over | Medium | P1 - Important |
| 3A | Lockers | QR code verification for key collection | High | P0 - Critical |
| 3B | Lockers | Extension only when remaining time <= 1 month | Low | P1 - Important |
| 3C | Lockers | Issue reporting with photo upload | Medium | P1 - Important |
| 3D | Lockers | QR code verification for key return / locker release | High | P0 - Critical |
| 3E | Lockers | Multi-step release flow with admin approval | Medium | P0 - Critical |

---

## 2. SYSTEM 1: NOTIFICATION SYSTEM OVERHAUL

### 2.1 Current State Analysis

**Current Files:**
- **Model:** `lib/data/mock_data.dart` - `Notification` class with fields: `id`, `type`, `text`, `time`, `read`, `relatedScreen`, `relatedId`
- **Service:** `lib/services/data_service.dart` - `_addNotification(message, type)` method, types: `personal`, `admin`, `campaign`, `generic`
- **UI:** `lib/screens/lost_found/lost_found_screens.dart` - `NotificationsScreen` (Line ~377-418)
- **Badge:** `lib/main.dart` - Notification bell with unread count in AppShell header (Line ~116-130)

**Current Problems:**
1. Public notifications expose sensitive details (item titles, descriptions)
2. No distinction between public and private notification content
3. No smart matching engine - matches are static mock data
4. No notification filtering or preference controls
5. All notifications visible to all users regardless of relevance

---

### 2.2 Change A: Public vs Private Notifications

#### Concept
- **Public Notifications:** Visible to ALL users. Show only a short, generic title. No sensitive details.
  - Example: "A lost item has been reported" (NOT "A lost Blue Samsung Galaxy S23 was reported")
  - Example: "A new event has been submitted"
  - Example: "A found item has been reported"
- **Private Notifications:** Sent to SPECIFIC users. Include detailed, actionable information.
  - Example (to reporter): "Your lost item LR-001 may have been found! A matching Phone was located in Block A."
  - Example (to admin): "A new lost report LR-007 requires review. Category: Phone, Location: Block A."

#### Changes Required

##### File: `lib/data/mock_data.dart`

**A) Update `Notification` model:**
```dart
class Notification {
  final String id;
  final String type;           // 'public', 'private'
  final String visibility;     // 'all', 'student', 'admin'
  final String text;           // Short title for public, detailed for private
  final String? detailText;    // Additional detail (only shown for private)
  final String time;
  final bool read;
  final String? relatedScreen;
  final String? relatedId;
  final String? targetUserId;  // Specific user for private notifications
  final String source;         // 'lost_found', 'events', 'lockers', 'issues', 'system'

  const Notification({
    required this.id,
    required this.type,
    this.visibility = 'all',
    required this.text,
    this.detailText,
    required this.time,
    this.read = false,
    this.relatedScreen,
    this.relatedId,
    this.targetUserId,
    this.source = 'system',
  });
}
```

**B) Update mock notification data to use new format:**
```dart
static const List<Notification> notifications = [
  Notification(
    id: 'N-001',
    type: 'private',
    visibility: 'student',
    text: 'Your lost item may have been found!',
    detailText: 'A matching Phone was found in Block A Corridor. Please visit the Lost & Found office.',
    time: '2 hours ago',
    relatedScreen: 'lost-detail',
    relatedId: 'LR-001',
    targetUserId: 'S220101',
    source: 'lost_found',
    read: false,
  ),
  Notification(
    id: 'N-002',
    type: 'public',
    visibility: 'all',
    text: 'A lost item has been reported',
    time: '5 hours ago',
    source: 'lost_found',
    read: true,
  ),
  Notification(
    id: 'N-003',
    type: 'private',
    visibility: 'student',
    text: 'Your lost report has been updated',
    detailText: 'Report LR-002 status changed to Matched - Pending.',
    time: 'Yesterday',
    relatedScreen: 'lost-detail',
    relatedId: 'LR-002',
    targetUserId: 'S220045',
    source: 'lost_found',
    read: true,
  ),
  Notification(
    id: 'N-004',
    type: 'public',
    visibility: 'all',
    text: 'A found item has been reported',
    time: '2 days ago',
    source: 'lost_found',
    read: true,
  ),
];
```

##### File: `lib/services/data_service.dart`

**C) Overhaul `_addNotification()` method (Line ~363-373):**
```dart
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
```

**D) Update ALL existing `_addNotification()` calls to use new public/private pattern:**

| Location | Current Message | New Public Message | Private Notification Added |
|----------|----------------|--------------------|---------------------------|
| `addLostReport()` Line ~56-59 | `'A new lost item was reported: ${report.title}'` | `'A lost item has been reported'` (type: 'public', source: 'lost_found') | YES - Send private to admin: `'New lost report ${report.id}: ${report.title} - ${report.category}, ${report.whereLost}'` |
| `addFoundReport()` Line ~64-68 | `'A found item was reported: ${report.description}'` | `'A found item has been reported'` (type: 'public', source: 'lost_found') | YES - Send private to admin with details |
| `reportIssue()` Line ~216-219 | `'A new issue was reported: ${issue.title}'` | `'A new campus issue has been reported'` (type: 'public', source: 'issues') | YES - Send private to admin with full details |
| `createEvent()` Line ~269-272 | `'A new event waiting for approval: ${event.title}'` | `'A new event has been submitted'` (type: 'public', source: 'events') | YES - Send private to admin with event title |
| `approveEvent()` Line ~293 | `'Event approved: ${event.title}'` | `'An event has been approved'` (type: 'public', source: 'events') | YES - Send private to event creator with details |
| `rejectEvent()` Line ~305 | `'Event rejected: ${event.title}'` | No public notification | YES - Send private ONLY to event creator |
| Status updates (all) | Various | Keep as private only | Already private, add `targetUserId` |

**E) Add notification filtering methods:**
```dart
// Get notifications visible to current user
List<mockdata.Notification> getNotificationsForUser(String? userId, bool isAdmin) {
  return notifications.where((n) {
    // Public notifications visible to all
    if (n.type == 'public') return true;
    // Private notifications: check target user or admin visibility
    if (n.type == 'private') {
      if (n.targetUserId != null && n.targetUserId == userId) return true;
      if (n.visibility == 'admin' && isAdmin) return true;
      if (n.visibility == 'all') return true;
    }
    return false;
  }).toList();
}

int getUnreadCountForUser(String? userId, bool isAdmin) {
  return getNotificationsForUser(userId, isAdmin).where((n) => !n.read).length;
}
```

##### File: `lib/screens/lost_found/lost_found_screens.dart`

**F) Modify `NotificationsScreen` (Line ~377-418):**
- Add filter tabs at the top: "All" | "Lost & Found" | "Events" | "Lockers" | "Issues"
- Use `getNotificationsForUser()` instead of raw `notifications` list
- For public notifications: show only `text` field (generic title)
- For private notifications: show `text` + expandable `detailText`
- Add different icon per `source`: lost_found = search, events = calendar, lockers = lock, issues = warning
- Add "Mark All as Read" button in AppBar actions

**G) Update notification list item UI:**
```
Design Spec for Notification Card:
- Public: Grey icon circle, text only, no expand
- Private: Red icon circle, text + detail expandable, tap to navigate
- Unread: Red dot indicator + slightly tinted background
- Source icon: Changes based on notification.source
- Filter chips: Horizontal scroll, one active at a time
```

##### File: `lib/main.dart`

**H) Modify notification badge count (Line ~116-130):**
- Use `getUnreadCountForUser(appState.userId, appState.isAdmin)` instead of `dataService.unreadNotificationCount`
- Requires accessing both `AppState` and `DataService` consumers

---

### 2.3 Change B: Smart Matching Engine

#### Concept
When a found item is reported, the system automatically scans all active lost reports and compares:
1. **Category match** (exact match, e.g. Phone == Phone)
2. **Location proximity** (same block or nearby block)
3. **Keyword overlap** (words from description)

If a match is found, it automatically:
- Creates an `LfMatch` record
- Sends a **private notification** to the lost item reporter
- Sends a **private notification** to admin
- Updates the lost report's `matchStatus`

#### Changes Required

##### File: `lib/services/data_service.dart`

**A) Add new method `_runSmartMatch()` after `addFoundReport()`:**
```dart
void _runSmartMatch(FoundReport foundReport) {
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

      // Private notification to student
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
```

**B) Modify `addFoundReport()` to call `_runSmartMatch()`:**
```dart
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
  // Run smart matching
  _runSmartMatch(report);
  notifyListeners();
}
```

---

### 2.4 Change C: Notification Preferences & Controls

#### Changes Required

##### File: `lib/services/data_service.dart`

**A) Add notification preference state:**
```dart
// Notification preferences
Map<String, bool> _notifPreferences = {
  'lost_found': true,
  'events': true,
  'lockers': true,
  'issues': true,
};

void toggleNotifPreference(String source) {
  _notifPreferences[source] = !(_notifPreferences[source] ?? true);
  notifyListeners();
}

bool getNotifPreference(String source) => _notifPreferences[source] ?? true;

void markAllNotificationsAsRead() {
  for (int i = 0; i < notifications.length; i++) {
    if (!notifications[i].read) {
      notifications[i] = mockdata.Notification(
        id: notifications[i].id,
        type: notifications[i].type,
        visibility: notifications[i].visibility,
        text: notifications[i].text,
        detailText: notifications[i].detailText,
        time: notifications[i].time,
        read: true,
        targetUserId: notifications[i].targetUserId,
        relatedScreen: notifications[i].relatedScreen,
        relatedId: notifications[i].relatedId,
        source: notifications[i].source,
      );
    }
  }
  notifyListeners();
}
```

##### File: `lib/screens/lost_found/lost_found_screens.dart`

**B) Add notification settings dialog accessible from NotificationsScreen AppBar:**
- Gear icon in AppBar -> opens bottom sheet with toggle switches
- Toggle per source: Lost & Found, Events, Lockers, Issues
- Filtered list respects these preferences

---

## 3. SYSTEM 2: EVENT MANAGEMENT SYSTEM IMPROVEMENTS

### 3.1 Current State Analysis

**Current Files:**
- **Model:** `lib/data/mock_data.dart` - `Event` class with fields: `id`, `title`, `date`, `time`, `location`, `category`, `organizer`, `description`, `status`, `hostStudentId`
- **Service:** `lib/services/data_service.dart` - `createEvent()`, `approveEvent()`, `rejectEvent()`, `markEventCompleted()`, `deleteEvent()`, `updateEventStatus()`, `sendEventNotice()`
- **Student UI:** `lib/screens/events/events_screens.dart` - `EventsHubScreen`, `EventDetailScreen`, `CreateEventScreen`, `ElectionsInfoScreen`
- **Admin UI:** `lib/screens/events/events_screens.dart` - `AdminEventsListScreen`, `AdminEventEditorScreen`, `AdminElectionsMgmtScreen`

**Current Problems:**
1. No date validation - events can be submitted any time
2. No PDF upload requirement for approval letters
3. Status workflow is too simple (Pending -> Approved/Rejected only)
4. No admin-to-student messaging/communication channel
5. Rejected events are deleted, not kept for resubmission
6. Notifications expose event titles publicly

---

### 3.2 Change A: 10-Day Advance Submission Rule

#### Concept
Students must submit events at least 10 days before the event date. The system validates this during form submission.

#### Changes Required

##### File: `lib/screens/events/events_screens.dart`

**A) Modify `CreateEventScreen` (Line ~647-737):**

1. **Replace text-based date input with `DatePicker`:**
   - Replace the plain `TextFormField` for date with a `GestureDetector` that opens `showDatePicker()`
   - Set `firstDate` to `DateTime.now().add(Duration(days: 10))`
   - Set `lastDate` to `DateTime.now().add(Duration(days: 365))`
   - Display selected date in formatted text

2. **Add validation in submit handler (Line ~712):**
```dart
// Before creating event:
final eventDate = DateTime.tryParse(_dateC.text);
if (eventDate == null) {
  _toast(context, 'Please select a valid date');
  return;
}
final daysUntilEvent = eventDate.difference(DateTime.now()).inDays;
if (daysUntilEvent < 10) {
  _toast(context, 'Events must be submitted at least 10 days in advance');
  return;
}
```

3. **Add visual notice about the rule:**
   - After the existing `NoticeBox`, add:
   ```dart
   NoticeBox(
     message: 'Events must be submitted at least 10 days before the event date to allow time for admin review.',
     borderColor: AppTheme.goldDark,
     bgColor: AppTheme.gold.withOpacity(0.12),
     textColor: const Color(0xFF7A5B00),
     icon: Icons.calendar_today_rounded,
   ),
   ```

---

### 3.3 Change B: PDF Approval Letter Upload

#### Concept
Students must upload an official approval letter (PDF) from management/faculty. Without this document, the system blocks submission.

#### Changes Required

##### File: `lib/data/mock_data.dart`

**A) Update `Event` model:**
```dart
class Event {
  // ... existing fields ...
  final String? approvalLetterPath;   // NEW: PDF file path
  final String? approvalLetterName;   // NEW: Original filename
  final bool hasApprovalLetter;       // NEW: Validation flag

  const Event({
    // ... existing params ...
    this.approvalLetterPath,
    this.approvalLetterName,
    this.hasApprovalLetter = false,
  });
}
```

##### File: `lib/screens/events/events_screens.dart`

**B) Modify `CreateEventScreen` - Add PDF upload section:**

Add after the Description field (Line ~710):
```dart
const SectionLabel('Approval Letter'),
NoticeBox(
  message: 'You must upload an official approval letter (PDF) from your faculty or management. This is mandatory for event submission.',
  borderColor: AppTheme.danger,
  bgColor: AppTheme.danger.withOpacity(0.06),
  textColor: const Color(0xFF8B2020),
  icon: Icons.description_rounded,
),
const SizedBox(height: 10),
// PDF upload button
GestureDetector(
  onTap: _pickApprovalLetter,
  child: Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _approvalLetterName != null ? Colors.green.withOpacity(0.08) : AppTheme.bgCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: _approvalLetterName != null ? Colors.green.withOpacity(0.3) : AppTheme.red.withOpacity(0.2),
        style: BorderStyle.solid,
      ),
    ),
    child: Column(children: [
      Icon(
        _approvalLetterName != null ? Icons.check_circle_rounded : Icons.upload_file_rounded,
        size: 36,
        color: _approvalLetterName != null ? Colors.green : AppTheme.red,
      ),
      const SizedBox(height: 8),
      Text(
        _approvalLetterName ?? 'Tap to upload PDF',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: _approvalLetterName != null ? Colors.green : AppTheme.textSecondary,
        ),
      ),
      if (_approvalLetterName == null)
        const Text('Only PDF format accepted', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
    ]),
  ),
),
```

**C) Add state variables and mock picker method in `_CreateEventState`:**
```dart
String? _approvalLetterName;
String? _approvalLetterPath;

void _pickApprovalLetter() {
  // In production, use file_picker package
  // For mock: simulate file selection
  setState(() {
    _approvalLetterName = 'Approval_Letter_Faculty_Computing.pdf';
    _approvalLetterPath = '/mock/path/approval.pdf';
  });
  _toast(context, 'PDF uploaded successfully');
}
```

**D) Add submission validation:**
```dart
// In submit handler, before creating event:
if (_approvalLetterName == null) {
  _toast(context, 'Please upload an approval letter (PDF) before submitting');
  return;
}
```

##### File: `pubspec.yaml`

**E) Add dependency (for production):**
```yaml
file_picker: ^8.0.0  # For actual file picking
```

---

### 3.4 Change C: Multi-Stage Status Workflow

#### Concept
Events go through multiple stages instead of just Pending -> Approved/Rejected:

```
Pending -> Under Review -> Approved / Rejected / Needs Revision
                                                       |
                                                       v
                                                 Re-submitted -> Under Review -> ...
```

#### Changes Required

##### File: `lib/data/mock_data.dart`

**A) Update `Event` model with new fields:**
```dart
class Event {
  // ... existing fields ...
  final String? rejectionReason;      // NEW: Why it was rejected
  final String? revisionNotes;        // NEW: What needs to change
  final List<EventMessage>? messages; // NEW: Admin-student communication
  final int revisionCount;            // NEW: How many times resubmitted
  final String? submittedDate;        // NEW: When first submitted

  const Event({
    // ... existing params ...
    this.rejectionReason,
    this.revisionNotes,
    this.messages,
    this.revisionCount = 0,
    this.submittedDate,
  });
}

// NEW model for admin-student communication
class EventMessage {
  final String id;
  final String senderId;        // 'admin' or student ID
  final String senderRole;      // 'admin' or 'student'
  final String message;
  final String timestamp;
  final String? attachmentName; // Optional attachment

  const EventMessage({
    required this.id,
    required this.senderId,
    required this.senderRole,
    required this.message,
    required this.timestamp,
    this.attachmentName,
  });
}
```

##### File: `lib/services/data_service.dart`

**B) Add new event workflow methods:**

```dart
void moveEventToReview(String id) {
  final index = pendingEvents.indexWhere((e) => e.id == id);
  if (index != -1) {
    final e = pendingEvents[index];
    pendingEvents[index] = Event(
      id: e.id, title: e.title, date: e.date, time: e.time,
      location: e.location, category: e.category, organizer: e.organizer,
      description: e.description, status: 'Under Review',
      hostStudentId: e.hostStudentId,
      approvalLetterPath: e.approvalLetterPath,
      approvalLetterName: e.approvalLetterName,
      hasApprovalLetter: e.hasApprovalLetter,
      messages: e.messages,
      revisionCount: e.revisionCount,
      submittedDate: e.submittedDate,
    );
    // Private notification to student
    _addNotification(
      'Your event is now under review',
      'private',
      detailText: 'Event "${e.title}" is being reviewed by admin. You will be notified of the decision.',
      targetUserId: e.hostStudentId,
      source: 'events',
    );
    notifyListeners();
  }
}

void requestEventRevision(String id, String reason) {
  final index = pendingEvents.indexWhere((e) => e.id == id);
  if (index != -1) {
    final e = pendingEvents[index];
    pendingEvents[index] = Event(
      id: e.id, title: e.title, date: e.date, time: e.time,
      location: e.location, category: e.category, organizer: e.organizer,
      description: e.description, status: 'Needs Revision',
      hostStudentId: e.hostStudentId,
      revisionNotes: reason,
      messages: e.messages,
      revisionCount: e.revisionCount,
      submittedDate: e.submittedDate,
    );
    // Private notification to student
    _addNotification(
      'Your event needs changes',
      'private',
      detailText: 'Event "${e.title}" requires revision: $reason',
      targetUserId: e.hostStudentId,
      source: 'events',
    );
    notifyListeners();
  }
}

void resubmitEvent(String id, {String? updatedTitle, String? updatedDescription}) {
  final index = pendingEvents.indexWhere((e) => e.id == id);
  if (index != -1) {
    final e = pendingEvents[index];
    pendingEvents[index] = Event(
      id: e.id,
      title: updatedTitle ?? e.title,
      date: e.date, time: e.time,
      location: e.location, category: e.category, organizer: e.organizer,
      description: updatedDescription ?? e.description,
      status: 'Pending',
      hostStudentId: e.hostStudentId,
      revisionCount: e.revisionCount + 1,
      submittedDate: e.submittedDate,
    );
    // Private notification to admin
    _addNotification(
      'Event resubmitted for review',
      'private',
      detailText: 'Event "${e.title}" has been revised and resubmitted (revision #${e.revisionCount + 1}).',
      visibility: 'admin',
      source: 'events',
    );
    notifyListeners();
  }
}
```

**C) Modify existing `rejectEvent()` (Line ~301-312):**
- **CURRENT:** Removes the event from `pendingEvents` entirely
- **NEW:** Keep the event in `pendingEvents` with status `'Rejected'` and store `rejectionReason`
```dart
void rejectEvent(String id, {String? reason}) {
  final index = pendingEvents.indexWhere((e) => e.id == id);
  if (index != -1) {
    final e = pendingEvents[index];
    pendingEvents[index] = Event(
      id: e.id, title: e.title, date: e.date, time: e.time,
      location: e.location, category: e.category, organizer: e.organizer,
      description: e.description, status: 'Rejected',
      hostStudentId: e.hostStudentId,
      rejectionReason: reason,
      revisionCount: e.revisionCount,
      submittedDate: e.submittedDate,
    );
    // Private notification ONLY to event creator
    _addNotification(
      'Your event has been rejected',
      'private',
      detailText: 'Event "${e.title}" was rejected.${reason != null ? " Reason: $reason" : ""} You can make changes and resubmit.',
      targetUserId: e.hostStudentId,
      source: 'events',
    );
    notifyListeners();
  }
}
```

---

### 3.5 Change D: Admin-to-Student Communication

#### Changes Required

##### File: `lib/services/data_service.dart`

**A) Add messaging method:**
```dart
void addEventMessage(String eventId, String senderId, String senderRole, String message) {
  // Check pending events first, then all events
  var index = pendingEvents.indexWhere((e) => e.id == eventId);
  List<Event> targetList;
  if (index != -1) {
    targetList = pendingEvents;
  } else {
    index = allEvents.indexWhere((e) => e.id == eventId);
    if (index == -1) return;
    targetList = allEvents;
  }

  final e = targetList[index];
  final newMessage = EventMessage(
    id: 'EM-${DateTime.now().millisecondsSinceEpoch}',
    senderId: senderId,
    senderRole: senderRole,
    message: message,
    timestamp: DateTime.now().toString().split('.')[0],
  );

  final updatedMessages = List<EventMessage>.from(e.messages ?? [])..add(newMessage);

  targetList[index] = Event(
    id: e.id, title: e.title, date: e.date, time: e.time,
    location: e.location, category: e.category, organizer: e.organizer,
    description: e.description, status: e.status,
    hostStudentId: e.hostStudentId,
    messages: updatedMessages,
    revisionCount: e.revisionCount,
    submittedDate: e.submittedDate,
  );

  // Notification to the other party
  if (senderRole == 'admin') {
    _addNotification(
      'Admin sent you a message about your event',
      'private',
      detailText: 'Regarding "${e.title}": $message',
      targetUserId: e.hostStudentId,
      source: 'events',
    );
  } else {
    _addNotification(
      'Student replied about event ${e.id}',
      'private',
      detailText: 'Regarding "${e.title}": $message',
      visibility: 'admin',
      source: 'events',
    );
  }
  notifyListeners();
}
```

##### File: `lib/screens/events/events_screens.dart`

**B) Modify `AdminEventsListScreen` pending event cards (Line ~288-320):**
- Add new action buttons: "Review" (moves to Under Review), "Request Revision" (opens dialog)
- Replace simple Approve/Reject with expanded workflow:
```
Row of actions:
  [Review]  [Approve]  [Revision]  [Reject]  [Message]
```

**C) Add new Admin Event Detail screen with communication panel:**
- New route: `/admin/events/detail/:id` for pending events
- Shows: Event details, approval letter viewer, status workflow buttons
- Bottom section: Message thread (chat-like UI) between admin and student
- Text input + Send button for admin messages

**D) Add Student Event Status screen:**
- New route: `/events/my-events`
- Shows list of student's submitted events with current status
- Tapping opens detail with:
  - Current status badge (Pending / Under Review / Needs Revision / Rejected / Approved)
  - If "Needs Revision": Shows revision notes + editable form + "Resubmit" button
  - If "Rejected": Shows rejection reason + option to resubmit
  - Message thread with admin
  - Status timeline showing all stage transitions

**E) Add route for My Events in `lib/main.dart`:**
```dart
GoRoute(path: '/events/my-events', builder: (_, __) => const MyEventsScreen()),
```

**F) Modify `EventsHubScreen` to add "My Events" button:**
- Add a `HubButton` or link: "My Submitted Events" showing count of pending events

---

## 4. SYSTEM 3: LOCKER MANAGEMENT SYSTEM - QR KEY COLLECTION & RELEASE

### 4.1 Current State Analysis

**Current Files:**
- **Model:** `lib/data/mock_data.dart` - `Locker`, `LockerBooking`, `LockerHistory` classes
- **Service:** `lib/services/data_service.dart` - `bookLocker()`, `releaseBooking()`, admin actions
- **Student UI:** `lib/screens/lockers/lockers_screens.dart` - `LockerHubScreen`, `BrowseLockersScreen`, `LockerBookingScreen`, `MyLockerScreen`
- **Admin UI:** `lib/screens/lockers/lockers_screens.dart` - `AdminLockerDashboardScreen`, `AdminLockersListScreen`, `AdminLockerDetailScreen`

**Current Problems:**
1. Key collection has no verification - just a text notice saying "visit the office"
2. No QR code flow for key pickup proof
3. Locker release is instant with no key return verification
4. No multi-step release process
5. Extension has no time restriction (says "coming soon")
6. Issue reporting redirects to generic Issues screen, no photo upload specific to lockers

---

### 4.2 Change A: QR Code Verification for Key Collection

#### Concept
After booking a key-type locker:
1. Student books locker -> Status: "Pending Pickup"
2. Student visits admin office
3. Admin generates a QR code in the system
4. Student scans QR code using the app
5. System confirms key collection -> Status: "Active"

#### Changes Required

##### File: `lib/data/mock_data.dart`

**A) Update `LockerBooking` model:**
```dart
class LockerBooking {
  // ... existing fields ...
  final String? keyCollectionQR;      // NEW: QR code for key pickup
  final bool keyCollected;             // NEW: Whether key has been collected
  final String? keyCollectionDate;     // NEW: When key was collected
  final String? keyReturnQR;          // NEW: QR code for key return
  final bool keyReturned;             // NEW: Whether key has been returned
  final String? keyReturnDate;        // NEW: When key was returned
  final String? releaseStatus;        // NEW: null, 'Requested', 'Pending Return', 'Returned', 'Completed'

  const LockerBooking({
    // ... existing params ...
    this.keyCollectionQR,
    this.keyCollected = false,
    this.keyCollectionDate,
    this.keyReturnQR,
    this.keyReturned = false,
    this.keyReturnDate,
    this.releaseStatus,
  });
}
```

##### File: `lib/services/data_service.dart`

**B) Add key collection QR methods:**
```dart
// Admin generates QR for key collection
String generateKeyCollectionQR(String bookingId) {
  final code = 'KEY-COL-${bookingId}-${Random().nextInt(999999).toString().padLeft(6, '0')}';
  final index = myBookings.indexWhere((b) => b.id == bookingId);
  if (index != -1) {
    final b = myBookings[index];
    myBookings[index] = LockerBooking(
      id: b.id, lockerId: b.lockerId, location: b.location,
      startDate: b.startDate, endDate: b.endDate, status: b.status,
      daysLeft: b.daysLeft, durationMonths: b.durationMonths,
      monthlyRent: b.monthlyRent, deposit: b.deposit, totalPaid: b.totalPaid,
      keyCollectionQR: code,
      keyCollected: false,
    );
  }
  _addLockerHistory(
    myBookings[index].lockerId,
    'Key collection QR generated',
    'ADMIN',
    'Admin generated QR code for key pickup',
  );
  _addNotification(
    'Your key collection QR is ready',
    'private',
    detailText: 'Please visit the admin office and scan the QR code to collect your locker key for ${myBookings[index].lockerId}.',
    targetUserId: 'S001',
    source: 'lockers',
  );
  notifyListeners();
  return code;
}

// Student scans QR to confirm key collection
bool scanKeyCollectionQR(String bookingId, String qrCode) {
  final index = myBookings.indexWhere((b) => b.id == bookingId);
  if (index == -1) return false;

  final b = myBookings[index];
  if (b.keyCollectionQR != qrCode || b.keyCollected) return false;

  // Update booking
  myBookings[index] = LockerBooking(
    id: b.id, lockerId: b.lockerId, location: b.location,
    startDate: b.startDate, endDate: b.endDate, status: 'Active',
    daysLeft: b.daysLeft, durationMonths: b.durationMonths,
    monthlyRent: b.monthlyRent, deposit: b.deposit, totalPaid: b.totalPaid,
    keyCollectionQR: b.keyCollectionQR,
    keyCollected: true,
    keyCollectionDate: DateTime.now().toString().split('.')[0],
  );

  // Update locker status to Active
  final lockerIndex = lockers.indexWhere((l) => l.id == b.lockerId);
  if (lockerIndex != -1) {
    final lk = lockers[lockerIndex];
    lockers[lockerIndex] = Locker(
      id: lk.id, location: lk.location, status: 'Active',
      studentId: lk.studentId, startDate: lk.startDate, endDate: lk.endDate,
      daysLeft: lk.daysLeft, lockType: lk.lockType, digitalCode: lk.digitalCode,
      monthlyRent: lk.monthlyRent, deposit: lk.deposit,
    );
  }

  _addLockerHistory(b.lockerId, 'Key collected - QR verified', 'system', 'Student scanned QR and collected key');
  _addNotification(
    'Key collected successfully!',
    'private',
    detailText: 'You have collected the key for locker ${b.lockerId}. Your rental period has started.',
    targetUserId: 'S001',
    source: 'lockers',
  );
  notifyListeners();
  return true;
}
```

##### File: `lib/screens/lockers/lockers_screens.dart`

**C) Modify `MyLockerScreen` (Line ~407-528):**

Add a new section when `booking.status == 'Pending Pickup'` and `locker.lockType == 'key'`:
```
Design Spec: Key Collection Section
+------------------------------------------+
|  KEY COLLECTION                          |
|  ----------------------------------------|
|  Step 1: Visit Admin Office   [DONE/TODO]|
|  Step 2: Scan QR Code         [ACTIVE]   |
|  ----------------------------------------|
|  [QR Code Input Field]                   |
|  [Verify & Collect Key]  <- GradientBtn  |
+------------------------------------------+
```

- Show QR input field with scan button
- On successful scan: show success dialog with key collection confirmation
- Status updates from "Pending Pickup" to "Active"

**D) Modify `AdminLockerDetailScreen` (Line ~606-948):**

Add "Generate Key Collection QR" button when locker status is "Pending Pickup" and lockType is "key":
```dart
if (lk.status == 'Pending Pickup' && lk.lockType == 'key') ...[
  _AdminActionButton(
    icon: Icons.qr_code_2_rounded,
    label: 'Generate Key Collection QR',
    subtitle: 'Student will scan this to confirm key pickup',
    color: AppTheme.red,
    onTap: () {
      final booking = dataService.myBookings.firstWhere(
        (b) => b.lockerId == lk.id && b.status == 'Pending Pickup',
        orElse: () => /* empty booking */,
      );
      if (booking.id.isNotEmpty) {
        final code = dataService.generateKeyCollectionQR(booking.id);
        _showQRDialog(context, 'Key Collection QR', code,
          'Show this QR code to the student. They must scan it to confirm key collection.');
      }
    },
  ),
],
```

---

### 4.3 Change B: Extension Time Restriction

#### Changes Required

##### File: `lib/screens/lockers/lockers_screens.dart`

**A) Modify "Request Extension" in `MyLockerScreen` (Line ~503):**

Replace the current placeholder toast with actual logic:
```dart
HubButton(
  icon: Icons.swap_horiz_rounded,
  label: 'Request Extension',
  subtitle: booking.daysLeft <= 30
    ? 'Extend your rental period'
    : 'Available when remaining time is 1 month or less (${booking.daysLeft} days left)',
  isPrimary: booking.daysLeft <= 30,
  onTap: booking.daysLeft <= 30
    ? () => _showExtensionDialog(context, booking)
    : () => _toast(context, 'Extension available only when remaining time is 1 month or less. You have ${booking.daysLeft} days remaining.'),
),
```

**B) Add extension dialog and handler:**
```dart
void _showExtensionDialog(BuildContext context, LockerBooking booking) {
  int extensionMonths = 1;
  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Extend Rental', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Current end date: ${fmtDate(booking.endDate)}'),
          const SizedBox(height: 16),
          // Duration selector: 1-6 months
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(onPressed: extensionMonths > 1 ? () => setState(() => extensionMonths--) : null, icon: const Icon(Icons.remove_circle_outline)),
            Text('$extensionMonths month(s)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            IconButton(onPressed: extensionMonths < 6 ? () => setState(() => extensionMonths++) : null, icon: const Icon(Icons.add_circle_outline)),
          ]),
          const SizedBox(height: 8),
          Text('Additional cost: RM${(10 * extensionMonths)}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.red)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<DataService>().extendBooking(booking.id, extensionMonths);
              _toast(context, 'Rental extended by $extensionMonths month(s)');
            },
            child: const Text('Confirm Extension', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ),
  );
}
```

##### File: `lib/services/data_service.dart`

**C) Add `extendBooking()` method:**
```dart
void extendBooking(String bookingId, int additionalMonths) {
  final index = myBookings.indexWhere((b) => b.id == bookingId);
  if (index == -1) return;
  final b = myBookings[index];

  if (b.daysLeft > 30) return; // Safety check

  final currentEnd = DateTime.parse(b.endDate);
  final newEnd = DateTime(currentEnd.year, currentEnd.month + additionalMonths, currentEnd.day);
  final newDaysLeft = newEnd.difference(DateTime.now()).inDays;
  final additionalCost = b.monthlyRent * additionalMonths;

  myBookings[index] = LockerBooking(
    id: b.id, lockerId: b.lockerId, location: b.location,
    startDate: b.startDate,
    endDate: newEnd.toString().split(' ')[0],
    status: b.status,
    daysLeft: newDaysLeft,
    durationMonths: b.durationMonths + additionalMonths,
    monthlyRent: b.monthlyRent, deposit: b.deposit,
    totalPaid: b.totalPaid + additionalCost,
    keyCollectionQR: b.keyCollectionQR, keyCollected: b.keyCollected,
    keyCollectionDate: b.keyCollectionDate,
  );

  // Update locker end date
  final lockerIndex = lockers.indexWhere((l) => l.id == b.lockerId);
  if (lockerIndex != -1) {
    final lk = lockers[lockerIndex];
    lockers[lockerIndex] = Locker(
      id: lk.id, location: lk.location, status: lk.status,
      studentId: lk.studentId, startDate: lk.startDate,
      endDate: newEnd.toString().split(' ')[0],
      daysLeft: newDaysLeft, lockType: lk.lockType,
      digitalCode: lk.digitalCode, monthlyRent: lk.monthlyRent,
      deposit: lk.deposit,
    );
  }

  _addLockerHistory(b.lockerId, 'Rental extended', 'system', 'Extended by $additionalMonths months. Additional: RM${additionalCost.toStringAsFixed(0)}');
  _addNotification(
    'Locker rental extended',
    'private',
    detailText: 'Locker ${b.lockerId} extended by $additionalMonths month(s). New end date: ${fmtDate(newEnd.toString().split(' ')[0])}.',
    targetUserId: 'S001',
    source: 'lockers',
  );
  notifyListeners();
}
```

---

### 4.4 Change C: Locker Issue Reporting with Photo

#### Changes Required

##### File: `lib/data/mock_data.dart`

**A) Add `LockerIssue` model:**
```dart
class LockerIssue {
  final String id;
  final String lockerId;
  final String studentId;
  final String description;
  final String status;          // 'Reported', 'Under Review', 'Resolved'
  final int photoCount;
  final String reportedDate;

  const LockerIssue({
    required this.id,
    required this.lockerId,
    required this.studentId,
    required this.description,
    required this.status,
    this.photoCount = 0,
    required this.reportedDate,
  });
}
```

##### File: `lib/services/data_service.dart`

**B) Add locker issue list and method:**
```dart
late List<LockerIssue> lockerIssues = [];

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
  lockerIssues.add(issue);

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
    detailText: 'Issue for locker $lockerId has been submitted. Admin will review it shortly.',
    targetUserId: 'S001',
    source: 'lockers',
  );
  notifyListeners();
}
```

##### File: `lib/screens/lockers/lockers_screens.dart`

**C) Modify "Report Locker Issue" button in `MyLockerScreen` (Line ~504):**
- Instead of redirecting to `/issues/report`, open a dedicated locker issue dialog:
```dart
HubButton(
  icon: Icons.report_problem_rounded,
  label: 'Report Locker Issue',
  subtitle: 'Damage, malfunction, etc.',
  onTap: () => _showLockerIssueDialog(context, booking.lockerId),
),
```

**D) Add `_showLockerIssueDialog()` method:**
```dart
void _showLockerIssueDialog(BuildContext context, String lockerId) {
  final descCtrl = TextEditingController();
  int photoCount = 0;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Report Locker Issue', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: descCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Describe the issue',
              hintText: 'e.g. Lock is jammed, damage on door...',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          // Photo upload mock
          GestureDetector(
            onTap: () => setState(() => photoCount++),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.red.withOpacity(0.2)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.camera_alt_rounded, color: AppTheme.red, size: 20),
                const SizedBox(width: 8),
                Text(
                  photoCount > 0 ? '$photoCount photo(s) attached' : 'Tap to add photo',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: photoCount > 0 ? Colors.green : AppTheme.textSecondary),
                ),
              ]),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () {
              if (descCtrl.text.trim().isNotEmpty) {
                context.read<DataService>().reportLockerIssue(lockerId, descCtrl.text.trim(), photoCount);
                Navigator.pop(ctx);
                _toast(context, 'Issue reported successfully');
              }
            },
            child: const Text('Submit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ),
  );
}
```

---

### 4.5 Change D: QR Code Verification for Key Return / Locker Release

#### Concept
When a student wants to release their locker:
1. Student taps "Release Locker" -> Status: "Release Requested"
2. Student visits admin office to return the key
3. Admin generates a release QR code
4. Student scans the QR code to confirm key return
5. Admin approves the release -> Status: "Released" / "Available"
6. Deposit refund is processed

#### Changes Required

##### File: `lib/services/data_service.dart`

**A) Replace current `releaseBooking()` with multi-step flow:**

```dart
// Step 1: Student requests release
void requestLockerRelease(String bookingId) {
  final index = myBookings.indexWhere((b) => b.id == bookingId);
  if (index == -1) return;
  final b = myBookings[index];

  myBookings[index] = LockerBooking(
    id: b.id, lockerId: b.lockerId, location: b.location,
    startDate: b.startDate, endDate: b.endDate,
    status: 'Release Requested',
    daysLeft: b.daysLeft, durationMonths: b.durationMonths,
    monthlyRent: b.monthlyRent, deposit: b.deposit, totalPaid: b.totalPaid,
    keyCollectionQR: b.keyCollectionQR, keyCollected: b.keyCollected,
    keyCollectionDate: b.keyCollectionDate,
    releaseStatus: 'Requested',
  );

  _addLockerHistory(b.lockerId, 'Release requested', 'system', 'Student requested locker release');
  _addNotification(
    'Locker release requested',
    'private',
    detailText: 'Student has requested to release locker ${b.lockerId}. Generate a return QR code when they visit.',
    visibility: 'admin',
    source: 'lockers',
  );
  _addNotification(
    'Release request submitted',
    'private',
    detailText: 'Your request to release locker ${b.lockerId} has been submitted. Please visit the admin office to return your key.',
    targetUserId: 'S001',
    source: 'lockers',
  );
  notifyListeners();
}

// Step 2: Admin generates return QR
String generateKeyReturnQR(String bookingId) {
  final code = 'KEY-RET-${bookingId}-${Random().nextInt(999999).toString().padLeft(6, '0')}';
  final index = myBookings.indexWhere((b) => b.id == bookingId);
  if (index != -1) {
    final b = myBookings[index];
    myBookings[index] = LockerBooking(
      id: b.id, lockerId: b.lockerId, location: b.location,
      startDate: b.startDate, endDate: b.endDate,
      status: b.status,
      daysLeft: b.daysLeft, durationMonths: b.durationMonths,
      monthlyRent: b.monthlyRent, deposit: b.deposit, totalPaid: b.totalPaid,
      keyCollectionQR: b.keyCollectionQR, keyCollected: b.keyCollected,
      keyCollectionDate: b.keyCollectionDate,
      keyReturnQR: code,
      keyReturned: false,
      releaseStatus: 'Pending Return',
    );
    _addLockerHistory(b.lockerId, 'Return QR generated', 'ADMIN', 'Admin generated QR for key return');
    _addNotification(
      'Return QR code is ready',
      'private',
      detailText: 'Please scan the QR code at the admin office to confirm key return for locker ${b.lockerId}.',
      targetUserId: 'S001',
      source: 'lockers',
    );
  }
  notifyListeners();
  return code;
}

// Step 3: Student scans return QR
bool scanKeyReturnQR(String bookingId, String qrCode) {
  final index = myBookings.indexWhere((b) => b.id == bookingId);
  if (index == -1) return false;

  final b = myBookings[index];
  if (b.keyReturnQR != qrCode || b.keyReturned) return false;

  myBookings[index] = LockerBooking(
    id: b.id, lockerId: b.lockerId, location: b.location,
    startDate: b.startDate, endDate: b.endDate,
    status: b.status,
    daysLeft: b.daysLeft, durationMonths: b.durationMonths,
    monthlyRent: b.monthlyRent, deposit: b.deposit, totalPaid: b.totalPaid,
    keyCollectionQR: b.keyCollectionQR, keyCollected: b.keyCollected,
    keyCollectionDate: b.keyCollectionDate,
    keyReturnQR: b.keyReturnQR,
    keyReturned: true,
    keyReturnDate: DateTime.now().toString().split('.')[0],
    releaseStatus: 'Returned',
  );

  _addLockerHistory(b.lockerId, 'Key returned - QR verified', 'system', 'Student scanned return QR and returned key');
  _addNotification(
    'Key returned successfully',
    'private',
    detailText: 'Key for locker ${b.lockerId} has been returned. Awaiting admin approval to complete release.',
    targetUserId: 'S001',
    source: 'lockers',
  );
  _addNotification(
    'Key returned for locker ${b.lockerId}',
    'private',
    detailText: 'Student has returned the key (QR verified). Please approve the release to complete the process.',
    visibility: 'admin',
    source: 'lockers',
  );
  notifyListeners();
  return true;
}

// Step 4: Admin approves release
void approveLockerRelease(String bookingId) {
  final index = myBookings.indexWhere((b) => b.id == bookingId);
  if (index == -1) return;
  final b = myBookings[index];

  // Update locker back to Available
  final lockerIndex = lockers.indexWhere((l) => l.id == b.lockerId);
  if (lockerIndex != -1) {
    final lk = lockers[lockerIndex];
    lockers[lockerIndex] = Locker(
      id: lk.id, location: lk.location, status: 'Available',
      lockType: lk.lockType, depositRefunded: true,
    );
  }

  // Remove booking
  myBookings.removeAt(index);

  _addLockerHistory(b.lockerId, 'Locker released - Admin approved', 'ADMIN', 'Release approved. Deposit: RM${b.deposit.toStringAsFixed(0)} refunded.');
  _addNotification(
    'Locker release completed!',
    'private',
    detailText: 'Your locker ${b.lockerId} has been released. Deposit of RM${b.deposit.toStringAsFixed(0)} will be refunded.',
    targetUserId: 'S001',
    source: 'lockers',
  );
  notifyListeners();
}
```

##### File: `lib/screens/lockers/lockers_screens.dart`

**B) Modify `MyLockerScreen` "Release Locker" button and add release flow UI (Line ~505):**

Replace the current simple release with a multi-step process:
```
Design Spec: Release Flow Section (shown when releaseStatus != null)
+------------------------------------------+
|  LOCKER RELEASE PROGRESS                 |
+------------------------------------------+
|  (1) [GREEN CHECK] Release Requested     |
|   |                Submitted today       |
|  (2) [ACTIVE/DONE] Visit Admin Office    |
|   |                Return your key       |
|  (3) [ACTIVE/PEND] Scan Return QR        |
|   |                [QR Input Field]      |
|   |                [Verify Button]       |
|  (4) [PENDING]     Admin Approval        |
|   |                Deposit refund        |
+------------------------------------------+
```

- Step 1: Always complete (Release Requested)
- Step 2: Active when `releaseStatus == 'Requested'`
- Step 3: Active when `releaseStatus == 'Pending Return'`, show QR input
- Step 4: Active when `releaseStatus == 'Returned'`, waiting for admin

**C) Modify `AdminLockerDetailScreen` to show release actions:**

Add new section when booking has `releaseStatus`:
```dart
// If release requested
if (booking.releaseStatus == 'Requested') ...[
  _AdminActionButton(
    icon: Icons.qr_code_2_rounded,
    label: 'Generate Return QR',
    subtitle: 'Student will scan to confirm key return',
    color: AppTheme.red,
    onTap: () {
      final code = dataService.generateKeyReturnQR(booking.id);
      _showQRDialog(context, 'Key Return QR', code,
        'Show this QR code to the student. They must scan it to confirm key return.');
    },
  ),
],

// If key returned, waiting for approval
if (booking.releaseStatus == 'Returned') ...[
  _AdminActionButton(
    icon: Icons.check_circle_rounded,
    label: 'Approve Release',
    subtitle: 'Key returned (QR verified). Complete the release.',
    color: Colors.green,
    onTap: () {
      dataService.approveLockerRelease(booking.id);
      _toast(context, 'Locker released. Deposit refund processed.');
      context.pop();
    },
  ),
],
```

---

## 5. DATA MODEL CHANGES (Summary)

### Modified Models

| Model | File | New Fields |
|-------|------|------------|
| `Notification` | `mock_data.dart` | `visibility`, `detailText`, `targetUserId`, `source` |
| `Event` | `mock_data.dart` | `approvalLetterPath`, `approvalLetterName`, `hasApprovalLetter`, `rejectionReason`, `revisionNotes`, `messages`, `revisionCount`, `submittedDate` |
| `LockerBooking` | `mock_data.dart` | `keyCollectionQR`, `keyCollected`, `keyCollectionDate`, `keyReturnQR`, `keyReturned`, `keyReturnDate`, `releaseStatus` |

### New Models

| Model | File | Purpose |
|-------|------|---------|
| `EventMessage` | `mock_data.dart` | Admin-student communication thread for event approval |
| `LockerIssue` | `mock_data.dart` | Dedicated locker issue reports with photo count |

---

## 6. FILE-BY-FILE CHANGE MAP

| File | Changes | Sections Affected |
|------|---------|-------------------|
| `lib/data/mock_data.dart` | Update Notification, Event, LockerBooking models; add EventMessage, LockerIssue models; update mock data | All model classes, MockData class |
| `lib/services/data_service.dart` | Overhaul notification system, add smart matching, event workflow methods, locker QR methods, extension logic, locker issues | _addNotification, addLostReport, addFoundReport, reportIssue, createEvent, rejectEvent + 12 new methods |
| `lib/screens/lost_found/lost_found_screens.dart` | NotificationsScreen filter tabs, public/private display, mark all read | NotificationsScreen |
| `lib/screens/events/events_screens.dart` | DatePicker, PDF upload, multi-stage status, revision flow, admin communication, MyEventsScreen | CreateEventScreen, AdminEventsListScreen, AdminEventEditorScreen + 2 new screens |
| `lib/screens/lockers/lockers_screens.dart` | QR key collection UI, extension dialog with restriction, locker issue dialog, release flow stepper, admin release actions | MyLockerScreen, AdminLockerDetailScreen |
| `lib/main.dart` | Filtered notification count, new routes for events | AppShell header, router |
| `pubspec.yaml` | file_picker dependency | dependencies |

---

## 7. NEW FILES REQUIRED

| File | Purpose | When to Create |
|------|---------|----------------|
| `lib/screens/events/my_events_screen.dart` | Student's submitted events with status tracking, revision, and messages | When implementing event workflow (System 2) |
| `lib/widgets/release_stepper.dart` | Reusable stepper widget for locker release flow | When implementing locker release (System 3) |
| `lib/widgets/notification_filter.dart` | Filter chip row widget for notification categories | When implementing notification overhaul (System 1) |

---

## 8. ROUTE CHANGES

### New Routes to Add in `lib/main.dart`

```dart
// Student Events
GoRoute(path: '/events/my-events', builder: (_, __) => const MyEventsScreen()),
GoRoute(path: '/events/my-events/:id', builder: (_, s) => MyEventDetailScreen(id: s.pathParameters['id']!)),

// Admin Events (pending detail with communication)
GoRoute(path: '/admin/events/pending/:id', builder: (_, s) => AdminPendingEventDetailScreen(id: s.pathParameters['id']!)),
```

---

## 9. PRIORITY & IMPLEMENTATION ORDER

### Phase 1 - Core Infrastructure (Implement First)
1. **Notification Model Overhaul** (2.2A-B) - Foundation for all other notification changes
2. **Notification Service Overhaul** (2.2C-E) - Update _addNotification and add filtering
3. **Update ALL notification calls** (2.2D) - Apply public/private pattern across codebase

### Phase 2 - Locker QR System (Implement Second)
4. **Key Collection QR Flow** (4.2) - Student books -> admin generates QR -> student scans -> active
5. **Locker Release QR Flow** (4.5) - Multi-step release with QR return verification
6. **Extension Restriction** (4.3) - Simple rule: only when <= 30 days remaining
7. **Locker Issue Reporting** (4.4) - Dedicated dialog with photo support

### Phase 3 - Event Management (Implement Third)
8. **10-Day Rule & DatePicker** (3.2) - Validation and proper date input
9. **PDF Upload Requirement** (3.3) - Approval letter upload with mock picker
10. **Multi-Stage Status Workflow** (3.4) - Pending -> Under Review -> Approved/Rejected/Needs Revision
11. **Re-submission Flow** (3.4C) - Keep rejected events, allow editing and resubmit
12. **Admin Communication** (3.5) - Message thread between admin and student

### Phase 4 - Smart Features (Implement Last)
13. **Smart Matching Engine** (2.3) - Auto-match found items to lost reports
14. **Notification UI Overhaul** (2.2F-G) - Filter tabs, expandable details, source icons
15. **Notification Preferences** (2.4) - Toggle switches per category

### Estimated Scope
- **Total screens modified:** 6 existing screens
- **Total new screens:** 3 (MyEventsScreen, MyEventDetailScreen, AdminPendingEventDetailScreen)
- **Total files modified:** 7 files
- **New data models:** 2 (EventMessage, LockerIssue)
- **Modified data models:** 3 (Notification, Event, LockerBooking)
- **New service methods:** ~15 methods
- **New dependencies:** 1 (file_picker)

---

## 10. VISUAL REFERENCE DESIGNS

### 10.1 Notification Card Variants

```
PUBLIC NOTIFICATION:
+------------------------------------------+
| [GREY CIRCLE: search]  A lost item has   |
|                        been reported     |
|                        5 hours ago       |
+------------------------------------------+

PRIVATE NOTIFICATION (collapsed):
+------------------------------------------+
| [RED CIRCLE: person]   Your lost item    |  [RED DOT]
|                        may have been     |
|                        found!            |
|                        2 hours ago    [>]|
+------------------------------------------+

PRIVATE NOTIFICATION (expanded):
+------------------------------------------+
| [RED CIRCLE: person]   Your lost item    |
|                        may have been     |
|                        found!            |
|  ----------------------------------------|
|  A matching Phone was found in Block A   |
|  Corridor. Match confidence: 87%.        |
|  Please visit the Lost & Found office.   |
|                        2 hours ago       |
+------------------------------------------+
```

### 10.2 Event Status Badges

```
[PENDING]        - Gold background, dark gold text
[UNDER REVIEW]   - Blue background, dark blue text
[NEEDS REVISION] - Orange background, dark orange text
[REJECTED]       - Red background, dark red text
[APPROVED]       - Green background, dark green text
[PUBLISHED]      - Primary gradient, white text
[COMPLETED]      - Grey background, grey text
```

### 10.3 Locker Release Stepper

```
+------------------------------------------+
|  RELEASE YOUR LOCKER                     |
+------------------------------------------+
|                                          |
|  (1) [GREEN CHECK]  Release Requested    |
|   |                 Submitted today      |
|   |                                      |
|  (2) [RED ACTIVE]   Visit Admin Office   |
|   |                 Return your key      |
|   |                                      |
|  (3) [GREY PENDING] Scan Return QR       |
|   |                 Verify key return    |
|   |                                      |
|  (4) [GREY PENDING] Release Approved     |
|                     Deposit refunded     |
|                                          |
+------------------------------------------+
```

### 10.4 Key Collection QR Flow

```
STUDENT SIDE (MyLockerScreen):
+------------------------------------------+
|  KEY COLLECTION                          |
+------------------------------------------+
|  Your locker key is ready for pickup.    |
|  Visit the admin office and scan the QR  |
|  code to confirm collection.             |
|                                          |
|  +------------------------------------+ |
|  | [QR icon] Enter QR code here...     | |
|  +------------------------------------+ |
|                                          |
|  [======= Verify & Collect Key ========] |
+------------------------------------------+

ADMIN SIDE (AdminLockerDetailScreen):
+------------------------------------------+
|  [QR CODE icon]                          |
|  Generate Key Collection QR              |
|  Student will scan this to confirm       |
|  key pickup                              |
|  -> Tap to generate                      |
+------------------------------------------+
```

---

*This blueprint documents all three system overhauls (Notification, Event Management, Locker Management) with exact file locations, code specifications, data model changes, and visual references. Use this as a systematic guide for implementation.*
