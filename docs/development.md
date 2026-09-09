# Building & Development

Guidelines for building, running, and contributing to Pocket Stack.

---

## Requirements

- **macOS:** macOS 14.0 (Sonoma) or newer
- **Xcode:** Xcode 16+ with Swift 6 support
- **Swift Package Dependencies:** Managed via Swift Package Manager inside `Pocket Stack.xcodeproj`

---

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/your-org/pocket-stack.git
cd "pocket-stack"
```

### 2. Open in Xcode

Open `Pocket Stack.xcodeproj` in Xcode:

```bash
open "Pocket Stack.xcodeproj"
```

Select the **Pocket Stack** scheme and your Mac as the run destination, then press `⌘R` to build and launch.

---

## Command Line Build

To build from the command line using `xcodebuild`:

```bash
xcodebuild -project "Pocket Stack.xcodeproj" \
           -scheme "Pocket Stack" \
           -destination "platform=macOS" \
           build
```

---

## AppKit & Accessory App Model

Pocket Stack runs as an accessory utility (`LSUIElement = YES`):
- It has no standard Dock icon.
- Floating panels are `NSPanel` instances with `.nonactivatingPanel` style masks to prevent interrupting the active application.
- For detailed definitions and rules regarding NoteFan, preview sizing, stack overlap, and edge layouts, refer to [DECK_TERMINOLOGY.md](../DECK_TERMINOLOGY.md).

---

## Sandboxing & Distribution

- **Entitlements:** Sandboxing is enabled under `Pocket Stack/Pocket Stack.entitlements`.
- **Microphone Access:** Microphone usage description is defined in `Pocket-Stack-Info.plist` for audio dictation.
- **Developer ID & Notarization:** Production builds should retain sandbox entitlements, use a hardened runtime, and be notarized using `xcrun notarytool`.
