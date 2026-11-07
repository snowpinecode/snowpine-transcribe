# Maintaining Snowpine Transcribe

## Build and test
You need macOS 26 or later and the Xcode Command Line Tools.

```bash
scripts/test.sh                  # unit tests, the no-network check, a render check
scripts/check-engine.sh          # the real speech engine, end to end, on this Mac
scripts/build-app.sh --install   # builds the app and moves it to ~/Applications
```

Without a signing identity, `build-app.sh` signs the app ad hoc. That is fine for testing. For a build signed with the release certificate, import it into a throwaway keychain (your login keychain is not touched):

```bash
export SIGN_KEYCHAIN=$(scripts/import-signing-cert.sh cert.p12 cert-password.txt)
export SIGN_IDENTITY="Snowpine Code App Signing"
scripts/build-app.sh
security delete-keychain "$SIGN_KEYCHAIN"   # when you're done
```

## Where things live
| What | Where |
| --- | --- |
| App icon | `Resources/AppIcon.svg` and `Resources/AppIcon.png` (1024 x 1024, transparent corners) |
| Colors and fonts | `Brand` in `Sources/SnowpineTranscribe/Views.swift`, `Resources/Fonts` |
| Speech engine | `Sources/SnowpineTranscribe/SpeechEngine.swift` |
| Export formats, search, line building | `Sources/SnowpineTranscribeCore` |
| Pictures | `SnowpineTranscribe --render-docs docs` draws the real screens with a made-up meeting |
| In-app updates | `Sources/SnowpineTranscribe/Updater.swift` (the only file that imports Sparkle); feed URL, public key and check settings in `Resources/Info.plist` |
| Sparkle in the app bundle | `scripts/embed-sparkle.sh` copies the framework in and signs its parts. Sparkle's helpers keep Sparkle's own setup with no entitlements, and `scripts/build-app.sh` fails if any carries entitlements, on any architecture |
| The update feed | `scripts/make-appcast.sh` signs the zip with the EdDSA key and writes `build/appcast.xml` |
| Sparkle version | `Package.swift` (exact) and `scripts/sparkle-tools.sh` (`VERSION` and `SHA256` of the tools download). Change them together |
| Web page | `site/`, published by `.github/workflows/pages.yml` |

Use `@StateObject` and `ObservableObject`, not `@State`: the `@State` macro needs full Xcode, and the app should build with only the Command Line Tools.

## Publish a download
Releasing needs three repository secrets (Settings > Secrets and variables > Actions):

| Secret | What it is |
| --- | --- |
| `CODESIGN_P12_BASE64` | The release certificate ("Snowpine Code App Signing") and its private key, as a base64 .p12 |
| `CODESIGN_P12_PASSWORD` | The .p12 password |
| `SPARKLE_ED_PRIVATE_KEY` | The EdDSA private key that signs updates. Its public half is `SUPublicEDKey` in `Resources/Info.plist` |

Set the version in `scripts/build-app.sh` and `scripts/package-release.sh`, then push a tag such as `v0.2.0`. `.github/workflows/release.yml` tests, builds a universal signed app, signs the zip, writes `appcast.xml`, and attaches `Snowpine-Transcribe.zip`, its `.sha256` and `appcast.xml` to the release.

The page links to `releases/latest/download/Snowpine-Transcribe.zip`, and installed copies read `.../releases/latest/download/appcast.xml`. So:
- Every release marked Latest must have `appcast.xml` attached, or update checks stop finding anything.
- Keep the same EdDSA key. A new one means installed copies refuse every update.
- Back up the .p12, its password and the EdDSA private key somewhere safe outside the repository.

## Check before every release
- Transcribe a real recording, and check a line by clicking its time.
- Try search, Copy All and each export.
- Run `"build/Products.noindex/Snowpine Transcribe.app/Contents/MacOS/SnowpineTranscribe" --update-check` on the packaged app: it reads the feed through Sparkle's Downloader helper, with no window, and reports what it found.
- After publishing, open the previous version, choose Check for Updates, install, and check that it relaunches as the new version.
- Keep the privacy promises: no network access in the app itself (only Sparkle's Downloader, for updates), no microphone, nothing uploaded.
