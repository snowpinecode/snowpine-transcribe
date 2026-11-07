# Security and privacy

Snowpine Transcribe handles recordings of people, so its controls keep those recordings, and their transcripts, on your Mac. Each control names where it is implemented, so it can be checked.

## Controls in place

| Control | Where |
| --- | --- |
| App Sandbox on, with no network entitlement: macOS blocks the app's own network access | `Resources/SnowpineTranscribe.entitlements` |
| In-app updates (Sparkle 2.10.1, pinned): the only network use. Sparkle's separate Downloader helper fetches the update feed and the update from GitHub, over https. Recordings and transcripts are never part of it | `Sources/SnowpineTranscribe/Updater.swift`, `Resources/Info.plist` |
| Turning off Check for Updates Automatically means no check starts unless you ask. While it is off, the app refuses background checks, including one already scheduled | `Sources/SnowpineTranscribe/Updater.swift` |
| Every update must be signed with the EdDSA key matching `SUPublicEDKey`, checked before it is unpacked. Nothing installs without your click | `Resources/Info.plist`, `scripts/make-appcast.sh` |
| Sparkle's helpers (Downloader, Installer, Updater) ship exactly as Sparkle ships them, with no extra entitlements. They are not sandboxed: the Installer has to replace the app, and giving the shared Downloader its own sandbox can clash with other apps that use Sparkle | `scripts/embed-sparkle.sh` |
| Two extra entitlements, both for Sparkle: `cs.disable-library-validation` (to load its bundled framework without an Apple Team ID) and a mach-lookup exception for its two local services (`-spks`, `-spki`), which are connections between processes on the Mac, not network access | `Resources/SnowpineTranscribe.entitlements` |
| No microphone or camera access | `Resources/SnowpineTranscribe.entitlements`, checked by `scripts/check-no-network.sh` |
| Only files you choose can be opened or saved | `com.apple.security.files.user-selected.read-write` |
| Speech is recognized on-device by Apple's `SpeechAnalyzer` | `Sources/SnowpineTranscribe/SpeechEngine.swift` |
| Only local audio and video files are accepted, and audio is never written to disk | `AppModel.add(_:)`, `AudioSource` in `SpeechEngine.swift` |
| A saved file that is huge, damaged, or claims another transcript's id is counted and kept, never loaded, so Delete always removes the file that was shown | `Sources/SnowpineTranscribeCore/LibraryStore.swift` |
| Markdown and subtitle exports can't be broken or turned into links by what was said | `TranscriptExport` in `Sources/SnowpineTranscribeCore/Transcript.swift` |
| No networking, microphone or camera APIs in the app's code, Sparkle imported in one file only, and exactly this set of entitlements, checked in CI | `scripts/check-no-network.sh`, `.github/workflows/ci.yml` |
| The build checks the entitlements actually signed into the app are exactly that set on every architecture, and that Sparkle's helpers carry none | `scripts/build-app.sh` |
| Hardened runtime on the app signature. Releases are signed in CI with one certificate from repository secrets, in a throwaway keychain | `scripts/build-app.sh`, `scripts/import-signing-cert.sh`, `.github/workflows/release.yml` |
| Secret scan of the full history on every push (pinned gitleaks) | `.github/workflows/secret-scan.yml` |
| No accounts, analytics, crash reporting or telemetry. The update check sends GitHub only what any download does, and can be turned off | the whole of `Sources/` |

The web page in `site/` is static: no scripts, cookies, analytics or forms, with a strict Content Security Policy.

## What is stored

Transcripts as JSON, plus a read-only bookmark so a line can play from the recording, in the app's sandboxed Application Support folder. They stay until you delete them in the app. Deleting a transcript also deletes its bookmark. The recording is never copied or changed. Removing the app doesn't remove this folder: delete your transcripts first, or remove `~/Library/Containers/com.snowpinecode.transcribe`.

## Limits

macOS, not this app, downloads and manages Apple's speech model, so the first use of a language may contact Apple. Update checks are on by default (at launch and once a day); turn them off in the app menu. Transcripts are stored unencrypted in the app's folder, protected like your other files by your Mac's login and FileVault.

## Reporting a problem

Please open an issue for anything that is not sensitive. For a vulnerability, use the repository's private vulnerability reporting (GitHub: Security > Report a vulnerability) instead of a public issue.
