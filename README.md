# Pocket Stack

Pocket Stack is a native macOS 26+ note app whose notes live in a floating deck at the screen edge. It is an accessory app: there is no Dock icon or ordinary main window.

## Features

- Rest, fan and expanded deck states on one or every connected display.
- Encrypted local notes with one Typora-style live Markdown editor for GFM, LaTeX math, syntax-highlighted code, links, tables, tasks and images.
- Global shortcuts: `⌥⌘N` new note, `⌥⌘A` all notes and `⌥⌘L` archive.
- Markdown, text, combined-document and `.stickies` JSON import/export.
- Realtime dictation at the current editor selection using either Apple on-device Speech or Gemini Live transcription.
- A disabled Sync settings preview. This release does not open an incoming socket or send notes over the local network.

## Architecture

The Xcode target uses file-system synchronized groups and is split by responsibility:

- `Domain`: value models and repository/dictation contracts; no UI, database or audio imports.
- `Data`: the actor-isolated SQLite repository, AES-GCM body encryption and transfer formats.
- `Platform`: Keychain, microphone/CoreAudio, audio conversion, Apple Speech and Gemini WebSocket implementations.
- `Features`: focused SwiftUI views plus the AppKit panels/controllers required for an accessory utility.
- `App`: dependency graph, app-wide observable state and lifecycle wiring.

SQLite runs in WAL mode. Note bodies are AES-GCM encrypted with a random 256-bit key stored in Keychain. Titles, colors and timestamps remain plaintext so note lists can render without decrypting every body. The Gemini API key is stored separately in Keychain.

Apple dictation uses `SpeechAnalyzer` and `DictationTranscriber.progressiveLongDictation`. Gemini uses `gemini-3.5-transcribe-live` over `URLSessionWebSocketTask` with mono PCM16 at 16 kHz in approximately 100 ms chunks. Pocket Stack never switches from Apple to Gemini automatically.

## Build and test

Open `Pocket Stack.xcodeproj` in Xcode 26 or run:

```sh
xcodebuild -project "Pocket Stack.xcodeproj" -scheme "Pocket Stack" -destination "platform=macOS" build
xcodebuild -project "Pocket Stack.xcodeproj" -scheme "Pocket Stack" -destination "platform=macOS" -only-testing:"Pocket StackTests" test
```

The native TextKit 2 Markdown editor is pinned to an exact package version for reproducible builds.

Developer ID distribution should retain the sandbox entitlements, use a stable bundle identifier and be notarized. Release automation and an updater are intentionally outside this version.

## Attribution

The deck interaction and portions of the implementation are derived from [Noty](https://github.com/aimen08/noty), available under the MIT License. The required notice is bundled in `Resources/THIRD-PARTY-NOTICES.txt`.
