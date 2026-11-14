#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

# Tests use isolated temporary recording folders, never the live recording library.
swift test --scratch-path .build-verification
swift run --scratch-path .build-verification TelomiAcceptanceRunner
xcodebuild -project Telomi.xcodeproj -scheme Telomi \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .build-mac-verification CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Telomi.xcodeproj -scheme Telomi \
  -configuration Debug -sdk iphonesimulator \
  -derivedDataPath .build-iphone-verification CODE_SIGNING_ALLOWED=NO build

print '构建及核心测试通过。产物位于 .build-mac-verification / .build-iphone-verification。'
print '锁屏、来电和蓝牙中断仍需 iPhone 真机验收；本脚本不运行云端接口。'
