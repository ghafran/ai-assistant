# Jetson Voice + Vision Assistant

An always-on, fully-offline, ChatGPT-style voice assistant with live camera vision, running entirely on a NVIDIA Jetson Orin Nano Super. Talk to it naturally, interrupt it mid-sentence, and it sees what you see through the camera.

No cloud. No API keys. No internet required after install.

---

## What it does

- **Always-on microphone** with voice activity detection — no wake word needed
- **Live camera vision** — every response has access to the current camera frame
- **Streaming speech → thought → speech pipeline** for fast conversational latency
- **Barge-in interruption** — start talking and it stops, like real conversation
- **Runs as a systemd service** and auto-starts on every boot
- **100% offline** — all models run locally on the Jetson GPU

## What it isn't

This is **not** a GPT-4o replica. You're running on a ~$500 edge device with 8GB of shared RAM, not a datacenter. Set expectations accordingly:

| Metric | This project | ChatGPT Advanced Voice |
|---|---|---|
| Response start latency | ~1-1.5 seconds | ~300-500 ms |
| Voice naturalness | Good (Kokoro TTS) | Excellent |
| Vision quality | Good for scenes/objects, weaker on fine text | Excellent |
| Conversation depth | 2-4 turns context | Long, coherent |
| Cost per query | $0 | Paid API |
| Privacy | Fully local | Cloud |
| Power draw | ~15W | Datacenter |

It feels like a real conversation, but it's not frontier-model smart. If you need GPT-4o-level quality, use GPT-4o. If you need offline, private, edge inference, this is for you.

---

## Hardware requirements

**Required:**
- Jetson Orin Nano Super Dev Kit, 8GB (the "Super" firmware update from late 2024 matters — it roughly doubles inference throughput)
- NVMe SSD, 256GB minimum — **do not run models off the SD card**
- USB webcam or CSI camera (IMX219/IMX477)
- USB microphone (array mics like ReSpeaker 2-Mic HAT work noticeably better)
- Speaker (USB or 3.5mm)
- Active cooling (the dev kit fan is fine; keep it on)

**Recommended:**
- Headphones for testing (otherwise the speaker feeds back into the mic and the bot interrupts itself)
- Gigabit ethernet for the initial model download (~8GB total across VLM, Whisper, and TTS)

**Software requirements:**
- JetPack 6.1 or later (Ubuntu 22.04 based)
- A regular user account with `sudo` privileges (not root)

---

## Architecture

```
┌─────────────┐   ┌──────────────────────────────────────────────┐
│   Camera    │──▶│ CameraSource (5 fps rolling frame buffer)    │
└─────────────┘   └──────────────┬───────────────────────────────┘
                                 │ latest JPEG (base64)
                                 ▼
┌─────────────┐   ┌──────────┐   ┌────────────┐   ┌──────────┐   ┌──────────┐
│     Mic     │──▶│ Silero   │──▶│ faster-    │──▶│  VILA    │──▶│ Kokoro   │──▶ Speaker
│  (16 kHz)   │   │   VAD    │   │ whisper    │   │  (VLM)   │   │   TTS    │   (24 kHz)
└─────────────┘   │ (CPU)    │   │ small.en   │   │ 3B INT4  │   │  ONNX    │
                  └──────────┘   │ CUDA       │   │ NanoLLM  │   │  CPU     │
                                 │ int8_fp16  │   │ :8050    │   │          │
                                 └────────────┘   └────────────┘   └──────────┘
```

Two systemd services run the show:

- **`jetson-vlm.service`** — runs the NanoLLM container serving VILA-1.5-3B over an OpenAI-compatible HTTP API on localhost:8050
- **`jetson-assistant.service`** — runs the Python voice pipeline (VAD → ASR → VLM client → TTS), depends on the VLM service being up

Plus a tiny `jetson-clocks.service` oneshot that reapplies max clocks on every boot.

## Model choices

| Stage | Model | Why |
|---|---|---|
| VAD | Silero VAD | Tiny, accurate, CPU-only |
| ASR | faster-whisper `small.en` (int8_float16) | Best quality/latency tradeoff on Orin Nano |
| VLM | VILA-1.5-3B (INT4 via MLC) | Purpose-built for Jetson, strong vision chat |
| TTS | Kokoro-82M ONNX | Dramatically better voice quality than Piper, still fast |

All swappable via config — see [Tuning](#tuning) below.

---

## Install

### 1. Flash JetPack 6.1+

Use NVIDIA SDK Manager or the official image. Boot, run through OEM setup, create your user account.

### 2. Move to NVMe

If you haven't already, migrate your root filesystem or at least `/home` to the NVMe SSD. Running models off the SD card is painfully slow and will wear it out.

### 3. Run the setup script

```bash
# Clone or copy the setup script to the Jetson
chmod +x setup_jetson_assistant.sh
./setup_jetson_assistant.sh
```

The script:
- Installs system packages, creates a Python venv, installs jetson-containers
- Enables MAX performance (Super mode) and creates 16GB swap
- Downloads Whisper, Kokoro TTS, and pre-pulls the VLM container
- Writes the agent code, launchers, and helper scripts
- Installs and enables the systemd services
- Starts everything

**Run time:** 30-60 minutes depending on network speed. Mostly waiting on apt, container pulls, and model downloads.

The script is **reentrant** — safe to re-run. See [Operations](#operations) for flags.

### 4. Verify and reboot

```bash
~/assistant/status.sh    # both services should be active (running)
~/assistant/logs.sh      # live logs
sudo reboot              # confirm auto-start works
```

After reboot you'll see the VLM container load (30-60s once cached), then the agent connect. Put on headphones and start talking.

---

## Operations

### Installer flags

```bash
./setup_jetson_assistant.sh            # resume: skip steps already completed
./setup_jetson_assistant.sh --status   # show installation progress + service state
./setup_jetson_assistant.sh --force    # re-run every step (does not wipe models)
./setup_jetson_assistant.sh --reset    # stop services, clear step markers
```

Each installation step writes a marker file to `~/assistant/.state/<step>.done` on success. Failed steps leave no marker, so re-running picks up from the last failure.

### Helper scripts

```bash
~/assistant/status.sh    # systemctl status for both services
~/assistant/logs.sh      # live tail of both journals (journalctl -f)
~/assistant/restart.sh   # restart both services in dependency order
~/assistant/stop.sh      # stop both services
```

### Direct systemctl

```bash
sudo systemctl status   jetson-vlm jetson-assistant
sudo systemctl restart  jetson-vlm jetson-assistant
sudo systemctl disable  jetson-assistant jetson-vlm   # stop auto-start on boot
sudo systemctl enable   jetson-assistant jetson-vlm   # re-enable

journalctl -u jetson-vlm -f
journalctl -u jetson-assistant -f
```

### Monitoring the Jetson

```bash
sudo tegrastats          # real-time GPU/CPU/RAM/temp
sudo nvpmodel -q         # confirm power mode (should be "MODE_MAXN" on Super)
```

---

## Tuning

Config is driven by environment variables in `/etc/systemd/system/jetson-assistant.service`. Edit, then `sudo systemctl daemon-reload && ~/assistant/restart.sh`.

| Variable | Default | Notes |
|---|---|---|
| `CAMERA_INDEX` | `0` | v4l2 device index. `v4l2-ctl --list-devices` to find yours |
| `TTS_VOICE` | `af_sarah` | Kokoro voice ID. Try `am_adam`, `af_bella`, `bf_emma`, etc. |
| `TTS_SPEED` | `1.1` | 1.0 = natural pace; >1 faster |
| `VLM_ENDPOINT` | `http://localhost:8050/v1/chat/completions` | Change if hosting VLM elsewhere |

### Swap the VLM

Edit `~/assistant/start_vlm.sh` and change the `--model` flag. Alternatives that fit in 8GB:

- `Efficient-Large-Model/VILA1.5-3b` — default; best overall
- `Qwen/Qwen2-VL-2B-Instruct` — snappier, stronger on OCR
- `Efficient-Large-Model/Llama-3-VILA1.5-8b` — tight fit, slower, higher quality

Then `~/assistant/restart.sh`.

### Swap the ASR

In `voice_agent.py`, change `FasterWhisperSTT("small.en")` to `"base.en"` (faster, less accurate) or `"medium.en"` (slower, more accurate). Restart the agent service.

### Reduce latency

In order of impact:
1. Move to a smaller VLM (Qwen2-VL-2B)
2. Drop Whisper to `base.en`
3. Lower `max_new_tokens` in `start_vlm.sh` (default 150 → try 100)
4. Shorten `MAX_HISTORY` in `voice_agent.py`

### Change personality

Edit `SYSTEM_PROMPT` in `voice_agent.py`, restart the agent service.

---

## Troubleshooting

### Agent service keeps restarting

Check the logs: `journalctl -u jetson-assistant -n 100`. Common causes:

- **VLM not up yet** — the agent waits up to 20 minutes for the VLM's health endpoint but will give up eventually. Check `journalctl -u jetson-vlm`
- **Camera index wrong** — run `v4l2-ctl --list-devices`, update `CAMERA_INDEX` env in the service unit
- **No audio devices** — verify `arecord -l` and `aplay -l` work as your user

### VLM service never becomes ready

First-run downloads can take 10-15 minutes. Tail logs with `journalctl -u jetson-vlm -f`. If it's genuinely stuck (no progress for 10+ min):

```bash
sudo systemctl stop jetson-vlm
docker rm -f vlm-server
sudo systemctl start jetson-vlm
```

If you see CUDA out-of-memory, your swap isn't active or you picked a model too big for 8GB. Verify with `free -h` and `nvpmodel -q`.

### Bot interrupts itself constantly

Your speaker output is feeding into the mic. Three fixes (in order of preference):

1. **Wear headphones** while testing
2. **Use a directional mic** (ReSpeaker array, shotgun mic)
3. **Enable echo cancellation** in PulseAudio — add `load-module module-echo-cancel` to `~/.config/pulse/default.pa`

### No audio from service but works when run manually

This is almost always a session/permissions issue. Verify:

```bash
loginctl show-user $USER | grep Linger       # should be Linger=yes
ls -la /run/user/$(id -u)/pulse/native       # should exist
groups $USER | grep -E 'audio|video'         # should include both
```

The installer enables linger, but if audio still fails, reboot once — PulseAudio needs the session socket to exist before the service can reach it.

### Device runs hot / throttles

```bash
sudo tegrastats
```

If you see `thermal` numbers above 75°C or frequent downclocking, either improve cooling or drop to 15W mode:

```bash
sudo nvpmodel -m 1
```

You lose about 30% inference throughput but the device stops thermal throttling.

### Something else

Full setup log: `~/assistant/setup.log`. Service logs via `journalctl`. The `--status` flag on the installer shows which steps completed successfully.

---

## Project layout

```
~/assistant/
├── voice_agent.py          # main pipeline (VAD → ASR → VLM → TTS)
├── start_vlm.sh            # launches the VLM container
├── start_agent.sh          # launches the voice pipeline
├── status.sh logs.sh       # operational helpers
├── restart.sh stop.sh      # operational helpers
├── models/
│   ├── kokoro-v0_19.onnx
│   └── voices.bin
├── .state/                 # installer step markers (do not edit)
└── setup.log

~/assistant-env/            # Python virtualenv
~/jetson-containers/        # dusty-nv/jetson-containers clone

/etc/systemd/system/
├── jetson-clocks.service
├── jetson-vlm.service
└── jetson-assistant.service
```

---

## Performance expectations

Measured on an Orin Nano Super 8GB with NVMe storage, VILA-1.5-3B + Whisper small.en + Kokoro:

| Stage | Typical latency |
|---|---|
| Speech end → ASR final | 150-300 ms |
| ASR → VLM first token | 600-1200 ms |
| VLM first token → first audio out | 100-200 ms |
| **End-of-speech → first audible reply** | **~900-1700 ms** |
| Sustained generation speed | ~20-30 tokens/sec |
| Cold boot → ready (cached models) | 30-60 s |
| First-ever boot (downloads VLM) | 10-15 min |

RAM usage at steady state is roughly 6.5-7GB of 8GB, which is why swap matters.

---

## Credits

Built on excellent open-source work:

- **[jetson-containers](https://github.com/dusty-nv/jetson-containers)** by dustynv — container orchestration for Jetson
- **[NanoLLM](https://dusty-nv.github.io/NanoLLM/)** — optimized LLM/VLM serving on Jetson
- **[VILA](https://github.com/NVlabs/VILA)** — the vision-language model
- **[faster-whisper](https://github.com/SYSTRAN/faster-whisper)** — CUDA-accelerated Whisper
- **[Kokoro TTS](https://github.com/thewh1teagle/kokoro-onnx)** — fast high-quality offline TTS
- **[Pipecat](https://github.com/pipecat-ai/pipecat)** by Daily — real-time voice agent framework
- **[Silero VAD](https://github.com/snakers4/silero-vad)** — voice activity detection

## License

The glue code in this project (setup script, `voice_agent.py`, helpers) is provided as-is. Each upstream model and library carries its own license — review them before commercial use, especially the VLM weights.
