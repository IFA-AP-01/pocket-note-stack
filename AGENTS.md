# Project Rules

- **Deck terminology:** Before changing anything under `Pocket Stack/Features/Deck`, read [`DECK_TERMINOLOGY.md`](DECK_TERMINOLOGY.md) and use its definitions for NoteFan, preview, length/depth, overlap, direction, and alignment.
- **Direct-edit discipline:** When the user names an exact file, symbol, value, or one-line operation, make only that requested change. Do not broaden it into an audit, refactor, architecture change, or unrelated verification. Once the editing tool reports success, stop unless compilation is required by these rules or the user explicitly requests further validation.
- Never add, generate, or modify unit tests in this project.
- Do not run unit tests. Validation is complete once the affected targets compile successfully.
- **Warning Policy:** Fix warnings caused by the code being changed and warnings explicitly identified by the user. Do not expand the task to unrelated project or toolchain warnings. Never suppress diagnostics or add workaround code; fix the relevant root cause using current Swift, SwiftUI, and AppKit best practices.
- **Scroll Layouts:** When placing `PocketNoteEditorView` inside a `ScrollView` (such as in `LibraryView`), you MUST pass `scrolls: false` so that it expands to fit its content (`fitsContent`). Do not use `.frame(minHeight: ...)` or fixed frames that constrain it into an inner-scrolling box.
