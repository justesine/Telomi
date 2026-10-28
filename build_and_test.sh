#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"
mkdir -p .build-tools .build-out
touch .build-tools/empty.modulemap

cat << 'EOF' > .build-tools/clt_fix_vfs.yaml
{
  "version": 0,
  "case-sensitive": "false",
  "roots": [
    {
      "name": "/Library/Developer/CommandLineTools/usr/include/swift",
      "type": "directory",
      "contents": [
        {
          "name": "bridging.modulemap",
          "type": "file",
          "external-contents": "/Users/esine/Developer/MemoFlow/.build-tools/empty.modulemap"
        }
      ]
    }
  ]
}
EOF

echo "==> 1/3 编译 MemoFlowCore 核心模块..."
swiftc \
  -vfsoverlay .build-tools/clt_fix_vfs.yaml \
  -Xcc -ivfsoverlay -Xcc .build-tools/clt_fix_vfs.yaml \
  -emit-module -emit-library \
  -module-name MemoFlowCore \
  -enable-testing \
  Sources/MemoFlowCore/Models/*.swift \
  Sources/MemoFlowCore/Services/*.swift \
  -emit-module-path .build-out/MemoFlowCore.swiftmodule \
  -o .build-out/libMemoFlowCore.dylib

echo "==> 2/3 编译 MemoFlowApp 原生界面应用与 App Bundle..."
swiftc \
  -vfsoverlay .build-tools/clt_fix_vfs.yaml \
  -Xcc -ivfsoverlay -Xcc .build-tools/clt_fix_vfs.yaml \
  -parse-as-library \
  Sources/MemoFlowCore/Models/*.swift \
  Sources/MemoFlowCore/Services/*.swift \
  Sources/MemoFlowApp/Views/*.swift \
  Sources/MemoFlowApp/MemoFlowApp.swift \
  -o MemoFlow.app/Contents/MacOS/MemoFlow

codesign --force --deep --sign - MemoFlow.app

echo "==> 3/3 编译并运行 PRD v1.1 验收测试套件..."
swiftc \
  -vfsoverlay .build-tools/clt_fix_vfs.yaml \
  -Xcc -ivfsoverlay -Xcc .build-tools/clt_fix_vfs.yaml \
  -parse-as-library \
  -I .build-out -L .build-out -lMemoFlowCore \
  -Xlinker -rpath -Xlinker @executable_path \
  Tests/MemoFlowCoreTests/PRDTestRunner.swift \
  -o .build-out/PRDTestRunner

./.build-out/PRDTestRunner
