#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

if ! find . -maxdepth 2 \( -name '*.xcodeproj' -o -name '*.xcworkspace' \) -print -quit | grep -q .; then
  echo "No Xcode project or workspace exists yet; documentation-only delivery verified."
  exit 0
fi

echo "An Xcode project exists. Configure this script with the discovered workspace/project, scheme, destination, build, and test commands."
exit 1
