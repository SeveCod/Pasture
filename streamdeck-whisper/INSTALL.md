# Botón Whisper para Stream Deck (push-to-talk, 100% local)

Mantienes pulsado el botón → graba. Lo sueltas → whisper.cpp transcribe en local y
el texto queda en el portapapeles.

**Cómo encaja:** Stream Deck no puede lanzar "al soltar", pero su acción *Hotkey*
sí mantiene la tecla pulsada mientras aprietas el botón (es lo que usa la gente
para el push-to-talk de Discord). Hammerspoon escucha esa tecla y distingue
pulsar de soltar.

---

## 1. Instalar dependencias

```bash
brew install whisper-cpp ffmpeg
brew install --cask hammerspoon
```

## 2. Descargar el modelo

```bash
mkdir -p ~/.whisper-models
curl -L -o ~/.whisper-models/ggml-small.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
```

`small` (~466 MB) va sobrado para frases cortas en español. Si quieres más
precisión y tienes Apple Silicon, cambia a `ggml-large-v3-turbo-q5_0.bin`
(~547 MB, misma URL cambiando el nombre) y ajusta `WHISPER_MODEL` en el script.

## 3. Instalar el script

```bash
mkdir -p ~/bin
cp whisper-ptt.sh ~/bin/whisper-ptt.sh
chmod +x ~/bin/whisper-ptt.sh
```

Pruébalo desde Terminal — la primera vez macOS pedirá permiso de micrófono:

```bash
~/bin/whisper-ptt.sh start
# habla 3 segundos
~/bin/whisper-ptt.sh stop
pbpaste
```

## 4. Configurar Hammerspoon

Arranca Hammerspoon, dale permiso de Accesibilidad, y pega el contenido de
`hammerspoon-snippet.lua` al final de `~/.hammerspoon/init.lua`.
Luego: menú de Hammerspoon → **Reload Config**.

Ojo: si el script se lanza desde Hammerspoon, el permiso de micrófono se le pide
a *Hammerspoon*, no a Terminal. Si no aparece el diálogo, concédelo a mano en
Ajustes del Sistema → Privacidad y seguridad → Micrófono.

## 5. Configurar el dial en Stream Deck +

Arrastra **Sistema → Hotkey** (Tecla rápida) al dial y rellena las tres ranuras:

| Ranura | Tecla | Qué hace |
|---|---|---|
| **Press** (pulsar) | `F13` | mantener = grabar, soltar = transcribir y copiar |
| **Rotate Left** (girar izq.) | `F14` | idioma anterior |
| **Rotate Right** (girar dcha.) | `F15` | idioma siguiente |

Ponle un icono de micrófono y un título tipo "Whisper".

Al girar verás un aviso en pantalla: *Whisper · Español* / *English* /
*Automático*. El idioma elegido se guarda en `~/.config/whisper-ptt/lang` y el
script lo lee en cada transcripción, así que sobrevive a reinicios.

Para cambiar la lista de idiomas, edita `LANGS` y `LABELS` arriba del snippet
de Hammerspoon (`"fr"`, `"de"`, `"pt"`… los que uses).

Ya está: giras hasta el idioma, mantienes pulsado el dial, hablas, sueltas, y
pegas con ⌘V.

> Si la ranura *Press* del dial no mantiene la tecla pulsada (soltar no
> transcribe), pasa el push-to-talk a un botón normal con `F13` y deja el dial
> solo para el idioma.

---

## Ajustes

Variables de entorno que lee el script (edítalas arriba del propio archivo):

| Variable | Por defecto | Para qué |
|---|---|---|
| `WHISPER_MODEL` | `~/.whisper-models/ggml-small.bin` | ruta del modelo |
| `WHISPER_LANG` | `auto` | fija `es` si siempre dictas en español (algo más rápido y evita que confunda idioma) |
| `WHISPER_AUDIO_DEVICE` | `:default` | micrófono concreto |

Para elegir otro micrófono, lista los dispositivos:

```bash
ffmpeg -f avfoundation -list_devices true -i ""
```

y usa `:1`, `:2`… (el número de la sección *audio devices*).

## Si algo falla

El log está en `/tmp/whisper-ptt/ptt.log` y el último audio en
`/tmp/whisper-ptt/rec.wav` — reprodúcelo para descartar problemas de micro.

- **"No se grabó audio"** → falta permiso de micrófono, o el dispositivo
  `:default` no es el correcto.
- **Suena el Tink pero nunca el Glass** → mira el log; suele ser la ruta del
  modelo.
- **Va lento** → prueba `ggml-base.bin` (~148 MB) o el `large-v3-turbo-q5_0`
  con Metal (el script ya exporta `GGML_METAL_PATH_RESOURCES`).
- **El Stream Deck no mantiene la tecla** → cambia el binding a modo toggle:
  un solo `hs.hotkey.bind` que alterne entre `start` y `stop`.
