# Pocket Stack 1.0.0

Pocket Stack is an ambient, edge-docked note companion for macOS. Always at hand, never in the way.

### Highlights

- **Edge-Docked Deck & NoteFan:** Your notes rest tucked at the screen edge (Bottom, Left, or Right). Hover the screen edge to fan out cards, hover a tab for an instant live preview, or drag a note out to float freely on your desktop.
- **Typora-Style Live Markdown:** Seamless WYSIWYG editing powered by TextKit 2, with full support for GitHub Flavored Markdown (GFM), syntax-highlighted code blocks, LaTeX math expressions, checklists, and tables.
- **Dual-Engine Dictation:** Real-time speech-to-text directly at your cursor—choose 100% offline, zero-latency Apple on-device Speech or high-accuracy streaming transcription with Gemini Live AI.
- **Local-First & Secure:** Stored in a fast local SQLite database (WAL mode) with note bodies encrypted via 256-bit AES-GCM and keys managed in Apple Keychain.
- **Zero Distraction:** Runs as a lightweight macOS accessory app (`LSUIElement`) without cluttering your Dock or interrupting active workflows.

---

### What's New

#### 🎴 Deck & NoteFan
- **Edge Placement:** Dock your deck at the Bottom, Left, or Right edge of any connected display.
- **Multi-State Interaction:**
  - **Rest State:** Compact, unobtrusive tabs tucked at your screen border.
  - **Fan State:** Smoothly reveals stacked, color-coded cards with note titles on edge hover.
  - **Preview State:** Live interactive preview on tab hover without opening a separate window.
  - **Floating State:** Detach any card into an independent, draggable floating window that stays accessible across spaces.
- **Color Coding:** Customize card accent colors for visual categorization and instant recognition.

#### ✍️ Markdown & TextKit 2 Editor
- **Live WYSIWYG Editing:** Renders formatted Markdown in place as you type.
- **Rich Elements:** Supports headings, bold, italic, strikethrough, blockquotes, inline/fenced code blocks with syntax highlighting, LaTeX math formulas, interactive checklists, and tables.
- **Import & Export:** Export notes to Markdown (`.md`), plain text (`.txt`), or combined master documents. Import existing notes and Apple Stickies JSON archives.

#### 🎙️ Voice Dictation
- **Apple Speech (On-Device):** Private, offline, zero-latency transcription using Apple Speech framework.
- **Gemini Live AI:** Low-latency streaming transcription over WebSocket PCM audio for complex vocabulary and technical dictation.
- **Live Insertion:** Streams recognized text directly at the cursor in your active note editor.

#### 🔒 Privacy & Performance
- **AES-GCM Encryption:** 256-bit AES encryption with keys stored in macOS Keychain.
- **SQLite with WAL Mode:** Fast local persistence with concurrency and data integrity.
- **Accessory App Architecture:** Runs cleanly in the background without stealing focus or occupying a Dock slot.

#### 🚀 Updates & Maintenance
- **Sparkle Integration:** Secure, signed updates (EdDSA) and automated update checks powered by Sparkle.
- **Global Shortcuts:**
  - `⌥⌘N`: Create a new note immediately.
  - `⌥⌘A`: Open the note library and archive search.
  - `⌥⌘L`: Archive the current note.

---

### System Requirements

- **macOS:** 14.0 (Sonoma) or newer.
- **Architecture:** Apple Silicon and Intel Macs.
