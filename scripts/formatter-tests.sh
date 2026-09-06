#!/bin/bash
# Compile Formatter.swift standalone with the fixture table and run it.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD=$(mktemp -d)
cp scripts/formatter-tests.swift "$BUILD/main.swift"   # swiftc wants top-level code in main.swift
swiftc -O Goji/Formatter.swift "$BUILD/main.swift" -o "$BUILD/formatter-tests"
"$BUILD/formatter-tests"
