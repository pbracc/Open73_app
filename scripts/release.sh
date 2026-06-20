#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# release.sh — publica una nueva versión de Open73 en GitHub Releases
#
# Requisitos: git, curl, jq
#
# Uso:
#   1. Editar latest.json con la nueva versión y las notas de release.
#   2. Copiar los artifacts de ambas plataformas a staging/:
#        Linux  : open73_X.Y.Z_amd64.AppImage
#                 open73_X.Y.Z_amd64.AppImage.tar.gz
#                 open73_X.Y.Z_amd64.AppImage.tar.gz.sig
#        Windows: open73_X.Y.Z_x64-setup.msi
#                 open73_X.Y.Z_x64-setup.msi.zip
#                 open73_X.Y.Z_x64-setup.msi.zip.sig
#        Nota: los .tar.gz, .zip y .sig los genera Tauri automáticamente
#              cuando TAURI_SIGNING_PRIVATE_KEY está configurado en el build.
#   3. Ejecutar:  ./scripts/release.sh
# ---------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LATEST_JSON="$REPO_ROOT/latest.json"
UPDATE_JSON="$REPO_ROOT/update.json"
STAGING_DIR="$REPO_ROOT/staging"
RELEASES_MD="$REPO_ROOT/RELEASES.md"
ENV_FILE="$REPO_ROOT/.env"

# ---- Colores ---------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

# ---- Dependencias ----------------------------------------------------------
for cmd in git curl jq; do
  command -v "$cmd" &>/dev/null || error "Falta el comando: $cmd"
done

# ---- Cargar token ----------------------------------------------------------
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
[[ -z "${GITHUB_TOKEN:-}" ]] && error "No se encontró GITHUB_TOKEN. Agregalo en .env: GITHUB_TOKEN=ghp_..."

# ---- Leer latest.json ------------------------------------------------------
VERSION=$(jq -r '.version' "$LATEST_JSON")
NOTES=$(jq -r '.notes'     "$LATEST_JSON")
TAG="v${VERSION}"

[[ "$VERSION" == "0.0.0" ]] && error "Actualizá la versión en latest.json antes de hacer el release."
[[ -z "$VERSION" ]]          && error "No se pudo leer 'version' de latest.json."

info "Versión detectada: $TAG"

# ---- Obtener owner/repo desde el remote ------------------------------------
REMOTE_URL=$(git -C "$REPO_ROOT" remote get-url origin)
REPO_PATH=$(echo "$REMOTE_URL" | sed -E 's#(git@github\.com:|https://github\.com/)##;s#\.git$##')
REPO_URL="https://github.com/${REPO_PATH}"
OWNER=$(echo "$REPO_PATH" | cut -d/ -f1)
REPO=$(echo "$REPO_PATH"  | cut -d/ -f2)

info "Repositorio: ${OWNER}/${REPO}"

# ---- Verificar que el tag no exista ya ------------------------------------
if git -C "$REPO_ROOT" rev-parse "$TAG" &>/dev/null; then
  error "El tag $TAG ya existe. Actualizá la versión en latest.json."
fi

# ---- Detectar binarios en staging/ -----------------------------------------
LINUX_APPIMAGE=$(find "$STAGING_DIR" -maxdepth 1 -type f -name "*.AppImage" ! -name "*.tar.gz" | head -1)
LINUX_TARGZ=$(find    "$STAGING_DIR" -maxdepth 1 -type f -name "*.AppImage.tar.gz"             | head -1)
LINUX_SIG=$(find      "$STAGING_DIR" -maxdepth 1 -type f -name "*.AppImage.tar.gz.sig"         | head -1)
WIN_MSI=$(find        "$STAGING_DIR" -maxdepth 1 -type f -name "*.msi" ! -name "*.zip"         | head -1)
WIN_ZIP=$(find        "$STAGING_DIR" -maxdepth 1 -type f -name "*.msi.zip"                     | head -1)
WIN_SIG=$(find        "$STAGING_DIR" -maxdepth 1 -type f -name "*.msi.zip.sig"                 | head -1)

[[ -z "$LINUX_APPIMAGE" && -z "$WIN_MSI" ]] && \
  error "No se encontraron binarios en staging/. Copiá al menos uno antes de continuar."

# Validar que si hay AppImage también hay .tar.gz y .sig (requeridos por el updater)
if [[ -n "$LINUX_APPIMAGE" ]]; then
  [[ -z "$LINUX_TARGZ" ]] && error "Falta el archivo .AppImage.tar.gz en staging/ (requerido por el updater)."
  [[ -z "$LINUX_SIG"   ]] && error "Falta el archivo .AppImage.tar.gz.sig en staging/ (requerido por el updater)."
fi
if [[ -n "$WIN_MSI" ]]; then
  [[ -z "$WIN_ZIP" ]] && error "Falta el archivo .msi.zip en staging/ (requerido por el updater)."
  [[ -z "$WIN_SIG" ]] && error "Falta el archivo .msi.zip.sig en staging/ (requerido por el updater)."
fi

[[ -n "$LINUX_APPIMAGE" ]] && info "Linux AppImage : $(basename "$LINUX_APPIMAGE")"
[[ -n "$LINUX_TARGZ"    ]] && info "Linux tar.gz   : $(basename "$LINUX_TARGZ")"
[[ -n "$WIN_MSI"        ]] && info "Windows MSI    : $(basename "$WIN_MSI")"
[[ -n "$WIN_ZIP"        ]] && info "Windows zip    : $(basename "$WIN_ZIP")"

# ---- Confirmar -------------------------------------------------------------
echo ""
warn "Se va a crear el release $TAG. ¿Continuar? [s/N]"
read -r CONFIRM
[[ "$CONFIRM" =~ ^[sS]$ ]] || { info "Cancelado."; exit 0; }

# ---- URLs de descarga (usadas en update.json y README) ---------------------
LINUX_APPIMAGE_FILENAME=$(basename "${LINUX_APPIMAGE:-}")
LINUX_TARGZ_FILENAME=$(basename "${LINUX_TARGZ:-}")
WIN_MSI_FILENAME=$(basename "${WIN_MSI:-}")
WIN_ZIP_FILENAME=$(basename "${WIN_ZIP:-}")

LINUX_APPIMAGE_URL="${REPO_URL}/releases/download/${TAG}/${LINUX_APPIMAGE_FILENAME}"
LINUX_TARGZ_URL="${REPO_URL}/releases/download/${TAG}/${LINUX_TARGZ_FILENAME}"
WIN_MSI_URL="${REPO_URL}/releases/download/${TAG}/${WIN_MSI_FILENAME}"
WIN_ZIP_URL="${REPO_URL}/releases/download/${TAG}/${WIN_ZIP_FILENAME}"

# ---- Actualizar latest.json ------------------------------------------------
LATEST_URL="${REPO_URL}/releases/latest"
jq --arg url "$LATEST_URL" '.url = $url' "$LATEST_JSON" > "${LATEST_JSON}.tmp" \
  && mv "${LATEST_JSON}.tmp" "$LATEST_JSON"

# ---- Generar update.json (formato Tauri v2 updater) ------------------------
info "Generando update.json..."
PUB_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
UPDATE_PLATFORMS="{}"

if [[ -n "$LINUX_SIG" ]]; then
  LINUX_SIGNATURE=$(cat "$LINUX_SIG")
  UPDATE_PLATFORMS=$(echo "$UPDATE_PLATFORMS" | jq \
    --arg url "$LINUX_TARGZ_URL" \
    --arg sig "$LINUX_SIGNATURE" \
    '. + {"linux-x86_64": {"url": $url, "signature": $sig}}')
fi

if [[ -n "$WIN_SIG" ]]; then
  WIN_SIGNATURE=$(cat "$WIN_SIG")
  UPDATE_PLATFORMS=$(echo "$UPDATE_PLATFORMS" | jq \
    --arg url "$WIN_ZIP_URL" \
    --arg sig "$WIN_SIGNATURE" \
    '. + {"windows-x86_64": {"url": $url, "signature": $sig}}')
fi

jq -n \
  --arg version "$VERSION" \
  --arg notes   "${NOTES:-}" \
  --arg pubdate "$PUB_DATE" \
  --argjson platforms "$UPDATE_PLATFORMS" \
  '{"version": $version, "notes": $notes, "pub_date": $pubdate, "platforms": $platforms}' \
  > "$UPDATE_JSON"

info "update.json generado."

# ---- Actualizar RELEASES.md ------------------------------------------------
LINUX_LINK=""
WIN_LINK=""
[[ -n "$LINUX_APPIMAGE" ]] && LINUX_LINK="[⬇ AppImage](${LINUX_APPIMAGE_URL})"
[[ -n "$WIN_MSI"        ]] && WIN_LINK="[⬇ MSI](${WIN_MSI_URL})"

NOTES_ESCAPED="${NOTES//$'\n'/ }"
ROW="| ${TAG} | ${LINUX_LINK} | ${WIN_LINK} | ${NOTES_ESCAPED} |"

awk -v row="$ROW" '
  /^\|[-| ]+\|/ {
    count++
    print
    if (count == 1 || count == 2) { print row }
    next
  }
  { print }
' "$RELEASES_MD" > "${RELEASES_MD}.tmp" && mv "${RELEASES_MD}.tmp" "$RELEASES_MD"

info "RELEASES.md actualizado."

# ---- Actualizar links de descarga en README.md -----------------------------
README="$REPO_ROOT/README.md"
if [[ -n "$LINUX_APPIMAGE" ]]; then
  sed -i "s|\\[⬇ Descargar\\]([^)]*) <!-- LINUX_ASSET -->|[⬇ Descargar](${LINUX_APPIMAGE_URL}) <!-- LINUX_ASSET -->|g" "$README"
  sed -i "s|\\[⬇ Download\\]([^)]*) <!-- LINUX_ASSET -->|[⬇ Download](${LINUX_APPIMAGE_URL}) <!-- LINUX_ASSET -->|g" "$README"
fi
if [[ -n "$WIN_MSI" ]]; then
  sed -i "s|\\[⬇ Descargar\\]([^)]*) <!-- WIN_ASSET -->|[⬇ Descargar](${WIN_MSI_URL}) <!-- WIN_ASSET -->|g" "$README"
  sed -i "s|\\[⬇ Download\\]([^)]*) <!-- WIN_ASSET -->|[⬇ Download](${WIN_MSI_URL}) <!-- WIN_ASSET -->|g" "$README"
fi
info "README.md actualizado."

# ---- Commit + tag + push ---------------------------------------------------
git -C "$REPO_ROOT" add latest.json update.json RELEASES.md README.md
git -C "$REPO_ROOT" commit -m "release: ${TAG}"
git -C "$REPO_ROOT" tag "$TAG"
git -C "$REPO_ROOT" push origin main
git -C "$REPO_ROOT" push origin "$TAG"
info "Commit y tag $TAG pusheados."

# ---- Crear GitHub Release via API ------------------------------------------
info "Creando GitHub Release..."
RELEASE_BODY="${NOTES:-Sin notas de release.}"

RELEASE_RESPONSE=$(curl -sf \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"tag_name\": \"${TAG}\",
    \"name\": \"Open73 ${TAG}\",
    \"body\": $(echo "$RELEASE_BODY" | jq -Rs .),
    \"draft\": false,
    \"prerelease\": false,
    \"make_latest\": \"true\"
  }" \
  "https://api.github.com/repos/${OWNER}/${REPO}/releases")

RELEASE_ID=$(echo "$RELEASE_RESPONSE" | jq -r '.id')
[[ -z "$RELEASE_ID" || "$RELEASE_ID" == "null" ]] && \
  error "No se pudo crear el release. Respuesta: $RELEASE_RESPONSE"

info "Release creado (id: $RELEASE_ID). Subiendo artifacts..."

# ---- Subir artifacts como assets -------------------------------------------
upload_asset() {
  local filepath="$1"
  local filename
  filename=$(basename "$filepath")
  local mime="application/octet-stream"

  info "Subiendo: $filename"
  RESULT=$(curl -sf \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Content-Type: ${mime}" \
    --data-binary @"$filepath" \
    "https://uploads.github.com/repos/${OWNER}/${REPO}/releases/${RELEASE_ID}/assets?name=${filename}")

  local state
  state=$(echo "$RESULT" | jq -r '.state // "error"')
  [[ "$state" == "uploaded" ]] || error "Falló la subida de $filename. Respuesta: $RESULT"
  info "$filename subido correctamente."
}

[[ -n "$LINUX_APPIMAGE" ]] && upload_asset "$LINUX_APPIMAGE"
[[ -n "$LINUX_TARGZ"    ]] && upload_asset "$LINUX_TARGZ"
[[ -n "$LINUX_SIG"      ]] && upload_asset "$LINUX_SIG"
[[ -n "$WIN_MSI"        ]] && upload_asset "$WIN_MSI"
[[ -n "$WIN_ZIP"        ]] && upload_asset "$WIN_ZIP"
[[ -n "$WIN_SIG"        ]] && upload_asset "$WIN_SIG"

echo ""
info "Release $TAG publicado exitosamente."
info "URL: ${REPO_URL}/releases/tag/${TAG}"

# ---- Limpiar staging/ ------------------------------------------------------
warn "¿Limpiar los artifacts de staging/? [s/N]"
read -r CLEAN
if [[ "$CLEAN" =~ ^[sS]$ ]]; then
  find "$STAGING_DIR" -maxdepth 1 -type f ! -name '.gitkeep' -delete
  info "staging/ limpiado."
fi
