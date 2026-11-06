# Build log

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
