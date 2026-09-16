#!/usr/bin/env bash
set -euo pipefail

runtime_dir=$(cd "$1" && pwd)
proj_prefix=$(cd "$2" && pwd)
dependency_prefix=${3:-}
mkdir -p "$runtime_dir/lib"

find "$proj_prefix/lib" -maxdepth 1 -type f \( -name '*.dylib' -o -name '*.so' -o -name '*.so.*' \) -exec cp -f {} "$runtime_dir/lib/" \; 2>/dev/null || true

processed=$(mktemp)
collect_files() { find "$runtime_dir/bin" "$runtime_dir/lib" -type f -print; }

if [[ "$(uname -s)" == Darwin ]]; then
  # Recursively copy non-system dependencies and rewrite them to @rpath.
  while true; do
    file=$(collect_files | while IFS= read -r candidate; do grep -Fxq "$candidate" "$processed" || { echo "$candidate"; break; }; done)
    [[ -n "$file" ]] || break
    echo "$file" >> "$processed"
    command file "$file" | grep -q 'Mach-O' || continue
    if [[ "$file" == *.dylib ]]; then install_name_tool -id "@rpath/$(basename "$file")" "$file"; fi
    while IFS= read -r dep; do
      case "$dep" in
        /usr/lib/*|/System/*|@rpath/*|@loader_path/*|@executable_path/*) ;;
        /*)
          name=$(basename "$dep")
          if [[ -f "$dep" && ! -f "$runtime_dir/lib/$name" ]]; then cp -f "$dep" "$runtime_dir/lib/"; fi
          if [[ -f "$runtime_dir/lib/$name" ]]; then install_name_tool -change "$dep" "@rpath/$name" "$file"; fi
          ;;
      esac
    done < <(otool -L "$file" | tail -n +2 | awk '{print $1}')
    # Homebrew and local SDK paths can also be embedded as LC_RPATH entries,
    # even when the linked library itself is otherwise static/relocatable.
    while IFS= read -r rpath; do
      case "$rpath" in
        /opt/homebrew/*|/usr/local/*|/Users/*|/private/var/*)
          install_name_tool -delete_rpath "$rpath" "$file" 2>/dev/null || true
          ;;
      esac
    done < <(otool -l "$file" | awk '/^[[:space:]]*path \/.* \(offset/ {print $2}')
    install_name_tool -add_rpath '@loader_path/../lib' "$file" 2>/dev/null || true
  done
  # Resolve @rpath references produced by CMake against known prefixes.
  while IFS= read -r file; do
    command file "$file" | grep -q 'Mach-O' || continue
    while IFS= read -r dep; do
      [[ "$dep" == @rpath/* ]] || continue
      name=$(basename "$dep")
      [[ -f "$runtime_dir/lib/$name" ]] && continue
      search_dirs=("$runtime_dir/lib" "$proj_prefix/lib")
      [[ -n "$dependency_prefix" ]] && search_dirs+=("$dependency_prefix/lib")
      candidate=$(find "${search_dirs[@]}" -maxdepth 1 -name "$name" -type f -print -quit 2>/dev/null || true)
      [[ -n "$candidate" ]] && cp -f "$candidate" "$runtime_dir/lib/$name"
    done < <(otool -L "$file" | tail -n +2 | awk '{print $1}')
  done < <(collect_files)
  while IFS= read -r file; do
    command file "$file" | grep -q 'Mach-O' || continue
    if otool -L "$file" | tail -n +2 | grep -E '/Users/|/opt/homebrew|/usr/local'; then
      echo "non-relocatable macOS dependency detected: $file" >&2
      otool -L "$file" >&2
      exit 1
    fi
  done < <(collect_files)
else
  command -v patchelf >/dev/null
  while true; do
    file=$(collect_files | while IFS= read -r candidate; do grep -Fxq "$candidate" "$processed" || { echo "$candidate"; break; }; done)
    [[ -n "$file" ]] || break
    echo "$file" >> "$processed"
    while IFS= read -r dep; do
      case "$(basename "$dep")" in
        libc.so.*|libm.so.*|libdl.so.*|librt.so.*|libpthread.so.*|ld-linux*.so.*) ;;
        *) [[ -f "$dep" ]] && { [[ -f "$runtime_dir/lib/$(basename "$dep")" ]] || cp -f "$dep" "$runtime_dir/lib/"; } ;;
      esac
    done < <(ldd "$file" 2>/dev/null | awk '/=> \// {print $3}')
    patchelf --set-rpath '$ORIGIN/../lib:$ORIGIN' "$file" 2>/dev/null || true
  done
  if find "$runtime_dir/bin" "$runtime_dir/lib" -type f -exec readelf -d {} \; 2>/dev/null | grep -E '/home/runner|/opt/hostedtoolcache' ; then
    echo 'non-relocatable Linux dependency detected' >&2; exit 1
  fi
fi
rm -f "$processed"
