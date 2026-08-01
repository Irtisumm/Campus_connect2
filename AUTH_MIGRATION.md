# Firebase Authentication Migration

Mock authentication has been replaced with Firebase Authentication + Cloud Firestore.
UI, routing and the Provider graph are unchanged.

## Architecture

| Layer | File | Responsibility |
|---|---|---|
| Models | `lib/models/user_profile.dart` | `UserProfile`, `UserRole` and `AccountStatus` enums |
| Models | `lib/models/auth_result.dart` | `AuthResult`, `AuthFailure`, error-code messages |
| Service | `lib/services/auth_service.dart` | Firebase Authentication only — credentials, nothing else |
| Service | `lib/services/user_service.dart` | Firestore `users` document CRUD + ID→email lookup |
| Service | `lib/services/admin_service.dart` | Approval, registration feed, account counts |
| State | `lib/services/app_state.dart` | Session state + orchestration; the only `ChangeNotifier` |

Firebase types never leave the three services — they raise `AuthFailure`,
which carries a message already safe to show to the user.

## Firestore schema — `users/{uid}`

The document ID **is** the Firebase Auth UID.

| Field       | Type      | Notes                                        |
|-------------|-----------|----------------------------------------------|
| `uid`       | string    | Same as the document ID                      |
| `studentId` | string    | Campus ID, stored uppercase (`S220500`)      |
| `fullName`  | string    |                                              |
| `authEmail` | string    | **Immutable.** The address Firebase Auth knows the account by; sign-in resolves to this |
| `email`     | string    | Display / contact address; editable from Profile |
| `faculty`   | string    |                                              |
| `role`      | string    | `student` \| `admin`                         |
| `status`    | string    | `Pending` \| `Active` \| `Rejected`          |
| `phone`     | string    | Optional, edited from the Profile screen     |
| `createdAt` | timestamp | Server timestamp                             |
| `updatedAt` | timestamp | Server timestamp                             |

Passwords are **never** stored here — they live only in Firebase Authentication.

`authEmail` and `email` start out identical. Editing your email on the Profile
screen changes only `email`; `authEmail` is frozen by the security rules, so a
profile edit can never lock an account out of sign-in.

## Registration is atomic

Firebase Auth and Firestore share no transaction, so registration rolls back by
hand: if the `users/{uid}` write fails, the just-created credential is deleted
via `AuthService.deleteCurrentAccount()`. An account cannot exist in
Authentication without a matching profile document. If the rollback itself
fails (offline mid-flow), the user is told to contact an administrator rather
than being left with a silently broken account.

## Required setup

### 1. Deploy the security rules

```bash
firebase deploy --only firestore:rules
```

`firestore.rules` allows one anonymous single-document lookup on `users` so the
login screen can resolve a Student ID to its email address. See the comment in
that file for the trade-off and a stricter alternative.

### 2. Create the first administrator

There is no admin account yet — the old `ADMIN001 / admin123` mock account is gone.

1. Firebase Console → **Authentication → Users → Add user**
   (e.g. `admin001@city.edu.my` with a password). Copy the generated **UID**.
2. Firestore → **Start collection** `users` → document ID = that UID:

```
uid        : <the UID you copied>
studentId  : ADMIN001
fullName   : Admin Panel
authEmail  : admin001@city.edu.my     <- must match the Auth account exactly
email      : admin001@city.edu.my
faculty    : Campus Operations
role       : admin
status     : Active
phone      : ""
createdAt  : (timestamp — now)
updatedAt  : (timestamp — now)
```

The admin can now sign in with `ADMIN001` **or** `admin001@city.edu.my`.

## Login flow

The login field still says "Student ID" and still accepts `S001`-style IDs.
`UserService.resolveAuthEmail()` maps the ID to the account's `authEmail`
through Firestore, then `AuthService` calls `signInWithEmailAndPassword`.
Typing an email address directly also works — including an outdated display
address, which is resolved back to the account's `authEmail`.

After a successful password check the Firestore profile gates entry:

| `status`   | Result                                                        |
|------------|---------------------------------------------------------------|
| `Pending`  | Signed straight back out — "Your account is waiting for administrator approval." |
| `Rejected` | Signed straight back out — "Your registration was rejected."   |
| `Active`   | Allowed in                                                     |

Role is also enforced: the admin form requires `role == admin`, the student form
requires `role == student`.

## Student lifecycle

1. Student registers → Firebase Auth account created → `users/{uid}` written with
   `status: Pending` → signed out immediately.
2. Admin opens **Student Registrations** (live Firestore feed) and approves.
3. Approval sets `status: Active`; the student can now sign in.

## Remember Me

Only the identifier (Student ID / email) is persisted in SharedPreferences.
The old `saved_password` key is deleted on next launch.
