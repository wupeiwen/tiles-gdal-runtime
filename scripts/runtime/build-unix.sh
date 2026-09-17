#!/usr/bin/env bash
set -euo pipefail

: "${RUNTIME_KEY:?RUNTIME_KEY is required}"
: "${GDAL_SOURCE_DIR:?GDAL_SOURCE_DIR is required}"
: "${PROJ_SOURCE_DIR:?PROJ_SOURCE_DIR is required}"

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
work_root=${RUNNER_TEMP:-/tmp}/tiles-gdal-${RUNTIME_KEY}
proj_prefix="$work_root/proj"
runtime_dir="$repo_root/runtime/$RUNTIME_KEY"
dependency_prefix=${DEPENDENCY_PREFIX:-}
build_jobs=${BUILD_JOBS:-2}
if ! [[ "$build_jobs" =~ ^[1-9][0-9]*$ ]]; then
  echo "BUILD_JOBS must be a positive integer" >&2
  exit 1
fi
cmake_platform_args=()

if [[ "$(uname -s)" == Darwin ]]; then
  : "${MACOSX_DEPLOYMENT_TARGET:=12.0}"
  export MACOSX_DEPLOYMENT_TARGET
  cmake_platform_args+=(
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET"
    '-DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF'
    '-DGDAL_USE_ZSTD=OFF'
  )
fi

prefix_path="$proj_prefix"
if [[ -n "$dependency_prefix" ]]; then prefix_path="$proj_prefix;$dependency_prefix"; fi

proj_args=(
  -S "$PROJ_SOURCE_DIR"
  -B "$work_root/proj-build"
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="$proj_prefix"
  -DBUILD_SHARED_LIBS=OFF
  -DBUILD_TESTING=OFF
  -DBUILD_APPS=OFF
  -DENABLE_TIFF=OFF
  -DENABLE_CURL=OFF
  "${cmake_platform_args[@]}"
)
if [[ "$(uname -s)" == Darwin ]]; then
  macos_sdk=$(xcrun --sdk macosx --show-sdk-path)
  proj_args+=(
    "-DSQLite3_INCLUDE_DIR=$macos_sdk/usr/include"
    "-DSQLite3_LIBRARY=$macos_sdk/usr/lib/libsqlite3.tbd"
  )
fi
if [[ -n "$dependency_prefix" ]]; then proj_args+=("-DCMAKE_PREFIX_PATH=$dependency_prefix"); fi

cmake "${proj_args[@]}"
cmake --build "$work_root/proj-build" --config Release --parallel "$build_jobs"
cmake --install "$work_root/proj-build" --config Release

cmake -S "$GDAL_SOURCE_DIR" -B "$work_root/gdal-build" \
  -C "$repo_root/scripts/common.cmake" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$runtime_dir" \
  -DCMAKE_PREFIX_PATH="$prefix_path" \
  -DPROJ_DIR="$proj_prefix/lib/cmake/proj" \
  -DCMAKE_INSTALL_RPATH='${ORIGIN}/../lib;@loader_path/../lib' \
  -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
  "${cmake_platform_args[@]}"
cmake --build "$work_root/gdal-build" --config Release --parallel "$build_jobs"
cmake --install "$work_root/gdal-build" --config Release

# GDAL installs many utility binaries by default. Keep only the CLI surface
# used by the desktop application so unrelated tools cannot pull in absolute
# Homebrew/system dependencies during relocation.
for binary in "$runtime_dir"/bin/*; do
  [[ -f "$binary" ]] || continue
  case "$(basename "$binary")" in
    gdal|gdalinfo|gdal_translate|gdalbuildvrt) ;;
    *) rm -f "$binary" ;;
  esac
done

mkdir -p "$runtime_dir/share/proj" "$runtime_dir/licenses"
cp -R "$proj_prefix/share/proj/." "$runtime_dir/share/proj/"
cp "$GDAL_SOURCE_DIR/LICENSE.TXT" "$runtime_dir/licenses/GDAL.txt"
cp "$PROJ_SOURCE_DIR/COPYING" "$runtime_dir/licenses/PROJ.txt"

"$repo_root/scripts/runtime/collect-unix-libs.sh" "$runtime_dir" "$proj_prefix" "$dependency_prefix"
node "$repo_root/scripts/verify-gdal-runtime.js" "$runtime_dir"
