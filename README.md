# XM Connect

Menu bar app for macOS that controls Sony XM-series headphones over Bluetooth RFCOMM. Sony ships
Sound Connect for phones only, so noise control, equalizer and battery are out of reach from a Mac.

## Status

Working on a WH-1000XM4: noise control, equalizer, battery, the settings the headset exposes, and
power off, read and written. The v2 path is checked against a recorded WF-1000XM5 session but has
never run against one.

## Build

```sh
make install   # builds, signs, and puts it in /Applications
make run       # runs it from .build
make test
make dmg       # a disk image to hand to someone else
```

Signed with a Developer ID when one is installed on the machine, ad hoc otherwise. `make notarize`
submits the disk image, once `xcrun notarytool store-credentials` has been run and its profile
named xm-connect.

It lives in the menu bar with no dock icon, and opens a window on request for when the panel is in
the way. Launch at login is a switch in the menu.

It holds the control channel only while its menu is open, and lets go a few seconds after it
closes. A headset accepts one control session at a time, so keeping the channel would lock Sony's
phone app out for as long as this app runs. It also never opens a channel to a headset that is
paired but disconnected, which would make macOS connect it behind your back.

## xmprobe

Connects to a paired headset, walks the handshake, and prints every frame in both directions.

```sh
swift run xmprobe
```

Run it from Terminal and accept the Bluetooth prompt. macOS attributes the request to the
terminal application, so a shell without that permission aborts the process.

It reads by default. Passing one of `--nc`, `--wind`, `--ambient <1-20>` (with `--voice` for focus
on voice), `--noise-off` or `--power-off` applies that change and reads the state back. `--explore`
additionally asks for every announced setting that has no decoder yet and prints the raw replies.

## Devices

The headset is asked what it can do and the menu is drawn from the answer, so there is no list of
permitted models. What has actually been confirmed, what was only checked against a recorded
session, and what is merely expected to work is set out in
[docs/devices](docs/devices/README.md).

## Protocol

Sony headsets speak one of two command tables over RFCOMM, and which one applies is decided by the
service the headset exposes rather than by its model name. Both tables, and where the existing
implementations disagree, are written up in [docs/research.md](docs/research.md).

## License

MIT. Not affiliated with, endorsed by, or sponsored by Sony. "Sony", "WH-1000XM" and related
product names are trademarks of Sony Group Corporation, used here only to describe compatibility.
