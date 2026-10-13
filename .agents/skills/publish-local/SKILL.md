---
name: publish-local
description: >-
  Compila y publica MacSCP localmente. Genera los artefactos de distribución en el directorio dist/ (.app, .dmg, .zip, dSYM, checksums SHA-256), instala la aplicación en /Applications de macOS con respaldo y registro en LaunchServices, y realiza commit y push de los cambios en Git. Úsalo cuando el usuario pida compilar para producción, publicar localmente, generar instaladores o empaquetar e instalar MacSCP.
---

# Publicación Local de MacSCP

Esta skill automatiza el ciclo completo de empaquetado, distribución local e integración con el repositorio de Git para el proyecto MacSCP.

## Resumen del Flujo de Trabajo

1. **Pre-verificación**:
   - Detecta el entorno de Xcode (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`).
   - Lee la versión actual desde `MacSCP/Resources/Info.plist` y valida la sincronización con `MacSCP/App/MacSCPApp.swift`.
2. **Compilación Release**:
   - Ejecuta `xcodebuild` con configuración `Release` hacia `.build/DerivedData`.
3. **Generación de Artefactos (`dist/`)**:
   - Copia `MacSCP.app`, `MacSCP.app.dSYM` y `MacSCP.swiftmodule` a `dist/`.
   - Realiza firmado ad-hoc (`codesign`).
   - Genera `dist/MacSCP.zip` preservando metadatos y enlaces de macOS (`ditto`).
   - Genera `dist/MacSCP.dmg` comprimido (UDZO) con acceso directo drag-and-drop a `/Applications`.
   - Calcula sumas de verificación `dist/SHA256SUMS.txt`.
4. **Instalación en `/Applications`**:
   - Cierra instancias previas en ejecución de MacSCP de forma limpia (`pkill -x MacSCP`).
   - Crea un respaldo de seguridad de la versión anterior (`/Applications/MacSCP.app.bak`).
   - Instala la nueva versión en `/Applications/MacSCP.app`.
   - Elimina marcas de cuarentena (`xattr -dr com.apple.quarantine`) y registra el bundle con LaunchServices (`lsregister`).
5. **Control de Versiones (Git)**:
   - Verifica el estado de trabajo (`git status --porcelain`).
   - Añade los archivos modificados (`git add -A`).
   - Realiza commit descriptivo (`release: v<version> (<build>)`).
   - Sube los cambios al branch remoto (`git push origin <branch>`).
   - Opcionalmente crea y sube el tag Git correspondiente (`git tag v<version>`).

---

## Ejecución Rápida

Puedes ejecutar directamente el script automatizado provisto en la skill:

```bash
# Publicación completa estándar (Build + Dist + Install + Git Push):
./.agents/skills/publish-local/scripts/publish.sh

# Publicación con tag de versión y apertura automática del app:
./.agents/skills/publish-local/scripts/publish.sh --tag --launch

# Omitir pasos según sea necesario:
./.agents/skills/publish-local/scripts/publish.sh --skip-git
./.agents/skills/publish-local/scripts/publish.sh --skip-install
```

---

## Pasos Detallados para el Agente

Cuando ejecutes este procedimiento de forma autónoma o asistas al usuario, sigue estos pasos:

### Paso 1: Verificación de Estado y Versión
Comprueba que no haya conflictos de merge y revisa la versión del proyecto:
```bash
git status
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" MacSCP/Resources/Info.plist)
echo "Versión a publicar: $VERSION"
```

### Paso 2: Compilación Release
Compila usando Xcode:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project MacSCP.xcodeproj \
  -scheme MacSCP \
  -configuration Release \
  -derivedDataPath .build/DerivedData \
  build
```
> [!NOTE]
> En entornos con sandbox restringido para macros de Swift, es necesario ejecutar este comando sin sandbox (`BypassSandbox: true`) debido a las llamadas a `swift-plugin-server`.

### Paso 3: Empaquetado en `dist/`
Prepara el directorio `dist/` y genera los artefactos:
```bash
mkdir -p dist
rm -rf dist/*

# Copiar bundle y símbolos
cp -R .build/DerivedData/Build/Products/Release/MacSCP.app dist/
cp -R .build/DerivedData/Build/Products/Release/MacSCP.app.dSYM dist/
cp -R .build/DerivedData/Build/Products/Release/MacSCP.swiftmodule dist/

# Firmado ad-hoc
codesign --force --deep --sign - dist/MacSCP.app

# Archivo ZIP
ditto -c -k --keepParent dist/MacSCP.app dist/MacSCP.zip

# Imagen de disco DMG con acceso directo a Aplicaciones
DMG_STAGING=$(mktemp -d /tmp/macscp_dmg_staging.XXXXXX)
cp -R dist/MacSCP.app "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
diskutil image create from --format UDZO --volumeName "MacSCP" "$DMG_STAGING" dist/MacSCP.dmg
rm -rf "$DMG_STAGING"

# Checksums SHA-256
(cd dist && shasum -a 256 MacSCP.dmg MacSCP.zip > SHA256SUMS.txt)
```

### Paso 4: Instalación Local en `/Applications`
Reemplaza la versión instalada de forma segura:
```bash
# Cerrar instancia si está corriendo
pkill -x MacSCP || true

# Respaldo de seguridad previo
[ -d /Applications/MacSCP.app ] && cp -R /Applications/MacSCP.app /Applications/MacSCP.app.bak && rm -rf /Applications/MacSCP.app

# Instalar y registrar
cp -R dist/MacSCP.app /Applications/
xattr -dr com.apple.quarantine /Applications/MacSCP.app 2>/dev/null || true
touch /Applications/MacSCP.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted /Applications/MacSCP.app
```

### Paso 5: Sincronización en Git
Confirma y sube los cambios:
```bash
if [ -n "$(git status --porcelain)" ]; then
    git add -A
    git commit -m "release: v${VERSION} (local build & dist)"
    git push origin $(git symbolic-ref --short HEAD)
fi
```

---

## Capacidades Adicionales y Extensiones de la Skill

La skill está preparada para incorporar validaciones y tareas adicionales según los requerimientos del proyecto:

1. **Sincronización y Bump Automático de Versión**:
   - Detectar incrementos semánticos (`major`, `minor`, `patch`).
   - Actualizar simultáneamente `MacSCP/Resources/Info.plist` y `MacSCP/App/MacSCPApp.swift`.
2. **Ejecución de Pruebas Automatizadas (Unit Tests)**:
   - Ejecutar `xcodebuild test` antes de la compilación de Release para evitar empaquetar versiones con regresiones.
3. **Firma con Apple Developer ID y Notarización**:
   - Para distribuir el `.dmg` fuera de la máquina local sin advertencias de macOS Gatekeeper (`xcrun notarytool submit`).
4. **Creación de Release en GitHub**:
   - Si la herramienta `gh` está autenticada, publicar automáticamente una Release en GitHub y adjuntar `dist/MacSCP.dmg` y `dist/MacSCP.zip`.
5. **Generador de Changelog / Notas de Versión**:
   - Extraer automáticamente el historial de commits desde el último tag de Git y agregarlo a un archivo `CHANGELOG.md` o al cuerpo de la release.
