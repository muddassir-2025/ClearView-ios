#!/usr/bin/env bash
# Xcode 16.4 ships an iOS 18.5 simulator runtime that cannot load
# /usr/lib/swift/libswiftWebKit.dylib. Apps built with a deployment target of
# iOS 18.3 or older that call one of WebKit's NS_REFINED_FOR_SWIFT APIs (for
# example WKWebView.callAsyncJavaScript) crash on launch with:
#
#   dyld: Library not loaded: /usr/lib/swift/libswiftWebKit.dylib
#
# WebKit documents a fallback: the runtime keeps a copy of the overlay in its
# cryptex. dyld already searches the build products directory before the
# runtime, so linking the overlay there lets the app launch on the affected
# runtime without changing the app's deployment target.
#
# See https://bugs.webkit.org/show_bug.cgi?id=293831
#
# Usage: simulator-webkit-shim.sh <simulator-udid> <derived-data-path>
set -euo pipefail

device_id="${1:?usage: simulator-webkit-shim.sh <simulator-udid> <derived-data-path>}"
derived_data="${2:?usage: simulator-webkit-shim.sh <simulator-udid> <derived-data-path>}"
products_dir="$derived_data/Build/Products/Debug-iphonesimulator"

runtime_id=$(xcrun simctl list devices -j | DEVICE_ID="$device_id" python3 -c '
import json, os, sys

device_id = os.environ["DEVICE_ID"]
for runtime_id, devices in json.load(sys.stdin)["devices"].items():
    if any(device["udid"] == device_id for device in devices):
        print(runtime_id)
        break
else:
    sys.exit(f"Simulator {device_id} is not registered with simctl")
')

runtime_root=$(xcrun simctl list runtimes -j | RUNTIME_ID="$runtime_id" python3 -c '
import json, os, sys

runtime_id = os.environ["RUNTIME_ID"]
for runtime in json.load(sys.stdin)["runtimes"]:
    if runtime["identifier"] == runtime_id:
        print(runtime["runtimeRoot"])
        break
else:
    sys.exit(f"Simulator runtime {runtime_id} is not installed")
')

installed="$runtime_root/usr/lib/swift/libswiftWebKit.dylib"
fallback="$runtime_root/System/Cryptexes/OS/usr/lib/swift/libswiftWebKit.dylib"

if [ -e "$installed" ]; then
  echo "libswiftWebKit.dylib is available in $runtime_id; no shim needed."
  exit 0
fi

if [ ! -e "$fallback" ]; then
  echo "::warning::libswiftWebKit.dylib is missing from both the simulator runtime and its cryptex; leaving the build products untouched."
  exit 0
fi

mkdir -p "$products_dir"
ln -sfn "$fallback" "$products_dir/libswiftWebKit.dylib"
echo "Using the $runtime_id cryptex copy of libswiftWebKit.dylib for simulator launches."
