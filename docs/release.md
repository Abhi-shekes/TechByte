# Release process

## Branch flow

```
feature branches ──► dev ──► (PR) ──► main
                              │
                              └─ merge triggers .github/workflows/release.yml
```

- Day-to-day work happens on `dev` (directly, or via short-lived feature
  branches merged into `dev`).
- `main` only moves via a pull request from `dev`.
- Merging a `dev → main` PR is the release trigger. Nothing else builds a
  signed artifact — pushes to `dev`, or PRs into `dev`, only run the
  verification workflow (`android.yml`: format, analyze, test, debug build).
- Any other PR merged into `main` (e.g. a hotfix branch) does **not** trigger
  a release. If you need that, merge the hotfix into `dev` first, then raise
  the `dev → main` PR as usual, or run the release workflow manually
  (`workflow_dispatch`) from the Actions tab.

## What happens on release

`.github/workflows/release.yml`:

1. Checks out `main`.
2. Bumps `pubspec.yaml`'s version: the patch digit and the build number
   (the part after `+`) both increment by one — e.g. `0.1.0+1` → `0.1.1+2`.
3. Restores `google-services.json` and the release keystore from secrets,
   builds a signed `flutter build apk --release` and
   `flutter build appbundle --release`.
4. Renames the outputs to `techbyte-v<versionName>-<buildNumber>-release.apk`
   / `.aab` — e.g. `techbyte-v0.1.1-2-release.apk`.
5. Commits the version bump back to `main`
   (`chore(release): bump version to vX.Y.Z+B [skip ci]`) and pushes a tag
   `vX.Y.Z+B`.
6. Creates a GitHub Release for that tag with both files attached and
   auto-generated release notes (commits since the previous tag).

`pubspec.yaml` is the single source of truth for the version — Flutter's
Android build reads `versionName`/`versionCode` from it directly, so
`android/app/build.gradle.kts` never needs to change.

## Required repository secrets

None of these exist on a fresh clone of this repo. Set them under
**Settings → Secrets and variables → Actions**:

| Secret | Contents |
|---|---|
| `GOOGLE_SERVICES_JSON` | `base64 -w0 android/app/google-services.json` |
| `RELEASE_KEYSTORE_BASE64` | `base64 -w0 <path to your .jks keystore>` |
| `RELEASE_KEYSTORE_PASSWORD` | Keystore password |
| `RELEASE_KEY_ALIAS` | Key alias (`techbyte`, if created via the script below) |
| `RELEASE_KEY_PASSWORD` | Key password |

Create the keystore with `tools/create_release_keystore.sh` — it also
registers the SHA-1/SHA-256 fingerprints with Firebase, which Google
Sign-In and Play Integrity both need in a release build. **Back the keystore
up outside this repository.** Losing it means you can never publish an
update to the same Play listing again.

Also required: **Settings → Actions → General → Workflow permissions** set
to "Read and write permissions", so the workflow can push the version-bump
commit and tag to `main`. If `main` has branch protection rules, add an
exception for `github-actions[bot]` (or the push step will fail).

## Manual re-run

If a release run fails after adding/fixing a secret, re-run it without
opening a new PR: **Actions → Release → Run workflow**, branch `main`.

## Distribution target

Releases currently publish to **GitHub Releases** only (APK + AAB attached).
There is no Play Console upload step yet — the AAB from the release is
uploaded to Play manually until that's added.
