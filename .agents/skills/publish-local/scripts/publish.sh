#!/usr/bin/env bash
# ==============================================================================
# publish.sh - Compilación, empaquetado en /dist, instalación local y git push
# para MacSCP en macOS.
# ==============================================================================

set -euo pipefail

# Colores para salida de terminal
BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$PROJECT_ROOT"

# Configuración por defecto
SKIP_GIT=false
SKIP_INSTALL=false
CREATE_TAG=false
LAUNCH_APP=false
COMMIT_MSG=""
XCODE_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# Ayuda
usage() {
    cat <<EOF
Uso: $(basename "$0") [OPCIONES]

Opciones:
  --skip-git             Omite commit y push en Git.
  --skip-install         Omite la instalación en /Applications.
  --tag                  Crea y sube un tag en Git con la versión actual (ej. v1.2.0).
  --launch               Abre la aplicación en /Applications al finalizar la instalación.
  --commit-msg "MENSAJE" Mensaje de commit personalizado para Git.
  --help                 Muestra esta ayuda.

EOF
    exit 0
}

# Parsear argumentos
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-git)
            SKIP_GIT=true
            shift
            ;;
        --skip-install)
            SKIP_INSTALL=true
            shift
            ;;
        --tag)
            CREATE_TAG=true
            shift
            ;;
        --launch)
            LAUNCH_APP=true
            shift
            ;;
        --commit-msg)
            COMMIT_MSG="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo -e "${RED}Opción no reconocida: $1${NC}"
            usage
            ;;
    esac
done

echo -e "${BLUE}${BOLD}==> Iniciando proceso de publicación de MacSCP...${NC}"

# 1. Validar entorno de compilación
if [ -d "$XCODE_DIR" ]; then
    export DEVELOPER_DIR="$XCODE_DIR"
else
    echo -e "${YELLOW}Advertencia: $XCODE_DIR no encontrado. Usando developer dir por defecto de xcode-select.${NC}"
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo -e "${RED}Error: xcodebuild no está disponible.${NC}"
    exit 1
fi

# 2. Extraer versión de Info.plist
PLIST_PATH="MacSCP/Resources/Info.plist"
if [ ! -f "$PLIST_PATH" ]; then
    echo -e "${RED}Error: No se encontró $PLIST_PATH.${NC}"
    exit 1
fi

MARKETING_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST_PATH" 2>/dev/null || echo "1.0.0")
BUILD_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST_PATH" 2>/dev/null || echo "$(date +%Y.%m.%d)")

echo -e "${GREEN}✓ Versión detectada: ${BOLD}v${MARKETING_VERSION} (Build ${BUILD_VERSION})${NC}"

# Validar sincronización con AppVersion en MacSCPApp.swift si existe
SWIFT_APP_FILE="MacSCP/App/MacSCPApp.swift"
if [ -f "$SWIFT_APP_FILE" ]; then
    SWIFT_VERSION=$(grep -E 'marketingVersion\s*=\s*' "$SWIFT_APP_FILE" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
    if [ -n "$SWIFT_VERSION" ] && [ "$SWIFT_VERSION" != "$MARKETING_VERSION" ]; then
        echo -e "${YELLOW}Advertencia: Discrepancia de versión detectada:${NC}"
        echo -e "   - Info.plist:      $MARKETING_VERSION"
        echo -e "   - MacSCPApp.swift: $SWIFT_VERSION"
    else
        echo -e "${GREEN}✓ Sincronización de versión con MacSCPApp.swift verificada.${NC}"
    fi
fi

# 3. Compilar configuración Release con xcodebuild
echo -e "\n${BLUE}${BOLD}==> [Paso 1/4] Compilando Release con xcodebuild...${NC}"
DERIVED_DATA=".build/DerivedData"
mkdir -p "$DERIVED_DATA"

xcodebuild -project MacSCP.xcodeproj \
           -scheme MacSCP \
           -configuration Release \
           -derivedDataPath "$DERIVED_DATA" \
           build >/dev/null

BUILT_APP="$DERIVED_DATA/Build/Products/Release/MacSCP.app"
BUILT_DSYM="$DERIVED_DATA/Build/Products/Release/MacSCP.app.dSYM"
BUILT_MODULE="$DERIVED_DATA/Build/Products/Release/MacSCP.swiftmodule"

if [ ! -d "$BUILT_APP" ]; then
    echo -e "${RED}Error: La compilación no generó $BUILT_APP.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Compilación Release completada con éxito.${NC}"

# 4. Generar artefactos en ./dist
echo -e "\n${BLUE}${BOLD}==> [Paso 2/4] Generando artefactos en ./dist...${NC}"
mkdir -p dist

# Limpiar artefactos anteriores
rm -rf dist/MacSCP.app dist/MacSCP.app.dSYM dist/MacSCP.swiftmodule dist/MacSCP.zip dist/MacSCP.dmg dist/SHA256SUMS.txt

# Copiar bundle y símbolos
cp -R "$BUILT_APP" dist/
if [ -d "$BUILT_DSYM" ]; then
    cp -R "$BUILT_DSYM" dist/
fi
if [ -d "$BUILT_MODULE" ]; then
    cp -R "$BUILT_MODULE" dist/
fi

# Firmado ad-hoc
codesign --force --deep --sign - dist/MacSCP.app >/dev/null 2>&1 || true

# Generar archivo ZIP (preservando atributos de macOS con ditto)
echo "  - Generando MacSCP.zip..."
ditto -c -k --keepParent dist/MacSCP.app dist/MacSCP.zip

# Generar archivo DMG (con symlink a /Applications para drag-and-drop)
echo "  - Generando MacSCP.dmg..."
DMG_STAGING=$(mktemp -d /tmp/macscp_dmg_staging.XXXXXX)
cp -R dist/MacSCP.app "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# Usar diskutil image si está disponible (macOS moderno), o fallback a hdiutil
if command -v diskutil >/dev/null 2>&1 && diskutil help image create >/dev/null 2>&1; then
    diskutil image create from --format UDZO --volumeName "MacSCP" "$DMG_STAGING" dist/MacSCP.dmg >/dev/null
else
    hdiutil create -volname "MacSCP" -srcfolder "$DMG_STAGING" -ov -format UDZO dist/MacSCP.dmg >/dev/null
fi
rm -rf "$DMG_STAGING"

# Generar checksums SHA-256
echo "  - Calculando checksums SHA-256..."
(cd dist && shasum -a 256 MacSCP.dmg MacSCP.zip > SHA256SUMS.txt)

echo -e "${GREEN}✓ Artefactos generados exitosamente en ./dist:${NC}"
ls -lh dist/ | grep -E "MacSCP|SHA256SUMS" | awk '{print "    " $9, "(" $5 ")"}'

# 5. Instalar en /Applications
if [ "$SKIP_INSTALL" = false ]; then
    echo -e "\n${BLUE}${BOLD}==> [Paso 3/4] Instalando MacSCP.app en /Applications...${NC}"
    
    # Cerrar instancia en ejecución si existe
    if pgrep -x "MacSCP" >/dev/null 2>&1; then
        echo -e "${YELLOW}  - Cerrando instancia de MacSCP en ejecución...${NC}"
        pkill -x "MacSCP" || true
        sleep 1
    fi
    
    TARGET_APP="/Applications/MacSCP.app"
    BACKUP_APP="/Applications/MacSCP.app.bak"
    
    if [ -d "$TARGET_APP" ]; then
        rm -rf "$BACKUP_APP"
        cp -R "$TARGET_APP" "$BACKUP_APP"
        rm -rf "$TARGET_APP"
    fi
    
    cp -R dist/MacSCP.app /Applications/
    
    # Limpiar atributos de cuarentena y registrar en LaunchServices
    xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
    touch "$TARGET_APP"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted "$TARGET_APP" 2>/dev/null || true
    
    echo -e "${GREEN}✓ Instalado en $TARGET_APP exitosamente.${NC}"
    
    if [ "$LAUNCH_APP" = true ]; then
        echo "  - Abriendo aplicación..."
        open "$TARGET_APP"
    fi
else
    echo -e "\n${YELLOW}==> [Paso 3/4] Instalación en /Applications omitida (--skip-install).${NC}"
fi

# 6. Git commit y push
if [ "$SKIP_GIT" = false ]; then
    echo -e "\n${BLUE}${BOLD}==> [Paso 4/4] Sincronizando cambios con Git...${NC}"
    
    # Comprobar si hay cambios
    STATUS_OUTPUT=$(git status --porcelain)
    if [ -n "$STATUS_OUTPUT" ]; then
        echo "  - Cambios detectados en el repositorio:"
        git status --short
        
        git add -A
        
        if [ -z "$COMMIT_MSG" ]; then
            COMMIT_MSG="release: v${MARKETING_VERSION} (build ${BUILD_VERSION})"
        fi
        
        git commit -m "$COMMIT_MSG"
        
        CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")
        echo "  - Empujando a origin/$CURRENT_BRANCH..."
        git push origin "$CURRENT_BRANCH"
        
        if [ "$CREATE_TAG" = true ]; then
            TAG_NAME="v${MARKETING_VERSION}"
            echo "  - Creando y subiendo tag $TAG_NAME..."
            git tag -f -a "$TAG_NAME" -m "Release $TAG_NAME"
            git push origin "$TAG_NAME" --force
        fi
        
        echo -e "${GREEN}✓ Git commit y push completados exitosamente.${NC}"
    else
        echo -e "${GREEN}✓ No hay cambios pendientes para commitear en Git.${NC}"
        
        if [ "$CREATE_TAG" = true ]; then
            TAG_NAME="v${MARKETING_VERSION}"
            echo "  - Creando y subiendo tag $TAG_NAME..."
            git tag -f -a "$TAG_NAME" -m "Release $TAG_NAME"
            git push origin "$TAG_NAME" --force
            echo -e "${GREEN}✓ Tag $TAG_NAME subido exitosamente.${NC}"
        fi
    fi
else
    echo -e "\n${YELLOW}==> [Paso 4/4] Paso de Git omitido (--skip-git).${NC}"
fi

echo -e "\n${GREEN}${BOLD}🎉 ¡Publicación completada con éxito!${NC}\n"
