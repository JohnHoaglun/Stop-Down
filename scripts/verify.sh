#!/usr/bin/env bash
#
# verify.sh — canonical verification entry point for Stop-Down.
#
# Discovers the Xcode project/workspace, a shared scheme, and a concrete
# iOS-simulator destination, then builds for the simulator and runs the unit
# test target. Exits non-zero on any failure so it can gate commits and CI.
#
# Usage:
#   scripts/verify.sh          # build + unit tests
#   scripts/verify.sh build    # build only
#   scripts/verify.sh test     # unit tests only (builds as a dependency)
#
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

mode="${1:-all}"
case "${mode}" in
  build|test|all) ;;
  *)
    echo "usage: $(basename "$0") [build|test|all]" >&2
    exit 2
    ;;
esac

# --- Discover the Xcode project or workspace (no guessing) ---
xcode_target="$(find . -maxdepth 2 \( -name '*.xcodeproj' -o -name '*.xcworkspace' \) -print -quit)"
if [[ -z "${xcode_target}" ]]; then
  echo "No Xcode project or workspace exists yet; documentation-only delivery verified."
  exit 0
fi
xcode_target="${xcode_target#./}"

case "${xcode_target}" in
  *.xcworkspace) spec_flag=(-workspace "${xcode_target}") ;;
  *.xcodeproj)   spec_flag=(-project "${xcode_target}") ;;
  *)
    echo "ERROR: unrecognized Xcode container: ${xcode_target}" >&2
    exit 1
    ;;
esac

# --- Discover a shared scheme ---
scheme="$(
  xcodebuild -list "${spec_flag[@]}" 2>/dev/null | awk '
    /Schemes:/        { flag = 1; next }
    flag && /^[[:space:]]+[^[:space:]]/ { sub(/^[[:space:]]+/, ""); print }
    flag && /^[^[:space:]]/            { flag = 0 }
  ' | sed -n '1p'
)"
if [[ -z "${scheme}" ]]; then
  echo "ERROR: could not discover a shared scheme via 'xcodebuild -list'." >&2
  exit 1
fi

# --- Discover a concrete iOS-simulator destination (prefer an iPhone) ---
sim_lines="$(xcodebuild -showdestinations "${spec_flag[@]}" -scheme "${scheme}" 2>/dev/null \
  | grep -E 'platform:iOS Simulator' \
  | grep -v 'placeholder' \
  | grep -v 'error:')"
if [[ -z "${sim_lines}" ]]; then
  echo "ERROR: no usable iOS Simulator destination found." >&2
  echo "       Install an iOS Simulator runtime matching the deployment target." >&2
  exit 1
fi
pick="$(printf '%s\n' "${sim_lines}" | grep -E 'name:iPhone' | head -1)"
[[ -z "${pick}" ]] && pick="$(printf '%s\n' "${sim_lines}" | head -1)"
sim_id="$(printf '%s' "${pick}" | sed -E 's/.*id:([0-9A-Fa-f-]+).*/\1/')"
sim_name="$(printf '%s' "${pick}" | sed -E 's/.*name:([^}]+)}/\1/')"
destination="platform=iOS Simulator,id=${sim_id}"

echo "project : ${xcode_target}"
echo "scheme  : ${scheme}"
echo "sim     : ${sim_name} (${sim_id})"
echo

if [[ "${mode}" == "build" || "${mode}" == "all" ]]; then
  echo "==> Building for ${sim_name}"
  xcodebuild build "${spec_flag[@]}" \
    -scheme "${scheme}" \
    -configuration Debug \
    -destination "${destination}" \
    -quiet
  echo
fi

if [[ "${mode}" == "test" || "${mode}" == "all" ]]; then
  echo "==> Running unit tests on ${sim_name}"
  xcodebuild test "${spec_flag[@]}" \
    -scheme "${scheme}" \
    -configuration Debug \
    -destination "${destination}" \
    -only-testing:Stop-DownTests \
    -quiet
  echo
fi

echo "verify: OK"
