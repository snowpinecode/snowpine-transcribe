<p align="center"><img src="Resources/AppIcon.png" width="128" alt="Snowpine Transcribe icon"></p>

# Snowpine Transcribe

A free, open source Mac app that turns your recordings into searchable transcripts, right on your Mac.
Made by [Snowpine Code](https://snowpinecode.com).

**[See the page and the short video](https://snowpinecode.github.io/snowpine-transcribe/)**

[![Watch the short video](docs/video-poster.jpg)](https://snowpinecode.github.io/snowpine-transcribe/)

Drop in a recording or a video and get text with a time on every line. Nothing is uploaded, and there's nothing to pay per minute.

## What it does

- **Audio or video.** Voice Memos, Zoom recordings, phone videos and more. Every sound track in a file is mixed in, so people on separate tracks aren't lost.
- **Fast.** In my test, a 4 hour recording took about 2 minutes on an M5 MacBook Pro. Your speed will depend on your Mac and your recording.
- **Search.** Find anything that was said.
- **Check it by ear.** Click a time to hear that moment.
- **Take it with you.** Copy it, or save it as text, Markdown, SRT or WebVTT subtitles, or JSON.
- **Keeps your transcripts.** They stay in the app until you delete them.

It doesn't record meetings or label who's talking.

## Install

**Download it:** [download the zip](https://github.com/snowpinecode/snowpine-transcribe/releases/latest/download/Snowpine-Transcribe.zip), open it, and drag Snowpine Transcribe to Applications. The app isn't signed with a paid Apple developer certificate, so macOS warns you the first time. Open it, click **Done**, then go to System Settings > Privacy & Security, scroll down and click **Open Anyway**.

**Or build it yourself,** which takes about a minute and skips the warning. You need the Xcode Command Line Tools (run `xcode-select --install` once) or Xcode.

```bash
git clone https://github.com/snowpinecode/snowpine-transcribe.git
cd snowpine-transcribe
scripts/build-app.sh --install
```

## Requirements

- macOS 26 or later, because it uses Apple's newer speech engine (`SpeechAnalyzer`). Tested on an Apple silicon MacBook Pro.
- If macOS doesn't have the speech model for your language, it downloads it once. macOS does that, not the app.

## Accuracy

It's usually good on clear speech, but it can mishear names, numbers and unusual words. Check anything important by clicking its time and listening.

## Privacy

- Speech is recognized **on your Mac** by Apple's on-device engine.
- The app runs in the **macOS App Sandbox with no network entitlement**, so macOS itself blocks it from the internet. The code has no networking calls, and CI checks that it stays that way (`scripts/check-no-network.sh`).
- It never uses your microphone or camera. It only opens files you choose.
- No accounts, analytics or tracking.
- Your recording is never copied. Transcripts, and a pointer back to the recording for playback, are saved in the app's own folder until you delete them.

If you record other people, ask them first.

## Build and test

```bash
scripts/test.sh          # unit tests, no-network check, render check
scripts/check-engine.sh  # end to end with the real speech engine on this Mac
scripts/build-app.sh     # build/Snowpine Transcribe.app
```

Exports, search and the transcript model live in `Sources/SnowpineTranscribeCore` (no UI, unit tested). The app is in `Sources/SnowpineTranscribe`. You can also run `SnowpineTranscribe --transcribe <file>` to print a transcript.

See [docs/MAINTAINING.md](docs/MAINTAINING.md) for releases.

## Contributing

Issues and pull requests are welcome. Please keep the privacy promises: no network access, no microphone, nothing uploaded. `scripts/test.sh` must pass.

## License

MIT. See [LICENSE](LICENSE). The bundled Inter and Plus Jakarta Sans fonts are under the SIL Open Font License (see `Resources/Fonts`). The Snowpine Code name and logo are not part of the MIT grant.
