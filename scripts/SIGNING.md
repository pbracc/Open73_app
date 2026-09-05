# Firma de releases — configuración de claves

Open73 usa el sistema de firma de Tauri v2 (`minisign`) para verificar la integridad de
los artifacts antes de instalarlos automáticamente.

## Claves generadas

Las claves están en `~/.tauri/` en la máquina de desarrollo Linux:

| Archivo | Contenido |
|---------|-----------|
| `~/.tauri/open73.key` | Clave privada **sin contraseña** (¡nunca compartir!) |
| `~/.tauri/open73.key.pub` | Clave pública (está embebida en `tauri.conf.json`) |

En Windows las mismas claves deben estar en `C:\Users\<usuario>\.tauri\`.

La clave privada fue generada con `pnpm tauri signer generate --force` sin contraseña —
solo necesitás el archivo para firmar, sin variables de password.

---

## Cómo firmar el build en Linux (vía Docker — método recomendado)

El script `scripts/build-appimage.sh` detecta la clave automáticamente desde
`~/.tauri/open73.key` sin necesidad de exportar nada:

```bash
./scripts/build-appimage.sh
```

Los 4 artefactos quedan en `release/`:
- `open73_X.Y.Z_amd64.AppImage` — instalador normal
- `open73_X.Y.Z_amd64.AppImage.tar.gz` — comprimido para el updater
- `open73_X.Y.Z_amd64.AppImage.tar.gz.sig` — firma (requerida por el updater)
- `latest.json` — generado automáticamente con la versión leída de `tauri.conf.json`

---

## Cómo firmar el build en Windows (PowerShell — método recomendado)

El script `scripts/build-windows.ps1` detecta la clave automáticamente desde
`C:\Users\<usuario>\.tauri\open73.key`:

```powershell
.\scripts\build-windows.ps1
```

Los 3 artefactos quedan en `release\`:
- `open73_X.Y.Z_x64_en-US.msi` — instalador normal
- `open73_X.Y.Z_x64_en-US.msi.zip` — comprimido para el updater
- `open73_X.Y.Z_x64_en-US.msi.zip.sig` — firma (requerida por el updater)

> Windows no genera `latest.json`. Ese archivo lo provee el build de Linux.

---

## Cómo firmar el build en macOS Intel (método recomendado)

El script `scripts/build-macos-intel.sh` (en el repo del código fuente) detecta la
clave automáticamente desde `~/.tauri/open73.key`:

```bash
./scripts/build-macos-intel.sh
```

Los 3 artefactos quedan en `release/`:
- `open73_X.Y.Z_intel.dmg` — instalador normal (drag-and-drop)
- `open73_X.Y.Z_intel.app.tar.gz` — comprimido para el updater
- `open73_X.Y.Z_intel.app.tar.gz.sig` — firma (requerida por el updater)

**Preparación de la Mac (una sola vez):**
```bash
# 1. Crear el directorio si no existe
mkdir -p ~/.tauri

# 2. Copiar la clave privada desde Linux/Windows (SCP, pendrive, etc.)
#    La clave es el mismo archivo open73.key usado en todas las plataformas.
scp usuario@linux-box:~/.tauri/open73.key ~/.tauri/open73.key

# 3. Verificar que Rust tiene el target Intel instalado
rustup target add x86_64-apple-darwin
```

> **Nota sobre Gatekeeper:** El DMG no está firmado con un Apple Developer Certificate
> ni notarizado. Al abrirlo por primera vez macOS mostrará una advertencia. El usuario
> puede ignorarla haciendo clic derecho → "Abrir". Las actualizaciones automáticas
> (in-app) funcionan igual porque usan la firma minisign, no la de Apple.

---

## Proceso de release completo

1. Construir en Linux → se generan 4 archivos en `release/`
2. Construir en Windows → se generan 3 archivos en `release\`
3. Construir en macOS Intel → se generan 3 archivos en `release/`
4. Copiar al repositorio `Open73_app`:
   - `open73_X.Y.Z_amd64.AppImage` + `.tar.gz` + `.tar.gz.sig` → `staging/`
   - `open73_X.Y.Z_x64_en-US.msi` + `.msi.zip` + `.msi.zip.sig` → `staging/`
   - `open73_X.Y.Z_intel.dmg` + `.app.tar.gz` + `.app.tar.gz.sig` → `staging/`
   - `latest.json` (generado por Linux) → **raíz del repositorio** (sobreescribe el anterior)
5. Editar `"notes"` en `latest.json` si se quiere agregar descripción del release
6. Ejecutar `./scripts/release.sh`
   - Lee versión y notas de `latest.json`
   - Genera `update.json` con las firmas leídas de los `.sig` (Linux + Windows + macOS Intel)
   - Actualiza `RELEASES.md` y `README.md`
   - Sube todo a GitHub Releases
   - Hace commit y push de `latest.json` + `update.json`

---

## ¿Perdiste la clave privada?

Si perdés el archivo `~/.tauri/open73.key`, generá un nuevo par:

```bash
pnpm tauri signer generate -w ~/.tauri/open73.key --force
# Dejar contraseña en blanco (Enter dos veces)
```

Luego actualizá `pubkey` en `src-tauri/tauri.conf.json` con el contenido del nuevo `.pub`.
