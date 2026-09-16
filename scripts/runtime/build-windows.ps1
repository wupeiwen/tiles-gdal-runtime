$ErrorActionPreference = 'Stop'
if (-not $env:RUNTIME_KEY -or -not $env:GDAL_SOURCE_DIR -or -not $env:PROJ_SOURCE_DIR) { throw 'RUNTIME_KEY, GDAL_SOURCE_DIR and PROJ_SOURCE_DIR are required' }

$RepoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$WorkRoot = Join-Path $env:RUNNER_TEMP "tiles-gdal-$env:RUNTIME_KEY"
$ProjPrefix = Join-Path $WorkRoot 'proj'
$RuntimeDir = Join-Path $RepoRoot "runtime\$env:RUNTIME_KEY"
$BuildJobs = 2
if ($env:BUILD_JOBS) {
  $BuildJobs = [int]$env:BUILD_JOBS
  if ($BuildJobs -lt 1) { throw 'BUILD_JOBS must be a positive integer' }
}

$ProjConfigureArgs = @(
  '-S', $env:PROJ_SOURCE_DIR,
  '-B', "$WorkRoot\proj-build",
  '-A', 'x64',
  '-DCMAKE_BUILD_TYPE=Release',
  "-DCMAKE_INSTALL_PREFIX=$ProjPrefix",
  "-DCMAKE_PREFIX_PATH=$env:CONDA_PREFIX",
  '-DBUILD_SHARED_LIBS=OFF',
  '-DBUILD_TESTING=OFF',
  '-DBUILD_APPS=OFF',
  '-DENABLE_TIFF=OFF',
  '-DENABLE_CURL=OFF'
)
cmake @ProjConfigureArgs
cmake --build "$WorkRoot\proj-build" --config Release --parallel $BuildJobs
cmake --install "$WorkRoot\proj-build" --config Release

$GdalConfigureArgs = @(
  '-S', $env:GDAL_SOURCE_DIR,
  '-B', "$WorkRoot\gdal-build",
  '-A', 'x64',
  '-C', "$RepoRoot\scripts\runtime\common.cmake",
  '-DCMAKE_BUILD_TYPE=Release',
  "-DCMAKE_INSTALL_PREFIX=$RuntimeDir",
  "-DCMAKE_PREFIX_PATH=$ProjPrefix;$env:CONDA_PREFIX",
  "-DPROJ_DIR=$ProjPrefix\lib\cmake\proj"
)
cmake @GdalConfigureArgs
cmake --build "$WorkRoot\gdal-build" --config Release --parallel $BuildJobs
cmake --install "$WorkRoot\gdal-build" --config Release

# Keep only the CLI surface used by the desktop application.
$KeepBinaries = @('gdal.exe', 'gdalinfo.exe', 'gdal_translate.exe', 'gdalbuildvrt.exe')
Get-ChildItem "$RuntimeDir\bin" -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Extension -eq '.exe' -and $KeepBinaries -notcontains $_.Name } |
  Remove-Item -Force

New-Item -ItemType Directory -Force "$RuntimeDir\share\proj", "$RuntimeDir\licenses" | Out-Null
Copy-Item "$ProjPrefix\share\proj\*" "$RuntimeDir\share\proj" -Recurse -Force
Copy-Item "$env:GDAL_SOURCE_DIR\LICENSE.TXT" "$RuntimeDir\licenses\GDAL.txt"
Copy-Item "$env:PROJ_SOURCE_DIR\COPYING" "$RuntimeDir\licenses\PROJ.txt"
Get-ChildItem "$RuntimeDir\lib", "$ProjPrefix\bin" -Filter *.dll -ErrorAction SilentlyContinue | Copy-Item -Destination "$RuntimeDir\bin" -Force
Get-ChildItem "$env:CONDA_PREFIX\Library\bin\*.dll" -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match '^(sqlite|zlib|zstd)' } |
  Copy-Item -Destination "$RuntimeDir\bin" -Force

node "$RepoRoot\scripts\verify-gdal-runtime.js" $RuntimeDir
