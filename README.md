# VAS CONTROL — TouchOSC for d&b En-Space

TouchOSC control surface for **d&b audiotechnik DS100 / DS100M / DS110** En-Space, modelled after Companion *Spezial Presets*: one shared Matrix Input, En-Space send gain, and exclusive zone routing (zones 1–4).

## Download

**[VAS CONTROL 1.0.tosc](VAS%20CONTROL%201.0.tosc)** — open in [TouchOSC](https://hexler.net/touchosc) (Mk2).

Pre-releases: `VAS CONTROL beta 0.01` … `0.04` in the repo (kept for history).

## OSC connection (TouchOSC)

| Setting | Value |
|---------|-------|
| Host | IP of the Soundscape engine |
| Send port | **50010** |
| Receive port | **50011** |

Both directions must be enabled. The DS100 replies on port **50011**. If Companion or another tool already listens on 50011, polling will not work.

## Features (1.0)

- Matrix Input **1–128** via encoder, **inputDec** / **inputInc**
- En-Space send gain fader (−120 … +24 dB) with **X32/Glue-style** fader law
- Zones 1–4: grey at −120 dB, zone colour at 0 dB; **only one zone on** at a time
- Zone 2 (center) on-colour: **magenta** RGB 255, 0, 255
- Polling: send gain, zone gains, channel name every **500 ms**; matrix input count every **2 s**

## Build from source

```bash
# New beta (0.05, 0.06, …) from highest existing beta
python3 scripts/pack-tosc.py

# Stable 1.0 from latest beta + lua/vas-control.lua
python3 scripts/pack-tosc.py --stable
```

- Layout source: highest `VAS CONTROL beta 0.xx.tosc`
- Logic: [`lua/vas-control.lua`](lua/vas-control.lua)

## OSC paths (prefix `/dbaudio1`)

- `/matrixinput/reverbsendgain/{n}`
- `/matrixinput/channelname/{n}`
- `/reverbinput/gain/{n}/{zone}`
- `/status/matrixinputcount`

## License

MIT — see repository license. d&b and TouchOSC are trademarks of their respective owners.
