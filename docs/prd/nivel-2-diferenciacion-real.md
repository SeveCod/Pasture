# PRD: Nivel 2 -- Diferenciacion real

**Producto:** Pasture (macOS)
**Version objetivo:** 1.2.0
**Fecha:** 2026-04-29
**Autor:** El Buscador de Problemas (PO)
**Estado:** BORRADOR -- pendiente de aprobacion

---

## 1. Problema

Pasture tiene dos limitaciones que frenan su utilidad real como herramienta de contexto para AI:

### 1A. El editor no aporta valor, y ademas compite mal

El `EditorView` actual es un `TextEditor` plano de SwiftUI. No tiene syntax highlighting, no tiene preview de Markdown, no tiene atajos avanzados. El usuario que escribe contextos complejos ya usa un editor dedicado (VS Code, Obsidian, Cursor, etc.). El resultado: el editor de Pasture es una zona muerta de la UI. Nadie edita ahi si puede evitarlo, y quien lo hace obtiene una experiencia inferior.

Pasture ya vigila el filesystem con `DispatchSource` y refleja cambios externos en ~0.5s. El watcher existe, funciona, pero el editor no lo aprovecha: si el usuario edita fuera, vuelve a Pasture y ve texto plano sin formato. La app no muestra lo que el usuario realmente va a alimentar al AI.

**Dolor concreto:** El usuario no puede ver como queda su Markdown renderizado dentro de Pasture. Tiene que imaginarselo o abrir otra herramienta. Y el editor actual le tienta a editar en Pasture, donde la experiencia es peor.

### 1B. Los templates son demasiado simples para prompts reales

El `TemplateEngine` actual soporta variables (`{{VAR}}`) y defaults (`{{VAR=default}}`). Esto cubre el caso basico: rellenar un nombre, un parametro, un valor. Pero los usuarios que crean "recetas de prompts" necesitan logica condicional y repeticion:

- "Si estoy trabajando en backend, incluye esta seccion de contexto; si no, omitela."
- "Tengo una lista de archivos/modulos/requisitos; repite este bloque para cada uno."

Sin condicionales ni bucles, el usuario acaba duplicando archivos de contexto con variaciones minimas, o concatenando manualmente bloques que deberian componerse de forma dinamica.

**Dolor concreto:** El usuario mantiene multiples archivos de contexto casi identicos, cambiando parrafos segun el caso. Es trabajo manual repetitivo que un template engine basico deberia resolver.

---

## 2. Contexto

- Pasture v1.1.0 esta publicada con collections, sort, drag & drop, y PastureKit como modulo testable.
- La app no tiene dependencias externas. Solo frameworks de Apple. Esta restriccion se mantiene.
- Es un proyecto de un solo desarrollador. El alcance debe ser manejable en un sprint corto.
- macOS 14+ es el target minimo (Sonoma). `AttributedString(markdown:)` esta disponible desde macOS 13.
- El `TemplateEngine` tiene 70+ tests en PastureKitTests. Cualquier extension debe mantener esa cobertura.

---

## 3. Solucion propuesta

### 3A. Preview-only con Markdown rendering

Convertir `EditorView` en `MarkdownPreviewView`: una vista de solo lectura que renderiza el contenido Markdown del archivo seleccionado.

**Decisiones de diseno:**

- **Sin edicion inline.** Se elimina el `TextEditor` y todo el flujo de auto-save (`saveSubject`, `debounce`, `file.updateDerivedProperties()`). Pasture deja de escribir en `~/.pasture/` salvo para operaciones explicitas (create, merge, import, move).
- **Boton "Open in Editor"** en la barra de estado del editor, que ejecuta `NSWorkspace.shared.open(file.url)` para abrir el archivo en la app por defecto del sistema.
- **Rendering con `AttributedString(markdown:)`** como base. Esta API es nativa, no requiere dependencias, y maneja correctamente headers, bold, italic, listas, links e inline code. Para bloques de codigo, se usa un estilo visual diferenciado (fondo, monospace) aunque sin syntax highlighting por colores.
- **Actualizacion reactiva:** El watcher de filesystem (`DispatchSource` + `debouncedReload()`) ya refresca `fm.files`. La preview se actualiza automaticamente porque observa `fm.files[idx].content`. No se necesita logica adicional.
- **Eliminacion de codigo muerto:** El `.onReceive` para `.forceSave` en `ContentView` y el comando de menu correspondiente se eliminan, ya que no hay nada que guardar.

### 3B. Template Engine con condicionales y bucles

Extender `TemplateEngine` en PastureKit con tres bloques nuevos:

- **`{{#if VAR}}...{{/if}}`** -- Renderiza el bloque solo si `VAR` tiene un valor no vacio asignado por el usuario.
- **`{{#unless VAR}}...{{/unless}}`** -- Inverso: renderiza solo si `VAR` esta vacio o no existe.
- **`{{#each ITEMS}}...{{/each}}`** -- Itera sobre los valores de `ITEMS` (separados por comas). Dentro del bloque, `{{.}}` es el valor actual y `{{@index}}` es el indice (0-based).

**Decisiones de diseno:**

- **Parsing por fases:** Primero se resuelven los bloques estructurales (if/unless/each) de adentro hacia afuera (bloques anidados), despues se sustituyen las variables simples. Esto evita conflictos entre la regex actual y los bloques.
- **`extractVariables()` se extiende** para detectar variables usadas en directivas `#if`, `#unless` y `#each`, ademas de las variables simples existentes. Las variables de bloque se marcan con un tipo para que la UI las trate de forma diferente.
- **`TemplateVariable` se extiende** con una propiedad `kind` (enum: `.simple`, `.boolean`, `.list`) para que `TemplateSheet` pueda mostrar el control adecuado:
  - `.simple` -> TextField (como ahora).
  - `.boolean` (usada en `#if` / `#unless`) -> Toggle (switch on/off).
  - `.list` (usada en `#each`) -> TextField multilinea donde cada linea es un item, o campo separado por comas.
- **Retrocompatibilidad total:** Los templates existentes (solo variables simples) funcionan exactamente igual. Los bloques son opt-in.
- **El regex actual se mantiene** para variables simples. Los bloques usan un parser separado (no regex puro, sino un parser de tokens basico).

---

## 4. Historias de usuario

### Preview Markdown (3A)

**HU-1: Ver Markdown renderizado**
Como creador de archivos de contexto para AI, quiero ver el contenido de mis archivos `.md` renderizado con formato (headers, listas, bold, code) dentro de Pasture, para verificar visualmente que el contexto que voy a alimentar esta bien estructurado.

**HU-2: Abrir archivo en editor externo**
Como creador de archivos de contexto, quiero abrir el archivo seleccionado directamente en mi editor favorito del sistema (VS Code, Obsidian, etc.) desde Pasture, para editar sin salir del flujo de trabajo.

**HU-3: Ver cambios reflejados automaticamente**
Como creador de archivos de contexto que edita en un editor externo, quiero que los cambios que hago fuera de Pasture se reflejen automaticamente en la preview renderizada, para no tener que refrescar manualmente.

### Template Engine avanzado (3B)

**HU-4: Incluir bloques condicionales en templates**
Como autor de prompts parametrizados, quiero usar `{{#if VAR}}...{{/if}}` en mis archivos de contexto, para incluir o excluir secciones del prompt segun el caso de uso sin mantener archivos duplicados.

**HU-5: Excluir bloques con unless**
Como autor de prompts parametrizados, quiero usar `{{#unless VAR}}...{{/unless}}` para incluir contenido por defecto que se omite cuando una variable tiene valor, para crear templates con fallbacks claros.

**HU-6: Iterar sobre listas en templates**
Como autor de prompts parametrizados, quiero usar `{{#each ITEMS}}...{{/each}}` para repetir un bloque de texto por cada elemento de una lista, para generar secciones dinamicas del prompt (ej: una lista de requisitos, modulos, archivos a analizar).

**HU-7: Rellenar condicionales y listas en la UI**
Como usuario de Pasture que hace Feed de un template con condicionales y listas, quiero que la TemplateSheet me muestre toggles para condicionales y campos de lista para each, para configurar el prompt antes de alimentarlo sin editar el archivo fuente.

**HU-8: Anidar bloques de template**
Como autor de prompts complejos, quiero anidar bloques condicionales y de iteracion (ej: un `{{#if}}` dentro de un `{{#each}}`), para crear templates con logica compuesta sin limitaciones artificiales.

---

## 5. Criterios de aceptacion

### HU-1: Ver Markdown renderizado

```
Given un archivo .md seleccionado con contenido "# Titulo\n\nTexto en **negrita** y `codigo`"
When el archivo se muestra en el panel de detalle
Then el contenido se muestra renderizado: "Titulo" como header, "negrita" en bold, "codigo" en monospace
  And no hay campo de texto editable
  And no hay cursor de edicion visible
```

```
Given un archivo .md con un bloque de codigo (triple backtick)
When el archivo se muestra en la preview
Then el bloque de codigo se muestra con fondo diferenciado y fuente monospace
  And el contenido del bloque no se interpreta como Markdown
```

```
Given un archivo .md con contenido que incluye listas, links y headers de multiples niveles
When el archivo se muestra en la preview
Then cada elemento se renderiza con su formato visual correspondiente
```

### HU-2: Abrir archivo en editor externo

```
Given un archivo .md seleccionado en Pasture
When el usuario pulsa el boton "Open in Editor" en la barra de estado
Then el archivo se abre en la aplicacion por defecto del sistema para archivos .md
  And Pasture permanece abierta en segundo plano
```

```
Given que no hay ninguna aplicacion configurada como editor por defecto para .md
When el usuario pulsa "Open in Editor"
Then el sistema muestra el dialogo estandar de seleccion de aplicacion
  And Pasture no se cuelga ni muestra un error no controlado
```

### HU-3: Ver cambios reflejados automaticamente

```
Given un archivo .md seleccionado y mostrado en la preview de Pasture
When el usuario modifica el archivo desde un editor externo y guarda
Then la preview en Pasture se actualiza con el contenido nuevo en menos de 2 segundos
  And no se requiere accion manual del usuario (ni click, ni refresh)
```

```
Given un archivo .md abierto en la preview
When el archivo se elimina externamente del filesystem
Then Pasture refleja la eliminacion: el archivo desaparece del sidebar y la preview muestra el estado vacio
```

### HU-4: Incluir bloques condicionales en templates

```
Given un template con contenido "Inicio {{#if BACKEND}}seccion backend{{/if}} Fin"
When se hace render con BACKEND = "yes"
Then el resultado es "Inicio seccion backend Fin"
```

```
Given un template con contenido "Inicio {{#if BACKEND}}seccion backend{{/if}} Fin"
When se hace render con BACKEND = "" (vacio)
Then el resultado es "Inicio  Fin"
```

```
Given un template con contenido "{{#if MISSING}}no deberia aparecer{{/if}}"
When se hace render sin proporcionar la variable MISSING
Then el resultado es "" (string vacio, sin el bloque)
```

### HU-5: Excluir bloques con unless

```
Given un template con contenido "{{#unless CUSTOM}}texto por defecto{{/unless}}"
When se hace render con CUSTOM = "" (vacio)
Then el resultado es "texto por defecto"
```

```
Given un template con contenido "{{#unless CUSTOM}}texto por defecto{{/unless}}"
When se hace render con CUSTOM = "mi texto"
Then el resultado es "" (string vacio)
```

### HU-6: Iterar sobre listas en templates

```
Given un template con contenido "{{#each FILES}}- Archivo: {{.}}\n{{/each}}"
When se hace render con FILES = "main.swift,App.swift,Utils.swift"
Then el resultado es "- Archivo: main.swift\n- Archivo: App.swift\n- Archivo: Utils.swift\n"
```

```
Given un template con contenido "{{#each ITEMS}}{{@index}}: {{.}}\n{{/each}}"
When se hace render con ITEMS = "a,b,c"
Then el resultado es "0: a\n1: b\n2: c\n"
```

```
Given un template con contenido "{{#each EMPTY}}item{{/each}}"
When se hace render con EMPTY = "" (vacio)
Then el resultado es "" (string vacio, el bloque no se ejecuta)
```

### HU-7: Rellenar condicionales y listas en la UI

```
Given un template con variables simples ({{NAME}}), condicionales ({{#if DEBUG}}) y listas ({{#each FILES}})
When se abre la TemplateSheet antes del Feed
Then la variable NAME se muestra como TextField
  And la variable DEBUG se muestra como Toggle (on/off)
  And la variable FILES se muestra como campo de texto donde se separan items por comas o saltos de linea
```

```
Given un template solo con variables simples (sin bloques)
When se abre la TemplateSheet
Then la UI se muestra exactamente igual que antes de esta feature (retrocompatibilidad)
```

### HU-8: Anidar bloques de template

```
Given un template "{{#each MODULES}}Modulo: {{.}} {{#if VERBOSE}}- detalle{{/if}}\n{{/each}}"
When se hace render con MODULES = "A,B" y VERBOSE = "yes"
Then el resultado es "Modulo: A - detalle\nModulo: B - detalle\n"
```

```
Given un template con bloques anidados a 2 niveles
When se hace render con las variables correspondientes
Then los bloques se resuelven correctamente de adentro hacia afuera
```

---

## 6. Metricas de exito

| Metrica | Estado actual | Objetivo |
|---------|---------------|----------|
| Lineas de codigo en EditorView | 23 (TextEditor editable) | Reemplazadas por MarkdownPreviewView read-only |
| Flujo de save eliminado | save(), forceSave, debounce activos | Eliminados (0 escrituras desde la UI al filesystem) |
| Tests de TemplateEngine | 25 tests | >= 50 tests (cubriendo if/unless/each + anidamiento + edge cases) |
| Bloques soportados por template | 0 (solo variables) | 3 (if, unless, each) |
| Retrocompatibilidad de templates | N/A | 100% -- todos los templates existentes producen el mismo output |

---

## 7. Fuera de alcance

- **Syntax highlighting para bloques de codigo.** La preview renderiza codigo con fondo diferenciado y monospace, pero sin colores por lenguaje. Esto requeriria un parser de sintaxis por lenguaje (TreeSitter, Highlight.js en WKWebView) que anade complejidad y potencialmente una dependencia.
- **Edicion inline de cualquier tipo.** No hay modo dual, no hay edicion rapida, no hay "quick edit". Pasture es visor + feed. Punto.
- **Selector de editor.** El boton "Open in Editor" usa la app por defecto del sistema. No hay preferencia dentro de Pasture para elegir editor. Si el usuario quiere VS Code, configura .md -> VS Code en Finder.
- **Operador `{{else}}` en condicionales.** En esta version, `{{#if}}` incluye o excluye. Para el caso contrario esta `{{#unless}}`. Un `{{#if}}...{{else}}...{{/if}}` anade complejidad al parser. Se reconsidera en una version futura si hay demanda.
- **Variables computadas o expresiones.** No hay `{{#if VAR == "valor"}}` ni `{{VAR | uppercase}}`. Las variables son strings simples; los condicionales evaluan presencia/ausencia, no contenido.
- **Template includes (`{{> partial}}`).** No se puede incluir un template dentro de otro. Cada archivo es una unidad independiente. La composicion se hace a nivel de Feed (seleccionar multiples archivos).
- **Preview en MenuBarView.** El menu bar sigue mostrando la lista de archivos con checkboxes para Feed rapido. No se anade preview de Markdown al menu bar.

---

## 8. Riesgos y dependencias

| Riesgo | Impacto | Mitigacion |
|--------|---------|------------|
| `AttributedString(markdown:)` no soporta todos los elementos Markdown (ej: tablas, footnotes) | Medio -- algunos archivos se veran incompletos | Documentar limitaciones. Evaluar alternativa `NSAttributedString` con HTML intermedio si las carencias son graves. No meter WKWebView salvo necesidad probada. |
| El parser de bloques del template engine introduce bugs en templates existentes | Alto -- rompe retrocompatibilidad | Suite de tests exhaustiva. Los tests actuales deben pasar sin modificacion. Anadir tests de regresion especificos. |
| Eliminar el editor puede molestar a usuarios que editaban en Pasture | Bajo -- la edicion actual es inferior a cualquier editor dedicado | El boton "Open in Editor" ofrece un flujo alternativo inmediato. La preview aporta mas valor que un editor plano. |
| Bloques anidados complejos son dificiles de depurar para el usuario | Medio -- un template con error de sintaxis puede dar output inesperado | Mostrar errores de sintaxis en la TemplateSheet (ej: "Bloque {{#if}} sin cerrar"). Limitar profundidad de anidamiento a 3 niveles. |
| El campo de lista ({{#each}}) en la UI es confuso: comas vs saltos de linea | Bajo -- afecta usabilidad, no funcionalidad | Usar comas como separador principal con trim de espacios. Aceptar saltos de linea como separador alternativo. Placeholder con ejemplo. |

---

## 9. Dependencias tecnicas

- **Ninguna dependencia externa nueva.** Todo se implementa con frameworks de Apple.
- **macOS 14+ (Sonoma)** sigue siendo el target minimo. `AttributedString(markdown:)` esta disponible desde macOS 13.
- **PastureKit** es donde se implementa toda la logica del template engine (testable, sin UI).
- **El watcher de filesystem existente** (`DispatchSource` en `MDFileManager`) es la base para la actualizacion reactiva de la preview. No requiere modificacion.

---

## 10. Orden de implementacion sugerido

1. **Primero: Preview Markdown (3A).** Es un cambio mas contenido (reemplaza un archivo, elimina codigo) y proporciona valor inmediato. Ademas, desbloquea la eliminacion de deuda tecnica (flujo de save).
2. **Segundo: Template Engine (3B).** Es un cambio aditivo (extiende sin romper) pero mas complejo. Requiere parser nuevo, tests extensivos, y cambios en la UI de TemplateSheet.

---

*Este PRD requiere aprobacion explicita antes de avanzar a la fase de arquitectura.*
