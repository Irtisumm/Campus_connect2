// ── Mock Data ─────────────────────────────────────────────────────
// Mirrors the data.js from the web prototype

// Issue and IssueHistory moved to lib/models/issue.dart for Firestore. The
// import makes them usable inside this file; the export keeps every existing
// `import '.../mock_data.dart'` working unchanged.
import '../models/issue.dart';
export '../models/issue.dart' show Issue, IssueHistory;

// Event, EventMessage, EventJoining and EventRole moved to lib/models/ for
// Firestore, for the same reason and by the same mechanism as Issue above.
// They must be declared exactly once: while a copy lived here as well, any
// file that saw both declarations failed to compile on the name clash, and
// AppState could not hand a screen the value DataService had produced. The
// re-export keeps every existing `import '.../mock_data.dart'` working
// unchanged — the constructors are identical, so MockData.events and every
// DataService method below still compile untouched.
import '../models/event.dart';
export '../models/event.dart' show Event;
export '../models/event_joining.dart' show EventJoining;
export '../models/event_message.dart' show EventMessage;
export '../models/event_role.dart' show EventRole;

// ── Models ────────────────────────────────────────────────────────
class LostReport {
  final String id, title, category, whereLost, whenLost, status, description;
  final int photos;
  final String? matchStatus;
  const LostReport({required this.id, required this.title, required this.category,
    required this.whereLost, required this.whenLost, required this.status,
    required this.description, this.photos = 0, this.matchStatus});
}

class FoundReport {
  final String id, description, category, whereFound, whenFound, status;
  final int photos;
  final String? handoverStatus; // null, 'Pending Handover', 'Handed Over', 'Claimed'
  final String? qrCode;         // one-time QR code for handover proof
  final bool qrScanned;
  final int handoverStep;       // 1-5, tracks stepper progress
  const FoundReport({required this.id, required this.description, required this.category,
    required this.whereFound, required this.whenFound, required this.status,
    this.photos = 0, this.handoverStatus, this.qrCode, this.qrScanned = false,
    this.handoverStep = 1});
}

class AdminLostReport {
  final String id, studentId, title, category, whereLost, status, createdDate;
  final int? aiScore;
  final String? matchedFoundId;
  const AdminLostReport({required this.id, required this.studentId, required this.title,
    required this.category, required this.whereLost, required this.status,
    required this.createdDate, this.aiScore, this.matchedFoundId});
}

class LfMatch {
  final String id, lostId, foundId, status, notes;
  final int score;
  const LfMatch({required this.id, required this.lostId, required this.foundId,
    required this.score, required this.status, required this.notes});
}

class Notification {
  final String id, type, text, time;
  final String visibility;     // 'all', 'student', 'admin'
  final String? detailText;    // Additional detail (only shown for private)
  final bool read;
  final String? relatedScreen, relatedId;
  final String? targetUserId; // if set, only show to this user
  final String source;         // 'lost_found', 'events', 'lockers', 'issues', 'system'
  const Notification({required this.id, required this.type, required this.text,
    required this.time, this.visibility = 'all', this.detailText, this.read = false,
    this.relatedScreen, this.relatedId, this.targetUserId, this.source = 'system'});
}

class Candidate {
  final String id, name, programme, position, manifesto;
  const Candidate({required this.id, required this.name, required this.programme,
    required this.position, required this.manifesto});
}

class Locker {
  final String id, location, status;
  final String? studentId, endDate, startDate;
  final int? daysLeft;
  final String lockType;        // 'key' or 'digital'
  // SECURITY: no `digitalCode` here. The unlock code belongs to the
  // owner-scoped booking only — a locker record is readable by everyone.
  final double monthlyRent;     // RM10/month
  final double deposit;         // RM100 deposit
  final bool depositRefunded;
  const Locker({required this.id, required this.location, required this.status,
    this.studentId, this.endDate, this.daysLeft, this.startDate,
    this.lockType = 'key', this.monthlyRent = 10.0,
    this.deposit = 100.0, this.depositRefunded = false});
}

class LockerBooking {
  final String id, lockerId, location, startDate, endDate, status;
  final int daysLeft;
  final int durationMonths;     // 2–12 months
  final double monthlyRent;
  final double deposit;
  final double totalPaid;       // deposit + total rental cost
  final String? keyCollectionQR;   // QR code for key collection
  final bool keyCollected;
  final String? keyCollectionDate;
  final String? keyReturnQR;       // QR code for key return
  final bool keyReturned;
  final String? keyReturnDate;
  final String? releaseStatus;     // null, 'Requested', 'Pending Return', 'Returned', 'Completed'

  const LockerBooking({required this.id, required this.lockerId, required this.location,
    required this.startDate, required this.endDate, required this.status, required this.daysLeft,
    this.durationMonths = 6, this.monthlyRent = 10.0, this.deposit = 100.0, this.totalPaid = 160.0,
    this.keyCollectionQR, this.keyCollected = false, this.keyCollectionDate,
    this.keyReturnQR, this.keyReturned = false, this.keyReturnDate, this.releaseStatus});
}

class LockerIssue {
  final String id;
  final String lockerId;
  final String studentId;
  final String description;
  final String status; // 'Reported', 'Under Review', 'Resolved'
  final int photoCount;
  final String reportedDate;

  const LockerIssue({required this.id, required this.lockerId, required this.studentId,
    required this.description, required this.status, this.photoCount = 0,
    required this.reportedDate});
}

class LockerHistory {
  final String action, staffId, timestamp;
  final String? reason;
  const LockerHistory({required this.action, required this.staffId, required this.timestamp, this.reason});
}

// StudentRegistration removed: student registrations now live in the Firestore
// `users` collection (see UserProfile / AdminService). It carried a plaintext
// `password` field, which must never exist outside Firebase Authentication.

// ── Mock Data ─────────────────────────────────────────────────────
class MockData {
  // Lost & Found
  static const List<LostReport> myLostReports = [
    LostReport(id:'LR-001',title:'Blue Samsung Galaxy S23',category:'Phone',whereLost:'Block A, Level 3',whenLost:'2026-03-20',status:'Active',description:'Black case with a small scratch on the back. Has a blue phone strap attached.',photos:3,matchStatus:'A possible match is under review.'),
    LostReport(id:'LR-002',title:'Student ID Card',category:'ID Card',whereLost:'Library',whenLost:'2026-03-18',status:'Matched - Pending',description:'Name: Ahmad Rizwan. Faculty of Engineering card.',matchStatus:'A possible match is under review.'),
    LostReport(id:'LR-003',title:'Black Leather Wallet',category:'Wallet',whereLost:'Cafeteria',whenLost:'2026-03-15',status:'Closed',description:'Contains IC and some cash. Has a red strip on the back.',photos:1),
    LostReport(id:'LR-004',title:'Locker Keys (Keychain: Soccer Ball)',category:'Keys',whereLost:'Sports Complex',whenLost:'2026-03-22',status:'Active',description:'2 keys on a small soccer ball keychain.'),
  ];

  static const List<FoundReport> myFoundReports = [
    FoundReport(id:'FR-001',description:'Black Android Phone',category:'Phone',whereFound:'Block A Corridor',whenFound:'2026-03-21',status:'In Inventory',photos:2,handoverStatus:'Handed Over',qrScanned:true,handoverStep:5),
    FoundReport(id:'FR-002',description:'Brown Wallet with cash',category:'Wallet',whereFound:'Cafeteria Table 5',whenFound:'2026-03-19',status:'Resolved',photos:1,handoverStatus:'Claimed',qrScanned:true,handoverStep:5),
    FoundReport(id:'FR-003',description:'Student ID Card – Siti Nur',category:'ID Card',whereFound:'Library Level 2',whenFound:'2026-03-18',status:'In Review',handoverStatus:'Pending Handover',handoverStep:2),
  ];

  static const List<Notification> notifications = [
    Notification(id:'N-001',type:'private',visibility:'student',text:'Your lost item may have been found!',detailText:'A matching Phone was found in Block A Corridor. Please visit the Lost & Found office.',time:'2 hours ago',relatedScreen:'lost-detail',relatedId:'LR-001',read:false,targetUserId:'S001',source:'lost_found'),
    Notification(id:'N-002',type:'public',visibility:'all',text:'A lost item has been reported',time:'5 hours ago',read:true,source:'lost_found'),
    Notification(id:'N-003',type:'private',visibility:'student',text:'Your lost report has been updated',detailText:'Report LR-002 status changed to Matched - Pending.',time:'Yesterday',relatedScreen:'lost-detail',relatedId:'LR-002',read:true,targetUserId:'S001',source:'lost_found'),
    Notification(id:'N-004',type:'public',visibility:'all',text:'A found item has been reported',time:'2 days ago',read:true,source:'lost_found'),
  ];

  static const List<AdminLostReport> allLostReports = [
    AdminLostReport(id:'LR-001',studentId:'S220101',title:'Blue Samsung Galaxy S23',category:'Phone',whereLost:'Block A, Level 3',status:'Active',createdDate:'2026-03-20',aiScore:87,matchedFoundId:'FR-001'),
    AdminLostReport(id:'LR-002',studentId:'S220045',title:'Student ID Card',category:'ID Card',whereLost:'Library',status:'Matched - Pending',createdDate:'2026-03-18',aiScore:95,matchedFoundId:'FR-003'),
    AdminLostReport(id:'LR-003',studentId:'S221238',title:'Black Leather Wallet',category:'Wallet',whereLost:'Cafeteria',status:'Closed',createdDate:'2026-03-15'),
    AdminLostReport(id:'LR-004',studentId:'S219987',title:'Locker Keys',category:'Keys',whereLost:'Sports Complex',status:'Active',createdDate:'2026-03-22'),
    AdminLostReport(id:'LR-005',studentId:'S220334',title:'Blue Backpack',category:'Bag',whereLost:'Lecture Hall B',status:'Active',createdDate:'2026-03-23',aiScore:62),
  ];

  static const List<LfMatch> matches = [
    LfMatch(id:'M-001',lostId:'LR-001',foundId:'FR-001',score:87,status:'Pending',notes:'Both are black Android phones found in Block A area within 1 day.'),
    LfMatch(id:'M-002',lostId:'LR-002',foundId:'FR-003',score:95,status:'Confirmed',notes:'Student ID card, name matches on description.'),
  ];

  // Issues
  static const List<Issue> myIssues = [
    Issue(id:'ISS-001',title:'Broken AC in Lecture Hall A2',category:'Facilities',location:'Block A, Level 2',status:'In Progress',createdDate:'2026-03-10',updatedDate:'2026-03-20',description:'The air conditioning has not been working for 2 weeks. Very hot during afternoon classes.'),
    Issue(id:'ISS-002',title:'Faulty Projector in LH-B5',category:'Facilities',location:'Block B, Level 5',status:'Resolved',createdDate:'2026-03-05',updatedDate:'2026-03-22',description:'Projector keeps turning off mid-lecture.'),
    Issue(id:'ISS-003',title:'Wifi down at Study Area',category:'IT',location:'Library Level 3',status:'New',createdDate:'2026-03-23',updatedDate:'2026-03-23',description:'WiFi access points are not broadcasting.'),
    Issue(id:'ISS-004',title:'Waterlogging at Entrance',category:'Safety',location:'Main Entrance',status:'Triaged',createdDate:'2026-03-21',updatedDate:'2026-03-22',description:'After rain, water accumulates at the main entrance stairway.'),
  ];

  static const List<Issue> allIssues = [
    Issue(id:'ISS-001',studentId:'S220101',title:'Broken AC in Lecture Hall A2',category:'Facilities',location:'Block A, Level 2',status:'In Progress',createdDate:'2026-03-10',updatedDate:'2026-03-20',description:'AC broken for 2 weeks.'),
    Issue(id:'ISS-002',studentId:'S220045',title:'Faulty Projector',category:'Facilities',location:'Block B, Level 5',status:'Resolved',createdDate:'2026-03-05',updatedDate:'2026-03-22',description:'Projector lamp issue.'),
    Issue(id:'ISS-003',studentId:'S220101',title:'Wifi down at Study Area',category:'IT',location:'Library Level 3',status:'New',createdDate:'2026-03-23',updatedDate:'2026-03-23',description:'WiFi down.'),
    Issue(id:'ISS-004',studentId:'S221238',title:'Waterlogging at Entrance',category:'Safety',location:'Main Entrance',status:'Triaged',createdDate:'2026-03-21',updatedDate:'2026-03-22',description:'Water accumulation after rain.'),
    Issue(id:'ISS-005',studentId:'S219987',title:'Dirty toilets at Block C',category:'Cleanliness',location:'Block C, Level 1',status:'Assigned',createdDate:'2026-03-19',updatedDate:'2026-03-19',description:'Toilets not cleaned.'),
  ];

  static const Map<String,List<IssueHistory>> issueHistory = {
    'ISS-001': [
      IssueHistory(date:'2026-03-10',from:null,to:'New',note:'Issue submitted by student.'),
      IssueHistory(date:'2026-03-11',from:'New',to:'Triaged',note:'Reviewed and confirmed by Facilities team.'),
      IssueHistory(date:'2026-03-13',from:'Triaged',to:'Assigned',note:'Assigned to maintenance team.'),
      IssueHistory(date:'2026-03-20',from:'Assigned',to:'In Progress',note:'Technician dispatched. Parts ordered.'),
    ],
    'ISS-002': [
      IssueHistory(date:'2026-03-05',from:null,to:'New',note:'Issue submitted.'),
      IssueHistory(date:'2026-03-06',from:'New',to:'Triaged',note:'Confirmed by IT team.'),
      IssueHistory(date:'2026-03-08',from:'Triaged',to:'Resolved',note:'Projector lamp replaced.'),
    ],
  };

  // Events
  static const List<Event> events = [
    Event(id:'EVT-001',title:'Final Semester Convocation 2026',date:'2026-04-10',time:'09:00 AM',location:'Main Auditorium',category:'Academic',organizer:'Academic Office',description:'Annual convocation ceremony for graduating students. Smart formal attire required.',status:'Published'),
    Event(id:'EVT-002',title:'Inter-Faculty Badminton Tournament',date:'2026-03-28',time:'08:00 AM',location:'Sports Complex – Court 1',category:'Sport',organizer:'Student Sports Club',description:'Open to all faculties. Register by 26 March. Prizes for top 3 teams.',status:'Published'),
    Event(id:'EVT-003',title:'AI & Machine Learning Workshop',date:'2026-03-26',time:'02:00 PM',location:'Block C, Lab C3-01',category:'Academic',organizer:'Faculty of Computing',description:'Hands-on workshop on PyTorch and model deployment. Bring your laptop.',status:'Published'),
    Event(id:'EVT-004',title:'Spring Cultural Night',date:'2026-04-05',time:'07:00 PM',location:'Multi-Purpose Hall',category:'Club',organizer:'Cultural Club',description:'Multicultural performances, food booths, and live music.',status:'Published'),
    Event(id:'EVT-005',title:'Blood Donation Drive',date:'2026-03-25',time:'09:00 AM',location:'Foyer, Block A',category:'General',organizer:'Red Crescent Society',description:'Donate blood and save lives. Free breakfast for all donors.',status:'Published'),
  ];

  static const List<Candidate> candidates = [
    Candidate(id:'C-001',name:'Amirul Hakim',programme:'BEng Electrical Engineering',position:'President',manifesto:'Committed to bridging the gap between students and management. Will focus on student welfare, better facilities, and improved mental health resources.'),
    Candidate(id:'C-002',name:'Priya Devi',programme:'BSc Computer Science',position:'Vice President',manifesto:'Advocating for tech-forward student services, faster WiFi across campus, and more collaboration opportunities with industry partners.'),
    Candidate(id:'C-003',name:'Lim Wei Jian',programme:'BA Business Administration',position:'Secretary General',manifesto:'Focused on transparent communication between the student council and the student body. Will publish monthly newsletters.'),
    Candidate(id:'C-004',name:'Nur Aisyah binti Rosli',programme:'BEd TESL',position:'Treasurer',manifesto:'Will ensure responsible and transparent management of student activity funds with detailed public financial reports each semester.'),
  ];

  // Lockers
  static const List<Locker> lockers = [
    Locker(id:'LK-A01',location:'Block A, Level 1',status:'Available',lockType:'digital'),
    Locker(id:'LK-A02',location:'Block A, Level 1',status:'Active',studentId:'S220334',startDate:'2026-01-04',endDate:'2026-06-30',daysLeft:98,lockType:'key',monthlyRent:10.0,deposit:100.0),
    Locker(id:'LK-A03',location:'Block A, Level 1',status:'Available',lockType:'key'),
    Locker(id:'LK-A04',location:'Block A, Level 1',status:'Pending Pickup',studentId:'S220045',lockType:'key'),
    Locker(id:'LK-A05',location:'Block A, Level 1',status:'Available',lockType:'digital'),
    Locker(id:'LK-A06',location:'Block A, Level 1',status:'Overdue',studentId:'S219001',startDate:'2025-12-01',endDate:'2026-03-01',daysLeft:-23,lockType:'key',monthlyRent:10.0,deposit:100.0),
    Locker(id:'LK-B01',location:'Block B, Level 2',status:'Available',lockType:'digital'),
    Locker(id:'LK-B02',location:'Block B, Level 2',status:'Active',studentId:'S221010',startDate:'2026-01-04',endDate:'2026-06-30',daysLeft:98,lockType:'digital'),
    Locker(id:'LK-B03',location:'Block B, Level 2',status:'Available',lockType:'key'),
    Locker(id:'LK-B04',location:'Block B, Level 2',status:'Blocked',lockType:'key'),
    Locker(id:'LK-C01',location:'Block C, Level 1',status:'Available',lockType:'digital'),
    Locker(id:'LK-C02',location:'Block C, Level 1',status:'Available',lockType:'key'),
  ];

  static const List<LockerBooking> myBookings = [
    LockerBooking(id:'BK-001',lockerId:'LK-A04',location:'Block A, Level 1',startDate:'2026-03-15',endDate:'2026-06-30',status:'Pending Pickup',daysLeft:98,durationMonths:4,monthlyRent:10.0,deposit:100.0,totalPaid:140.0),
  ];

  static const Map<String,List<LockerHistory>> lockerHistory = {
    'LK-A02': [
      LockerHistory(action:'Booked by student',staffId:'system',timestamp:'2026-01-04 09:15',reason:'Student self-booking'),
      LockerHistory(action:'Activate – Key Collected',staffId:'STAFF-02',timestamp:'2026-01-05 10:30',reason:'Student verified with ID'),
    ],
    'LK-A06': [
      LockerHistory(action:'Booked by student',staffId:'system',timestamp:'2025-12-01 10:00',reason:'Student self-booking'),
      LockerHistory(action:'Marked Overdue',staffId:'system',timestamp:'2026-03-02 00:00',reason:'Auto: end date passed'),
    ],
  };

  // Locker Issues
  static const List<LockerIssue> lockerIssues = [
    LockerIssue(id:'LI-001',lockerId:'LK-A02',studentId:'S001',description:'Lock not opening properly',status:'Reported',photoCount:2,reportedDate:'2026-03-20'),
  ];

  // Student registrations are read live from Firestore — see
  // AdminService.watchStudentRegistrations().
}
