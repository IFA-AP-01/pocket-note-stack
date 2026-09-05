# Project Rules

- Never add, generate, or modify unit tests in this project.
- Do not run unit tests. Validation is complete once the affected targets compile successfully.
- **Scroll Layouts:** When placing `PocketNoteEditorView` inside a `ScrollView` (such as in `LibraryView`), you MUST pass `scrolls: false` so that it expands to fit its content (`fitsContent`). Do not use `.frame(minHeight: ...)` or fixed frames that constrain it into an inner-scrolling box.
