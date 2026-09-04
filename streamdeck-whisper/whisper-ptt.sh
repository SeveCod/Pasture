#!/usr/bin/env bash
# whisper-ptt.sh — Push-to-talk con whisper.cpp local.
#   start  -> empieza a grabar
#   stop   -> para, transcribe y copia el texto al portapapeles
#
# Configurable por variables de entorno:
#   WHISPER_MODEL         (por defecto ~/.whisper-models/ggml-small.bin)
#   WHISPER_LANG          (auto | es | en ...)
#   WHISPER_AUDIO_DEVICE  (":default" o ":0", ":1"... ver README)

set -uo pipefail

MODEL="${WHISPER_MODEL:-$HOME/.whisper-models/ggml-small.bin}"
AUDIO_DEVICE="${WHISPER_AUDIO_DEVICE:-:default}"

# Idioma: lo escribe el dial (Hammerspoon) en este fichero.
# WHISPER_LANG, si está definida, manda por encima.
LANG_FILE="$HOME/.config/whisper-ptt/lang"
LANG_OPT="${WHISPER_LANG:-$(cat "$LANG_FILE" 2>/dev/null || echo auto)}"
[ -n "$LANG_OPT" ] || LANG_OPT="auto"

WORKDIR="/tmp/whisper-ptt"
WAV="$WORKDIR/rec.wav"
PIDFILE="$WORKDIR/ffmpeg.pid"
LOG="$WORKDIR/ptt.log"
mkdir -p "$WORKDIR"

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export PATH

FFMPEG="$(command -v ffmpeg || true)"
WHISPER="$(command -v whisper-cli || command -v whisper-cpp || true)"

# Metal (aceleración GPU) para la build de Homebrew
if command -v brew >/dev/null 2>&1; then
  GGML_METAL_PATH_RESOURCES="$(brew --prefix whisper-cpp 2>/dev/null)/share/whisper-cpp"
  export GGML_METAL_PATH_RESOURCES
fi

notify() {
  /usr/bin/osascript -e "display notification \"${1//\"/\\\"}\" with title \"Whisper\"" >/dev/null 2>&1
}

die() { notify "$1"; echo "$(date '+%F %T') ERROR: $1" >>"$LOG"; exit 1; }

[ -n "$FFMPEG" ]  || die "ffmpeg no encontrado (brew install ffmpeg)"
[ -n "$WHISPER" ] || die "whisper-cli no encontrado (brew install whisper-cpp)"

start() {
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    exit 0   # ya estaba grabando
  fi
  rm -f "$WAV"
  "$FFMPEG" -hide_banner -loglevel error \
    -f avfoundation -i "$AUDIO_DEVICE" \
    -ac 1 -ar 16000 -y "$WAV" >>"$LOG" 2>&1 &
  echo $! >"$PIDFILE"
  /usr/bin/afplay /System/Library/Sounds/Tink.aiff >/dev/null 2>&1 &
}

stop() {
  [ -f "$PIDFILE" ] || exit 0
  pid="$(cat "$PIDFILE")"
  rm -f "$PIDFILE"

  kill -INT "$pid" 2>/dev/null
  for _ in $(seq 1 60); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.05
  done
  kill -0 "$pid" 2>/dev/null && kill -TERM "$pid" 2>/dev/null

  [ -s "$WAV" ] || die "No se grabó audio (¿permiso de micrófono?)"

  [ -f "$MODEL" ] || die "Modelo no encontrado: $MODEL"

  txt="$("$WHISPER" -m "$MODEL" -f "$WAV" -l "$LANG_OPT" -nt -np -t 4 2>>"$LOG" \
        | tr -d '\r' \
        | grep -v -e '\[BLANK_AUDIO\]' -e '\[SOUND\]' -e '\[MUSIC\]' \
        | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        | sed '/^$/d')"

  if [ -z "$txt" ]; then
    notify "Sin texto (audio vacío o demasiado corto)"
    exit 0
  fi

  printf '%s' "$txt" | /usr/bin/pbcopy
  /usr/bin/afplay /System/Library/Sounds/Glass.aiff >/dev/null 2>&1 &

  preview="$(printf '%s' "$txt" | head -c 90)"
  notify "Copiado: $preview"
}

case "${1:-}" in
  start) start ;;
  stop)  stop ;;
  *) echo "uso: $0 start|stop" >&2; exit 2 ;;
esac
