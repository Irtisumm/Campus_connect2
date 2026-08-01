# Seed Admin — One-Time Administrator Setup

There is no admin account in Firebase yet, so admin login is unreachable. This
creates the first administrator: a **Firebase Authentication account** plus the
matching **`users/{uid}` Firestore document**. After the admin exists, the
normal login flow takes over — this script plays no part in sign-in and is not
part of the shipped app.

## Why a script, and why the Admin SDK

The `users` create rule in `firestore.rules` pins `role == 'student'` and
`status == 'Pending'`, so **no client — not even a signed-in one — can write an
admin document through the app**. The first admin must be created out-of-band.

This script uses the **Firebase Admin SDK**, which is the supported server path
(a Cloud Function would use the same SDK). It is the only place in the project
that holds elevated privileges, and it runs on your machine, not in the app.

It does **not**:
- bypass Firebase Authentication for login — it creates a real credential the
  admin signs in with;
- manually edit Firestore documents in the console — it writes them through the
  Admin SDK;
- change the login flow — `AuthService` / `UserService` / `AppState` are
  untouched.

## Safety properties

- **Idempotent.** Re-running when the admin already exists reuses the account
  (looked up by email) and repairs the document (looked up by `studentId`),
  instead of creating a duplicate.
- **No password logged.** The password is set in `seed_admin.mjs` and written to
  Auth; it is never printed beyond the one summary line telling you what it is.
- **No silent deletes.** If a stale `users` document with the same `studentId`
  exists on a different uid, it is left in place and flagged for you to remove
  from the console.
- **No orphaned credentials.** If the Firestore write fails, the error is
  reported with nothing half-committed; re-running repairs it.

## Prerequisites

- Node.js (v18+) and npm — check with `node --version`.
- The Firebase CLI is already installed (`firebase --version` → 15.24.0).

## Steps

### 1. Get a service-account key

Firebase Console → **Project settings** (gear icon, top-left) → **Service
accounts** tab → **Generate new private key** → confirm. Save the downloaded
JSON file as:

```
d:\Campus_connect2\tools\serviceAccount.json
```

This file is git-ignored (`tools/.gitignore`). **Keep it secret.** It grants
full admin access to your Firebase project.

### 2. Install the dependency

```bash
cd d:\Campus_connect2\tools
npm install
```

This installs `firebase-admin` only, inside `tools/node_modules/` (also
git-ignored).

### 3. (Optional) Configure the admin

Open [tools/seed_admin.mjs](tools/seed_admin.mjs) and edit the `ADMIN` block at
the top if you want different credentials. The defaults are:

| Field      | Default value          |
|------------|------------------------|
| studentId  | `ADMIN001`             |
| email      | `admin001@city.edu.my` |
| password   | `Admin@12345`          |
| fullName   | `Admin Panel`          |
| faculty    | `Campus Operations`    |

You only need to change these once; after the admin exists you can change the
password from the app or Firebase Console.

### 4. Run the seeder

```bash
cd d:\Campus_connect2\tools
node seed_admin.mjs
```

You should see:

```
Created Firebase Auth account  ✓  uid=…
Created Firestore users/…  ✓  role=admin, status=Active

✅ Done. You can now sign in with:
   Student ID: ADMIN001
   Email:      admin001@city.edu.my
   (password is the one set above — change it in the app or Firebase Console.)
```

### 5. Sign in

Open the app, use the **admin** login form with:

- **Student ID:** `ADMIN001` (or the email `admin001@city.edu.my`)
- **Password:** `Admin@12345` (or whatever you set)

The existing login flow resolves `ADMIN001` → `authEmail` via Firestore, then
signs in through Firebase Authentication. No code changed.

## Cleaning up

After the admin is created and verified:

- You can delete `tools/node_modules/` — re-install with `npm install` if you
  ever need to re-seed.
- **Do not** delete `tools/serviceAccount.json` if you plan to re-run; if you
  are done seeding and want to reduce risk, delete it and revoke the key from
  the Firebase Console (Service accounts → the key → Delete).

## What the document looks like

The script writes exactly these fields to `users/{uid}` (matching the schema in
`AUTH_MIGRATION.md`):

```
uid        : <Auth UID>          # same as the document ID
studentId  : ADMIN001
fullName   : Admin Panel
authEmail  : admin001@city.edu.my
email      : admin001@city.edu.my
faculty    : Campus Operations
role       : admin
status     : Active
phone      : ""
createdAt  : <server timestamp>
updatedAt  : <server timestamp>
```

No `password` field is ever written — passwords live only in Firebase
Authentication, per the security rules (`!request.resource.data.keys().hasAny(['password'])`).
