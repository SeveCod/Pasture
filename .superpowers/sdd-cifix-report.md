# CI fix — UNNotificationSettings no Sendable

**Rama:** `feat/v1.10-ux-a11y-simplify`

## Fallo

CI (macos-15, compilador más nuevo que el local) rechazaba
`Sources/Pasture/SystemNotifier.swift:50`:

```
error: non-sendable result type 'UNNotificationSettings' cannot be sent from
nonisolated context in call to instance method 'notificationSettings()'
```

`SystemNotifier` es `@MainActor`, así que el `await` sobre la API async
`notificationSettings()` hacía cruzar el objeto `UNNotificationSettings`
—no Sendable— una frontera de aislamiento. El build local no lo reproduce
(comprobación de `SendableCompletionHandlers` más laxa en el toolchain viejo).

## Cambio

Un único fichero, `Sources/Pasture/SystemNotifier.swift`:

- `isDenied()` conserva su firma y semántica exacta (`.denied` → `true`,
  todo lo demás → `false`; el guard `isBundled` intacto), pero delega en
  un helper nuevo.
- Helper añadido: `private nonisolated static func authorizationStatus() async
  -> UNAuthorizationStatus`, que usa `withCheckedContinuation` +
  `getNotificationSettings { }` (API de completion handler). El objeto
  `UNNotificationSettings` no sale del closure; lo único que cruza es el
  enum `UNAuthorizationStatus`, que sí es Sendable.

Sin `@preconcurrency import`, sin `@unchecked Sendable`. El texto de Settings
que depende de `isDenied()` no cambia de comportamiento.

## Verificación

- `swift build` → `Build complete!`, `grep -c warning` = **0**.
- `~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift test`
  → **711 tests en 75 suites, todos verdes**.
- CI no verificado desde aquí (se re-ejecuta al hacer push el controlador);
  el razonamiento del fix es el único indicador disponible en local.
