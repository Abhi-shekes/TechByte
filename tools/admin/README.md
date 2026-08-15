# TechByte admin tools

Content management, deliberately **outside** the mobile app.

The app is a read-only consumer of published content. Nothing here ships to a
device, and the Firestore rules enforce that: `questions` is
`allow write: if isAdmin()`, and `isAdmin()` reads a custom claim that only a
privileged credential can set. A client cannot grant itself the claim.

No hosted admin panel, no SaaS, no paid service — this is a local CLI run by
someone who already has the service-account key.

## Setup

```bash
cd tools/admin
npm install
```

You need a service-account key with Firebase Admin privileges:

```bash
# Firebase console → Project settings → Service accounts → Generate new private key
export GOOGLE_APPLICATION_CREDENTIALS=/absolute/path/to/serviceAccount.json
```

**Never commit that key.** It bypasses every security rule.

## Commands

```bash
# Grant admin to a user (by email). Run once per admin.
node admin.mjs grant-admin you@example.com

# Validate a content file without writing anything
node admin.mjs validate content/batch-01.json

# Publish (validates first, refuses on any failure)
node admin.mjs publish content/batch-01.json

# List what is published
node admin.mjs list --status published --limit 20

# Unpublish without deleting — content stays for review
node admin.mjs unpublish <questionId>

# Review reports filed from the app
node admin.mjs reports
```

## Content format

An array of question objects matching the app's model. Same shape the app
persists, minus the fields the tool fills in (`id`, `source`, timestamps):

```json
[
  {
    "type": "why",
    "category": "networking",
    "subcategory": "tcp",
    "difficulty": "medium",
    "question": "Why would anyone choose UDP when TCP guarantees delivery?",
    "shortAnswer": "Because the guarantee is paid for in time…",
    "whyItMatters": "…",
    "realWorldExample": "…",
    "technicalDetails": "…",
    "interviewAngle": "…",
    "followUpQuestion": "…",
    "tags": ["tcp", "udp"]
  }
]
```

`publish` sets `source: "curated"` and `status: "published"`.

## Validation

`validate` applies the same rules as the in-app `QuestionValidator`, so
content that would be rejected on-device is rejected here instead of shipping
and being silently filtered:

- question ends in `?`, 20–220 characters
- no definition openers (`What is…`, `Define…`)
- short answer 40–900 characters
- known `type`, `category`, `difficulty` values
- no placeholder or meta text
- no near-duplicates within the file, by token-overlap fingerprint

The rules themselves live in `tools/content/validator.mjs`, shared with the
bulk generator and with CI. This file used to carry its own looser copy, which
meant content could pass `validate` here and still be dropped on-device.

Duplicate detection against *already published* Firestore content is still not
done here — it needs the full remote corpus and is better run as a periodic
audit. Duplicates against **bundled** content are caught, since the packs are
on disk: `node ../content/validate.mjs <your-file.json>` checks a candidate
file against the shipped corpus in one pass.
