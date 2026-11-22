# Ghostty Kitty Trail

Módulo de estela del cursor para Ghostty en macOS. La app compilada conserva
el comportamiento normal de Ghostty hasta que se habilita la opción.

## Configuración

Agrega estas líneas a tu archivo de configuración de Ghostty y recárgalo.
Los nombres, valores y unidades corresponden a las cuatro opciones base de Kitty.
Ghostty usa su sintaxis habitual con `=`.

```ini
cursor_trail = 1
cursor_trail_decay = 0.1 0.4
cursor_trail_start_threshold = 2
cursor_trail_color = none
```

- `cursor_trail` indica la permanencia en la celda destino, en milisegundos. El valor predeterminado `0` desactiva la estela.
- `cursor_trail_decay` indica los tiempos rápido y lento en segundos.
- `cursor_trail_start_threshold` admite un umbral común o un par `X Y` en celdas. Cambiar de panel dentro de la misma pestaña omite el filtro de distancia.
- `cursor_trail_color` admite un color hexadecimal, un nombre o `none` para usar el color del cursor.

## Implementación

`modules/animation.zig` adapta la interpolación de cuatro esquinas de
[Kitty](https://github.com/kovidgoyal/kitty/blob/dd4ac51ad2f52a7859b41240e7f887010bf4210d/kitty/cursor_trail.c)
a Zig. Usa producto punto normalizado, decaimiento exponencial con tiempo
monótono, medio píxel de tolerancia y atenuación cuando la aplicación oculta
el cursor. El estado de la animación vive en el contenedor de la pestaña.
`CursorTrailView.swift` convierte las posiciones de los paneles a un espacio
común y compone un cuadrilátero con Core Animation cuya máscara deja libre
el cursor actual. El renderizador solo publica cambios y el overlay deja de
pedir cuadros al terminar. Durante un redimensionado se reinicia la estela.

`modules/config.zig` implementa las opciones. `integration.patch` conecta
el módulo al renderizador, a la configuración y a la app de Ghostty.
`install-module.sh` comprueba la estructura y aplica la integración antes
de copiar los tres archivos.

## Compilación y actualizaciones

El workflow comprueba a diario el último tag estable de Ghostty, clona ese
tag, aplica el módulo, instala la versión de Zig declarada por el tag y
compila en macOS ARM64. También se puede lanzar desde **Actions**.
Si el build pasa, se publica el ZIP en **Releases**. Si cambia un punto de
integración, Actions señala el conflicto y conserva la última compilación
publicada. El ZIP se instala manualmente en la Mac.

La versión base de la integración es Ghostty v1.4.0. El binario se compila
con la configuración local de Ghostty para Apple Silicon.
