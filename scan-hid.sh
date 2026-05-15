#!/usr/bin/env bash
set -euo pipefail

swiftc Sources/Tools/HIDScan.swift -o build/hid-scan -framework IOKit -framework CoreFoundation
build/hid-scan
