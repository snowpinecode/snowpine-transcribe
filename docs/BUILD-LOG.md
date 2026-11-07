# Build log

## 2026-11-06: version 0.2.1

No changes to how Snowpine Transcribe works. This release exists to prove in-app updates end to end: a copy of the version before it finds this one, and one click installs it.

Checked by a person at the Mac on Nov 6: the previous version installed the update in place.

## 2026-11-06: version 0.2.0

- In-app updates with Sparkle 2.10.1 (pinned, the one third-party dependency). It checks GitHub at launch and once a day, says when a new version is out, and one click installs it. Check for Updates and Check for Updates Automatically are in the app menu; with automatic checks off, background checks are refused.
- The app still has no network entitlement. Sparkle's separate Downloader helper fetches the feed and the update. Every update must carry a valid EdDSA signature. Recordings and transcripts are never part of it. New entitlements, for Sparkle only: `cs.disable-library-validation` and a mach-lookup exception for its two local services.
- Releases are signed with one self-signed certificate instead of ad hoc. Builds go to `build/Products.noindex`, so Spotlight doesn't list a second copy.
- Fixes from a code review: a saved file claiming another transcript's id, or a huge one, is set aside and counted instead of loaded, so Delete always removes the file shown; Markdown and subtitle exports escape what they export; a cancelled job's late results can't touch the next job; a part of the sound that can't be read fails the job instead of being skipped; reloading the list keeps a transcript that couldn't be saved; only audio and video files are accepted.

Checked here on an M5 MacBook Pro, macOS 27: 21 unit tests, the no-network and render checks, `scripts/check-engine.sh`, a signed universal build, `--update-check` reaching GitHub through Sparkle's helper. A 4 hour file took 128 seconds at 13 MB peak memory; Cancel stopped it at once. Silence, a video with no sound, a cut-off file, a fake file and a silent first track all behave. An independent review (Codex) of this change found nothing.

## 2026-11-05: version 0.1.0

First release. A Mac app that turns recordings into searchable transcripts using Apple's on-device `SpeechAnalyzer`, in the App Sandbox with no network entitlement.

Checked on an M5 MacBook Pro, macOS 27.0.1, with the Command Line Tools only:
- 16 unit tests: times, exports, search, line building, the transcript library, damaged files.
- `scripts/check-engine.sh`: the real engine transcribes a spoken script with the right words and times.
- A 4 hour file took 125 seconds with about 13 MB peak memory in the app. Cancel stopped it in under a second. It was 61 seconds of narration with music, repeated, not a real meeting.
- 60 seconds of silence gives no text. A video with no sound, a cut-off file and a fake file each give a clear error.
- A file with a silent first track and speech on the second track is transcribed.
- Inside the sandboxed app, the engine works with no network entitlement.
- An independent Codex review found 5 real problems, all fixed.

Not yet checked: accuracy on a real long meeting, Intel Macs and macOS 26 itself.
