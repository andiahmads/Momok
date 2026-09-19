#!/bin/bash

set -euo pipefail

REPOSITORY="andiahmads/Momok"
APP_PATH="/Applications/Momok.app"
ARCHIVE_NAME="Momok-macOS-universal.zip"
EXPECTED_BUNDLE_ID="com.andiahmads.momok"
LOCAL_APP=""
LOCAL_REPOSITORY_ROOT=""
TEMP_DIR=""
STAGED_APP=""
PREVIOUS_APP=""
RESTORE_PREVIOUS=0
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

say() {
  printf '\n%s\n' "$1"
}

fail() {
  printf '\nMomok belum dapat di-install.\n%s\n' "$1" >&2
  exit 1
}

cleanup() {
  if [ "$RESTORE_PREVIOUS" -eq 1 ] && [ -n "$PREVIOUS_APP" ] && [ -e "$PREVIOUS_APP" ]; then
    rm -rf -- "$APP_PATH/Contents"
    ditto "$PREVIOUS_APP" "$APP_PATH" || true
    RESTORE_PREVIOUS=0
  fi

  if [ -n "$STAGED_APP" ] && [ -e "$STAGED_APP" ]; then
    rm -rf -- "$STAGED_APP"
  fi

  if [ -n "$PREVIOUS_APP" ] && [ -e "$PREVIOUS_APP" ]; then
    rm -rf -- "$PREVIOUS_APP"
  fi

  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf -- "$TEMP_DIR"
  fi
}

remove_legacy_copies() {
  local legacy_app

  for legacy_app in \
    "/Applications/Momok.app.backup-"* \
    "$HOME/.Trash/Momok-previous-"*.app
  do
    [ -e "$legacy_app" ] || continue
    "$LSREGISTER" -u "$legacy_app" >/dev/null 2>&1 || true
    rm -rf -- "$legacy_app"
  done
}

remove_local_build_copies() {
  local built_app

  [ -n "$LOCAL_REPOSITORY_ROOT" ] || return
  for built_app in \
    "$LOCAL_REPOSITORY_ROOT/zig-out/Ghostty.app" \
    "$LOCAL_REPOSITORY_ROOT/zig-out/Momok.app"
  do
    [ -e "$built_app" ] || continue
    "$LSREGISTER" -u "$built_app" >/dev/null 2>&1 || true
    rm -rf -- "$built_app"
  done
}

trap cleanup EXIT INT TERM

if [ "$(uname -s)" != "Darwin" ]; then
  fail "Installer ini hanya untuk macOS."
fi

if [ "${1:-}" = "--app" ]; then
  [ "$#" -eq 2 ] || fail "Gunakan: install.sh --app /path/to/Momok.app"
  [ -d "$2" ] || fail "Bundle hasil build tidak ditemukan: $2"
  LOCAL_APP="$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")"
  [ "$LOCAL_APP" != "$APP_PATH" ] || fail "Bundle sumber harus berbeda dari $APP_PATH."
  BUILT_APP="$LOCAL_APP"
elif [ "$#" -eq 0 ]; then
  say "Memeriksa build Momok terbaru yang berhasil dirilis..."
  # Resolve latest once so the archive and checksum cannot come from different
  # releases when a new build is published during the download.
  RELEASE_URL="$(curl -fsSLI --retry 3 -o /dev/null -w '%{url_effective}' "https://github.com/$REPOSITORY/releases/latest")" \
    || fail "Tidak dapat memeriksa release terbaru. Cek koneksi internet."
  case "$RELEASE_URL" in
    "https://github.com/$REPOSITORY/releases/tag/"*) ;;
    *) fail "Alamat release tidak valid: $RELEASE_URL" ;;
  esac
  RELEASE_TAG="${RELEASE_URL##*/}"
  DOWNLOAD_URL="https://github.com/$REPOSITORY/releases/download/$RELEASE_TAG/$ARCHIVE_NAME"
  say "Mengunduh Momok $RELEASE_TAG..."
  TEMP_DIR="$(mktemp -d /tmp/momok-installer.XXXXXX)"

  if ! curl -fL --retry 3 --progress-bar "$DOWNLOAD_URL" -o "$TEMP_DIR/$ARCHIVE_NAME"; then
    fail "Release Momok belum tersedia atau koneksi internet bermasalah. Coba lagi beberapa saat."
  fi

  curl -fsSL --retry 3 "$DOWNLOAD_URL.sha256" -o "$TEMP_DIR/$ARCHIVE_NAME.sha256" \
    || fail "Checksum release tidak tersedia. Aplikasi lama tidak diubah."
  EXPECTED_CHECKSUM="$(awk 'NR == 1 {print $1}' "$TEMP_DIR/$ARCHIVE_NAME.sha256")"
  [[ "$EXPECTED_CHECKSUM" =~ ^[[:xdigit:]]{64}$ ]] || fail "Format checksum release tidak valid."
  ACTUAL_CHECKSUM="$(shasum -a 256 "$TEMP_DIR/$ARCHIVE_NAME" | awk '{print $1}')"
  [ "$ACTUAL_CHECKSUM" = "$EXPECTED_CHECKSUM" ] || fail "Checksum download tidak cocok. Aplikasi lama tidak diubah."

  ditto -x -k "$TEMP_DIR/$ARCHIVE_NAME" "$TEMP_DIR/unpacked"
  BUILT_APP="$TEMP_DIR/unpacked/Momok.app"
  [ -d "$BUILT_APP" ] || fail "File download tidak berisi Momok.app yang valid."
else
  fail "Argumen tidak dikenal. Gunakan tanpa argumen atau --app /path/to/Momok.app."
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BUILT_APP/Contents/Info.plist" 2>/dev/null || true)"
[ "$BUNDLE_ID" = "$EXPECTED_BUNDLE_ID" ] || fail "Bundle ID tidak valid: ${BUNDLE_ID:-tidak ditemukan}."
[ -x "$BUILT_APP/Contents/MacOS/ghostty" ] || fail "Executable Momok tidak ditemukan."
if [ -z "$LOCAL_APP" ]; then
  codesign --verify --deep --strict "$BUILT_APP" || fail "Signature aplikasi hasil download tidak valid."
fi
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILT_APP/Contents/Info.plist" 2>/dev/null || true)"
APP_COMMIT="$(/usr/libexec/PlistBuddy -c 'Print :GhosttyCommit' "$BUILT_APP/Contents/Info.plist" 2>/dev/null || true)"

if [ -n "$LOCAL_APP" ]; then
  BUILD_ROOT="$(dirname "$(dirname "$LOCAL_APP")")"
  if [ "$(basename "$BUILD_ROOT")" = "build" ] && \
    [ "$(basename "$(dirname "$BUILD_ROOT")")" = "macos" ]
  then
    LOCAL_REPOSITORY_ROOT="$(dirname "$(dirname "$BUILD_ROOT")")"
    touch "$BUILD_ROOT/.metadata_never_index"
  fi
fi

say "Memasang Momok ke folder Applications..."
STAGED_APP="/Applications/.Momok.installing.$$.app"
PREVIOUS_APP="/Applications/.Momok.previous.$$.app"

rm -rf -- "$STAGED_APP" "$PREVIOUS_APP"
ditto "$BUILT_APP" "$STAGED_APP"

osascript -e 'tell application id "com.andiahmads.momok" to quit' >/dev/null 2>&1 &
MOMOK_QUIT_PID=$!
for _ in 1 2 3 4 5; do
  kill -0 "$MOMOK_QUIT_PID" 2>/dev/null || break
  sleep 0.2
done
kill "$MOMOK_QUIT_PID" 2>/dev/null || true
wait "$MOMOK_QUIT_PID" 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -f "$APP_PATH/Contents/MacOS/ghostty" >/dev/null 2>&1 || break
  sleep 0.2
done
pkill -f "$APP_PATH/Contents/MacOS/ghostty" 2>/dev/null || true

if [ -n "$LOCAL_APP" ]; then
  pkill -f "$LOCAL_APP/Contents/MacOS/ghostty" 2>/dev/null || true
fi

if [ -e "$APP_PATH" ]; then
  [ ! -L "$APP_PATH" ] || fail "$APP_PATH berupa symlink; hapus secara manual sebelum melanjutkan."
  ditto "$APP_PATH" "$PREVIOUS_APP"
  RESTORE_PREVIOUS=1
  rm -rf -- "$APP_PATH/Contents"
  if ! ditto "$STAGED_APP" "$APP_PATH"; then
    fail "Gagal mengganti aplikasi di $APP_PATH. Versi sebelumnya akan dipulihkan."
  fi
  RESTORE_PREVIOUS=0
else
  if ! mv "$STAGED_APP" "$APP_PATH"; then
    fail "Gagal memasang aplikasi di $APP_PATH."
  fi
  STAGED_APP=""
fi

if [ -e "$PREVIOUS_APP" ]; then
  touch -r "$PREVIOUS_APP" "$APP_PATH"
  rm -rf -- "$PREVIOUS_APP"
fi
PREVIOUS_APP=""

if [ -e "$STAGED_APP" ]; then
  rm -rf -- "$STAGED_APP"
fi
STAGED_APP=""

remove_legacy_copies
remove_local_build_copies
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true
if [ -n "$LOCAL_APP" ]; then
  "$LSREGISTER" -u "$LOCAL_APP" >/dev/null 2>&1 || true
  rm -rf -- "$LOCAL_APP"
fi
"$LSREGISTER" -f "$APP_PATH" >/dev/null 2>&1 || true
open "$APP_PATH"

say "Momok berhasil di-install dan sudah dibuka."
printf '%s\n' "Aplikasi: $APP_PATH"
printf '%s\n' "Versi: ${APP_VERSION:-tidak diketahui} | Commit: ${APP_COMMIT:-tidak diketahui}"
printf '%s\n' "Untuk update, jalankan kembali perintah installer yang sama."
