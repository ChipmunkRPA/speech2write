# Speech2Write

Voice dictation for macOS. Press a hotkey, talk, and Speech2Write types the transcription into whatever app you are working in. Speech recognition runs on-device by default.

Speech2Write is an open-source project from [CPA Automation](https://cpaautomation.ai), invented and maintained by Ray Sang. It is based on [FluidVoice](https://github.com/altic-dev/FluidVoice) by altic-dev and remains licensed under the GNU General Public License v3.0. See [CHANGES.md](CHANGES.md) for the modifications made in this fork.

## Features

- Global hotkey dictation into any app via accessibility APIs
- On-device speech recognition — audio is transcribed locally, not sent to a server
- Two speech engines: Parakeet TDT v2 (fastest local, English only) and Apple Speech (macOS 26+, multilingual)
- Live transcription preview with a notch-aware overlay
- Close-to-menu-bar behavior so dictation remains available after closing the main window
- Optional AI post-processing that runs entirely on-device via Apple Intelligence (off by default)
- Custom dictionary and local vocabulary boosting for names and uncommon terms
- Optional field vocabulary presets for AI, law, accounting, finance, investment, art, politics, journalism, software, and cybersecurity
- Local transcription and audio history with export
- Menu bar integration, per-app prompt profiles, adaptive light/dark theme

## Default engine

The out-of-box speech model is Parakeet TDT v2, the fastest local English model in the app. It runs entirely on-device on Apple Silicon. Other models, including multilingual options, can be selected in settings.

## Install (one time)

Download the app and installer from the [latest release](https://github.com/ChipmunkRPA/speech2write/releases/latest) into one folder:

- `Speech2Write-<version>.zip` — the app
- `install.sh` — the installer

Some releases also include `Speech2Write-model-parakeet-v2.tar.gz`, which preloads the speech model into `~/Library/Application Support/FluidAudio/Models`. Without it, Speech2Write offers to download the model on first use.

Then run:

```sh
chmod +x install.sh && ./install.sh
```

With the GitHub CLI authenticated against your personal GitHub account, a single command does all of the above:

```sh
gh release download -R ChipmunkRPA/speech2write -p 'install.sh' && chmod +x install.sh && ./install.sh --fetch
```

The installer verifies that the app has an intact Developer ID signature from the expected Speech2Write signing team before copying it to `/Applications`. Current release builds are not yet Apple-notarized, so the installer clears Gatekeeper quarantine after signature verification. It then installs any included speech model and launches the app. On first launch, grant Microphone and Accessibility access when prompted — Accessibility is what lets the app type your dictation into other apps.

## Vocabulary presets

Setup offers ten optional vocabulary packs: AI & Data, Law, Accounting, Finance, Investment, Art & Design, Politics, Journalism, Software, and Cybersecurity. Each pack contains 25 curated terms, for 250 preset terms in total. The same toggles remain available under **Custom Dictionary → Vocabulary Boosting**.

Preset selections and custom words stay on the Mac. They are used only by the local Parakeet engine, can be enabled or disabled independently, and are included in app settings backups. Enabling a pack also enables vocabulary boosting; disabling the master Boosting switch keeps selections saved without applying them.

## Build from source

Requirements: macOS 15 or later, Apple Silicon, and the Xcode Command Line Tools (a full Xcode install is not required).

```sh
swift build -c release
```

Or run `./build.sh`. The release binary is written to `.build/release`.

`./scripts/package.sh` creates the signed app and release archive. To notarize a distributable release, first store an Apple notarytool keychain profile, then set `SPEECH2WRITE_NOTARY_PROFILE` to that profile name when packaging. Set `SPEECH2WRITE_REQUIRE_NOTARIZATION=1` in release automation to prevent an accidental unnotarized release.

## Privacy

- Speech-to-text runs on-device; dictated audio and text stay on your Mac.
- Dictation refuses to type into secure password fields. Avoid dictating secrets — transcripts are kept locally per your history retention setting.
- Diagnostic logs are restricted to your macOS account and record only operational metadata such as character counts, never dictated text, rewrite instructions, typing previews, or window titles.
- Vendor telemetry from the upstream project (PostHog analytics and altic.dev feedback endpoints) has been removed. The app contains no analytics or telemetry.
- Optional AI post-processing runs only via Apple Intelligence on-device. No other AI provider can be configured, so dictated text is never sent to a remote AI service. Off by default.
- Dictation history is retained for 90 days by default; the retention window is configurable in Settings, down to 1 day.

## License

GPLv3 — see [LICENSE](LICENSE). This is a modified version of FluidVoice; the modifications are documented in [CHANGES.md](CHANGES.md) and are also licensed under GPLv3.

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md), and report security issues through the repository's private vulnerability-reporting flow described in [.github/SECURITY.md](.github/SECURITY.md).
