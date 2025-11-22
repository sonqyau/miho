#!/usr/bin/env bash
set -euo pipefail
umask 077

log(){ printf '%s\n' "$1"; }
die(){ printf 'ERR:%s\n' "$1" >&2; exit 1; }

root="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd -P)"
src="${root}/../source"
dst="${root}/../build"
stub="${root}/capi.go"
[ -d "$src" ] || die "source absent"
[ -r "$stub" ] || die "stub unreadable"
command -v go >/dev/null 2>&1 || die "Go toolchain missing"
mkdir -p "$dst"

arch_in="${1:-$(uname -m)}"
case "$arch_in" in
  arm64|aarch64) sets=(arm64) ;;
  x86_64|amd64)  sets=(amd64) ;;
  dual|all)      sets=(arm64 amd64) ;;
  *)             die "unsupported arch" ;;
esac

trap 'rm -f -- "$src/.capi.go"' EXIT INT TERM
cp "$stub" "$src/.capi.go"

build(){
  local a="$1"
  local out="${dst}/libmihomo_${a}.dylib"
  log "compile:${a}"
  ( cd "$src" && GOOS=darwin GOARCH="$a" CGO_ENABLED=1 GO111MODULE=on go build -trimpath -buildmode=c-shared -o "$out" ./.capi.go )
  ln -sf "libmihomo_${a}.dylib" "${dst}/libmihomo.dylib"
  local hdr="${dst}/libmihomo_${a}.h"
  [ -f "$hdr" ] || die "header missing:${a}"
  install -m 0644 "$hdr" "${dst}/libmihomo.h"
  log "ready:${a}"
}

for a in "${sets[@]}"; do
  build "$a"
done
