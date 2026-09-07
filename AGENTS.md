# Project Rules

- Never add, generate, or modify unit tests in this project.
- Do not run unit tests. Validation is complete once the affected targets compile successfully.
- **Warning Policy:** Fix warnings caused by the code being changed and warnings explicitly identified by the user. Do not expand the task to unrelated project or toolchain warnings. Never suppress diagnostics or add workaround code; fix the relevant root cause using current Swift, SwiftUI, and AppKit best practices.
- **Scroll Layouts:** When placing `PocketNoteEditorView` inside a `ScrollView` (such as in `LibraryView`), you MUST pass `scrolls: false` so that it expands to fit its content (`fitsContent`). Do not use `.frame(minHeight: ...)` or fixed frames that constrain it into an inner-scrolling box.
