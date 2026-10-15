# Repository Guidelines

## Project Structure & Module Organization

SkyNear is a Swift 6 package targeting iOS 17+, with no Xcode project or backend. `Sources/RadarCore/` contains shared models, networking, location handling, and attribution resources. `Sources/SkyNear/` contains the SwiftUI app, views, state store, and Live Activity operations. `Sources/SkyNearWidgets/` implements WidgetKit and ActivityKit presentation. XCTest cases live in `Tests/RadarCoreTests/`. App assets and the privacy manifest live in `Resources/`.

`Package.swift` defines targets; `xtool.yml` and the two root `*-Info.plist` files configure packaging. Treat `SkyNear_*_Fix/`, `patch-backups/`, and `.bak` files as repair utilities or historical snapshots; make application changes in `Sources/`.

## Build, Test, and Development Commands

Run build commands in Ubuntu/WSL from the repository root with Swift, an appropriate Apple SDK, and xtool configured:

- `bash build-ipa.sh`: builds an IPA, writes `build.log`, and validates a newly generated package.
- `xtool dev build --ipa`: runs the build directly.
- `python3 verify-ipa.py "path/to/SkyNear.ipa"`: checks package structure, arm64 executables, and extension configuration.
- `python3 verify-widget-ipa.py "path/to/SkyNear.ipa"`: checks widget executable linkage.
- `python3 verify-signing-space.py "path/to/SkyNear.ipa"`: checks Mach-O space needed for signing.

Run only one build at a time. Remove a stale build lock only after confirming the previous process has stopped.

## Coding Style & Naming Conventions

Follow existing Swift style: four-space indentation, `UpperCamelCase` types, and `lowerCamelCase` functions and properties. Preserve API field names used by decoded models. Keep shared logic in `RadarCore` and presentation in the app or widget target. Respect Swift 6 concurrency isolation and `Sendable` declarations. No formatter or linter configuration is included.

## Testing Guidelines

Use XCTest classes named `*Tests` and methods named `test...`. Add regression cases for decoding, missing data, unit conversions, stale positions, and geographic edge cases. Run `RadarCoreTests` with a compatible Apple/iOS test runner; plain Linux `swift test` cannot run the imported iOS frameworks. No numeric coverage threshold is configured. Follow `TESTPLAN.md` for device checks and report checks that were not executed.

## Commit & Pull Request Guidelines

Git history is unavailable in this checkout. Use concise, imperative commit subjects, such as `Fix stale widget positions`. PRs should describe the behavior change, link relevant issues, record validation and toolchain details, and include screenshots for UI changes.

## Privacy & Configuration

Keep certificates, provisioning profiles, and credentials out of source changes. Preserve location disclosures, source attribution, and explicit unknown or stale-data states.
