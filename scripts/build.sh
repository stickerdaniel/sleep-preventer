#!/bin/bash
set -e

cd "$(dirname "$0")/.."

echo "Building sleep-preventer release..."
swift build -c release
echo "Built: .build/release/sleep-preventer"
