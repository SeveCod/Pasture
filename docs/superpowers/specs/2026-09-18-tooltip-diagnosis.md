# Diagnóstico de los tooltips de la toolbar — PARCIAL, pendiente de observación

Fecha: 2026-09-18 · Origen: Task 1 del plan `2026-09-18-sidebar-tree-simplification.md`
Estado: **ABIERTO**. Este fichero existe porque la Task 1 lo exigía como entregable y
faltaba; su conclusión **NO está cerrada**.

## Por qué este fichero estaba vacío y por qué importa

El plan era explícito: «No se escribe ni un `.help()` nuevo hasta tener una causa
**observada**», y el entregable era este documento. Nunca se creó. Aun así, la Task 6 se
ejecutó (`b9715a6`, agrupar la toolbar en un `+`) y después se **revirtió** (`80a6379`, HEAD).

Es decir: el objetivo nº 2 de la v1.11 se dio por cerrado **sin una sola observación
registrada y con su arreglo deshecho**. Es el patrón de «cifra autoestimada» aplicado a una
corrección: si la causa era la hipótesis 1, los tooltips siguen hoy tan invisibles como antes
de la rama.

## Lo que SÍ está verificado (por código, 2026-09-18)

| Comprobación | Resultado |
|---|---|
| Elementos de nivel superior en el único `ToolbarItemGroup(placement: .primaryAction)` | **9** (`ContentView.swift:176-242`), uno de ellos condicional (`if selectedFiles.count > 1`), de donde salen los ~10 controles que declara el CHANGELOG |
| ¿Siguen los `.help()` escritos? | Sí — 7 en el grupo de la toolbar, ~30 en toda la app |
| Dónde se aplica `.help()` | Sobre el **`Button`**, no sobre su `Label` — que es justo la diferencia que plantea la hipótesis 2 |
| Control fuera de la toolbar | `EditorStatusBar.swift:53` lleva `.help("Open in default editor (Cmd+E)")` sobre un `Button` de la barra de estado |
| Estado de la Task 6 | Aplicada en `b9715a6` y **revertida** en `80a6379` |

Conclusión parcial: **la hipótesis 1 (desbordamiento del `ToolbarItemGroup`) sigue viva**, porque
la estructura que la provocaba está hoy intacta tras la reversión.

## Lo que FALTA, y sólo se puede hacer con la app delante

Nada de esto es deducible del código: requiere pasar el ratón por la interfaz. Son los
Steps 2-4 del plan, literales:

1. **Control.** Con una nota seleccionada, pasar el ratón 2 s completos sobre «Open in Editor»
   en la barra de estado inferior.
   - Aparece → el problema es específico de la toolbar, seguir en el punto 2.
   - **No aparece → las dos hipótesis quedan invalidadas; parar y avisar.**
2. **Experimento 1 (desbordamiento).** Con la ventana a su ancho habitual, contar los botones
   visibles y si sale el chevron `»`. Ensanchar a pantalla completa hasta que no quede ninguno
   desbordado y volver a probar el último del grupo.
   - Aparece → hipótesis 1 **confirmada**, y el arreglo es reducir elementos (la Task 6 que se
     revirtió).
   - No aparece → hipótesis 1 descartada, ir al 3.
3. **Experimento 2 (hipótesis 2).** Mover un `.help()` del `Button` a su `Label` y comprobar.
   Reversible; el plan lo marca como el único experimento que toca código.

## Recomendación

No tocar la toolbar hasta completar el punto 1. Si el control de la barra de estado tampoco
muestra tooltip, el problema no es la toolbar y cualquier reorganización de botones sería
trabajo perdido — que es exactamente lo que el plan quería evitar exigiendo este fichero
antes que el código.
