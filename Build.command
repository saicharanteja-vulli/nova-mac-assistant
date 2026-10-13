#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
if [[ ! -x runtime/ollama ]]; then
  print -u2 "Place the official Ollama runtime in runtime/ (see README.md)."
  exit 1
fi
mkdir -p Nova.app/Contents/MacOS Nova.app/Contents/Resources .build-cache
cp resources/Info.plist Nova.app/Contents/Info.plist
cp -R runtime Nova.app/Contents/Resources/Runtime
swiftc -parse-as-library -target arm64-apple-macos14.0 Nova.swift Brain.swift -o Nova.app/Contents/MacOS/Nova -framework SwiftUI -framework AppKit -framework Speech -framework AVFoundation -module-cache-path .build-cache
codesign --force --deep --sign - Nova.app
print 'Built Nova.app'
