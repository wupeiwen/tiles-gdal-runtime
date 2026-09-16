# tiles-gdal-runtime

独立构建和发布 Tiles Download 使用的裁剪版 GDAL runtime。该项目只负责
GDAL/PROJ 源码、平台工具链、依赖重定位、许可证、校验和 GitHub Release；
业务项目不在 `npm run dist` 时编译 GDAL。

当前发布目标：

- `darwin-arm64`：Apple Silicon，最低 macOS 12，使用 macOS 26 runner
- `win32-x64`：Windows x64，使用 Windows 2025 runner

启用的 GDAL 能力为 VRT、GTiff、PNG、PROJ 和 `gdal raster tile`。网络、
数据库、JPEG、WebP 以及未被客户端使用的 GDAL 工具均不打包。

## 构建

GitHub Actions 默认只在手动触发或发布时运行，避免业务仓库每次提交消耗额度：

```text
Actions → Build runtime → Run workflow
```

也可以在对应平台本地运行：

```bash
export RUNTIME_KEY=darwin-arm64
export GDAL_SOURCE_DIR=/path/to/gdal-3.13.3
export PROJ_SOURCE_DIR=/path/to/proj-9.8.1
export MACOSX_DEPLOYMENT_TARGET=12.0
scripts/runtime/build-unix.sh
node scripts/verify-gdal-runtime.js runtime/darwin-arm64
```

Windows 使用 PowerShell：

```powershell
$env:RUNTIME_KEY = 'win32-x64'
$env:GDAL_SOURCE_DIR = 'D:\src\gdal-3.13.3'
$env:PROJ_SOURCE_DIR = 'D:\src\proj-9.8.1'
.\scripts\runtime\build-windows.ps1
node scripts\verify-gdal-runtime.js runtime\win32-x64
```

发布前必须通过版本、驱动、PROJ 数据和 GeoTIFF → XYZ PNG 冒烟测试。
macOS 还会检查 Mach-O 最低系统版本和绝对 Homebrew/runner 路径。

## Release 文件

每个 Release 上传：

```text
darwin-arm64-gdal-<gdal>-proj-<proj>.tar.gz
win32-x64-gdal-<gdal>-proj-<proj>.zip
checksums.txt
runtime-manifest.json
```

业务项目通过 `TILES_GDAL_RUNTIME_RELEASE` 下载对应版本，验证通过后才会打包。

GDAL、PROJ、PNG、TIFF、zlib、zstd 等许可证和 NOTICE 必须随 runtime 发布。
