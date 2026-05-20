# Hermes Agent Bar

Hermes Agent Bar (`HermesBar`) es una app nativa de macOS para usar Hermes Agent desde la barra superior.

## Qué hace

- Agrega un icono `⚚ Hermes` en la barra superior de macOS.
- Click izquierdo: abre directamente el chat.
- Click derecho: abre un menú vertical con acciones rápidas.
- Ejecuta Hermes desde una UI nativa tipo terminal.
- Permite enviar prompts, usar comandos slash locales, seleccionar proyecto, ejecutar `hermes doctor`, abrir sesiones en Terminal y abrir la configuración.
- Recuerda tamaño de texto, alto del panel de salida y último proyecto seleccionado.

## Requisitos

- macOS 13 o superior.
- Xcode Command Line Tools.
- Hermes Agent CLI instalado.
- Hermes disponible en alguna de estas rutas:
  - `~/.local/bin/hermes`
  - `/opt/homebrew/bin/hermes`
  - `/usr/local/bin/hermes`
  - o en el `PATH` actual.

Verifica Hermes antes de instalar:

```bash
command -v hermes
hermes doctor
```

Si falta Swift o las herramientas de Xcode:

```bash
xcode-select --install
```

## Instalación rápida

Clona el repositorio:

```bash
git clone https://github.com/cerealskill/hermes-agent-bar.git
cd hermes-agent-bar
```

Construye la app:

```bash
./scripts/build_app.sh
```

Prueba la app sin instalarla:

```bash
open build/HermesBar.app
```

Instálala en `/Applications`:

```bash
./scripts/install_app.sh
```

Ábrela desde Spotlight, Finder o Terminal:

```bash
open /Applications/HermesBar.app
```

## Actualizar

Desde la carpeta del repositorio:

```bash
git pull --ff-only
./scripts/install_app.sh
open /Applications/HermesBar.app
```

## Build manual

Si quieres compilar sin el script:

```bash
swift build -c release
```

El script `scripts/build_app.sh` además crea el bundle `build/HermesBar.app`, genera `Info.plist`, valida el plist y firma la app localmente con firma ad-hoc.

## Uso

- Click izquierdo en `⚚ Hermes`: abre el chat.
- Click derecho en `⚚ Hermes`: abre acciones como abrir chat, comandos slash, cancelar ejecución, copiar/guardar/limpiar salida, usar clipboard, adjuntar archivo, seleccionar proyecto, ejecutar `hermes doctor`, abrir Terminal, abrir configuración, ajustar texto y salir.
- Escribe una tarea y presiona `Enter` para enviarla.
- Usa `Shift+Enter` para insertar una nueva línea.
- Usa el botón `/` o la acción `Comandos slash` para ver comandos disponibles.
- Comandos locales del wrapper: `/copy`, `/save`, `/paste`, `/doctor` y `/project`.
- `/clear`, `/new` y `/reset` limpian la sesión local y actualizan el indicador superior.

## Estructura

```text
Package.swift
Sources/HermesBar/main.swift
scripts/build_app.sh
scripts/install_app.sh
README.md
```

## Solución de problemas

### Hermes no aparece desde la app

Las apps abiertas desde Finder no heredan siempre el mismo entorno del shell. Hermes Agent Bar busca `hermes` en rutas comunes. Verifica:

```bash
command -v hermes
hermes doctor
```

Si Hermes está en otra ruta, edita `hermesCandidates` en:

```text
Sources/HermesBar/main.swift
```

### macOS bloquea la app

La app se firma localmente con firma ad-hoc. Si macOS muestra una advertencia, abre:

```text
System Settings -> Privacy & Security
```

y permite abrir la app manualmente.

### Reinstalar desde cero

```bash
osascript -e 'tell application "HermesBar" to quit' >/dev/null 2>&1 || true
rm -rf /Applications/HermesBar.app
./scripts/install_app.sh
open /Applications/HermesBar.app
```

## Desarrollo

Compilar:

```bash
swift build -c release
```

Crear bundle local:

```bash
./scripts/build_app.sh
```

Validar bundle:

```bash
plutil -lint build/HermesBar.app/Contents/Info.plist
codesign --verify --deep --strict build/HermesBar.app
```

## Licencia

MIT
