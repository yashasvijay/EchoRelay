# EchoRelay

Native macOS SwiftUI app for routing Mac audio to AirPlay receivers. It is designed as an Airfoil-style core: capture audio playing on the Mac, optionally scope capture to one app, discover AirPlay receivers with Bonjour, stream to multiple receivers, adjust per-speaker volume, apply a simple three-band EQ, and schedule group starts against a common wall-clock timestamp.

## What is implemented

- System-wide Mac audio capture using ScreenCaptureKit, with no virtual audio driver.
- Per-application audio source selection.
- Bonjour discovery of `_airplay._tcp` and `_raop._tcp` receivers.
- AirPlay 1 / AirPlay 2 streaming through the `cliairplay` helper.
- Multiple selected receivers in one session.
- Same scheduled start time for selected receivers; the build uses NTP timing so it does not require privileged PTP ports.
- Per-output volume and mute.
- Three-band bass/mid/treble EQ in the captured PCM path.
- Silence monitor that stops after prolonged silence.
- Menu-bar control.

## Receiver coverage

This build focuses on AirPlay receivers, so it can target Apple TV, HomePod, AirPlay-compatible Sonos, and other AirPlay hardware. Chromecast and direct Bluetooth transport are not included in this first build. Bluetooth devices remain usable as normal macOS audio outputs, but EchoRelay does not yet act as a separate Bluetooth streaming client.

## Requirements

- macOS 14.4 or later.
- Xcode 16 or newer.
- A Mac signed into a development team for local development.
- A local network with an AirPlay receiver.

## Build

1. Open `EchoRelay.xcodeproj` in Xcode.
2. Select the EchoRelay target and set your Signing Team.
3. Build and run.
4. macOS will request Screen & System Audio Recording access. Enable EchoRelay in System Settings → Privacy & Security → Screen & System Audio Recording, then restart the app.
5. Click **Install AirPlay Engine** once. The app downloads the latest `cliairplay` macOS binary from the Music Assistant project at runtime and stores it under `~/Library/Application Support/EchoRelay`.
6. Select **All Mac Audio** or a specific app, select one or more AirPlay speakers, and enable **Transmit**.

## Important licensing note

EchoRelay does not copy or embed the `cliairplay` implementation into its Swift source. It downloads the upstream helper as a separate executable at runtime. The upstream project is GPL-3.0 overall, with additional third-party notices; see its repository and release notices for the exact license terms. If you redistribute the helper with EchoRelay, preserve the upstream GPL-3.0 license and third-party notices.

## Known limitations in this build

- The app is not code-signed/notarized here because this environment does not contain Xcode or a macOS build system.
- There is no Chromecast transport yet.
- Direct Bluetooth streaming is not yet implemented as a separate EchoRelay transport.
- Metadata/artwork forwarding is not wired because ScreenCaptureKit does not by itself expose track metadata for arbitrary apps.
- The multi-room sync path uses NTP timing in this unprivileged build. It schedules a common start time, but it should not be described as the exact PTP-grade sync path used by specialized AirPlay implementations.
