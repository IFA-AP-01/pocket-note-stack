# Project Rules

- Never add, generate, or modify unit tests in this project.
- Do not run unit tests. Validation is complete once the affected targets compile successfully.
- **Scroll Layouts:** When placing `NoteTextView` (or any `NativeTextViewWrapper` from `MarkdownEngine`) inside a `ScrollView`, you MUST set `heightBehavior: .fitsContent` in its `MarkdownEditorConfiguration`. Do not use `.scrollDisabled(true)` or fixed frames, as they cause zero-height collapse or nested scrolling.
