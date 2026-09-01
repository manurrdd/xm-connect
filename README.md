# XM Connect

Menu bar app for macOS that controls Sony XM-series headphones over Bluetooth RFCOMM. Sony ships
Sound Connect for phones only, so noise control, equalizer and battery are out of reach from a Mac.

## Status

Reads are verified against a WH-1000XM4: handshake, capabilities, noise control, equalizer and
battery. Writes are implemented and unit tested, but not yet confirmed on hardware.

## Build

```sh
make app     # .build/XMConnect.app
make run
make test
```

The app is a menu bar item with no dock icon. It is signed ad hoc, so the first launch needs
Right click, Open, or System Settings, Privacy & Security.

## xmprobe

Connects to a paired headset, walks the handshake, and prints every frame in both directions.

```sh
swift run xmprobe
```

Run it from Terminal and accept the Bluetooth prompt. macOS attributes the request to the
terminal application, so a shell without that permission aborts the process.

It reads by default. Passing one of `--nc`, `--wind`, `--ambient <1-20>` (with `--voice` for focus
on voice), `--noise-off` or `--power-off` applies that change and reads the state back.

## Protocol

Sony headsets speak one of two command tables over RFCOMM, and which one applies is decided by the
service the headset exposes rather than by its model name. Both tables, and where the existing
implementations disagree, are written up in [docs/research.md](docs/research.md).

## License

MIT. Not affiliated with, endorsed by, or sponsored by Sony. "Sony", "WH-1000XM" and related
product names are trademarks of Sony Group Corporation, used here only to describe compatibility.
