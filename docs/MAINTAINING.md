# Maintaining Snowpine Transcribe

## Build and test
You need macOS 26 or later and the Xcode Command Line Tools.

```bash
scripts/test.sh                  # unit tests, the no-network check, a render check
scripts/check-engine.sh          # the real speech engine, end to end, on this Mac
scripts/build-app.sh --install   # builds the app and moves it to ~/Applications
```

## Where things live
| What | Where |
| --- | --- |
| App icon | `Resources/AppIcon.svg` and `Resources/AppIcon.png` (1024 x 1024, transparent corners) |
| Colors and fonts | `Brand` in `Sources/SnowpineTranscribe/Views.swift`, `Resources/Fonts` |
| Speech engine | `Sources/SnowpineTranscribe/SpeechEngine.swift` |
| Export formats, search, line building | `Sources/SnowpineTranscribeCore` |
| Pictures | `SnowpineTranscribe --render-docs docs` draws the real screens with a made-up meeting |
| Web page | `site/`, published by `.github/workflows/pages.yml` |

Use `@StateObject` and `ObservableObject`, not `@State`: the `@State` macro needs full Xcode, and the app should build with only the Command Line Tools.

## Publish a download
Set the version and push a tag, such as `v0.2.0`. `.github/workflows/release.yml` tests, builds and attaches the zip. The page links to `releases/latest/download/Snowpine-Transcribe.zip`, so it always gets the newest one.

## Check before every release
- Transcribe a real recording, and check a line by clicking its time.
- Try search, Copy All and each export.
- Keep the privacy promises: no network access, no microphone, nothing uploaded.
