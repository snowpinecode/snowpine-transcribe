# Security and privacy

Snowpine Transcribe handles recordings of people, so its controls keep those recordings, and their transcripts, on your Mac. Each control names where it is implemented, so it can be checked.

## Controls in place

| Control | Where |
| --- | --- |
| App Sandbox on, with no network entitlement: macOS blocks all network access | `Resources/SnowpineTranscribe.entitlements` |
| No microphone or camera access | `Resources/SnowpineTranscribe.entitlements`, checked by `scripts/check-no-network.sh` |
| Only files you choose can be opened or saved | `com.apple.security.files.user-selected.read-write` |
| Speech is recognized on-device by Apple's `SpeechAnalyzer` | `Sources/SnowpineTranscribe/SpeechEngine.swift` |
| Only local files are accepted, and audio is never written to disk | `AudioSource` in `SpeechEngine.swift` |
| No networking APIs in the code, checked in CI | `scripts/check-no-network.sh`, `.github/workflows/ci.yml` |
| Hardened runtime on the app signature | `scripts/build-app.sh` |
| Secret scan of the full history on every push (pinned gitleaks) | `.github/workflows/secret-scan.yml` |
| No accounts, analytics, crash reporting or telemetry | the whole of `Sources/` |

The web page in `site/` is static: no scripts, cookies, analytics or forms, with a strict Content Security Policy.

## What is stored

Transcripts as JSON, plus a read-only bookmark so a line can play from the recording, in the app's sandboxed Application Support folder. They stay until you delete them in the app. Deleting a transcript also deletes its bookmark. The recording is never copied or changed. Removing the app doesn't remove this folder: delete your transcripts first, or remove `~/Library/Containers/com.snowpinecode.transcribe`.

## Limits

macOS, not this app, downloads and manages Apple's speech model, so the first use of a language may contact Apple. Transcripts are stored unencrypted in the app's folder, protected like your other files by your Mac's login and FileVault.

## Reporting a problem

Please open an issue for anything that is not sensitive. For a vulnerability, use the repository's private vulnerability reporting (GitHub: Security > Report a vulnerability) instead of a public issue.
