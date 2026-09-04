# Hallazgos verificados — usabilidad, accesibilidad y simplificación (2026-09-03)

Revisión con tres agentes read-only (usabilidad/heurísticas Nielsen, accesibilidad WCAG/VoiceOver, simplificación de código). Los hallazgos marcados ✅ fueron verificados de forma independiente contra el código por el coordinador antes de entrar en el plan. Los cálculos de contraste usan luminancia sRGB linealizada, ratio = (L1+0.05)/(L2+0.05).

Estado del árbol al auditar: `main` limpio salvo `?? streamdeck-whisper/` (ajeno, no tocar).

---

## A. Usabilidad

### Alta

**UX-1 ✅ El borrado es permanente: no usa la Papelera y no hay undo.**
`MDFileManager.swift:295` y `:385` usan `FileManager.default.removeItem(at:)`; el alert lo confirma en `ContentView.swift:123` ("will be permanently deleted"). Cero usos de `trashItem`, `recycle`, `UndoManager` en `Sources/Pasture/`. Un macOS nativo debe mandar a la Papelera.

**UX-2 ✅ No existe vía directa de crear una nota vacía.**
`PastureApp.swift:16` — `CommandGroup(replacing: .newItem) { }` anula Cmd+N sin reemplazo; la toolbar (`ContentView.swift:193-218`) solo ofrece New Collection / Paste / Import / Scan Folder.

**UX-3 Las acciones headless quedan mudas si el permiso de notificaciones está denegado.**
`SystemNotifier.swift:21-22` — `guard granted else { return }` descarta el aviso en silencio. Por ahí pasa todo el feedback de hotkeys/`pasture://`/Servicios, incluido "Possible secret detected — feed cancelled" (`HeadlessActions.swift:56-67`).

**UX-4 El Memory Inbox es invisible fuera de la ventana principal; las propuestas caducan solas a los 14 días.**
Único punto de entrada: banner del sidebar (`SidebarView.swift:66-92`). `MenuBarView` no tiene indicador, no hay notificación al llegar una propuesta, y el TTL se aplica en silencio (`MDFileManager.swift:117-120`). Con el modo "menu bar only" activo, el airlock humano falla por descubribilidad.

### Media

**UX-5 En el Inbox, "Reject" es inmediato e irreversible y "Approve" no da feedback de éxito.**
`ReviewInboxSheet.swift:122` — Reject sin confirmación borra el par del inbox (`MDFileManager.swift:158-161`); `ReviewInboxSheet.swift:185-186` — `case .success: break` descarta la URL resultante.

**UX-6 Aplicar un preset exige dos niveles de menú en la ventana principal, un clic en el menu bar.**
`ContentView.swift:304-313` (submenú Apply/Rename/Delete) vs `MenuBarView.swift:100-103` (clic directo aplica).

**UX-7 El botón Feed no dice cuál será la acción del clic cuando hay destino por defecto.**
`FeedAction.swift:36-47` — el clic puede copiar al portapapeles o SOBRESCRIBIR un fichero según la estrella de Settings; el tooltip genérico no nombra el destino.

**UX-8 "Clear conversation" usa icono de reintentar (`arrow.counterclockwise`) y borra el chat multi-turno sin confirmación.**
`AskView.swift:380-389` → `AskViewModel.clear` (`AskViewModel.swift:104-109`).

**UX-9 Si el registro del hotkey global falla, el toggle queda activado y el error solo va a stderr.**
`GlobalHotkeyManager.swift:59-65`; el toggle de `SettingsView.swift:65-68` no refleja nada. El patrón de caption de error ya existe en la misma pestaña (`loginItemError`, `SettingsView.swift:49-53`).

**UX-10 Borrar con teclado solo funciona con exactamente un fichero seleccionado.**
`SidebarView.swift:232-237` — guard `selectedFiles.count == 1`; con selección múltiple, silencio. `fm.delete(files:)` ya acepta array.

### Baja

**UX-11 El menú contextual del fichero no incluye "Open in Editor".**
`SidebarView.swift:257-286` — solo Rename / Move to… / Delete.

**UX-12 "Scan Folder" deja una colección vacía residual cuando no encuentra ningún .md.**
`MDFileManager+Import.swift:66` crea la colección ANTES de enumerar; con `count == 0` (líneas 89-91) solo fija `lastError`.

### Fuera del top (candidatos futuros, sin tarea)
- "Merge" concatena en orden de fecha aunque el sidebar esté ordenado por nombre (`ContentView.swift:96` filtra sobre `fm.files`), sin indicarlo en el sheet.

---

## B. Accesibilidad

### Alta

**A11Y-1 ✅ `pastureAmber` (#E8944A) como texto/icono con significado en modo claro: 2,20:1 (falla AA; requerido 4,5:1 texto / 3:1 icono).**
Usos: `FileRow.swift:22` (badge stale), `SidebarView.swift:104` (banner de revisión), `ReviewInboxSheet.swift:111-114` (aviso "Possible secrets" — un aviso de seguridad), `SettingsView.swift:202` (estrella de destino por defecto). Sobre la tarjeta del inbox (~#EAE9E4): 1,98:1. `pastureWarningLight` (#8F4F1A) mide 6,20:1 y ya existe (`DesignTokens.swift:116`) con helper `pastureWarning(_:)` (`DesignTokens.swift:209-211`).

**A11Y-2 ✅ `pastureTemplate` (#D4793B) como texto en claro: 2,91:1 (badge "Template" sobre #FDF3EB, `TemplateBadge.swift:16`) y 3,10:1 (nombres `{{VAR}}` en TemplateSheet, `FeedAction.swift:127-129`). Contradice el claim "≥4.5:1" del CLAUDE.md.** En dark mide 4,95:1 y cumple. No existe helper adaptativo para este token (`DesignTokens.swift:89` es un único `static let`).

**A11Y-3 ✅ Los toasts efímeros nunca se anuncian a VoiceOver.**
`FeedService.swift:203-212` (`showFeedback`, auto-dismiss 2,5 s) — por ahí pasan también errores ("Export failed"). 0 usos de `AccessibilityNotification` en `Sources/Pasture/`. El fin del streaming de Ask tampoco se anuncia.

**A11Y-4 ✅ Cero soporte de Reduce Motion (0 ocurrencias de `accessibilityReduceMotion`).**
`AskView.swift:441-452` (`PulseModifier`, `repeatForever` durante todo el streaming), transición del toast (`PastureEmptyState.swift:57`, `ContentView.swift:141`), scroll animado por delta (`AskView.swift:140-144`), scaleEffect en hover (`FeedAction.swift:101-102`).

### Media

**A11Y-5 TemplateSheet: TextFields sin etiqueta accesible ligada a su variable** (`FeedAction.swift:133-141`) — VoiceOver lee solo el placeholder, idéntico en todas las filas. Tampoco enfoca el primer campo al abrir (NameInputSheet sí lo hace con `@FocusState`).

**A11Y-6 Sheets sin salida por Escape**: `ReviewQueueSheet.swift:18-19` y `ReviewInboxSheet.swift:30-31` solo tienen "Done" con `.defaultAction`; no hay `.cancelAction`.

**A11Y-7 El diff del Inbox distingue actual/propuesto SOLO por color** (`ReviewInboxSheet.swift:148-156`: gris vs `pastureSuccess`). WCAG 1.4.1; para VoiceOver ambos bloques son indistinguibles — se aprueba sin saber qué parte es nueva.

**A11Y-8 `FileRow` no combina sus elementos** (`FileRow.swift:8-43`): nombre, badges y fecha son elementos VO sueltos ("1.2K" sin contexto). `MenuBarFileRow.swift:42-44` ya hace lo correcto.

**A11Y-9 Estado de uso de contexto en Ask comunicado solo por color** (`AskView.swift:22-29`, `:69-73`): verde/ámbar/rojo sin texto equivalente en el label.

### Baja

**A11Y-10 Tamaños de fuente fijos que no escalan**: `DesignTokens.swift:288` (`pastureEditor` 13 pt — fuente del preview completo), `MenuBarFileRow.swift:25` (9), `SidebarView.swift:81,110` (9), `ReviewInboxSheet.swift:158` (12).

**A11Y-11 Hint con gesto de iOS en macOS** (`MenuBarFileRow.swift:44`): "Double-tap to toggle selection".

**A11Y-12 Iconos decorativos de empty states sin `accessibilityHidden(true)`**: `PastureEmptyState.swift:9` (leaf), `AskView.swift:238` (bubble).

### Verificado como correcto (no tocar)
Labels/hints sistemáticos en toolbar/menu bar/Settings; alerts de secretos con Cancel por defecto (SEC-6); pares principales de texto cumplen (5,0–8,1:1); texto sobre el gradiente Feed 8,09/6,82:1.

---

## C. Simplificación

**SIMP-1 ✅ 14 símbolos de diseño muertos en `DesignTokens.swift`** (verificado con grep por símbolo, 0 usos fuera del fichero): `pastureMidGradient`, `pastureAccentDeep`, `pastureEditorProse`, `pastureSidebarGradient`, `shadowHover`, `shadowModal`, `animationSlow`, `springResponse`, `springDamping`, `PastureLayout.searchBarHeight`, `.summaryBarHeight`, `.statusBarHeight`, `.editorTopPadding`; más el alias `pastureGrassOrange` (`DesignTokens.swift:113`, 1 uso en `PastureEmptyState.swift:18`). ⚠️ `pastureSageGreen`/`pastureAmber` NO son muertos: los consume `LinearGradient.pastureBrand` (`DesignTokens.swift:227`).

**SIMP-2 ✅ Chrome de feed duplicado ContentView↔MenuBarView**: `secretAlertMessage(for:)` idéntico (`ContentView.swift:402-411` vs `MenuBarView.swift:77-86`), `.alert` de secretos (125-139 vs 61-73), `.sheet` TemplateSheet (109-116 vs 44-51), `feedbackOverlay` (179-184 vs 267-272), `executeFeed` (344-346 vs 239-241).

**SIMP-3 `proposeNote`/`proposeAppend` comparten la cola entera** (`MCPTools.swift:164-183` vs `215-235`): cap → secretos → dedupe → save → mensaje. Las validaciones de destino difieren a propósito — NO extraerlas. Cubierto por `MCPProposalToolsTests` y `MCPProposalDispatchTests`.

**SIMP-4 `JSONValue.arrayValue`** (`MCPMessage.swift:92`) — alias literal de `.array`, un solo consumidor (`MCPTools.swift:421`).

**SIMP-5 Micro**: `ContentView.swift:368-371` — `if let existing = … { _ = existing; … }` → `!= nil`.

### Señalado, SIN tarea (decisión de producto o beneficio marginal)
- `Proposal.autoApproved` (Proposal.swift:43-45): reserva documentada de la Fase 2 del Memory Inbox; retirarlo es decisión del propietario (reintroducible sin migración por ser `Bool?` con `schemaVersion`).
- Namespaces de settings (Export/AI/FeedFormat/Integration): patrón repetido pero SIN abstracción — cada uno cabe en pantalla, un protocolo genérico añadiría indirección (AISettings mezcla Keychain). Incoherencia latente documentada: IntegrationSettings postea `didChangeNotification` en sus setters; los otros tres dependen de que SettingsView lo postee a mano.
- Auto-clear de clipboard implementado dos veces (`FeedService.swift:187`, `HeadlessActions.swift:72`): invariante de seguridad sin test unitario, feedback distinto — no unificar sin más motivo.
- APIs públicas solo-tests (`AIClient.buildRequest` single-turn, `DOCXConverter.convertAttributedString`, `SecretScanResult.kinds`, `TokenEstimator.estimatedCost/formattedCost`): no son código muerto; dan cobertura. Candidato único de retirada: `buildRequest` single-turn.
- Descartado partir ContentView/SettingsView/MCPTools: ya descompuestos internamente.
