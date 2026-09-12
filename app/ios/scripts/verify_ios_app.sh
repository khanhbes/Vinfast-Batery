#!/usr/bin/env bash

set -euo pipefail

app_path="${1:-}"

if [[ -z "$app_path" || ! -d "$app_path" ]]; then
  echo "Usage: $0 /path/to/Runner.app" >&2
  exit 64
fi

plist_value() {
  local plist_path="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Print :${key}" "$plist_path" 2>/dev/null
}

verify_macho() {
  local binary_path="$1"
  local label="$2"

  if [[ ! -f "$binary_path" ]]; then
    echo "Missing executable for ${label}: ${binary_path}" >&2
    exit 1
  fi

  if ! /usr/bin/file "$binary_path" | /usr/bin/grep -q 'Mach-O'; then
    echo "Executable is not a Mach-O binary for ${label}: ${binary_path}" >&2
    /usr/bin/file "$binary_path" >&2
    exit 1
  fi

  if ! /usr/bin/lipo "$binary_path" -verify_arch arm64; then
    echo "Executable does not contain the arm64 device architecture: ${binary_path}" >&2
    /usr/bin/lipo -info "$binary_path" >&2 || true
    exit 1
  fi
}

app_plist="$app_path/Info.plist"
if [[ ! -f "$app_plist" ]]; then
  echo "The app bundle has no Info.plist: ${app_path}" >&2
  exit 1
fi

app_executable="$(plist_value "$app_plist" CFBundleExecutable || true)"
if [[ -z "$app_executable" ]]; then
  echo "CFBundleExecutable is missing from ${app_plist}" >&2
  exit 1
fi
verify_macho "$app_path/$app_executable" "application"

framework_count=0
while IFS= read -r -d '' framework_path; do
  framework_count=$((framework_count + 1))
  framework_name="$(/usr/bin/basename "$framework_path" .framework)"
  framework_plist="$framework_path/Info.plist"

  if [[ ! -f "$framework_plist" ]]; then
    framework_plist="$framework_path/Resources/Info.plist"
  fi
  if [[ ! -f "$framework_plist" ]]; then
    framework_plist="$framework_path/Versions/Current/Resources/Info.plist"
  fi
  if [[ ! -f "$framework_plist" ]]; then
    echo "Framework has no Info.plist: ${framework_path}" >&2
    exit 1
  fi

  framework_executable="$(plist_value "$framework_plist" CFBundleExecutable || true)"
  if [[ -z "$framework_executable" ]]; then
    echo "CFBundleExecutable is missing from ${framework_plist}" >&2
    exit 1
  fi
  if [[ "$framework_executable" != "$framework_name" ]]; then
    echo "Framework executable name mismatch: ${framework_path}" >&2
    echo "Expected '${framework_name}', found '${framework_executable}'." >&2
    exit 1
  fi

  framework_binary="$framework_path/$framework_executable"
  if [[ ! -f "$framework_binary" ]]; then
    framework_binary="$framework_path/Versions/Current/$framework_executable"
  fi
  verify_macho "$framework_binary" "framework ${framework_name}"
done < <(/usr/bin/find "$app_path/Frameworks" -type d -name '*.framework' -print0 2>/dev/null || true)

while IFS= read -r -d '' dylib_path; do
  verify_macho "$dylib_path" "dynamic library $(/usr/bin/basename "$dylib_path")"
done < <(/usr/bin/find "$app_path/Frameworks" -type f -name '*.dylib' -print0 2>/dev/null || true)

echo "Verified ${app_executable} and ${framework_count} embedded frameworks for arm64."
