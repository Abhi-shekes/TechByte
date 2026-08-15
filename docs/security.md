# Security

## Authentication

Google Sign-In through Firebase Auth, and nothing else. No email/password, no
phone/OTP, no anonymous, no other federated providers.

This is a security property, not just a product decision: there is no password
to store, reset, or leak, and no credential of the user's ever reaches the app.

### Flow

```
GoogleSignIn.authenticate()
   → ID token (JWT signed by Google)
   → GoogleAuthProvider.credential(idToken:)
   → FirebaseAuth.signInWithCredential()
```

The app receives an ID token and hands it straight to Firebase. It never sees
a password.

### Session handling

- `attemptLightweightAuthentication()` restores a session silently on launch.
  Failure is silent by design — it just means showing the sign-in screen.
- Sign-out clears **both** Firebase and Google, so the next sign-in shows the
  account picker rather than silently reusing the account.
- Account deletion calls `disconnect()` to revoke the grant, then deletes the
  Firebase user, then clears local data.
- `requires-recent-login` is handled explicitly: the user is asked to sign in
  again rather than shown a generic failure.

## Data collected

Only what authentication and basic profile display require:

- Firebase UID
- Google display name
- Email
- Profile image URL

Nothing else is read from the Google account. No contacts, no Drive, no
calendar — no additional OAuth scopes are requested at all.

## Firestore rules

Full rules in `firestore.rules`. Principles:

**Ownership is a path check.** Everything a user owns lives under
`/users/{uid}/…`, so authorisation is `request.auth.uid == uid` rather than
comparing a field inside the document.

**Privilege never comes from a document field.** Admin status is a custom claim
(`request.auth.token.admin`), set server-side. A client cannot grant it to
itself. Any rule that reads a field to decide privilege is one write away from
being an escalation.

**Content is read-only to clients.** Questions are published through the admin
workflow. `allow write: if isAdmin()` — the app never writes content.

**Published-only reads.** `resource.data.status == 'published'` keeps drafts
invisible.

**Reports are write-only.** A user may file a report and cannot read, edit or
delete any report, including their own. Reports are moderation input, not user
content.

**Fails closed.** A final `match /{document=**} { allow read, write: if false; }`
means adding a collection without rules denies access rather than silently
inheriting.

## App Check

Attests that requests come from a genuine build. This is what stops someone
extracting the config and draining the shared Firebase and Gemini quotas —
which, in a project designed around free tiers, is the most realistic abuse.

Play Integrity in release, debug provider in debug.

## Client-side content safety

Model output is never trusted:

- Structured output schema constrains shape and taxonomy values.
- `QuestionValidator` rejects stub text, meta text ("as an AI"), banned
  phrasings and near-duplicates.
- Users can report content, which removes it from the feed immediately.

## Crashlytics hygiene

Never logged: passwords, tokens, API secrets, personal data. Collection is
disabled in debug so local stack traces stay in the console and do not pollute
release statistics.

## Secrets

Not committed:

- `android/app/google-services.json`
- `lib/firebase_options.dart`
- `android/key.properties`, `*.jks`, `*.keystore`

CI restores config from a repository secret. Nothing in the codebase hardcodes
a client id, API key or OAuth secret.

Note that `google-services.json` is not a credential in the strict sense — it
ships inside every APK. It is kept out of the repository because it is
regenerable at zero cost and there is no reason to publish project config.
Actual protection comes from App Check and Firestore rules.

## Account deletion

Per §34, deletion must remove the associated data:

1. Revoke the Google grant (`disconnect()`).
2. Delete the Firebase user.
3. Clear local preferences and database.
4. Delete `/users/{uid}` and subcollections — **still to do**, needs a
   server-side cascade when Firestore sync is switched on.
