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

### Local release packaging

`scripts/release-from-archive.sh` produces two distribution artifacts:

- `Pocket-Stack-<version>.zip` is signed with Sparkle's EdDSA key and is used only by the automatic update feed.
- `Pocket-Stack-<version>.dmg` is the branded drag-to-Applications installer published for new downloads. The DMG and the app inside it are both signed, notarized, and stapled before upload.

DMG packaging requires `create-dmg` 1.2.3 or newer. Install it with `brew install create-dmg`, then run the release script from a logged-in macOS GUI session. The first run may ask for permission to let the terminal control Finder; that permission is required to apply the custom background and icon layout.
