# Changes from upstream FluidVoice

This repository is a modified version of [FluidVoice](https://github.com/altic-dev/FluidVoice), an open source macOS voice dictation app licensed under the GNU General Public License v3.0. This notice is provided under GPLv3 section 5(a).

- Upstream project: https://github.com/altic-dev/FluidVoice
- Forked at upstream commit: `4cf2754eb064fc0ea1feb71dc564657c90a4a71a`
- Date of fork and modification: 2026-07-03
- Maintained by: Ray Sang
- Repository: https://github.com/ChipmunkRPA/speech2write

## Modifications

- Rebranded as the Speech2Write project from CPA Automation (app name, icon, theme, and UI copy).
- Removed PostHog analytics: the vendor API key and host were deleted at fork time, and as of 1.1.8 the entire analytics subsystem is removed.
- Removed altic.dev feedback and transcription-example upload endpoints.
- Auto-updater disabled by default and repointed away from the upstream release repository.
- Default speech model changed to Parakeet TDT v2 (fastest local English model) on Apple Silicon.
- The GPLv3 license is retained unchanged; see [LICENSE](LICENSE). All modifications in this fork are licensed under GPLv3.

## 1.4.1

- Expanded every optional field vocabulary pack to 25 curated terms, for 250 preset terms in total while keeping the all-enabled built-in vocabulary within Parakeet's 256-term runtime limit.

## 1.4.0

- Published Speech2Write as an open-source CPA Automation project and added `cpaautomation.ai` branding throughout the app and documentation.
- Added ten optional, locally stored vocabulary presets for AI & Data, Law, Accounting, Finance, Investment, Art & Design, Politics, Journalism, Software, and Cybersecurity.
- Added a vocabulary selection step to onboarding and matching per-preset toggles in Custom Dictionary settings.
- Merged enabled preset terms with personal custom words using case-insensitive deduplication and user-word priority, while keeping the combined built-in catalog below Parakeet's term limit.
- Added preset selections to settings backups and regression tests for catalog completeness, unknown preset IDs, brand vocabulary migration, and merged-term priority.

## 1.3.0

- Rebranded the product as Speech2Write across the app, onboarding, permission prompts, menu bar, settings, exports, packaging, installer, and documentation.
- Added a new speech-wave-to-writing app icon and matching monochrome menu bar mark, with no mascot imagery or embedded text.
- Preserved the existing signed bundle identifier so macOS Accessibility approval, microphone permission, preferences, history, and hotkey settings continue across the rename.
- Added rollback-safe migration from the previous `/Applications` app name and updated the built-in pronunciation vocabulary for “Speech2Write.”

## 1.2.3

- Fixed hotkey reassignment so changing Right Option to Left Option (or any other binding) atomically replaces the live shortcut set and clears pending press/hold state; the previous key can no longer remain active.
- Fixed modifier-only prompt shortcuts using the wrong shared state bucket, which could make prompt hotkeys interfere with each other or become stuck.
- Added regression tests for side-specific modifiers, live replacement, keyboard chords, mouse shortcuts, duplicate normalization, conflicts, and persistence.
- Enforced one SwiftUI window and added a process-level single-instance lock so extra windows or separately launched app copies cannot install competing global event taps.
- Hardened privacy by removing dictated text, rewrite instructions, typing previews, and window titles from diagnostic logs, and restricting log files to the current user.
- Restored full Hardened Runtime library validation, strengthened Developer ID packaging checks, added optional Apple notarization support, and made the installer reject modified or unexpectedly signed app bundles before replacing the installed copy.

## 1.2.2

- Fixed: dictation refused to type into any app while an unrelated process held the macOS secure-input latch (for example a stuck loginwindow after screen lock, or Terminal's Secure Keyboard Entry). The secure-field guard is now target-aware: it blocks only when the app being typed into has a secure text field focused or itself holds the latch.

## 1.2.1

- Security review round 2 (SR-5829): packaging/install scripts and brand assets are now tracked in the repo (they were silently gitignored by an upstream rule); dependencies are pinned by exact revision to public upstream repositories (FluidAudio @ 72625bb and mediaremote-adapter @ cf30c4f); the app is signed with Hardened Runtime enabled using minimal entitlements (microphone, Apple Events, and disable-library-validation — the last is structurally required while the build is ad-hoc signed, because library validation only admits Team-ID-signed libraries and ad-hoc signatures have none; full library validation lands with Developer ID signing); dictation now refuses to type into secure input contexts (password fields) with a notification; required code-owner PR reviews enabled on main (repository admin exempt pending a second maintainer).

## 1.2.0

Security-review remediations (SR-5829). Dictation, Write/Rewrite via Apple Intelligence, meeting/file transcription, snippets, correction learning, custom dictionary and vocabulary boosting, press-enter auto-send, stats, history, backups, media auto-pause, and both overlays are unchanged.

- Removed the local REST API server (SR-5829 Q3): the loopback HTTP listener on port 47733 and its dictionary/history/inference endpoints are deleted; nothing consumed the API.
- Removed the Cohere/external-CoreML model registry and its HuggingFace download spec (SR-5829 Q4): dead wiring for a retired engine; the stored-settings enum case remains for raw-value compatibility but has no artifacts, download, or provider path.
- Removed Command Mode and the generic LLM chat-HTTP client stack (SR-5829 Q5): CommandModeService, TerminalService, chat history, LLMClient, thinking-token parsers, the remote model-listing/verification HTTP calls, and every OpenAI/Anthropic client path; Apple Intelligence (on-device) is the only enhancement path and the binary contains no generic chat-HTTP client.
- Added a dictation history retention policy (SR-5829 Q6): transcript history was previously unbounded (only saved audio had a byte budget). History entries older than the configured window — 1, 7, 30, or 90 days, or Forever — are now deleted automatically, along with their saved audio, at launch and after each new dictation. The default is 90 days and applies to existing installs on first launch after upgrade; a "History retention" picker in Settings controls it, and the setting round-trips through backups. Secure-delete/overwrite of purged entries is deliberately not implemented: on APFS/SSD storage overwriting does not reliably destroy data, so FileVault full-disk encryption is the at-rest control.

## 1.1.9

Dead-code purge. No user-visible feature changes: dictation (Parakeet TDT v2 and Apple Speech), Write/Edit mode, meeting/file transcription, snippets, correction learning, custom dictionary and vocabulary boosting, press-enter auto-send, stats, history, backups, the local API server, media auto-pause, and both overlays are unchanged.

- Removed the retired speech-engine implementations that the two-engine allowlist made unreachable: Whisper (whisper.cpp), Nemotron 3.5, Cohere Transcribe, Parakeet Flash (realtime), and the Qwen3 preview hooks. The engines' stored-settings enum cases remain so old settings and backups still decode; any legacy selection now lands on the platform default engine on the first read after upgrade (previously that took one extra read). The Cohere/Nemotron language settings, their pickers, and their onboarding routes are gone.
- Removed the SwiftWhisper and PromiseKit package dependencies.
- Removed the dormant in-app auto-updater (SimpleUpdater) and its settings surface (auto-update check, beta releases, update-prompt snooze). The manual "Check for Updates" that opens the internal releases page is unchanged. Previously downloaded rollback backups and Whisper model caches on disk become orphaned.
- Removed the inert "Fluid Intelligence" private-AI-provider scaffolding (never enabled in this fork — its compile flag and bridge type do not exist here) along with all of its settings, onboarding card, provider rows, prompt-picker entries, and backup fields. Re-attaching the upstream bridge now requires restoring the files from version control.
- Removed dead Command Mode entry-point UI (settings shortcut row, welcome guide card, overlay mode row) and the expanded command-output notch. The Command Mode service and views stay compiled behind the build flag, but flipping the flag alone no longer fully restores the feature.
- Removed the superseded OpenAI-compatible chat clients (AIProvider/OpenAICompatibleProvider, FunctionCallingProvider), the Hugging Face instance downloader (install-validation helpers remain for Parakeet), the unbuildable Xcode project and test tree (the build is SwiftPM-only), and assorted dead UI (unused AISettingsView shell, API-key editor remnants, hidden voice-engine filters and status views, onboarding welcome sound, unused icon views and assets).

## 1.1.4

- Removed all cloud AI providers (OpenAI, Anthropic, xAI, Groq, Cerebras, Google, OpenRouter, and custom OpenAI-compatible endpoints). AI enhancement is now local-only: Apple Intelligence on-device, or Ollama / LM Studio on this Mac. A one-time migration clears any previously configured cloud selection and its verification state; API keys already stored in the macOS Keychain are not deleted but are no longer used.

## 1.1.5

- Removed the local-server AI providers (Ollama and LM Studio). Apple Intelligence on-device is now the sole AI enhancement provider. A one-time migration clears any previously configured Ollama / LM Studio selection, saved provider entries, and verification state; if one of them was the active enhancement provider, dictation falls back to raw transcription.
- Retired Command Mode from the UI (sidebar, settings shortcut row, welcome guide, and global hotkey). It required an OpenAI-compatible chat endpoint, which no longer exists in this build. A previously configured Command Mode shortcut now does nothing.

## 1.1.8

- Removed the analytics subsystem entirely. The PostHog collection service, event definitions, anonymous install identifier, every capture call site, the "Share Anonymous Analytics" settings toggle, the opt-out confirmation dialog, and the "What we collect" disclosure sheet are all gone — the app contains no analytics or telemetry code. The post-transcription edit tracker remains solely to power correction auto-learning and sends nothing anywhere.

## 1.1.7

- Clarified the voice-training progress label in Custom Dictionary: "understood" is now "recognized in a row", and the recorder caption explains that new mishearings are captured for replacement rules rather than counted as recordings.

## 1.1.6

- Explicit English-only labeling for the Blazing Fast (Parakeet TDT v2) engine. Every engine card in onboarding and settings now carries a language row ("Language: English only" for Blazing Fast, "Languages: English + 8 others" for Apple Speech), the card descriptions state language support up front, the onboarding voice-engine step points non-English users to Apple Speech, and the settings card warns when the stored dictation language is not English while Blazing Fast is offered.
