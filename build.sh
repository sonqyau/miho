#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

MODE="spm"              # spm|xcode
PROFILE="release"       # debug|release
BUNDLE=false
SIGNER=""
EXT=false
KERNEL_FORCE=false
GEO_FORCE=false
CLEAN=false

PROJECT="miho.xcodeproj"
SCHEME="miho"
APP="miho"
DAEMON="ProxyDaemon"
APP_ID="com.swift.miho"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd -P)"
SPM_DIR=".build/release"
XCODE_DIR="build"
CORE_DIR="${ROOT}/miho/Resources/Kernel"
KERNEL_REPO="https://github.com/MetaCubeX/mihomo.git"
KERNEL_BRANCH="Alpha"
KERNEL_SRC_DIR="${CORE_DIR}/source"
CONFIG_URL="https://raw.githubusercontent.com/MetaCubeX/mihomo/refs/heads/Meta/docs/config.yaml"
CONFIG_PATH="${ROOT}/miho/Resources/config.yaml"

log(){ printf '%s\n' "$*"; }
err(){ printf 'ERR:%s\n' "$*" >&2; }
die(){ err "$*"; exit 1; }

TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/miho.XXXX")"
trap 'rm -rf -- "${TMPDIR}"' EXIT

fetch(){ local url="$1"; local out="$2";
    curl -fsS --retry 5 --retry-delay 2 --connect-timeout 10 -L "$url" -o "$out" || return 22;
}

arch(){
    case "$(uname -m)" in
        arm64|aarch64) printf 'arm64' ;;
        x86_64)        printf 'amd64' ;;
        *) die "Unsupported architecture: $(uname -m)" ;;
    esac
}

release(){
    local tag="Prerelease-Alpha"
    local tmp="${TMPDIR}/release.json"
    fetch "https://api.github.com/repos/MetaCubeX/mihomo/releases/tags/${tag}" "$tmp"
    printf '%s' "$tmp"
}

asset(){
    local jsonfile="$1"; local arch="$2"
    if command -v jq >/dev/null 2>&1; then
        jq -r --arg arch "$arch" '.assets[] | .browser_download_url | select(test("mihomo-darwin-"+$arch+"-alpha-.*\\.gz$"))' "$jsonfile" | head -n1
    else
        grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+"' "$jsonfile" \
            | sed -E 's/.*"([^"]+)".*/\1/' \
            | grep "mihomo-darwin-${arch}-alpha-.*\\.gz$" || true
    fi
}

checks(){
    local jsonfile="$1"
    if command -v jq >/dev/null 2>&1; then
        jq -r '.assets[] | .browser_download_url | select(test("checksums.txt$"))' "$jsonfile" | head -n1
    else
        grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+"' "$jsonfile" \
            | sed -E 's/.*"([^"]+)".*/\1/' \
            | grep "checksums.txt$" || true
    fi
}

digest(){
    local f="$1"
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$f" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$f" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$f" | awk '{print $2}'
    else
        return 1
    fi
}

kernel(){
    mkdir -p "$CORE_DIR"
    local arch; arch="$(arch)"
    local release_json; release_json="$(release)"
    local asset_url; asset_url="$(asset "$release_json" "$arch")"
    [ -n "$asset_url" ] || die "no kernel asset found for darwin-$arch"

    local tmp_asset="${TMPDIR}/binary.gz"
    log "Acquiring kernel artifact ${asset_url##*/}"
    fetch "$asset_url" "$tmp_asset" || die "Kernel download failure"

    local checksums_url; checksums_url="(checks "$release_json" || true)"
    if [ -n "$checksums_url" ]; then
        local tmp_checks="${TMPDIR}/checksums.txt"
        if fetch "$checksums_url" "$tmp_checks"; then
            local asset_name asset_expected
            asset_name="$(basename "$asset_url")"
            asset_expected="$(awk -v a="$asset_name" '$0~a{print $1; exit}' "$tmp_checks" || true)"
            if [ -n "$asset_expected" ]; then
                local actual; actual="$(digest "$tmp_asset" || true)"
                if [ -z "$actual" ]; then
                    log "SHA256 utility unavailable; skipping verification"
                elif [ "$actual" != "$asset_expected" ]; then
                    die "Checksum mismatch expected=${asset_expected} actual=${actual}"
                fi
            fi
        fi
    fi

    local tmp_bin="${TMPDIR}/miho.bin"
    if ! gunzip -c "$tmp_asset" > "$tmp_bin"; then
        die "Kernel extraction failure"
    fi
    chmod +x "$tmp_bin"
    mv -f "$tmp_bin" "${CORE_DIR}/binary"
    log "Kernel staged at ${CORE_DIR}/binary"
}

source(){
    mkdir -p "$CORE_DIR"
    if ! command -v git >/dev/null 2>&1; then
        die "Git unavailable for kernel source retrieval"
    fi

    if [ -d "$KERNEL_SRC_DIR/.git" ] && [ "$KERNEL_FORCE" = true ]; then
        rm -rf -- "$KERNEL_SRC_DIR"
    fi

    if [ -d "$KERNEL_SRC_DIR/.git" ]; then
        log "Syncing kernel source ${KERNEL_BRANCH}"
        git -C "$KERNEL_SRC_DIR" fetch --depth 1 origin "$KERNEL_BRANCH" >/dev/null 2>&1 || die "Kernel source fetch failure"
        git -C "$KERNEL_SRC_DIR" checkout -q "$KERNEL_BRANCH" >/dev/null 2>&1 || die "Kernel branch switch failure"
        git -C "$KERNEL_SRC_DIR" reset --hard "origin/${KERNEL_BRANCH}" >/dev/null 2>&1 || die "Kernel source reset failure"
        git -C "$KERNEL_SRC_DIR" clean -fdx >/dev/null 2>&1 || true
    else
        log "Cloning kernel source ${KERNEL_BRANCH}"
        git clone --depth 1 --branch "$KERNEL_BRANCH" --single-branch "$KERNEL_REPO" "$KERNEL_SRC_DIR" >/dev/null 2>&1 || die "Kernel source clone failure"
    fi
}

config(){
    mkdir -p "$(dirname "$CONFIG_PATH")"
    local tmp="${TMPDIR}/config.yaml"
    fetch "$CONFIG_URL" "$tmp" || die "Reference configuration download failure"
    mv -f "$tmp" "$CONFIG_PATH"
    log "Reference configuration staged at $CONFIG_PATH"
}

geo(){
    local RES="${ROOT}/miho/Resources"
    mkdir -p "$RES"
    if [ ! -f "$RES/Country.mmdb.lzfse" ] || [ "$GEO_FORCE" = true ]; then
        local src="https://github.com/MetaCubeX/meta-rules-dat/raw/release/country.mmdb"
        local tmp_mmdb="${TMPDIR}/country.mmdb"
        fetch "$src" "$tmp_mmdb" || die "Country dataset download failure"
        if command -v lzfse >/dev/null 2>&1; then
            lzfse -encode -i "$tmp_mmdb" -o "${TMPDIR}/country.lzfse" || die "LZFSE compression failure"
            mv -f "${TMPDIR}/country.lzfse" "$RES/Country.mmdb.lzfse"
        else
            mv -f "$tmp_mmdb" "$RES/Country.mmdb"
            log "LZFSE encoder unavailable; stored raw Country.mmdb"
        fi
        log "Country dataset staged at ${RES}"
    fi
    if [ ! -f "$RES/geosite.dat.lzfse" ] && [ "$GEO_FORCE" = true ]; then
        local src2="https://github.com/MetaCubeX/meta-rules-dat/raw/release/geosite.dat"
        local tmp2="${TMPDIR}/geosite.dat"
        if fetch "$src2" "$tmp2"; then
            if command -v lzfse >/dev/null 2>&1; then
                lzfse -encode -i "$tmp2" -o "${TMPDIR}/geosite.lzfse" && mv -f "${TMPDIR}/geosite.lzfse" "$RES/geosite.dat.lzfse"
            else
                mv -f "$tmp2" "$RES/geosite.dat"
                log "LZFSE encoder unavailable; stored raw geosite.dat"
            fi
            log "Geosite dataset staged at ${RES}"
        else
            log "Optional geosite dataset unavailable"
        fi
    fi
}

prepare(){
    if [ ! -f "${CORE_DIR}/binary" ] || [ "$KERNEL_FORCE" = true ]; then
        kernel
    fi
    source
    if [ ! -f "$CONFIG_PATH" ]; then
        config
    fi
    local RES="${ROOT}/miho/Resources"
    if [ "$GEO_FORCE" = true ] || [ ! -f "$RES/Country.mmdb.lzfse" ] && [ ! -f "$RES/Country.mmdb" ]; then
        geo
    fi
}

spm(){
    swift build -c "$PROFILE"
    log "SwiftPM build complete"
}

xcode(){
    local cfg="Release"
    [ "$PROFILE" = "debug" ] && cfg="Debug"
    [ "$CLEAN" = true ] && (rm -rf "$XCODE_DIR" || true) && xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$cfg" clean >/dev/null 2>&1 || true
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$cfg" -derivedDataPath "$XCODE_DIR" build >/dev/null 2>&1
    log "Xcode build complete"
}

pack(){
    local bundle="${SPM_DIR}/${APP}.app"
    rm -rf -- "$bundle"
    mkdir -p "${bundle}/Contents/MacOS" "${bundle}/Contents/Helpers" "${bundle}/Contents/Resources" "${bundle}/Contents/Library/LaunchDaemon"
    cp -a -- "${SPM_DIR}/${APP}" "${bundle}/Contents/MacOS/" 2>/dev/null || die "Primary binary missing: ${SPM_DIR}/${APP}"
    [ -f "${SPM_DIR}/${DAEMON}" ] && cp -a -- "${SPM_DIR}/${DAEMON}" "${bundle}/Contents/Helpers/" || true
    cp -a -- "${CORE_DIR}/binary" "${bundle}/Contents/Resources/" || true
    if [ -f "miho/Supporting Files/Info.plist" ]; then
        cp -a -- "miho/Supporting Files/Info.plist" "${bundle}/Contents/Info.plist"
    else
        die "Info.plist missing"
    fi
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${APP}" "${bundle}/Contents/Info.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${APP_ID}" "${bundle}/Contents/Info.plist" 2>/dev/null || true
    log "Bundle staged at ${bundle}"
}

sign(){
    [ -n "$SIGNER" ] || die "Signing identity undefined"
    local bundle="${SPM_DIR}/${APP}.app"

    if [ -f "${bundle}/Contents/Helpers/${DAEMON}" ]; then
        codesign --force --sign "$SIGNER" --entitlements "miho/Sources/Daemons/ProxyDaemon/ProxyDaemon.entitlements" --options runtime --timestamp "${bundle}/Contents/Helpers/${DAEMON}" || die "Helper codesign failure"
    fi
    codesign --force --sign "$SIGNER" --entitlements "miho/miho.entitlements" --options runtime --timestamp --deep "$bundle" || die "Bundle codesign failure"
    codesign --verify --deep --strict "$bundle" || die "Codesign verification failure"
    log "Bundle signed ${bundle}"
}

summary(){
    printf '\n'
    printf 'mode=%s config=%s bundle=%s extension=%s clean=%s signer=%s\n' "$MODE" "$PROFILE" "$BUNDLE" "$EXT" "$CLEAN" "[[${SIGNER:-}]]"
    if [ "$MODE" = "spm" ] && [ "$BUNDLE" = true ]; then
        local path="${SPM_DIR}/${APP}.app"
        [ -d "$path" ] && du -sh "$path" | awk '{print "bundle_size=" $1}'
    fi
    printf '\n'
}

while [ ${#:-0} -gt 0 ]; do
    case "${1:-}" in
        --mode) MODE="${2:-}"; shift 2 ;;
        --config) PROFILE="${2:-}"; shift 2 ;;
        --bundle) BUNDLE=true; shift ;;
        --sign) SIGNER="${2:-}"; shift 2 ;;
        --network-extension) EXT=true; shift ;;
        --download-kernel) KERNEL_FORCE=true; shift ;;
        --download-geo) GEO_FORCE=true; shift ;;
        --clean) CLEAN=true; shift ;;
        --help) printf 'Usage: %s [--mode spm|xcode] [--config debug|release] [--bundle] [--sign "IDENT"]\n' "$0"; exit 0 ;;
        *) die "Unknown option: ${1:-}" ;;
    esac
done

log "mode=${MODE} config=${PROFILE} bundle=${BUNDLE} extension=${EXT} clean=${CLEAN}"

prepare

if [ "$MODE" = "spm" ]; then
    spm
    if [ "$BUNDLE" = true ]; then
        pack
        [ -n "$SIGNER" ] && sign
    fi
else
    xcode
fi

summary
exit 0
