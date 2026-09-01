# Protocol research

Findings from reading the existing implementations. Every claim states where it comes from.
Anything not verified against hardware is marked as such.

## Transport

Identical across both protocol families:

- Frame: `3E | type | seq | length (4 bytes BE) | payload | checksum | 3C`
- Checksum: wrapping sum from `type` through the last payload byte
- `3C`, `3D` and `3E` inside the body are escaped as `3D` followed by the byte minus `0x10`
- Every DATA frame received is answered with an ACK (type `01`) carrying the flipped sequence bit

Two data types exist: `0C` (DATA_MDR) and `0E` (DATA_MDR_NO2). HeadBridge accepts both, sony-tray
only `0C`. Firmware revisions differ on which one they emit, so both must be handled on receive.

## Families and detection

| | RFCOMM service UUID | Models |
|---|---|---|
| v1 (legacy) | `96CC203E-5068-46AD-B32D-E316F5E069BA` | WH-1000XM2/XM3/XM4, WH-XB900N, MDR-XB950BT |
| v2 | `956C7B26-D49A-4BA8-B03F-B17D393CB6E2` | WH-1000XM5/XM6, WF-1000XM5/XM6, WH-CH720N, ULT Wear |

The family is decided by the UUID the headset's SDP record accepts, never by model name.
SonyHeadphonesClient does exactly this in `Client.cpp`: it tries v2, falls back to legacy, and the
UUID that connected selects the parser. The per-model lists other projects publish are inference,
not measurement — SonyBridge classifies the WF-1000XM4 as v2 and the WH-1000XM4 as v1, and has
hardware-verified only the WH-CH720N.

A third transport exists, tandem over BLE (`MDR_BLE_SERVICE_UUID_TANDEM_OVER_BLE_HPC`), v2 only.
Out of scope.

## Differences between v1 and v2

Shared: framing, acknowledgement, capability discovery (`06`/`07`), and the opcodes for EQ and
NC/ambient.

Divergent:

| | v1 | v2 |
|---|---|---|
| Protocol info reply | version as Int16BE, four bytes | version as Int32BE plus two table-support bytes, eight bytes |
| Support function list | one byte per function | every function id followed by a priority byte |
| General setting capability | `D1 slot format subject summary` | `D1 slot settingType format subject summary` |
| General setting on/off | on is `01` | on is `00` |
| Battery | `10` get, `11` ret, `13` notify | `22` get, `23` ret, `25` notify |
| Power off | `22` (COMMON_SET_POWER_OFF) | `24` (POWER_SET_STATUS) |
| EQ inquired type | `01` (PRESET_EQ) | `00` |
| NC/ambient inquired type | `02` (combined NC + ambient) | `17`, `19` or `22` by variant |
| NC/ambient payload | 8 bytes | 6 to 9 bytes by variant |
| EQ presets | genre names (Rock, Pop, Jazz, Dance, EDM, R&B, Acoustic) | Bright, Excited, Mellow, Relaxed, Vocal, Treble Boost, Bass Boost, Speech |
| Support-function ids | NC+ambient `62`, ambient `63`, battery `11`, left/right `15`, case `18`, power off `21`, EQ `51` | NC `6B`/`6D`/`67`, battery `20`/`21`/`22`, EQ `50`/`52` |

The two reply layouts are confirmed by a WH-1000XM4 capture, in
[devices/WH-1000XM4.md](devices/WH-1000XM4.md). They are easy to get wrong, because the opcodes are
the same in both families and only the shape of the answer changes.

Opcode `22` collides: power off in v1, battery query in v2. Command tables and parsers have to be
separate per family rather than one table with conditionals.

## v1 noise control: mirror, do not hardcode

The combined payload is eight bytes:

```
68 | 02 | effect | ncSettingType | ncValue | asmSettingType | asmId | asmLevel
```

The implementations disagree on two of those fields:

| Source | ncSettingType | effect | Verified on |
|---|---|---|---|
| libmdr | `01` (LEVEL_ADJUSTMENT) | `01` (ON) | unverified, WIP branch |
| borea | `01` | `11` | WH-1000XM4, no releases |
| HeadBridge (docs) | `02` (DUAL_SINGLE_OFF) | `11` | WH-1000XM3 |
| sony-connect-osx | device-reported, `02` as fallback | `11` | WH-1000XM4 |

A WH-1000XM4 settles it: both the capability reply and the state reply carry `ncSettingType 02`,
so the two implementations that hardcode `01` are writing a value their own device never reported.
The capture is in [devices/WH-1000XM4.md](devices/WH-1000XM4.md).

sony-connect-osx settles it without choosing: it stores `ncSettingType`, `asmSettingType` and
`asmId` as they arrive in the device's own `67` return, and echoes them back on every set. That is
the only approach that survives differences across models and firmware revisions, and it is the one
to adopt.

`ncValue` is a single axis: `02` dual (ANC), `01` single (wind reduction), `00` off (ambient).
`asmLevel` runs 1 to 20, and `asmId` separates normal (`00`) from focus on voice (`01`).

## v2 noise variants

The announced function decides both the inquiry to use and the fields the payload carries. Sony
names the two after the same feature set, which is what pairs them up:

| Function | Inquiry | Mode field | Noise field | Trailing |
|---|---|---|---|---|
| `64` | `13` | no | on/off | |
| `65` | `14` | no | dual/single/off | |
| `68` | `15` | yes | dual/single/off | |
| `6A` | `16` | yes | dual/single/off | |
| `6B` | `17` | yes | none | |
| `6D` | `19` | yes | none | noise adaptation off, standard sensitivity |
| `67` | `22` | no | none | |

Every payload runs `68`, inquiry, value-changed, total effect, then the fields above, then the
ambient sound mode and its level. `6B`, `6D` and `67` appear in recorded sessions; the rest come
from the message definitions.

## Feature surface

libmdr defines 29 features as the protocol ceiling: identity, battery (single, left/right, case),
playback metadata and control, volume, noise cancelling, ambient sound, adaptive ambient sound,
speak-to-chat, listening modes, equalizer, DSEE, paired-device management, pairing mode, general
settings, assignable controls, noise control button, auto power off, wearing detection, auto pause,
head gestures, voice guidance and its volume, shutdown, connection mode, safe listening, and source
switch control.

What the existing applications implement:

| | NC/ambient | EQ | Battery | Power off | Volume | Speak-to-chat | Touch panel | DSEE | v1 | v2 |
|---|---|---|---|---|---|---|---|---|---|---|
| sony-connect-osx | yes | presets + 6 bands | yes | yes, plus idle timer | yes | yes | yes | no | yes | no |
| HeadBridge | yes | yes | yes | no | yes | no | no | no | yes | partial |
| borea | yes | no | yes | no | yes | no | no | no | yes | no |
| sony-tray | yes | presets + 6/10 bands | yes | yes | no | no | no | no | no | yes |
| SonyBridge | yes | yes | yes | yes | no | yes | no | yes | yes | yes |
| XMBar, sonytuibar | yes | yes | yes | yes | yes | yes | yes | yes | WIP | yes |

None covers both families at the same depth, and none ships a notarized binary.

## State of libmdr

v1 support in SonyHeadphonesClient lives on the `v1-compat` branch, unreleased, and its README
lists it as pending while asking for volunteers with hardware. The V1T1 code is written and is the
most complete reference available, but it is not validated.

## Devices

Notes per model live in [devices](devices/). A file there says which of its claims came from
hardware in hand and which came from a recorded session someone else published, because the two
are not worth the same.

## Sources

- [mos9527/SonyHeadphonesClient](https://github.com/mos9527/SonyHeadphonesClient) (MIT) — `libmdr`, protocol tables for V1T1/V1T2/V2T1/V2T2
- [abhiinhii/sony-tray](https://github.com/abhiinhii/sony-tray) (MIT) — Swift v2 implementation, verified on WH-1000XM5
- [herenickname/HeadBridge](https://github.com/herenickname/HeadBridge) (MIT) — Swift v1 implementation and wire notes, verified on WH-1000XM3
- [SapphoSys/borea](https://github.com/SapphoSys/borea) (zlib) — Swift v1, WH-1000XM4
- [tanat/sony-connect-osx](https://github.com/tanat/sony-connect-osx) (no license) — behaviour studied only, no code reused
- [ohm-app/sony-headphones-bluetooth-documentation](https://github.com/ohm-app/sony-headphones-bluetooth-documentation) — protocol notes
