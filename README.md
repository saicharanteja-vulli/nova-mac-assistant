# Nova
### A local AI voice assistant prototype for macOS

Nova combines a SwiftUI interface, Apple speech APIs and a local Ollama model for spoken conversation and a small set of reviewed Mac actions.

## Features
- Spoken conversation and a reactive particle sphere
- Local notes, remembered facts and timers
- Supported app launching and browser searches
- Menu-bar access and “Hey Nova” phrase parsing
- Review steps for supported actions such as saving memories and opening web searches

## Requirements
Apple Silicon Mac, macOS 14+, Xcode Command Line Tools, and several GB of free memory/storage for the local model.

## Build from source
This source package excludes the Ollama runtime and model weights.
1. Obtain the macOS runtime from the [official Ollama releases](https://github.com/ollama/ollama/releases). The original package used v0.40.2.
2. Place the runtime executable, its accompanying libraries and license notices in `runtime/`, with the executable at `runtime/ollama`. Preserve the runtime distribution's relative library layout.
3. Run `zsh Build.command`.
4. Open `Nova.app`, allow the requested microphone/speech permissions, and use **Prepare Nova** to download the configured model if needed.

The build creates a locally signed app; it is not Apple-notarized. Runtime acquisition is manual and a fresh third-party runtime installation has not been tested in this source-only package.

## Privacy and practical limits
AI chat uses an Ollama endpoint on `127.0.0.1:11435`. Speech recognition may use Apple servers when on-device recognition is unavailable. Browser searches are sent to Google. The wake phrase uses speech recognition rather than a dedicated offline wake detector.

Notes, memories, timers and logs retain the original `JarvisPro` application-data path for compatibility. Timers need the app running; sleep can delay alerts. The assistant cannot control arbitrary interfaces or retrieve live search results.

## Verification status
Source compilation can be checked independently of the model. End-to-end microphone recognition, wake accuracy, voice quality and login launch still need testing on the user's Mac. This is a personal prototype, not a production assistant.
