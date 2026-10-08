# MacSCP

Aplicación nativa de macOS inspirada en WinSCP, minimalista, rápida y diseñada para SwiftUI en Xcode.

---

## Características Implementadas

1. **Gestor Gráfico de Conexiones SSH (`~/.ssh/config`)**:
   - Lee automáticamente al iniciar las conexiones definidas en tu archivo `~/.ssh/config` (y sugerencias de `~/.ssh/known_hosts`).
   - Interfaz con buscador en tiempo real por alias, host o usuario.
   - Muestra indicador de llaves privadas (`🔑 id_rsa`) o saltos (`🔀 ProxyJump`).
   - Opción para agregar conexiones manuales o recargar el archivo en cualquier momento.

2. **Doble Panel de Navegación**:
   - Panel izquierdo: Archivos locales de tu Mac.
   - Panel derecho: Archivos remotos en el servidor SSH.
   - Barra divisoria redimensionable (*Split View*).

3. **Integración con Nextpad++ y Sincronización Automática al Guardar**:
   - Al hacer doble clic en cualquier archivo remoto, se descarga a un directorio temporal de caché (`~/Library/Caches/MacSCP/RemoteEdit/...`).
   - Se abre de inmediato en tu aplicación **/Applications/Nextpad++.app** (o editor predeterminado si se ejecutara en otra máquina).
   - Un monitor de eventos del sistema (`DispatchSourceFileSystemObject` + polling de respaldo) detecta cuando guardas cambios en Nextpad++ (`Cmd + S`).
   - Al guardar, MacSCP sube automáticamente el archivo al servidor reemplazando el contenido anterior y refresca la lista remota.

4. **Copia Rápida entre Paneles (Subir y Descargar)**:
   - Botón central **Subir (`→`)**: Copia el archivo local seleccionado a la ruta remota activa.
   - Botón central **Bajar (`←`)**: Descarga el archivo remoto seleccionado a la ruta local activa.
   - También disponible mediante clic derecho en cualquier archivo.

5. **Copia Rápida Remoto a Remoto (Servidor a Servidor)**:
   - Clic derecho en un archivo o carpeta remota > **"Copiar a otra ubicación en servidor..."**.
   - Se abre un diálogo para ingresar la ruta de destino remota.
   - La copia se ejecuta directamente en el servidor (`cp -r`) mediante SSH, de forma instantánea y sin consumir ancho de banda de tu Mac.

6. **Iconos Simples y Visualización Clara de Extensión**:
   - Iconos limpios: carpeta azul para directorios y documento para archivos.
   - Columna/insignia destacada con la extensión del archivo en mayúsculas (ej. `TXT`, `PY`, `JSON`, `SH`).

7. **Ruta Completa (Path) con Clic Derecho para Copiar**:
   - La parte superior de cada panel muestra la ruta absoluta actual en monoespaciado.
   - Clic derecho sobre la barra de ruta > **"Copiar ruta al portapapeles"**.
   - También permite doble clic en la barra para editar o ingresar una ruta directamente, botón para subir un nivel (`..`) y botón de refresco.

8. **Tasa de Transferencia y Porcentaje de Carga/Descarga**:
   - Panel de estado inferior en tiempo real durante subidas y descargas.
   - Barra de progreso nativa, porcentaje exacto (ej. `64.2%`), tasa de transferencia en tiempo real (ej. `3.8 MB/s`), y bytes transferidos vs. tamaño total.

---

## Cómo Abrir y Compilar en Xcode

1. Abre la carpeta del proyecto en Finder:
   ```bash
   open .
   ```
2. Haz doble clic en el archivo **`MacSCP.xcodeproj`** para abrirlo en Xcode.
   *(También puedes abrir la carpeta directamente en Xcode con `File > Open...` gracias al `Package.swift` incluido).*
3. Selecciona tu Mac como destino de compilación (esquina superior de Xcode).
4. Presiona **`Cmd + R`** (o el botón Play) para compilar y ejecutar la aplicación.

---

## Estructura del Proyecto

```
macscp/
├── MacSCP.xcodeproj/          # Proyecto Xcode listo para abrir
│   └── project.pbxproj
├── Package.swift               # Manifiesto Swift Package Manager alternativo
├── MacSCP/
│   ├── App/
│   │   └── MacSCPApp.swift     # Punto de entrada de la aplicación macOS
│   ├── Models/
│   │   ├── SSHConnection.swift # Modelo de datos de conexión SSH
│   │   ├── FileItem.swift      # Modelo de archivo/directorio (local y remoto)
│   │   └── TransferProgress.swift # Progreso, velocidad y bytes
│   ├── Services/
│   │   ├── SSHConfigParser.swift  # Lector y parser de ~/.ssh/config
│   │   ├── SFTPClient.swift       # Cliente SFTP v3 nativo sobre ssh -s sftp
│   │   ├── LocalFileManager.swift # Explorador del sistema de archivos local
│   │   └── FileWatchService.swift # Monitor de guardado de Nextpad++ y auto-upload
│   ├── ViewModels/
│   │   └── AppViewModel.swift     # Coordinador central de la interfaz y servicios
│   ├── Views/
│   │   ├── MainView.swift         # Vista principal con doble panel
│   │   ├── FileBrowserPanel.swift # Panel de navegación de archivos
│   │   ├── PathHeaderView.swift   # Barra de ruta con copia al portapapeles
│   │   ├── ConnectionsSheet.swift # Listado gráfico de servidores SSH
│   │   ├── RemoteCopySheet.swift  # Diálogo de copia en el mismo servidor
│   │   ├── TransferProgressView.swift # Barra de velocidad y porcentaje
│   │   └── ToastBannerView.swift  # Notificaciones flotantes
│   └── Resources/
│       ├── Info.plist             # Metadatos del bundle
│       ├── MacSCP.entitlements    # Entitlements para ejecución de procesos
│       └── Assets.xcassets/       # Catálogo de recursos e iconos
└── README.md
```

