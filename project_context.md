# Campus Connect — Full Project Context
> **Purpose of this file:** Paste this entire file into any AI tool (ChatGPT, Claude, Perplexity, Gemini, etc.) as context so it fully understands your project before you ask questions or request help.

---

## 1. Project Summary

**Name:** Campus Connect
**Type:** Flutter mobile application (Android/iOS)
**Purpose:** A comprehensive campus management system for a university that digitises five core campus services into one app.
**Current State:** Fully functional prototype using in-memory mock data (no Firebase yet). All screens and business logic are implemented. UI is complete with a custom red/dark gradient theme.

**Two user types:**
- **Students** — submit reports, book lockers, join and create events, track issues
- **Admins** — approve/reject everything, manage all data across all modules

---

## 2. Technology Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3.x (Dart) |
| State Management | Provider (`ChangeNotifier`) — `Consumer`, `Consumer2` |
| Navigation | GoRouter (declarative routing) |
| Local Storage | `shared_preferences` (credentials + profile overrides) |
| QR Code | `qr_flutter` (generate), `mobile_scanner` (scan) |
| File Picker | `file_picker` (PDF approval letters, photos) |
| Animation | `flutter_animate` |
| Clipboard | `flutter/services.dart` — `Clipboard.setData` |
| Theme | Custom `AppTheme` — dark cards, red gradient header |
| Data Layer | In-memory (`MockData` seeds → `DataService` mutable lists) |

---

## 3. Project File Structure

```
lib/
├── main.dart                          ← App entry, all GoRouter routes, AppShell
├── data/
│   └── mock_data.dart                 ← All data models + seed data (MockData class)
├── services/
│   ├── data_service.dart              ← All business logic, state, notifyListeners()
│   ├── auth_service.dart              ← Login, logout, credentials, profiles
│   ├── app_state.dart                 ← Thin wrapper: userId, isAdmin, userName
│   └── photo_service.dart             ← PhotoUploadService (image handling)
├── screens/
│   ├── auth/
│   │   ├── splash_screen.dart
│   │   ├── login_screen.dart
│   │   └── registration_screen.dart
│   ├── lost_found/
│   │   └── lost_found_screens.dart    ← All L&F screens in one file
│   ├── issues/
│   │   └── issues_screens.dart        ← All Issues screens in one file
│   ├── events/
│   │   ├── events_screens.dart        ← EventsHubScreen, EventDetailScreen, CreateEventScreen, AdminEventsListScreen, etc.
│   │   ├── my_events_screen.dart      ← MyEventsScreen, MyEventDetailScreen, AdminPendingEventDetailScreen
│   │   └── manage_event_screen.dart   ← ManageMyEventScreen (4-tab creator dashboard)
│   ├── lockers/
│   │   └── lockers_screens.dart       ← All Locker screens in one file
│   ├── admin/
│   │   └── admin_registrations_screen.dart
│   └── profile/
│       └── profile_screen.dart
├── theme/
│   └── app_theme.dart                 ← AppTheme colors, gradients, TextStyles
└── widgets/
    ├── common.dart                    ← Shared widgets: CardRow, GradientButton, EmptyState, SectionLabel, etc.
    └── (other widget files)
```

---

## 4. User Roles & Test Credentials

### Student Accounts
| Student ID | Password | Name |
|---|---|---|
| S001 | pass123 | Ahmad Rizwan |
| S002 | pass123 | Fatima Hassan |
| S003 | pass123 | Mohammad Ali |

### Admin Accounts
| Admin ID | Password | Name |
|---|---|---|
| ADMIN001 | admin123 | Admin Panel |
| ADMIN002 | admin123 | Manager Account |

### Login Toggle
The LoginScreen has a toggle switch to switch between Student and Admin login mode.

---

## 5. Architecture & Patterns

### State Management
- `DataService extends ChangeNotifier` — single source of truth for all data
- `AuthService extends ChangeNotifier` — handles authentication state
- `AppState extends ChangeNotifier` — wraps AuthService, exposes `userId`, `isAdmin`, `userName`
- All screens use `Consumer<DataService>` or `Consumer2<DataService, AppState>` to rebuild on data changes
- Every data mutation ends with `notifyListeners()` to trigger UI rebuild
- `DataService.refresh()` — public method to force a rebuild (used by pull-to-refresh)

### Navigation
- GoRouter with `ShellRoute` for the bottom navigation bar (4 tabs)
- Admin routes all prefixed with `/admin/`
- Student routes are flat (e.g., `/events/create`, `/lockers/my-locker`)
- Navigate with `context.push('/route')` and `context.pop()`

### Role-Based Access Control
- UI elements conditionally shown based on `appState.isAdmin`
- Event creator features check `event.hostStudentId == appState.userId`
- File access: `DataService.canAccessFilePath()` — admins always, students only own events
- Event actions: `DataService.canPerformAction()` — creator = full access, team roles = permission-based

### Data Duplication Pattern
Several lists exist in parallel — one for student view, one for admin:
- `myLostReports` (student) ↔ `allLostReports` (admin)
- `myIssues` (student) ↔ `allIssues` (admin)
- `allEvents` (published) ↔ `pendingEvents` (awaiting approval)
When admin updates, both lists are synced simultaneously.

---

## 6. Complete Route Table

```
/                          → SplashScreen
/login                     → LoginScreen
/register                  → RegistrationScreen
/profile                   → ProfileScreen

── Bottom Nav Shell ──
/lost-found                → LostFoundHubScreen
/issues                    → IssuesHubScreen
/events                    → EventsHubScreen
/lockers                   → LockerHubScreen

── Lost & Found ──
/lost-found/report-lost    → ReportLostScreen
/lost-found/report-found   → ReportFoundScreen
/lost-found/my-lost        → MyLostReportsScreen
/lost-found/my-found       → MyFoundReportsScreen
/lost-found/lost/:id       → LostDetailScreen
/lost-found/found/:id      → FoundDetailScreen
/lost-found/notifications  → NotificationsScreen

── Admin Lost & Found ──
/admin/lost-found/lost-list    → AdminLostListScreen
/admin/lost-found/found-list   → AdminFoundListScreen
/admin/lost-found/match-list   → AdminMatchListScreen
/admin/lost-found/lost/:id     → AdminLostDetailScreen
/admin/lost-found/found/:id    → AdminFoundDetailScreen
/admin/lost-found/match/:id    → AdminMatchDetailScreen

── Issues ──
/issues/report             → ReportIssueScreen
/issues/my-issues          → MyIssuesScreen
/issues/detail/:id         → IssueDetailScreen

── Admin Issues ──
/admin/issues/list         → AdminIssuesListScreen
/admin/issues/detail/:id   → AdminIssueDetailScreen

── Events ──
/events/create             → CreateEventScreen
/events/my-events          → MyEventsScreen
/events/my-events/:id      → MyEventDetailScreen
/events/manage/:id         → ManageMyEventScreen
/events/detail/:id         → EventDetailScreen
/events/elections          → ElectionsInfoScreen

── Admin Events ──
/admin/events/list         → AdminEventsListScreen
/admin/events/pending/:id  → AdminPendingEventDetailScreen
/admin/events/editor       → AdminEventEditorScreen (new event)
/admin/events/editor/:id   → AdminEventEditorScreen (edit existing)
/admin/events/elections    → AdminElectionsMgmtScreen

── Lockers ──
/lockers/browse            → BrowseLockersScreen
/lockers/detail/:id        → LockerBookingScreen
/lockers/my-locker         → MyLockerScreen

── Admin Lockers ──
/admin/lockers/list        → AdminLockersListScreen
/admin/lockers/detail/:id  → AdminLockerDetailScreen

── Admin Other ──
/admin/registrations       → AdminRegistrationsScreen
```

---

## 7. All Data Models (from mock_data.dart)

### LostReport
```dart
String id, title, category, whereLost, whenLost, status, description
int photos
String? matchStatus
```

### FoundReport
```dart
String id, description, category, whereFound, whenFound, status
int photos, handoverStep  // handoverStep: 1-5
String? handoverStatus    // null | 'Pending Handover' | 'Handed Over' | 'Claimed'
String? qrCode
bool qrScanned
```

### AdminLostReport
```dart
String id, studentId, title, category, whereLost, status, createdDate
int? aiScore              // AI match confidence 0-100
String? matchedFoundId
```

### LfMatch
```dart
String id, lostId, foundId, status, notes
int score                 // AI confidence score
```

### Issue
```dart
String id, title, category, location, status, createdDate, updatedDate, description
String? studentId
List<String> imagePaths
```
**Status values:** `New` → `Triaged` → `Assigned` → `In Progress` → `Resolved`
**Categories:** `Facilities`, `IT`, `Safety`, `Cleanliness`

### IssueHistory
```dart
String date, to          // 'to' = new status
String? from, note       // 'from' = old status
```

### Event
```dart
String id, title, date, time, location, category, organizer, description, status
String? hostStudentId    // student who created it (set on create)
String? approvalLetterPath, approvalLetterName
bool hasApprovalLetter
String? rejectionReason  // set on rejectEvent()
String? revisionNotes    // set on requestEventRevision()
List<EventMessage>? messages
int revisionCount
String? submittedDate
String eventType         // 'Open' | 'Club' | 'Club+Payment' | 'Paid'
bool isPrivate, clubIdRequired, isPaid
double price
List<String> attendeeIds, pendingJoiningIds
String? qrTicketPath
```
**Status values:** `Pending` → `Under Review` → `Needs Revision` → (resubmit) → `Published` | `Rejected`

### EventMessage
```dart
String id, senderId, senderRole, message, timestamp
String? attachmentName
// senderRole: 'admin' | 'student'
```

### EventJoining
```dart
String id, eventId, studentId, name, courseName, joinedDate
String? clubId
String status            // 'Pending' | 'Approved' | 'Rejected'
String? paymentStatus    // null | 'Pending' | 'Completed'
String? qrTicketCode     // generated on approval
bool hasAttended
```

### EventRole
```dart
String id, eventId, studentId, studentName
String role              // 'Organizer' | 'Staff' | 'Volunteer'
List<String> permissions // 'scan_qr' | 'manage_participants' | 'edit_event'
```

### Locker
```dart
String id, location, status, lockType  // lockType: 'key' | 'digital'
String? studentId, endDate, startDate
int? daysLeft
String? digitalCode      // 4-digit code for digital locks
double monthlyRent       // RM 10.00
double deposit           // RM 100.00
bool depositRefunded
```
**Status values:** `Available` | `Pending Pickup` | `Active` | `Overdue` | `Blocked`

### LockerBooking
```dart
String id, lockerId, location, startDate, endDate, status
int daysLeft, durationMonths  // 2–12 months
double monthlyRent, deposit, totalPaid  // totalPaid = deposit + first month = RM110
String? keyCollectionQR, keyReturnQR
bool keyCollected, keyReturned
String? keyCollectionDate, keyReturnDate
String? releaseStatus    // null | 'Requested' | 'Pending Return' | 'Returned' | 'Completed'
```

### LockerIssue
```dart
String id, lockerId, studentId, description, status, reportedDate
int photoCount
// status: 'Reported' | 'Under Review' | 'Resolved'
```

### LockerHistory
```dart
String action, staffId, timestamp
String? reason
```

### Notification
```dart
String id, type, text, time, source
String visibility        // 'all' | 'student' | 'admin'
String? detailText, relatedScreen, relatedId, targetUserId
bool read
// source: 'lost_found' | 'events' | 'lockers' | 'issues' | 'system'
```

### StudentRegistration
```dart
String id, studentId, name, email, faculty, password, status, submittedDate
// status: 'Pending' | 'Approved' | 'Rejected'
```

### UserProfile (AuthService)
```dart
String userId, role, name, email, programme, phone
// role: 'student' | 'admin'
```

### Candidate (Elections)
```dart
String id, name, programme, position, manifesto
```

---

## 8. DataService — Key Methods Reference

### Lost & Found
```dart
addLostReport(LostReport)                          // student submits lost report
addFoundReport(FoundReport)                        // student submits found report
updateLostReportStatus(id, newStatus)              // student updates own report
updateAdminLostReportStatus(id, newStatus)         // admin updates + syncs to student view
updateFoundReportStatus(id, newStatus)             // update found report status
generateReceiveQR(foundReportId)  → String         // admin: QR for found item receive
scanReceiveQR(foundReportId, qrCode)  → bool       // student: scan QR to confirm handover
generateHandoverQR(foundReportId)  → String        // admin: QR for item claiming
completeHandover(foundReportId)                    // finalize claim, status = Resolved
```

### Issues
```dart
reportIssue(Issue)                                 // student submits issue
updateIssueStatus(id, newStatus)                   // admin: update + sync + add history
deleteIssue(id)                                    // admin: remove from both lists
```

### Events
```dart
createEvent(Event)                                 // student: adds to pendingEvents (hostStudentId required)
approveEvent(id)                                   // admin: moves to allEvents, status = Published
setEventUnderReview(id)                            // admin: status = Under Review
requestEventRevision(id, revisionNotes)            // admin: status = Needs Revision
rejectEvent(id, {String reason})                   // admin: status = Rejected
resubmitEvent(id, Event)  → bool                   // student: resets to Pending, revisionCount++
updateEventDetails(id, Event)  → bool              // creator: edit event details
markEventCompleted(id)                             // admin: status = Completed
deleteEvent(id)                                    // admin: remove from all/pending lists
sendEventNotice(id, message)                       // admin: send notice to creator
addEventMessage(eventId, senderId, senderRole, message)  // admin/student: chat thread

getEventById(id)  → Event?                         // searches both pendingEvents + allEvents
getEventsForHost(hostStudentId)  → List<Event>     // events created by specific student
```

### Event Joining
```dart
requestJoinEvent(eventId, studentId, name, courseName, {clubId})  → EventJoining
quickJoinEvent(eventId, studentId, name, courseName)  → bool      // open free events only
completePaymentAndJoin(joiningId, amountPaid)  → bool             // paid events
approveEventJoining(joiningId)                                     // creator/admin approve
rejectEventJoining(joiningId, {String reason})                     // creator/admin reject
getJoiningRequestsForEvent(eventId)  → List<EventJoining>          // all records for event
getJoiningRecord(eventId, studentId)  → EventJoining?              // approved record for student
getJoiningById(joiningId)  → EventJoining?                         // fetch by ID
getEventAttendees(eventId)  → List<EventJoining>                   // approved attendees only
getUserJoinedEvents(studentId)  → List<EventJoining>               // student's joined events
verifyAndMarkAttendance(eventId, qrCode)  → bool                   // scan QR at entry
toggleManualAttendance(joiningId)                                  // manual check-in toggle
```

### Event Roles
```dart
getRolesForEvent(eventId)  → List<EventRole>
assignRole({eventId, studentId, studentName, role, permissions})
removeRole(roleId)
canPerformAction(eventId, userId, action)  → bool
```

### Lockers
```dart
bookLocker(lockerId, {durationMonths})             // student: creates booking + updates locker
requestLockerExtension(bookingId, additionalMonths)  → bool
requestLockerRelease(bookingId)                    // student: initiates release
releaseBooking(bookingId)                          // alias for requestLockerRelease
reportLockerIssue(lockerId, description, photoCount)
updateLockerStatus(lockerId, newStatus)            // admin: flexible status update
terminateLocker(lockerId)                          // admin: force release, deposit forfeited
blockLocker(lockerId, {reason})                    // admin: block locker
releaseLockerAdmin(lockerId)                       // admin: mark released
```

### Notifications
```dart
markNotificationAsRead(id)
addNotification(message, type)
refresh()                                          // force notifyListeners() — for pull-to-refresh
```

---

## 9. AuthService — Key Methods Reference

```dart
login(id, password, isAdminLogin)  → Future<bool>
logout()
switchRole(id, password, toAdmin)
addApprovedStudent(studentId, password, name, {email, programme, phone})
getCurrentUserProfile()  → UserProfile?
updateCurrentUserProfile({name, email, programme, phone})  → Future<bool>
isStudentIdTaken(studentId)  → bool
saveCredentials(id, password)                      // Remember Me
loadSavedCredentials()  → Future<Map<String,String>?>
clearSavedCredentials()
```

---

## 10. Module Summaries

### Module 1: Lost & Found Management
- Students report lost or found items with category, location, date, description, photos
- AI matching engine cross-references reports and assigns confidence scores (`aiScore` 0–100)
- Admin reviews matches and confirms/rejects
- 5-step QR handover process tracks physical item transfer from admin to student
- Notification system alerts students of match status changes

### Module 2: Issue Management
- Students report campus problems (facilities, IT, safety, cleanliness) with photos
- Full audit trail in `issueHistory` — every status change logged with timestamp and note
- Admin progresses issues: `New → Triaged → Assigned → In Progress → Resolved`
- Both admin and student lists synced in real time

### Module 3: Locker Management
- Students browse and self-book campus lockers (2–12 month duration)
- One locker per student enforced
- Supports key-type lockers (QR key collection/return) and digital-code lockers
- Pricing: RM 100 deposit + RM 10/month rent, paid upfront for first month
- Students can extend (when ≤30 days left) or release their locker
- Admin: activate, block, terminate, generate QR codes, view history

### Module 4: Event Management
- 4 event types: Open (free), Club (private), Club+Payment, Paid
- Student-created events go through: Pending → Under Review → Needs Revision / Rejected / Published
- Admin–student messaging thread during review process
- Creator gets 4-tab Management Dashboard: Overview, Participants, Roles, Entry/QR
- QR ticket system for registered attendees; QR scan for entry verification
- Team role system: Organizer / Staff / Volunteer with granular permissions

### Module 5: Admin Panel
- Unified admin interface governing all 4 modules plus student registrations
- No admin-specific navigation shell — uses route-based admin screens
- Student registrations: review, approve (creates live account), reject
- Elections management: manage candidate content and election timeline

---

## 11. ManageMyEventScreen — 4-Tab Dashboard

**Route:** `/events/manage/:id`
**Access:** Only `event.hostStudentId == appState.userId` OR assigned team member with permission

| Tab | Key Features |
|---|---|
| **Overview** | Status banner, stats (Registered / Pending / Attended), admin message thread, edit event dialog |
| **Participants** | Filter: All / Pending / Approved / Rejected, approve/reject requests, payment status badge, QR preview |
| **Roles** | Add Organizer / Staff / Volunteer, assign permissions (scan_qr, manage_participants, edit_event), remove roles |
| **Entry / QR** | Live QR camera scanner, `verifyAndMarkAttendance()`, progress bar, checked-in list, manual toggle |

---

## 12. MyEventsScreen — Status-Aware UI

**Route:** `/events/my-events`
- Shows all events created by `appState.userId` (searches both `pendingEvents` + `allEvents`)
- Pull-to-refresh: calls `dataService.refresh()`
- Status color coding:
  - `Published` = green
  - `Rejected` = red
  - `Needs Revision` = amber/gold
  - `Under Review` = blue
  - `Pending` = grey
- Published events show a **Manage** chip → navigates to `/events/manage/:id`

---

## 13. EventsHubScreen — My Submissions Strip

**Route:** `/events`
- Uses `Consumer2<DataService, AppState>` to show a "My Submissions" horizontal strip when user has created events
- Strip shows compact 180px cards with title, date, and status badge
- "My Events" button in toolbar shows count badge: `My Events (2)`
- Tapping a Published card → Manage Dashboard; others → MyEventDetailScreen

---

## 14. Notification System

Every significant action generates a notification via `DataService._addNotification()`:

| Attribute | Options |
|---|---|
| `type` | `public`, `private`, `personal` |
| `visibility` | `all`, `student`, `admin` |
| `targetUserId` | specific student ID or null |
| `source` | `lost_found`, `events`, `lockers`, `issues`, `system` |
| `relatedScreen` | screen route for deep linking |

---

## 15. Current Limitations & Future Work

| Item | Status |
|---|---|
| Database | ❌ No Firebase — all data is in-memory, lost on restart |
| Authentication | ⚠️ Mock credentials in source code (not production-safe) |
| Payment | ⚠️ Simulated — no real payment gateway |
| Photo upload | ⚠️ `PhotoUploadService` partially implemented — paths stored but not uploaded |
| Push notifications | ❌ In-app only — no FCM/APNs |
| Elections voting | ⚠️ UI only — no real vote casting logic |
| Multi-locker admin view | ✅ Complete |
| Event AI matching | ⚠️ Simulated score — no real NLP engine |

---

## 16. Common Widgets (common.dart)

```dart
GradientButton(label, onPressed)          // Red gradient primary button
OutlineBtn(label, onPressed)              // Outlined secondary button
CardRow(title, subtitle, trailing, onTap) // Standard list card
SectionLabel(text)                        // Section header text
EmptyState(title, subtitle, icon)         // Empty list placeholder
AdminBar()                                // Admin-only banner strip
```

---

## 17. Theme Constants (AppTheme)

```dart
AppTheme.red              // Primary red: Color(0xFFC41E3A)
AppTheme.bgApp            // Background: dark near-black
AppTheme.bgCard           // Card background: slightly lighter
AppTheme.textPrimary      // Main text color
AppTheme.textMuted        // Secondary/muted text
AppTheme.primaryGradient  // Red gradient (left to right)
AppTheme.headerGradient   // Dark-to-red gradient (AppBar)
AppTheme.theme            // Full MaterialApp ThemeData
```

---

## 18. How to Ask Other AIs for Help Using This File

**Paste this entire file** at the start of your conversation, then ask things like:

- *"Based on the project above, write a new screen for [feature]"*
- *"Add a [method] to DataService following the existing patterns"*
- *"Fix a bug where [describe issue] in [screen name]"*
- *"Generate unit tests for DataService event methods"*
- *"Write a Firebase migration plan for this project"*
- *"Create a new data model for [feature] following the existing model style"*
- *"Write an API design for a REST backend that matches this DataService"*
- *"Help me write Chapter 3 methodology based on this system"*
