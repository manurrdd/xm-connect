# Device coverage

The app never decides what a headset can do from its model name. It connects to whichever MDR
service the headset answers on, asks what functions it announces, and draws only those. What
follows is therefore about evidence, not about a list of permitted devices.

| Evidence | Devices |
|---|---|
| Confirmed on hardware | WH-1000XM4 |
| Checked against a recorded session | WF-1000XM5 (firmware 6.1.0) |
| Same command table, untried | WH-1000XM2, WH-1000XM3, WF-1000XM3, WI-1000XM2 |
| Same command table, untried | WH-1000XM5, WH-1000XM6, WF-1000XM4, WF-1000XM6 |

"Confirmed" means someone changed a setting and the headset obeyed. "Checked against a recording"
means the parsers agree with frames a device really sent, which proves reading and proves nothing
about writing. "Untried" means the device speaks a command table this project implements, and
nobody has run it.

Per-model notes are in this directory. Each one says where its claims come from.

## What is implemented

Noise cancelling, wind reduction where the device has a field for it, ambient sound with its own
level range and focus on voice, the equalizer with the presets the device publishes, battery for
headphones and earbud cases, power off, and the general settings the device announces, under the
names it gives them. On v1 also DSEE, speak-to-chat, pause when removed, and when the headset
powers itself off.

Every v2 noise variant that carries an ambient level is covered: the announced function picks the
inquiry and the payload shape, so a device announcing `64`, `65`, `68`, `6A`, `6B`, `6D` or `67`
is handled. Only `6B`, `6D` and `67` have ever been seen in a capture.

## What is not

- v1 devices that announce noise cancelling (`61`) or ambient sound (`63`) on their own instead of
  the combined `62`. Their payloads are shorter and differ; every XM model announces the combined
  one, so this is a gap for older non-XM hardware.
- v2 variants with no ambient level: `01`, `11`, `12` and `21`. Ambient there is a switch rather
  than a slider, and guessing at it is worse than leaving it out.
- Table 2. It rides on its own data type, repeats opcodes with other meanings, and carries a second
  function list in a different id namespace. Frames arriving on it are acknowledged and ignored,
  which is why reading a WF-1000XM5 does not corrupt what table 1 said.
- Assignable controls, adaptive sound control, the noise cancelling optimizer, playback volume,
  connection mode, voice guidance and paired device management. A WH-1000XM4 announces all of them
  and answers when asked; the replies are in its notes.
- Everything outside v1 for the settings above: a v2 headset is asked for none of them, because
  nothing has confirmed the opcodes carry the same meaning there.

## Reporting a device

`swift run xmprobe --explore` prints everything a headset announces and answers, decoded where
possible and in hex where not. That output is what a model's notes are made of.
