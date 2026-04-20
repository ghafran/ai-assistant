#!/usr/bin/env bash
# =============================================================================
# Jetson Orin Nano — Offline Voice+Vision Assistant Setup (Reentrant)
# =============================================================================
# Target: Jetson Orin Nano Super (8GB), JetPack 6.1+
# Result: Always-on, offline, ChatGPT-style voice agent with live camera vision
#
# Reentrant: safe to run multiple times. Each step checks if already done.
# Services: everything runs via systemd and auto-starts on boot.
#
# Usage:
#   chmod +x setup_jetson_assistant.sh
#   ./setup_jetson_assistant.sh            # full setup
#   ./setup_jetson_assistant.sh --status   # check what's done
#   ./setup_jetson_assistant.sh --reset    # wipe state, stop services
#   ./setup_jetson_assistant.sh --force    # re-run every step
#
# Run as a regular user with sudo privileges. Do NOT run with sudo directly.
# =============================================================================

set -euo pipefail

# ---- Config ----------------------------------------------------------------
INSTALL_DIR="${HOME}/assistant"
VENV_DIR="${HOME}/assistant-env"
MODELS_DIR="${INSTALL_DIR}/models"
STATE_DIR="${INSTALL_DIR}/.state"
LOG_FILE="${INSTALL_DIR}/setup.log"
SWAP_SIZE_GB=16
PYTHON_BIN="python3"
JC_DIR="${HOME}/jetson-containers"

SVC_VLM="jetson-vlm"
SVC_AGENT="jetson-assistant"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# ---- Arg parsing -----------------------------------------------------------
FORCE=0
ACTION="install"
for arg in "$@"; do
    case "$arg" in
        --force)  FORCE=1 ;;
        --status) ACTION="status" ;;
        --reset)  ACTION="reset" ;;
        --help|-h) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "Unknown arg: $arg"; exit 1 ;;
    esac
done

mkdir -p "${INSTALL_DIR}" "${MODELS_DIR}" "${STATE_DIR}"
: >> "${LOG_FILE}"

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*" | tee -a "${LOG_FILE}"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"   | tee -a "${LOG_FILE}"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "${LOG_FILE}"; }
err()  { echo -e "${RED}[ERR]${NC} $*"    | tee -a "${LOG_FILE}"; exit 1; }
skip() { echo -e "${YELLOW}[SKIP]${NC} $* (done; use --force to redo)" | tee -a "${LOG_FILE}"; }

# ---- Idempotency helpers ---------------------------------------------------
# Each step writes a marker file on success. If present and --force not set,
# the step is skipped on subsequent runs.
step_done()  { [[ -f "${STATE_DIR}/$1.done" ]]; }
mark_done()  { date -u +%FT%TZ > "${STATE_DIR}/$1.done"; }

run_step() {
    local name="$1"; shift
    local fn="$1"; shift
    if step_done "$name" && [[ $FORCE -eq 0 ]]; then
        skip "$name"; return 0
    fi
    log "Running step: $name"
    if "$fn" "$@"; then
        mark_done "$name"
        ok "Finished step: $name"
    else
        err "Step failed: $name (rerun after fixing; marker NOT written)"
    fi
}

# ---- Actions: status / reset ----------------------------------------------
show_status() {
    echo "=========================================="
    echo " Setup status"
    echo "=========================================="
    echo " State dir: ${STATE_DIR}"
    echo
    local any=0
    for marker in "${STATE_DIR}"/*.done; do
        [[ -e "$marker" ]] || break
        any=1
        printf "  ✓ %-30s %s\n" "$(basename "$marker" .done)" "$(cat "$marker")"
    done
    [[ $any -eq 0 ]] && echo "  (no steps completed)"
    echo
    echo " Services:"
    for svc in "${SVC_VLM}" "${SVC_AGENT}"; do
        if systemctl list-unit-files "${svc}.service" &>/dev/null; then
            local e a
            e=$(systemctl is-enabled "${svc}.service" 2>/dev/null || echo "?")
            a=$(systemctl is-active  "${svc}.service" 2>/dev/null || echo "?")
            printf "  %-25s enabled=%-10s active=%s\n" "${svc}" "$e" "$a"
        else
            printf "  %-25s not installed\n" "${svc}"
        fi
    done
    echo
    exit 0
}

do_reset() {
    echo "This stops services and wipes setup markers (models kept on disk)."
    read -r -p "Continue? [y/N] " ans
    [[ "${ans}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
    sudo systemctl disable --now "${SVC_AGENT}.service" 2>/dev/null || true
    sudo systemctl disable --now "${SVC_VLM}.service"   2>/dev/null || true
    rm -rf "${STATE_DIR}"
    mkdir -p "${STATE_DIR}"
    ok "Reset done. Re-run this script to reinstall."
    exit 0
}

[[ "$ACTION" == "status" ]] && show_status
[[ "$ACTION" == "reset"  ]] && do_reset

# ---- Preflight -------------------------------------------------------------
if [[ $EUID -eq 0 ]]; then
    err "Do not run this script as root. Run as your normal user with sudo privileges."
fi

log "Starting Jetson assistant setup (reentrant). Logs: ${LOG_FILE}"

if [[ ! -f /etc/nv_tegra_release ]]; then
    err "Not a Jetson device (/etc/nv_tegra_release missing)."
fi
log "Jetson: $(head -1 /etc/nv_tegra_release)"

# Keep sudo alive for the whole run
sudo -v
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill ${SUDO_KEEPALIVE_PID} 2>/dev/null || true' EXIT

# =============================================================================
# STEPS
# =============================================================================

step_system_packages() {
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        python3-pip python3-venv python3-dev \
        git cmake build-essential pkg-config curl wget \
        libportaudio2 portaudio19-dev libsndfile1 libsndfile1-dev \
        ffmpeg v4l-utils alsa-utils pulseaudio pulseaudio-utils \
        libopenblas-dev libomp-dev \
        libjpeg-dev zlib1g-dev \
        libcurl4-openssl-dev libssl-dev \
        jq htop nvme-cli
}

step_performance_mode() {
    sudo nvpmodel -m 0 || warn "nvpmodel -m 0 failed (need JetPack 6.1+ for Super mode)"
    sudo jetson_clocks || warn "jetson_clocks failed"

    # Persist max clocks at every boot
    sudo tee /etc/systemd/system/jetson-clocks.service > /dev/null <<'UNIT'
[Unit]
Description=Apply Jetson max clocks at boot
After=nvpmodel.service
Wants=nvpmodel.service

[Service]
Type=oneshot
ExecStart=/usr/bin/jetson_clocks
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
    sudo systemctl daemon-reload
    sudo systemctl enable --now jetson-clocks.service || warn "jetson-clocks service enable failed"
}

step_swap() {
    if swapon --show 2>/dev/null | grep -q "/swapfile"; then
        log "Swap already active"
    else
        if [[ ! -f /swapfile ]]; then
            sudo fallocate -l "${SWAP_SIZE_GB}G" /swapfile
            sudo chmod 600 /swapfile
            sudo mkswap /swapfile
        fi
        sudo swapon /swapfile
    fi
    if ! grep -q "^/swapfile " /etc/fstab; then
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    fi
    # zram competes with disk swap for model paging — disable it
    if systemctl list-unit-files nvzramconfig.service &>/dev/null; then
        sudo systemctl disable --now nvzramconfig 2>/dev/null || true
    fi
}

step_hw_probe() {
    {
        echo "--- Cameras ---"; v4l2-ctl --list-devices 2>&1 || echo "(none)"
        echo "--- Audio in ---"; arecord -l 2>&1 || echo "(none)"
        echo "--- Audio out ---"; aplay -l 2>&1 || echo "(none)"
    } | tee -a "${LOG_FILE}"
}

step_venv() {
    if [[ ! -d "${VENV_DIR}" ]]; then
        ${PYTHON_BIN} -m venv "${VENV_DIR}"
    fi
    # shellcheck source=/dev/null
    source "${VENV_DIR}/bin/activate"
    pip install --upgrade pip setuptools wheel
}

step_jetson_containers() {
    if [[ ! -d "${JC_DIR}" ]]; then
        git clone --depth 1 https://github.com/dusty-nv/jetson-containers "${JC_DIR}"
    else
        git -C "${JC_DIR}" pull --ff-only || warn "jetson-containers pull failed; continuing"
    fi
    pushd "${JC_DIR}" >/dev/null
    bash install.sh
    popd >/dev/null

    # Make sure this user can run docker without sudo (needed by run.sh)
    if ! groups "${USER}" | grep -qw docker; then
        sudo usermod -aG docker "${USER}"
        warn "Added ${USER} to docker group. You may need to log out/in for it to take effect for interactive shells (services already see it)."
    fi
}

step_python_deps() {
    # shellcheck source=/dev/null
    source "${VENV_DIR}/bin/activate"
    pip install --no-cache-dir \
        "numpy<2.0" opencv-python pillow sounddevice \
        aiohttp aiofiles python-dotenv
    pip install --no-cache-dir silero-vad onnxruntime
    pip install --no-cache-dir faster-whisper
    pip install --no-cache-dir "pipecat-ai[silero]" || warn "pipecat install had issues"
    pip install --no-cache-dir kokoro-onnx soundfile
}

step_download_tts_models() {
    local m="${MODELS_DIR}/kokoro-v0_19.onnx"
    local v="${MODELS_DIR}/voices.bin"
    if [[ ! -s "${m}" ]]; then
        wget --continue -O "${m}.part" \
            https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files/kokoro-v0_19.onnx
        mv "${m}.part" "${m}"
    fi
    if [[ ! -s "${v}" ]]; then
        wget --continue -O "${v}.part" \
            https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files/voices.bin
        mv "${v}.part" "${v}"
    fi
}

step_cache_whisper() {
    # shellcheck source=/dev/null
    source "${VENV_DIR}/bin/activate"
    python - <<'PY'
from faster_whisper import WhisperModel
WhisperModel("small.en", device="cuda", compute_type="int8_float16")
print("Whisper small.en cached OK")
PY
}

step_pull_vlm_container() {
    pushd "${JC_DIR}" >/dev/null
    local tag
    tag=$(./autotag nano_llm 2>/dev/null | tail -1 || true)
    if [[ -z "${tag}" ]]; then
        warn "autotag nano_llm returned empty; service will pull at first run"
        popd >/dev/null; return 0
    fi
    ./run.sh --workdir /opt "${tag}" bash -c 'echo nano_llm cached' \
        || warn "Container prepull failed — will pull at first service run"
    popd >/dev/null
}

step_write_agent_code() {
cat > "${INSTALL_DIR}/voice_agent.py" <<'PYEOF'
#!/usr/bin/env python3
"""Offline voice+vision assistant. Streaming duplex with barge-in."""
import asyncio, aiohttp, base64, cv2, json, os, sys, time, logging
import numpy as np
from pathlib import Path

from pipecat.frames.frames import (
    AudioRawFrame, TextFrame, EndFrame,
    UserStartedSpeakingFrame, UserStoppedSpeakingFrame,
)
from pipecat.pipeline.pipeline import Pipeline
from pipecat.pipeline.runner import PipelineRunner
from pipecat.pipeline.task import PipelineTask, PipelineParams
from pipecat.processors.frame_processor import FrameProcessor
from pipecat.vad.silero import SileroVADAnalyzer
from pipecat.transports.local.audio import LocalAudioTransport, LocalAudioTransportParams

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
log = logging.getLogger("assistant")

ROOT = Path(__file__).parent
MODELS = ROOT / "models"
VLM_ENDPOINT = os.getenv("VLM_ENDPOINT", "http://localhost:8050/v1/chat/completions")
CAMERA_INDEX = int(os.getenv("CAMERA_INDEX", "0"))
VOICE = os.getenv("TTS_VOICE", "af_sarah")
TTS_SPEED = float(os.getenv("TTS_SPEED", "1.1"))
MAX_HISTORY = 4

SYSTEM_PROMPT = """You are a helpful voice assistant with vision. You see through a camera and speak through a speaker.
Rules:
- Keep replies short and conversational — this is voice, not text.
- Describe what you see naturally when relevant ("I can see you're holding...").
- One or two sentences is usually enough.
- If the user asks about something visual, use the image. If not, just chat.
- Never use markdown, bullets, or formatting. Plain spoken language only."""


class CameraSource:
    def __init__(self, device=0, fps=5):
        self.device, self.fps = device, fps
        self.latest_b64 = None
        self._cap, self._running = None, False

    def _open(self):
        self._cap = cv2.VideoCapture(self.device)
        if not self._cap.isOpened():
            raise RuntimeError(f"Cannot open camera {self.device}")
        self._cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        self._cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        log.info(f"Camera {self.device} opened")

    async def run(self):
        self._open()
        self._running = True
        interval = 1.0 / self.fps
        while self._running:
            ret, frame = self._cap.read()
            if ret:
                frame_s = cv2.resize(frame, (448, 448))
                ok_, buf = cv2.imencode('.jpg', frame_s, [cv2.IMWRITE_JPEG_QUALITY, 85])
                if ok_:
                    self.latest_b64 = base64.b64encode(buf).decode()
            await asyncio.sleep(interval)

    def stop(self):
        self._running = False
        if self._cap: self._cap.release()


camera = CameraSource(device=CAMERA_INDEX)

from faster_whisper import WhisperModel


class FasterWhisperSTT(FrameProcessor):
    def __init__(self, model_size="small.en"):
        super().__init__()
        log.info(f"Loading Whisper {model_size}...")
        self.model = WhisperModel(model_size, device="cuda", compute_type="int8_float16")
        self._buf = bytearray(); self._speaking = False
        log.info("Whisper loaded")

    async def process_frame(self, frame, direction):
        await super().process_frame(frame, direction)
        if isinstance(frame, UserStartedSpeakingFrame):
            self._buf.clear(); self._speaking = True
            await self.push_frame(frame, direction); return
        if isinstance(frame, UserStoppedSpeakingFrame):
            self._speaking = False
            if len(self._buf) > 3200:
                audio = np.frombuffer(bytes(self._buf), dtype=np.int16).astype(np.float32) / 32768.0
                t0 = time.time()
                segments, _ = self.model.transcribe(
                    audio, language="en", beam_size=1,
                    vad_filter=False, condition_on_previous_text=False)
                text = " ".join(s.text for s in segments).strip()
                log.info(f"ASR ({time.time()-t0:.2f}s): {text!r}")
                if text: await self.push_frame(TextFrame(text))
            self._buf.clear()
            await self.push_frame(frame, direction); return
        if isinstance(frame, AudioRawFrame) and self._speaking:
            self._buf.extend(frame.audio)
        await self.push_frame(frame, direction)


class VLMProcessor(FrameProcessor):
    def __init__(self, endpoint):
        super().__init__()
        self.endpoint = endpoint; self.history = []

    async def process_frame(self, frame, direction):
        await super().process_frame(frame, direction)
        if not isinstance(frame, TextFrame):
            await self.push_frame(frame, direction); return
        user_text = frame.text.strip()
        if not user_text: return

        content = [{"type": "text", "text": user_text}]
        if camera.latest_b64:
            content.append({"type": "image_url",
                "image_url": {"url": f"data:image/jpeg;base64,{camera.latest_b64}"}})
        self.history.append({"role": "user", "content": content})

        messages = [{"role": "system", "content": SYSTEM_PROMPT}]
        messages.extend(self.history[-(MAX_HISTORY * 2):])
        payload = {"messages": messages, "stream": True, "max_tokens": 150, "temperature": 0.7}

        t0 = time.time(); first = False; assistant_text = ""
        try:
            timeout = aiohttp.ClientTimeout(total=60, connect=5)
            async with aiohttp.ClientSession(timeout=timeout) as session:
                async with session.post(self.endpoint, json=payload) as resp:
                    if resp.status != 200:
                        body = await resp.text()
                        log.error(f"VLM {resp.status}: {body[:200]}")
                        await self.push_frame(TextFrame("Sorry, I had a problem thinking about that."))
                        return
                    async for raw in resp.content:
                        line = raw.decode(errors='ignore').strip()
                        if not line or not line.startswith("data:"): continue
                        data = line[5:].strip()
                        if data == "[DONE]": break
                        try:
                            obj = json.loads(data)
                            delta = obj["choices"][0].get("delta", {}).get("content", "")
                        except Exception:
                            continue
                        if delta:
                            if not first:
                                log.info(f"VLM first token in {time.time()-t0:.2f}s"); first = True
                            assistant_text += delta
                            await self.push_frame(TextFrame(delta))
            if assistant_text:
                self.history.append({"role": "assistant", "content": assistant_text})
            log.info(f"VLM done ({time.time()-t0:.2f}s): {assistant_text!r}")
        except asyncio.TimeoutError:
            log.error("VLM timeout")
            await self.push_frame(TextFrame("Sorry, that took too long."))
        except Exception as e:
            log.exception(f"VLM failure: {e}")
            await self.push_frame(TextFrame("Sorry, something went wrong."))


class KokoroTTSProcessor(FrameProcessor):
    def __init__(self, model_path, voices_path, voice="af_sarah", speed=1.1):
        super().__init__()
        from kokoro_onnx import Kokoro
        log.info("Loading Kokoro TTS...")
        self.tts = Kokoro(str(model_path), str(voices_path))
        self.voice, self.speed = voice, speed
        self._buf = ""
        log.info("Kokoro loaded")

    def _flush(self, b):
        return any(b.endswith(p) for p in (".", "!", "?", "\n")) or len(b) > 120

    async def _say(self, text):
        text = text.strip()
        if not text: return
        loop = asyncio.get_event_loop()
        samples, sr = await loop.run_in_executor(
            None, lambda: self.tts.create(text, voice=self.voice, speed=self.speed, lang="en-us"))
        pcm = (samples * 32767).astype(np.int16).tobytes()
        await self.push_frame(AudioRawFrame(pcm, sr, 1))

    async def process_frame(self, frame, direction):
        await super().process_frame(frame, direction)
        if isinstance(frame, TextFrame):
            self._buf += frame.text
            if self._flush(self._buf):
                chunk, self._buf = self._buf, ""
                await self._say(chunk)
            return
        if isinstance(frame, (UserStartedSpeakingFrame, EndFrame)):
            if self._buf.strip() and isinstance(frame, EndFrame):
                chunk, self._buf = self._buf, ""
                await self._say(chunk)
            else:
                self._buf = ""
        await self.push_frame(frame, direction)


async def wait_for_vlm(timeout=1200):
    log.info(f"Waiting for VLM at {VLM_ENDPOINT} (up to {timeout}s)...")
    deadline = time.time() + timeout
    async with aiohttp.ClientSession() as session:
        while time.time() < deadline:
            try:
                url = VLM_ENDPOINT.replace("/chat/completions", "/models")
                async with session.get(url, timeout=aiohttp.ClientTimeout(total=3)) as r:
                    if r.status < 500:
                        log.info("VLM is up"); return True
            except Exception:
                pass
            await asyncio.sleep(3)
    return False


async def main():
    if not await wait_for_vlm():
        log.error("VLM never came up."); sys.exit(1)

    cam_task = asyncio.create_task(camera.run())
    await asyncio.sleep(1)

    transport = LocalAudioTransport(LocalAudioTransportParams(
        audio_in_enabled=True, audio_out_enabled=True,
        audio_in_sample_rate=16000, audio_out_sample_rate=24000,
        vad_enabled=True, vad_analyzer=SileroVADAnalyzer(),
        vad_audio_passthrough=True,
    ))
    stt = FasterWhisperSTT("small.en")
    vlm = VLMProcessor(VLM_ENDPOINT)
    tts = KokoroTTSProcessor(MODELS / "kokoro-v0_19.onnx", MODELS / "voices.bin",
                             voice=VOICE, speed=TTS_SPEED)

    pipeline = Pipeline([transport.input(), stt, vlm, tts, transport.output()])
    task = PipelineTask(pipeline, PipelineParams(allow_interruptions=True, enable_metrics=True))
    log.info("Assistant live. Start talking.")
    runner = PipelineRunner()
    try: await runner.run(task)
    finally:
        camera.stop(); cam_task.cancel()

if __name__ == "__main__":
    try: asyncio.run(main())
    except KeyboardInterrupt: log.info("Bye.")
PYEOF
    chmod +x "${INSTALL_DIR}/voice_agent.py"
}

step_write_launchers() {
cat > "${INSTALL_DIR}/start_vlm.sh" <<EOF
#!/usr/bin/env bash
# NanoLLM VLM server on :8050 (OpenAI-compatible API).
set -e
cd "${JC_DIR}"
TAG=\$(./autotag nano_llm | tail -1)
docker rm -f vlm-server 2>/dev/null || true
exec ./run.sh --name vlm-server -p 8050:8050 "\${TAG}" \\
    python3 -m nano_llm.agents.web_chat \\
        --api mlc \\
        --model Efficient-Large-Model/VILA1.5-3b \\
        --vision-model openai/clip-vit-large-patch14-336 \\
        --max-new-tokens 150 \\
        --web-port 8050
EOF

cat > "${INSTALL_DIR}/start_agent.sh" <<EOF
#!/usr/bin/env bash
set -e
# shellcheck source=/dev/null
source "${VENV_DIR}/bin/activate"
cd "${INSTALL_DIR}"
exec python voice_agent.py
EOF

    chmod +x "${INSTALL_DIR}/start_vlm.sh" "${INSTALL_DIR}/start_agent.sh"
}

step_install_services() {
    # VLM service
    sudo tee /etc/systemd/system/${SVC_VLM}.service > /dev/null <<EOF
[Unit]
Description=NanoLLM Vision-Language Model Server
After=network-online.target docker.service
Wants=network-online.target docker.service
Requires=docker.service

[Service]
Type=simple
User=${USER}
Group=${USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/start_vlm.sh
ExecStop=/usr/bin/docker stop vlm-server
ExecStopPost=/usr/bin/docker rm -f vlm-server
Restart=always
RestartSec=10
TimeoutStartSec=1200
LimitMEMLOCK=infinity
SuccessExitStatus=0 1

[Install]
WantedBy=multi-user.target
EOF

    # Agent service
    local uid
    uid=$(id -u "${USER}")
    sudo tee /etc/systemd/system/${SVC_AGENT}.service > /dev/null <<EOF
[Unit]
Description=Jetson Voice+Vision Assistant
After=sound.target ${SVC_VLM}.service
Wants=${SVC_VLM}.service
Requires=${SVC_VLM}.service

[Service]
Type=simple
User=${USER}
Group=${USER}
SupplementaryGroups=audio video
WorkingDirectory=${INSTALL_DIR}
Environment="VLM_ENDPOINT=http://localhost:8050/v1/chat/completions"
Environment="CAMERA_INDEX=0"
Environment="TTS_VOICE=af_sarah"
Environment="TTS_SPEED=1.1"
Environment="XDG_RUNTIME_DIR=/run/user/${uid}"
Environment="PULSE_SERVER=unix:/run/user/${uid}/pulse/native"
ExecStart=${INSTALL_DIR}/start_agent.sh
Restart=always
RestartSec=5
TimeoutStartSec=900

[Install]
WantedBy=multi-user.target
EOF

    # User linger lets the user's Pulse/session survive without login.
    # Essential for headless boot-time audio.
    sudo loginctl enable-linger "${USER}" || warn "loginctl enable-linger failed"

    sudo systemctl daemon-reload
}

step_write_helpers() {
    cat > "${INSTALL_DIR}/status.sh" <<EOF
#!/usr/bin/env bash
systemctl status ${SVC_VLM}.service --no-pager || true
echo
systemctl status ${SVC_AGENT}.service --no-pager || true
EOF
    cat > "${INSTALL_DIR}/logs.sh" <<EOF
#!/usr/bin/env bash
exec journalctl -u ${SVC_VLM}.service -u ${SVC_AGENT}.service -f -n 100
EOF
    cat > "${INSTALL_DIR}/restart.sh" <<EOF
#!/usr/bin/env bash
sudo systemctl restart ${SVC_VLM}.service
sleep 3
sudo systemctl restart ${SVC_AGENT}.service
echo "Restarted. Tail: ${INSTALL_DIR}/logs.sh"
EOF
    cat > "${INSTALL_DIR}/stop.sh" <<EOF
#!/usr/bin/env bash
sudo systemctl stop ${SVC_AGENT}.service
sudo systemctl stop ${SVC_VLM}.service
EOF
    chmod +x "${INSTALL_DIR}"/{status,logs,restart,stop}.sh
}

step_enable_services() {
    # Enable at boot
    sudo systemctl enable "${SVC_VLM}.service"
    sudo systemctl enable "${SVC_AGENT}.service"

    # Start now (idempotent: restart handles already-running)
    sudo systemctl restart "${SVC_VLM}.service"
    sleep 5
    sudo systemctl restart "${SVC_AGENT}.service"
}

# =============================================================================
# EXECUTE
# =============================================================================
run_step system_packages      step_system_packages
run_step performance_mode     step_performance_mode
run_step swap                 step_swap
run_step hw_probe             step_hw_probe
run_step venv                 step_venv
run_step jetson_containers    step_jetson_containers
run_step python_deps          step_python_deps
run_step download_tts_models  step_download_tts_models
run_step cache_whisper        step_cache_whisper
run_step pull_vlm_container   step_pull_vlm_container
run_step write_agent_code     step_write_agent_code
run_step write_launchers      step_write_launchers
run_step install_services     step_install_services
run_step write_helpers        step_write_helpers
run_step enable_services      step_enable_services

# =============================================================================
# REPORT
# =============================================================================
cat <<EOF

============================================================
 SETUP COMPLETE — services installed, enabled, and running
============================================================

Install dir:    ${INSTALL_DIR}
Virtualenv:     ${VENV_DIR}
Models:         ${MODELS_DIR}
State markers:  ${STATE_DIR}
Log file:       ${LOG_FILE}

SERVICES (start automatically on every boot)
--------------------------------------------
  ${SVC_VLM}.service     VLM container on :8050
  ${SVC_AGENT}.service   Voice+vision agent

HELPERS
-------
  ${INSTALL_DIR}/status.sh    service status
  ${INSTALL_DIR}/logs.sh      live tail of both services
  ${INSTALL_DIR}/restart.sh   restart both
  ${INSTALL_DIR}/stop.sh      stop both

RERUN THIS SCRIPT
-----------------
  ./setup_jetson_assistant.sh            # skip finished steps
  ./setup_jetson_assistant.sh --status   # show progress + service state
  ./setup_jetson_assistant.sh --force    # redo all steps
  ./setup_jetson_assistant.sh --reset    # stop services, wipe markers

FIRST BOOT
----------
On the very first run the VLM service will download ~4GB of model weights.
Expect 10-15 minutes before the agent responds. Watch progress with:
  ${INSTALL_DIR}/logs.sh

GOTCHAS
-------
- Without echo cancellation your speaker will retrigger the mic.
  Use headphones, a directional mic, or enable ALSA/Pulse AEC.
- If audio fails as a service, the most common cause is that user linger
  isn't active. Verify: loginctl show-user ${USER} | grep Linger
- Reboot to confirm auto-start works:  sudo reboot

============================================================
EOF