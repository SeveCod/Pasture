-- === Whisper push-to-talk + idioma por dial (Stream Deck +) =================
-- Pega esto al final de ~/.hammerspoon/init.lua y recarga la config.
--
--   Dial pulsado  -> F13  : mantener = grabar, soltar = transcribir + copiar
--   Girar izq.    -> F14  : idioma anterior
--   Girar dcha.   -> F15  : idioma siguiente

local HOME = os.getenv("HOME")
local WHISPER_PTT = HOME .. "/bin/whisper-ptt.sh"
local LANG_DIR = HOME .. "/.config/whisper-ptt"
local LANG_FILE = LANG_DIR .. "/lang"

-- Ciclo de idiomas. Añade o quita los que quieras ("fr", "de", "pt"...).
local LANGS = { "auto", "es", "en" }
local LABELS = { auto = "Automático", es = "Español", en = "English" }

hs.fs.mkdir(HOME .. "/.config")
hs.fs.mkdir(LANG_DIR)

local langIndex = 1

local function loadLang()
  local f = io.open(LANG_FILE, "r")
  if not f then return end
  local cur = (f:read("*a") or ""):gsub("%s+", "")
  f:close()
  for i, l in ipairs(LANGS) do
    if l == cur then langIndex = i end
  end
end

local function saveLang()
  local f = io.open(LANG_FILE, "w")
  if f then
    f:write(LANGS[langIndex])
    f:close()
  end
end

local function cycleLang(delta)
  langIndex = ((langIndex - 1 + delta) % #LANGS) + 1
  saveLang()
  hs.alert.closeAll()
  hs.alert.show("Whisper · " .. (LABELS[LANGS[langIndex]] or LANGS[langIndex]), 0.7)
end

loadLang()
saveLang() -- crea el fichero en el primer arranque

-- Push-to-talk
local function ptt(action)
  return function()
    hs.task.new("/bin/bash", nil, { WHISPER_PTT, action }):start()
  end
end

hs.hotkey.bind({}, "F13", ptt("start"), ptt("stop"))

-- Idioma
hs.hotkey.bind({}, "F14", function() cycleLang(-1) end)
hs.hotkey.bind({}, "F15", function() cycleLang(1) end)
-- ===========================================================================
