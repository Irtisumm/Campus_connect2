# Campus Connect — Storyboard Guide

> **What is a Storyboard?**
> A storyboard is a sequence of app screenshots (or sketches) arranged like a comic strip, showing how a user moves through the app to complete a task. Each frame = one screen. Each arrow = one action (tap, swipe, submit).

---

## How to Use This Guide

1. Run the app on your emulator or phone
2. Navigate to each screen listed below
3. Take a screenshot of each screen
4. Arrange them in order using **Canva**, **Figma**, **PowerPoint**, or **Google Slides**
5. Add arrows between screens and label each action

---

## Recommended Flows to Include

Your project has **5 modules**. For a complete storyboard, cover these **4 flows**:

| Flow | Actor | Screens Needed | Purpose |
|---|---|---|---|
| **Flow A** | Student | 6 screens | Login → Browse Events → Join Event |
| **Flow B** | Student | 7 screens | Create & Submit Event → Admin Approves → Manage |
| **Flow C** | Student | 5 screens | Report Lost Item → Admin Matches → Claim |
| **Flow D** | Admin | 6 screens | Admin Panel full overview (all modules) |

> **Tip:** You do not have to include all four. For a minimum viable storyboard, do **Flow A + Flow B** — they tell the most complete story of your system.

---

---

# FLOW A — Student Joins an Event
**Actor:** Student (logged in as S001 / pass123)
**Goal:** Student browses campus events and joins one

---

### Frame 1 — Splash Screen
- **Route:** `/` (app launch)
- **Screen:** SplashScreen
- **What to show:** Campus Connect logo, loading animation
- **Label this frame:** *"User opens the Campus Connect app"*
- **Arrow action:** → Auto-redirects after 2 seconds

---

### Frame 2 — Login Screen
- **Route:** `/login`
- **Screen:** LoginScreen
- **What to show:** Login form filled in with Student ID and password. "Student" tab selected.
- **Highlight:** Student ID field, Password field, Login button
- **Label:** *"Student enters credentials and taps Login"*
- **Arrow action:** Tap **Login** →

---

### Frame 3 — Events Hub
- **Route:** `/events`
- **Screen:** EventsHubScreen
- **What to show:** List of upcoming events (Convocation, Badminton, AI Workshop etc.)
- **Highlight:** The event cards, the "My Events" button in the toolbar
- **Label:** *"Student sees all upcoming campus events"*
- **Arrow action:** Tap on an event card →

---

### Frame 4 — Event Detail
- **Route:** `/events/detail/EVT-002` (Inter-Faculty Badminton Tournament)
- **Screen:** EventDetailScreen
- **What to show:** Event title, date, location, description, Join button
- **Highlight:** The **Join Event** button at the bottom
- **Label:** *"Student views event details and decides to join"*
- **Arrow action:** Tap **Join Event** →

---

### Frame 5 — Join Confirmation / QR Ticket
- **Route:** Same screen (`/events/detail/EVT-002`) after joining
- **Screen:** EventDetailScreen — post-join state
- **What to show:** "You are registered!" banner, QR ticket code displayed
- **Highlight:** The QR code ticket, "Already Joined" status
- **Label:** *"Student is registered and receives a QR ticket"*
- **Arrow action:** Student saves/shows QR at event entry →

---

### Frame 6 — Notifications
- **Route:** `/lost-found/notifications`
- **Screen:** NotificationsScreen
- **What to show:** Notification: "Successfully joined event — your QR ticket has been generated"
- **Highlight:** The event joining notification card
- **Label:** *"Student receives in-app confirmation notification"*

---

**Flow A Summary Arrow Diagram:**
```
[Splash] → [Login] → [Events Hub] → [Event Detail] → [Joined + QR] → [Notification]
```

---
---

# FLOW B — Student Creates Event → Admin Approves → Student Manages
**Actor:** Student then Admin
**Goal:** Show the full event creation and approval lifecycle

---

### Frame 1 — Events Hub (Create button)
- **Route:** `/events`
- **Screen:** EventsHubScreen
- **What to show:** Hub with "➕ Create" button visible in toolbar
- **Highlight:** The **Create** button
- **Label:** *"Student taps Create to submit a new event"*
- **Arrow action:** Tap **➕ Create** →

---

### Frame 2 — Create Event Form
- **Route:** `/events/create`
- **Screen:** CreateEventScreen
- **What to show:** Form filled in — event title, date, location, category, organizer, description. PDF approval letter uploaded.
- **Highlight:** All filled fields, the uploaded approval letter, Submit button
- **Label:** *"Student fills in event details and uploads approval letter"*
- **Arrow action:** Tap **Submit for Approval** →

---

### Frame 3 — My Events (Pending Status)
- **Route:** `/events/my-events`
- **Screen:** MyEventsScreen
- **What to show:** The newly created event card with a yellow/grey **"Pending"** status badge
- **Highlight:** The status badge, event card
- **Label:** *"Event appears in 'My Events' with Pending status — awaiting admin review"*
- **Arrow action:** *[Switch to Admin account]* →

---

### Frame 4 — Admin: Pending Events List
- **Route:** `/admin/events/list`
- **Screen:** AdminEventsListScreen — Pending tab
- **What to show:** The submitted event visible in the pending list with student name and submission date
- **Highlight:** The event row, Quick Approve / Quick Reject buttons
- **Label:** *"Admin sees the new event submission in the pending queue"*
- **Arrow action:** Tap the event to review →

---

### Frame 5 — Admin: Event Detail Review
- **Route:** `/admin/events/pending/:id`
- **Screen:** AdminPendingEventDetailScreen
- **What to show:** Full event details, approval letter viewer, admin message input box, Approve / Reject / Revision buttons
- **Highlight:** The **Approve** button, the message thread area
- **Label:** *"Admin reviews the event and approval letter, then approves it"*
- **Arrow action:** Tap **Approve** →

---

### Frame 6 — My Events (Published Status) — back to Student
- **Route:** `/events/my-events`
- **Screen:** MyEventsScreen
- **What to show:** The same event now showing a green **"Published"** badge. A **"Manage"** button is now visible.
- **Highlight:** The Published badge, the Manage chip/button
- **Label:** *"Student sees the event is now Published — Manage button appears"*
- **Arrow action:** Tap **Manage** →

---

### Frame 7 — Manage My Event Dashboard
- **Route:** `/events/manage/:id`
- **Screen:** ManageMyEventScreen
- **What to show:** The 4-tab dashboard — Overview tab showing event stats (Registered, Pending, Attended). Show the tab bar clearly.
- **Highlight:** Overview stats, the 4 tabs (Overview / Participants / Roles / Entry)
- **Label:** *"Creator accesses their full event management dashboard"*

---

**Flow B Summary Arrow Diagram:**
```
[Events Hub] → [Create Form] → [My Events: Pending]
                                      ↓
                             [Admin: Pending List] → [Admin: Review + Approve]
                                      ↓
                             [My Events: Published] → [Manage Dashboard]
```

---
---

# FLOW C — Student Reports Lost Item → Admin Matches → Student Claims
**Actor:** Student then Admin
**Goal:** Show the Lost & Found lifecycle

---

### Frame 1 — Lost & Found Hub
- **Route:** `/lost-found`
- **Screen:** LostFoundHubScreen
- **What to show:** The hub with "Report Lost", "Report Found", "My Lost Reports", "My Found Reports" buttons
- **Highlight:** **Report Lost** button
- **Label:** *"Student opens the Lost & Found module"*
- **Arrow action:** Tap **Report Lost** →

---

### Frame 2 — Report Lost Form
- **Route:** `/lost-found/report-lost`
- **Screen:** ReportLostScreen
- **What to show:** Form filled in — Item name, Category (Phone), Where Lost (Block A), When Lost, Description
- **Highlight:** All form fields, Submit button
- **Label:** *"Student fills in details of the lost item and submits"*
- **Arrow action:** Tap **Submit** →

---

### Frame 3 — My Lost Reports
- **Route:** `/lost-found/my-lost`
- **Screen:** MyLostReportsScreen
- **What to show:** The submitted report with status **"Active"**. Show other existing reports too.
- **Highlight:** The new report card, Active status badge
- **Label:** *"Report is submitted with Active status — awaiting a match"*
- **Arrow action:** *[Admin reviews]* →

---

### Frame 4 — Admin: Match List
- **Route:** `/admin/lost-found/match-list`
- **Screen:** AdminMatchListScreen
- **What to show:** A match entry with AI score (e.g., 87%) linking a lost phone to a found phone
- **Highlight:** The AI match score, the Confirm button
- **Label:** *"Admin reviews the AI-generated match with 87% confidence score"*
- **Arrow action:** Tap to confirm match → Generate QR →

---

### Frame 5 — Student: Lost Report Detail (Matched)
- **Route:** `/lost-found/lost/LR-001`
- **Screen:** LostDetailScreen
- **What to show:** Status now shows **"Matched - Pending"**. Match notification visible.
- **Highlight:** Updated status, match info
- **Label:** *"Student is notified — their item has been matched"*
- **Arrow action:** Student visits office, scans QR →

---

**Flow C Summary Arrow Diagram:**
```
[L&F Hub] → [Report Lost Form] → [My Lost Reports: Active]
                                         ↓
                              [Admin: Match List] → [Confirm Match + QR]
                                         ↓
                              [Lost Detail: Matched] → Student claims item
```

---
---

# FLOW D — Admin Panel Overview
**Actor:** Admin
**Goal:** Show that the admin controls all modules from one panel

> Use this flow to demonstrate the admin side of your system. You only need 1 screenshot per module.

---

### Frame 1 — Admin Login
- **Route:** `/login`
- **Screen:** LoginScreen — Admin tab selected
- **What to show:** Login form with **Admin** toggle ON, ADMIN001 entered
- **Label:** *"Admin logs in with admin credentials"*

---

### Frame 2 — Admin: Events Pending List
- **Route:** `/admin/events/list`
- **Screen:** AdminEventsListScreen
- **What to show:** List of pending event submissions with student names and dates
- **Label:** *"Admin sees all pending event approval requests"*

---

### Frame 3 — Admin: Issues List
- **Route:** `/admin/issues/list`
- **Screen:** AdminIssuesListScreen
- **What to show:** All campus issues from all students, status badges visible
- **Label:** *"Admin monitors all campus issue reports"*

---

### Frame 4 — Admin: Lockers List
- **Route:** `/admin/lockers/list`
- **Screen:** AdminLockersListScreen
- **What to show:** All lockers with statuses (Available, Active, Overdue, Blocked)
- **Label:** *"Admin manages all locker assignments and statuses"*

---

### Frame 5 — Admin: Lost & Found Match Review
- **Route:** `/admin/lost-found/match-list`
- **Screen:** AdminMatchListScreen
- **What to show:** AI-generated match list with confidence scores
- **Label:** *"Admin reviews AI-assisted lost & found matches"*

---

### Frame 6 — Admin: Student Registrations
- **Route:** `/admin/registrations`
- **Screen:** AdminRegistrationsScreen
- **What to show:** Pending student registration requests with Approve / Reject buttons
- **Label:** *"Admin approves or rejects new student account registrations"*

---

**Flow D Summary Arrow Diagram:**
```
[Admin Login] → [Events Admin] → [Issues Admin] → [Lockers Admin]
                                                         ↓
                                      [L&F Match Admin] → [Registrations Admin]
```

---
---

## Step-by-Step: How to Build the Storyboard

### Step 1 — Take Screenshots

Run your app and take screenshots of each frame listed above.

**On Windows (Android Emulator):**
- Press `Ctrl + S` inside the emulator window, **OR**
- Use the **camera icon** in the emulator sidebar, **OR**
- Press `Windows key + Shift + S` to snip the screen

**On a real phone:**
- Android: `Volume Down + Power` button together
- iOS: `Side button + Volume Up`

---

### Step 2 — Choose Your Tool

| Tool | Best For | Free? |
|---|---|---|
| **Canva** (canva.com) | Fast, drag-and-drop, phone frame templates | ✅ Free |
| **Figma** (figma.com) | Professional, great for grouping flows | ✅ Free |
| **PowerPoint / Google Slides** | Easy if you already have it | ✅ Free |
| **Microsoft Whiteboard** | Good for hand-drawn style | ✅ Free |

**Recommended: Canva** — search for "Mobile App Storyboard" template.

---

### Step 3 — Arrange Screens

For each flow:
1. Place screenshots **left to right** in sequence
2. Add an **arrow** between each screen
3. Write the **action label** on the arrow (e.g., "Tap Login", "Tap Submit")
4. Add a **frame number** and **short title** below each screenshot
5. Put each flow on its own **row** or **page**

---

### Step 4 — Add Phone Frames (Optional but Recommended)

In Canva or Figma, search for **"phone mockup"** or **"iPhone frame"** and place your screenshots inside the phone outline. This makes the storyboard look professional.

---

### Step 5 — Add a Title and Legend

At the top of your storyboard add:
- **Title:** "Campus Connect — User Flow Storyboard"
- **Date**
- **Your name / group members**
- **Legend:** Small box explaining icons (e.g., → = Navigation, ⚡ = System Action, 👤 = User Action)

---

## Minimum Screens Summary

If you are short on time, these **20 screens** are the absolute minimum for a complete storyboard:

| # | Screen | Flow |
|---|---|---|
| 1 | Splash Screen | A |
| 2 | Login Screen (Student) | A |
| 3 | Events Hub | A, B |
| 4 | Event Detail | A |
| 5 | Event — Joined + QR Ticket | A |
| 6 | Create Event Form | B |
| 7 | My Events — Pending status | B |
| 8 | Admin Events Pending List | B, D |
| 9 | Admin Event Detail (Approve/Reject) | B |
| 10 | My Events — Published status | B |
| 11 | Manage My Event Dashboard | B |
| 12 | Lost & Found Hub | C |
| 13 | Report Lost Form | C |
| 14 | My Lost Reports | C |
| 15 | Admin Match List (with AI score) | C, D |
| 16 | Lost Report Detail — Matched status | C |
| 17 | Admin Issues List | D |
| 18 | Admin Lockers List | D |
| 19 | Admin Registrations | D |
| 20 | Notifications Screen | A |

---

## Final Checklist

- [ ] Screenshots taken for all selected frames
- [ ] Screenshots cropped to just the phone screen
- [ ] Screens placed in correct order left-to-right per flow
- [ ] Arrows drawn between screens
- [ ] Action labels written on each arrow
- [ ] Frame titles added below each screen
- [ ] Flow labels added (Flow A, Flow B, etc.)
- [ ] Title block added at the top
- [ ] Phone frame/mockup added (optional)
- [ ] Exported as PDF or PNG for submission
