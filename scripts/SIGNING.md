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

## Proceso de release completo

1. Construir en Linux → se generan 4 archivos en `release/`
2. Construir en Windows → se generan 3 archivos en `release\`
3. Copiar al repositorio `Open73_app`:
   - `open73_X.Y.Z_amd64.AppImage` + `.tar.gz` + `.tar.gz.sig` → `staging/`
   - `open73_X.Y.Z_x64_en-US.msi` + `.msi.zip` + `.msi.zip.sig` → `staging/`
   - `latest.json` (generado por Linux) → **raíz del repositorio** (sobreescribe el anterior)
4. Editar `"notes"` en `latest.json` si se quiere agregar descripción del release
5. Ejecutar `./scripts/release.sh`
   - Lee versión y notas de `latest.json`
   - Genera `update.json` con las firmas leídas de los `.sig`
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
