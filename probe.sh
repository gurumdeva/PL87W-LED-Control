#!/usr/bin/env bash
set -euo pipefail

swiftc Sources/Tools/HIDProbe.swift -o build/hid-probe -framework IOKit -framework CoreFoundation
build/hid-probe
