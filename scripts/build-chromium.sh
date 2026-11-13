#!/bin/bash
# build-chromium.sh [sync|apply|gen|build|all]: Cra's engine, Chrome's own framework with Cra's layer
# (docs/chromium-engine.md), from a Chrome stable tag.
#
#   sync   the tag at depth 1 with its Mac deps and Chrome's PGO profiles, then hooks (~40 min, ~30 GB)
#   apply  Cra's layer and hooks (engine/chromium/apply.sh)
#   gen    out/Cra_<arch>/args.gn: official build, ThinLTO + PGO, H.264/AAC (proprietary_codecs)
#   build  the app (Chromium.app with the framework and its helpers)
#
# CHROMIUM_TAG (default below), CRA_ARCH (arm64 or x64; default arm64), CHROMIUM_ROOT (default
# ~/chromium.noindex: .noindex keeps Spotlight out). Needs ~45 GB for one CPU. Never edit this file
# while it runs (bash reads it as it goes).
set -euo pipefail
CHROMIUM_TAG="${CHROMIUM_TAG:-157.0.8103.81}"
ARCH="${CRA_ARCH:-arm64}"
ROOT="${CHROMIUM_ROOT:-$HOME/chromium.noindex}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEPOT="${DEPOT_TOOLS:-$HOME/cef-build.noindex/depot_tools}"
export PATH="$DEPOT:$PATH" DEPOT_TOOLS_UPDATE=0
OUT="out/Cra_$ARCH"

sync() {
  mkdir -p "$ROOT"
  cat > "$ROOT/.gclient" <<EOF
solutions = [{
  "name": "src",
  "url": "https://chromium.googlesource.com/chromium/src.git@refs/tags/$CHROMIUM_TAG",
  "managed": False,
  "custom_deps": {},
  "custom_vars": {"checkout_pgo_profiles": True},
}]
target_os = ["mac"]
EOF
  (cd "$ROOT" && gclient sync --no-history --nohooks --with_tags -r "src@refs/tags/$CHROMIUM_TAG")
  (cd "$ROOT" && gclient runhooks)
  echo "$CHROMIUM_TAG" > "$ROOT/.cra-tag"
}

apply() {
  "$REPO/engine/chromium/apply.sh" "$ROOT/src"
}

gen() {
  mkdir -p "$ROOT/src/$OUT"
  cat > "$ROOT/src/$OUT/args.gn" <<EOF
# Written by Cra's scripts/build-chromium.sh.
target_cpu = "$ARCH"
is_official_build = true
is_debug = false
is_component_build = false
symbol_level = 0
blink_symbol_level = 0
v8_symbol_level = 0
enable_dsyms = false
proprietary_codecs = true
ffmpeg_branding = "Chrome"
enable_widevine = true
enable_background_mode = false
disable_fieldtrial_testing_config = true
clang_use_chrome_plugins = false
EOF
  (cd "$ROOT/src" && gn gen "$OUT")
}

build() {
  (cd "$ROOT/src" && nice -n 15 autoninja -C "$OUT" chrome)
}

case "${1:-all}" in
  sync) sync ;;
  apply) apply ;;
  gen) gen ;;
  build) build ;;
  all) sync; apply; gen; build ;;
  *) echo "usage: $0 [sync|apply|gen|build|all]" >&2; exit 2 ;;
esac
