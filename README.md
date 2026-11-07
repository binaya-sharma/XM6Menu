<div align="center">

# XM6 Controller for macOS

**Battery, noise control, output switching, and listening level, right from your menu bar.**

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-22c55e.svg)](LICENSE)

<table>
  <tr>
    <td align="center" valign="middle" width="45%">
      <img src="Resources/XM6ProductRender.png" alt="Illustrative render of black over-ear headphones" width="320">
    </td>
    <td align="center" valign="middle" width="55%">
      <img src="Resources/XM6ControllerUI-v6.png" alt="XM6 Controller showing a connected WH-1000XM6, battery, ANC, AMB and OFF controls, volume, media controls with an Accessibility permission disclosure, and sound outputs" width="330">
    </td>
  </tr>
  <tr>
    <td align="center"><sub>WH-1000XM6 · illustrative render</sub></td>
    <td align="center"><sub>Native macOS menu-bar controls</sub></td>
  </tr>
</table>

</div>

XM6 Controller is a lightweight, native SwiftUI companion for Sony WH-1000XM6
headphones. It lives in the menu bar, keeps all data on your Mac, and has no
accounts, analytics, or network service.

## What works

| Feature | Support |
| --- | --- |
| Connection | Find a paired WH-1000XM6, connect, and disconnect |
| Battery | Read percentage and charging state from the headphone |
| Noise control | Noise Cancelling, Ambient levels 1–20, and Off |
| Headphone button sync | Reflect physical NC/AMB changes while open and resync when reopened |
| Wear detection | Show whether the XM6 is worn and refresh while the popover is open |
| Listening level | Read and change the active macOS output volume |
| Media controls | Previous, Play/Pause, and Next for the active media app |
| Launch at Login | Optional native macOS startup registration in Settings |
| Sound output | List Core Audio devices and switch the default output |
| Verification | Read settings back from the XM6 before showing them as synced |

The Bluetooth controls have been exercised end to end on a real WH-1000XM6,
including repeated ANC, Ambient, Off, battery, volume, output, and reconnect
cycles.

## Quick start

Requires macOS 14 or newer and a WH-1000XM6 already paired in **System Settings
→ Bluetooth**.

```sh
./scripts/build-app.sh
open "outputs/XM6 Controller.app"
```

There is no Dock window. After launch, select the **S** icon on the right side
of the menu bar. The first media-control click asks for Accessibility permission
so macOS can receive the requested media key. The app does not monitor input.
You can also open `Package.swift` directly in Xcode.

Open **Settings** from the popover to enable **Launch at Login**.

## How it works

- SwiftUI provides the menu-bar popover and Settings window.
- IOBluetooth handles the classic Bluetooth connection and the XM6 control
  channel.
- Core Audio supplies the real output-device list and system volume controls.
- A deliberately small Sony v2 protocol implementation handles only battery
  and noise control, serializing requests so refreshes and button clicks do not
  compete for the headphone's single channel.

Sony does not publish a supported macOS control API for these features. The
headphone protocol is reverse engineered, so battery and noise controls should
still be considered experimental. If the XM6 does not confirm a change, the app
shows an error instead of pretending it succeeded.

## Security and privacy

- Device and audio information stays on the Mac; the app has no networking,
  telemetry, advertising, analytics, or third-party packages.
- Device discovery is restricted to WH-1000XM6 names so XM6 commands are never
  intentionally sent to older Sony protocol generations.
- Incoming control frames are length- and checksum-validated. Raw frame bytes
  are private, debug-level logs rather than public informational logs.
- The optional battery fallback executes the fixed system binary
  `/usr/sbin/system_profiler` with fixed arguments. There is no shell evaluation
  or user-controlled command construction.
- The listening-level display is macOS output volume, not a calibrated dB or
  hearing-exposure measurement.
- The local app is ad-hoc signed and unsandboxed because classic Bluetooth is
  required. Public distribution would additionally require Developer ID
  signing, hardened runtime, notarization, and a final entitlements review.

See the [Security Review Guide](docs/SECURITY_CHECKLIST.md) for the release
security and privacy checks.

## Current limits

Equalizer control and multipoint peer management are not available through this
app. Use Sony | Sound Connect for those features.

## License

The reverse-engineered protocol behavior is independently implemented in Swift.
Public interoperability research released under open-source licenses informed
the protocol work, but no third-party application source is copied, bundled,
linked, installed, or contacted at runtime.

XM6 Controller is available under the [MIT License](LICENSE). Sony and
WH-1000XM6 are trademarks of their respective owner; this project is independent
and is not affiliated with or endorsed by Sony. The headphone image above is an
illustrative generated render, not official Sony product artwork.
