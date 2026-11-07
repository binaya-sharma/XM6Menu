# Security Review Guide

Review these areas before publishing an XM6 Controller release.

## Permissions and privacy

- Bluetooth access is limited to paired WH-1000XM6 control and status.
- Accessibility is requested only after a user selects a media-control button.
- Media controls post Previous, Play/Pause, or Next only after a direct click.
- The app does not install an event tap or monitor keyboard and mouse input.
- Launch at Login changes only after the user toggles it in Settings and uses
  the native Service Management framework.
- No device data, playback data, analytics, or telemetry leaves the Mac.
- Permission descriptions match the behavior of the release build.

## Code and dependencies

- No secrets, credentials, private keys, or personal paths are committed.
- Swift package dependencies are reviewed and pinned. The current app has none.
- Bluetooth frames are length-bounded and checksum-validated.
- Raw protocol frames remain private debug logs.
- User-controlled text is never passed to a shell or executable command.

## Build and distribution

- Tests and the framework-free verification checks pass.
- Real XM6 ANC, AMB, OFF, battery, wear status, connection, and media controls are tested.
- The release app is built from a clean staging directory.
- `codesign --verify --deep --strict` succeeds.
- Public builds use Developer ID, hardened runtime, and notarization.
- Final entitlements contain only required capabilities.
- Release artifacts and checksums come from the reviewed commit.

## Release review

- README behavior, permissions, limitations, and screenshots match the app.
- Accessibility labels and keyboard navigation are verified.
- No ignored development files or build caches are included.
- `main` matches the intended release commit and the working tree is clean.
