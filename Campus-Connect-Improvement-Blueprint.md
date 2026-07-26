# Campus Connect - Improvement Blueprint v3.0
## Changes & Enhancements Requested
### Based on User Feedback Analysis

---

## TABLE OF CONTENTS

1. [Summary of Requested Changes](#1-summary-of-requested-changes)
2. [Feature 1: Found Report Step-by-Step Flow](#2-feature-1-found-report-step-by-step-flow)
3. [Feature 2: Auto-Save Login Credentials](#3-feature-2-auto-save-login-credentials)
4. [Feature 3: Admin User Analytics Dashboard](#4-feature-3-admin-user-analytics-dashboard)
5. [Feature 4: Improved Notification System](#5-feature-4-improved-notification-system)
6. [Feature 5: Auto-Match Notification for Lost Items](#6-feature-5-auto-match-notification-for-lost-items)
7. [Feature 6: Personalized Notifications](#7-feature-6-personalized-notifications)
8. [File-by-File Change Map](#8-file-by-file-change-map)
9. [New Files Required](#9-new-files-required)
10. [Data Model Changes](#10-data-model-changes)
11. [Priority & Implementation Order](#11-priority--implementation-order)

---

## 1. SUMMARY OF REQUESTED CHANGES

| # | Feature | Category | Complexity | Priority |
|---|---------|----------|------------|----------|
| 1 | Found Report step-by-step handover flow with QR proof | Lost & Found | High | P0 - Critical |
| 2 | Auto-save login credentials (Remember Me) | Authentication | Medium | P1 - Important |
| 3 | Admin can see total accounts, active users, analytics | Admin Dashboard | Medium | P1 - Important |
| 4 | Notifications show title only, hide sensitive details | Notifications | Medium | P0 - Critical |
| 5 | Auto-match notification when lost item matches found item in inventory | Lost & Found | High | P0 - Critical |
| 6 | Personal notifications (match alerts sent only to the reporter) | Notifications | Medium | P1 - Important |

---

## 2. FEATURE 1: Found Report Step-by-Step Flow

### Current Behavior
- Student submits a found report -> instantly shows "In Inventory" status
- No guided step-by-step process after submission
- QR code flow exists but is not presented as a clear multi-step journey

### Requested Behavior
After a student makes a found report, the flow should be a **step-by-step process**:

```
Step 1: Submit Found Report       [DONE - tick mark]
Step 2: Go to Inventory Office    [PENDING / IN PROGRESS]
Step 3: Hand over the item        [PENDING]
Step 4: Scan QR from staff        [PENDING]
Step 5: Handover Confirmed        [tick mark on completion]
```

### Changes Required

#### File: `lib/screens/lost_found/lost_found_screens.dart`

**A) Modify `ReportFoundScreen` success view (Lines ~118-119)**
- **CURRENT:** Shows a simple `_SuccessView` with message "Thank you! Please hand the item to the Lost & Found Office."
- **NEW:** Replace with a `_FoundReportStepperView` widget that shows a vertical stepper/timeline:
  - Step 1: "Report Submitted" - checked/completed
  - Step 2: "Visit Inventory Office (Block A, Level 1)" - current step, highlighted
  - Step 3: "Hand over the item to staff" - pending
  - Step 4: "Scan QR code from inventory staff" - pending
  - Step 5: "Handover Confirmed" - pending
- Include a "View My Found Reports" button to navigate and track progress
- Include a "Back to Hub" button

**B) Modify `FoundDetailScreen` (Lines ~243-374)**
- **CURRENT:** Shows card details + QR scan section separately
- **NEW:** Add a **progress stepper** at the top of the detail screen that reflects the current handover stage:
  - When `status == 'In Inventory'` and `qrCode == null`: Steps 1 done, Step 2 active
  - When `qrCode != null` and `!qrScanned`: Steps 1-2 done, Step 3 active (show QR input)
  - When `qrScanned == true`: All steps done, show success tick mark with confetti/celebration UI
- The stepper should be a new shared widget `_HandoverStepper` with parameters:
  - `currentStep: int` (0-4)
  - Each step shows: step number, title, subtitle, icon, completed state

**C) Modify `FoundReport` data model in `lib/data/mock_data.dart`**
- Add new field: `int handoverStep` (default: 1, range 1-5) to track which step the user is on
- Update existing `FoundReport` constructor and all usages

**D) Modify `DataService` in `lib/services/data_service.dart`**
- `addFoundReport()`: Set initial `handoverStep = 1`
- `generateReceiveQR()`: Update `handoverStep = 3`
- `scanReceiveQR()`: Update `handoverStep = 5` on success
- Add new method: `updateHandoverStep(String foundReportId, int step)`

### New Widget: `_HandoverStepper`

```
Design Spec:
- Vertical stepper layout
- Each step: Circle (24px) with step number or check icon
- Active step: Red gradient circle, bold title
- Completed step: Green circle with check, strike-through or muted title
- Pending step: Grey circle, muted title
- Vertical connector line between steps (2px, colored based on completion)
- Step titles:
  1. "Report Submitted"
  2. "Visit Inventory Office"
  3. "Hand Over Item"
  4. "QR Verification"
  5. "Handover Complete"
```

---

## 3. FEATURE 2: Auto-Save Login Credentials

### Current Behavior
- Login screen has no "Remember Me" option
- Credentials are not saved between sessions
- Users must re-enter Student ID and password every time

### Requested Behavior
- Add a "Remember Me" toggle/checkbox on the login screen
- If enabled, save the Student ID and password locally (SharedPreferences)
- On next app launch, auto-fill the saved credentials
- Must ask user for permission/consent before saving
- Clear saved credentials on explicit logout

### Changes Required

#### File: `lib/screens/auth/login_screen.dart`

**A) Add "Remember Me" checkbox (after the "Forgot Password?" row, ~Line 155)**
- **NEW:** Add a `Row` with:
  - `Checkbox` widget with `_rememberMe` state variable
  - Text: "Remember my credentials" (12px, w600, textSecondary)
- Checkbox uses `AppTheme.red` as active color

**B) Modify `_handleLogin()` method (~Line 43)**
- **AFTER** successful login, check if `_rememberMe` is true
- If true, call `AuthService.saveCredentials(id, password)` to persist
- If false, call `AuthService.clearSavedCredentials()`

**C) Modify `initState()` (~Line 30)**
- On init, call `AuthService.loadSavedCredentials()`
- If credentials exist, pre-fill `_idCtrl` and `_passCtrl`
- Set `_rememberMe = true` if credentials were loaded

#### File: `lib/services/auth_service.dart`

**A) Add credential persistence methods:**
```dart
// New imports needed
import 'package:shared_preferences/shared_preferences.dart';

// New methods:
Future<void> saveCredentials(String id, String password) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('saved_user_id', id);
  await prefs.setString('saved_password', password);
  await prefs.setBool('remember_me', true);
}

Future<Map<String, String>?> loadSavedCredentials() async {
  final prefs = await SharedPreferences.getInstance();
  final remember = prefs.getBool('remember_me') ?? false;
  if (!remember) return null;
  final id = prefs.getString('saved_user_id');
  final pass = prefs.getString('saved_password');
  if (id != null && pass != null) return {'id': id, 'password': pass};
  return null;
}

Future<void> clearSavedCredentials() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('saved_user_id');
  await prefs.remove('saved_password');
  await prefs.setBool('remember_me', false);
}
```

#### File: `pubspec.yaml`

- **ADD** dependency: `shared_preferences: ^2.2.0` (if not already present)

#### File: `lib/services/app_state.dart`

- Expose credential save/load/clear methods through `AppState` so the login screen can call them

---

## 4. FEATURE 3: Admin User Analytics Dashboard

### Current Behavior
- Admin dashboard (Lost & Found) only shows lost/found/match stats
- No visibility into how many students are using the app
- No total account count or active user tracking

### Requested Behavior
- Admin should see:
  - Total registered accounts
  - Total active accounts (logged in at least once)
  - Total currently online/active users (approximate)
  - Breakdown by role (students vs admins)
- This should be visible from the admin dashboard

### Changes Required

#### File: `lib/screens/lost_found/lost_found_screens.dart`

**A) Modify `AdminLFDashboardScreen` (~Line 420-449)**
- **ADD** a new section after "Admin Tools":
  - `SectionLabel('User Analytics')`
  - Stats Row with:
    - Total Accounts (count from AuthService)
    - Active Users (approximation or tracking)
    - Pending Registrations
  - A `HubButton` linking to a new Admin User Analytics screen (or inline)

#### File: `lib/services/auth_service.dart`

**A) Add user analytics methods:**
```dart
int get totalStudentAccounts => _studentAccounts.length;
int get totalAdminAccounts => _adminAccounts.length;
int get totalAccounts => totalStudentAccounts + totalAdminAccounts;
```

#### File: `lib/services/app_state.dart`

**A) Expose user analytics:**
```dart
int get totalAccounts => _authService.totalAccounts;
int get totalStudentAccounts => _authService.totalStudentAccounts;
int get totalAdminAccounts => _authService.totalAdminAccounts;
```

#### Optional: New Screen `AdminUserAnalyticsScreen`

If a dedicated screen is desired:
- Route: `/admin/user-analytics`
- Shows: Total accounts, active students, pending registrations, role breakdown
- Could include a simple list of registered student IDs

---

## 5. FEATURE 4: Improved Notification System

### Current Behavior
- Notifications show full details including item descriptions
- Lost and found report notifications include the item description in the notification text
- All notifications are visible to everyone

### Requested Behavior
- Notifications should show **title only**, NOT the description
- For Lost & Found: "Someone just posted a lost item" or "Someone just posted a found item"
- For Events: "A new event has been created" (title only, no details)
- For Issues: "A new issue has been reported" (title only, no details)
- **Hide important/sensitive descriptions** from notification text
- Keep full details accessible only when the user navigates to the actual report

### Changes Required

#### File: `lib/services/data_service.dart`

**A) Modify `addLostReport()` (~Line 45-61)**
- **CURRENT:** `'A new lost item was reported: ${report.title}'`
- **NEW:** `'Someone just posted a lost item report'`
- Remove the item title from notification text

**B) Modify `addFoundReport()` (~Line 63-69)**
- **CURRENT:** `'A found item was reported: ${report.description}'`
- **NEW:** `'Someone just reported a found item'`
- Remove the description from notification text

**C) Modify `reportIssue()` (~Line 213-221)**
- **CURRENT:** `'A new issue was reported: ${issue.title}'`
- **NEW:** `'A new campus issue has been reported'`

**D) Modify `createEvent()` (~Line 266-274)**
- **CURRENT:** `'A new event waiting for approval: ${event.title}'`
- **NEW:** `'A new event has been submitted for approval'`

**E) Modify `approveEvent()` (~Line 293)**
- **CURRENT:** `'Event approved: ${event.title}'`
- **NEW:** `'An event has been approved and published'`

**F) Review ALL `_addNotification()` calls across the file**
- Replace any notification that exposes sensitive/detailed information with a generic title-only version
- Status update notifications can remain as-is since they are personal (e.g., "Lost report LR-001 status updated to Resolved")

#### File: `lib/data/mock_data.dart`

**G) Update mock notification data**
- Update the pre-populated notifications to use the new title-only format

---

## 6. FEATURE 5: Auto-Match Notification for Lost Items

### Current Behavior
- AI match scoring exists in admin view but is static (mock data)
- No automatic notification to students when their lost item matches a found item
- Students have to manually check their reports

### Requested Behavior
- When a found item is added to inventory, the system should check if it matches any active lost reports
- Matching criteria: same `category` + similar `location` (same block or nearby)
- If a match is found, send a **personal notification** to the lost item reporter:
  - "Your lost item may have been found! Please check your lost report for details."
- The notification should be `type: 'personal'` so only the reporter sees it
- Update the lost report's `matchStatus` field with match info

### Changes Required

#### File: `lib/services/data_service.dart`

**A) Modify `addFoundReport()` method**
- **AFTER** adding the found report to the list, run a matching check:
```dart
void _checkForMatches(FoundReport foundReport) {
  for (var lost in myLostReports) {
    if (lost.status == 'Active' && lost.category == foundReport.category) {
      // Category match found - send personal notification
      _addNotification(
        'Your lost item may have been found! Check your report ${lost.id} for updates.',
        'personal',
      );
      // Update the lost report's matchStatus
      final index = myLostReports.indexOf(lost);
      myLostReports[index] = LostReport(
        id: lost.id, title: lost.title, category: lost.category,
        whereLost: lost.whereLost, whenLost: lost.whenLost,
        status: lost.status, description: lost.description,
        photos: lost.photos,
        matchStatus: 'Potential match found! A similar ${lost.category} item is now in inventory.',
      );
    }
  }
}
```

**B) Call `_checkForMatches()` at the end of `addFoundReport()`**

#### File: `lib/data/mock_data.dart`

**C) Update `Notification` model if needed**
- Add optional fields: `relatedScreen` and `relatedId` to enable tapping a notification to navigate to the related report
- **CURRENT:** `relatedScreen` and `relatedId` already exist in the model - just ensure they are populated for match notifications

---

## 7. FEATURE 6: Personalized Notifications

### Current Behavior
- Notifications have a `type` field (`personal`, `admin`, `campaign`)
- All notifications appear in the same list regardless of type
- No filtering by user or role

### Requested Behavior
- Personal notifications (match alerts, status updates) should only show to the specific user
- Generic notifications (someone posted lost/found, events) can be public
- Match notifications must be personal and only visible to the item reporter

### Changes Required

#### File: `lib/data/mock_data.dart`

**A) Update `Notification` model**
- Add field: `String? targetUserId` - if set, only show to that user
- Null means visible to everyone

#### File: `lib/services/data_service.dart`

**B) Modify `_addNotification()` method**
- Add optional parameter: `String? targetUserId`
- Pass through to the Notification constructor

**C) Add filtered notification getter:**
```dart
List<Notification> getNotificationsForUser(String? userId) {
  return notifications.where((n) {
    if (n.targetUserId == null) return true; // Public notification
    return n.targetUserId == userId; // Personal notification for this user
  }).toList();
}
```

**D) Modify match notifications to include `targetUserId`**
- When creating match notifications, set `targetUserId` to the student who made the lost report

#### File: `lib/screens/lost_found/lost_found_screens.dart`

**E) Modify `NotificationsScreen` (~Line 377)**
- Use `getNotificationsForUser(appState.userId)` instead of `dataService.notifications`
- Import and use `AppState` to get current user ID

#### File: `lib/main.dart`

**F) Modify notification badge count in header (~Line 116)**
- Use filtered notification count based on current user

---

## 8. FILE-BY-FILE CHANGE MAP

| File | Changes | Sections Affected |
|------|---------|-------------------|
| `lib/screens/lost_found/lost_found_screens.dart` | Stepper widget, FoundDetail stepper, AdminDashboard analytics section, Notifications filtering | ReportFoundScreen, FoundDetailScreen, AdminLFDashboardScreen, NotificationsScreen |
| `lib/screens/auth/login_screen.dart` | Remember Me checkbox, auto-fill logic | _LoginScreenState |
| `lib/services/auth_service.dart` | Credential persistence, user analytics getters | New methods |
| `lib/services/app_state.dart` | Expose analytics + credential methods | New methods |
| `lib/services/data_service.dart` | Notification text changes, auto-match logic, notification filtering, handover step tracking | addLostReport, addFoundReport, reportIssue, createEvent, _addNotification, new methods |
| `lib/data/mock_data.dart` | FoundReport handoverStep field, Notification targetUserId field, mock data updates | Model classes, MockData constants |
| `lib/main.dart` | Filtered notification badge count | AppShell header |
| `pubspec.yaml` | shared_preferences dependency | dependencies |

---

## 9. NEW FILES REQUIRED

No new files are strictly required. All changes can be made within existing files. However, if the codebase grows, consider:

| Potential New File | Purpose | When to Create |
|---|---|---|
| `lib/widgets/handover_stepper.dart` | Extract the `_HandoverStepper` widget for reusability | If the stepper is used in more than 2 screens |
| `lib/screens/admin/admin_analytics_screen.dart` | Dedicated admin user analytics page | If analytics section becomes complex |

---

## 10. DATA MODEL CHANGES

### `FoundReport` (in `lib/data/mock_data.dart`)

```dart
// ADD new field:
class FoundReport {
  // ... existing fields ...
  final int handoverStep; // NEW: 1-5, tracks stepper progress

  const FoundReport({
    // ... existing params ...
    this.handoverStep = 1, // NEW
  });
}
```

### `Notification` (in `lib/data/mock_data.dart`)

```dart
// ADD new field:
class Notification {
  // ... existing fields ...
  final String? targetUserId; // NEW: if set, only show to this user

  const Notification({
    // ... existing params ...
    this.targetUserId, // NEW
  });
}
```

---

## 11. PRIORITY & IMPLEMENTATION ORDER

### Phase 1 - Critical (Implement First)
1. **Notification Privacy** (Feature 4) - Quick win, change notification text strings
2. **Found Report Stepper Flow** (Feature 1) - Core UX improvement
3. **Auto-Match Notifications** (Feature 5) - High-value feature

### Phase 2 - Important (Implement Second)
4. **Personalized Notifications** (Feature 6) - Depends on Feature 4 & 5
5. **Auto-Save Login** (Feature 2) - UX convenience
6. **Admin User Analytics** (Feature 3) - Admin visibility

### Estimated Scope
- **Total screens modified:** 5-6 existing screens
- **Total files modified:** 7-8 files
- **New widgets:** 1 (HandoverStepper)
- **New data fields:** 2 (handoverStep, targetUserId)
- **New dependencies:** 1 (shared_preferences)

---

## 12. VISUAL REFERENCE: Found Report Stepper Design

```
+------------------------------------------+
|  FOUND REPORT PROGRESS                   |
+------------------------------------------+
|                                          |
|  (1) [GREEN CHECK]  Report Submitted     |
|   |                 Mar 26, 2026         |
|   |                                      |
|  (2) [RED ACTIVE]   Visit Inventory      |
|   |                 Office Block A, L1   |
|   |                                      |
|  (3) [GREY PENDING] Hand Over Item       |
|   |                 Give item to staff   |
|   |                                      |
|  (4) [GREY PENDING] QR Verification      |
|   |                 Scan staff QR code   |
|   |                                      |
|  (5) [GREY PENDING] Handover Complete    |
|                     All done!            |
|                                          |
+------------------------------------------+
```

### Stepper Colors
- **Completed step circle:** Green (#4CAF50), white check icon
- **Active step circle:** Red gradient (#C41E3A -> #E8475F), white step number
- **Pending step circle:** Grey (#B0BEC5), grey step number
- **Completed connector line:** Green (#4CAF50), 2px
- **Active connector line:** Red (#C41E3A), 2px
- **Pending connector line:** Grey (#E0E0E0), 2px dashed

---

*This blueprint documents all requested changes with exact file locations, line references, and implementation details. Use this as a guide for systematic implementation of Campus Connect v3.0 improvements.*
