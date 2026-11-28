# Sourced by a harness that compiles app files on top of CraCore (not a harness itself: no `test-`).
#
# Builds CraCore once as a library, libCraCore.dylib and its module, with the harness's
# CRA_TEST_SWIFTC_FLAGS (coverage, a sanitizer), and keeps it under build/harness-cracore/, keyed
# on CraCore's sources, those flags and the compiler. The next harness, and the next run, link it
# instead of compiling CraCore's 370 files again: that was most of every such harness's time.
#
# After sourcing, "${CRACORE[@]}" goes on the harness's swiftc line in place of CraCore's sources.
# It links the library, adds Sources/Cra/App/CraCoreExports.swift (so app files see CraCore as they
# do in the app) and passes -j, so swiftc compiles on every core. With CRA_TEST_KEEP set, the
# library is kept next to the test binaries, for coverage.py's llvm-cov.

cracore_build() {
  local root jobs flags tag key cache dir tmp
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  jobs="${CRA_SWIFTC_JOBS:-$(sysctl -n hw.ncpu)}"
  flags="${CRA_TEST_SWIFTC_FLAGS:-}"
  local sources=("$root"/Packages/CraCore/Sources/CraCore/*.swift "$root"/Packages/CraCore/Sources/CraCore/Perf/*.swift)
  tag="$(printf '%s\n' "$flags" "$(xcrun swiftc --version 2>&1)" | shasum | cut -c1-12)"
  key="$({ printf '%s\n' "${sources[@]#"$root"/}"; cat "${sources[@]}"; } | shasum | cut -c1-12)"
  cache="$root/build/harness-cracore"
  dir="$cache/$tag-$key"
  if [ ! -f "$dir/libCraCore.dylib" ]; then
    mkdir -p "$cache"
    tmp="$(mktemp -d "$cache/.building.XXXXXX")"
    echo "Building CraCore for the harnesses (again only when it changes)" >&2
    # $flags unquoted on purpose: it is a list of swiftc flags, as on every harness's line.
    # shellcheck disable=SC2086
    if ! xcrun swiftc -swift-version 5 -parse-as-library $flags -j "$jobs" \
        -emit-library -emit-module -module-name CraCore -emit-module-path "$tmp/CraCore.swiftmodule" \
        -Xlinker -install_name -Xlinker @rpath/libCraCore.dylib \
        "${sources[@]}" -o "$tmp/libCraCore.dylib"; then
      rm -rf "$tmp"
      return 1
    fi
    # The older CraCore built with these flags; never this one, which a harness started alongside
    # may have put in place and be linking or running against right now.
    for old in "$cache/$tag"-*; do [ "$old" = "$dir" ] || rm -rf "$old"; done
    # Another harness got there first: keep its copy (mv onto a folder would move this one inside it).
    if [ -d "$dir" ]; then rm -rf "$tmp"; else mv "$tmp" "$dir" 2>/dev/null || rm -rf "$tmp"; fi
  fi
  CRACORE=(-j "$jobs" -I "$dir" -L "$dir" -lCraCore
           -Xlinker -rpath -Xlinker "$dir" -Xlinker -rpath -Xlinker @executable_path
           "$root/Sources/Cra/App/CraCoreExports.swift")
  [ -z "${CRA_TEST_KEEP:-}" ] || cp "$dir/libCraCore.dylib" "$CRA_TEST_KEEP/"
}

cracore_build
