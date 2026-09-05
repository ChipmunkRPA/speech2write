# Contributing to Speech2Write

Thanks for helping improve Speech2Write, an open-source CPA Automation project.

## Development setup

Requirements:

- macOS 15 or later on Apple Silicon
- Xcode or the matching Xcode Command Line Tools
- Swift 6.2 or later

Build and test before opening a pull request:

```sh
swift build
swift test
swiftformat --config .swiftformat <changed Swift files>
swiftlint lint --strict --config .swiftlint.yml <changed Swift files>
```

Keep pull requests focused, describe user-visible behavior, and add regression tests for bug fixes. Do not commit credentials, signing certificates, speech models, generated app bundles, or personal transcription data.

By contributing, you agree that your contribution is licensed under GPLv3, consistent with [LICENSE](LICENSE).

For security vulnerabilities, follow [.github/SECURITY.md](.github/SECURITY.md) instead of opening a public issue.
