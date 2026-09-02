# Pocket Stack Editor — Ship Readiness Audit & Recovery Plan

> Status: **NO-SHIP**  
> Audit date: 2026-09-02  
> Scope: Native macOS note editor, Markdown round-trip, Library integration, Deck integration, dependencies, performance, accessibility, persistence, and release validation.  
> Purpose: This is a project note and remediation backlog. It is not evidence that any listed issue has been fixed.

## 1. Executive summary

The current experimental block editor does not meet the original product goal and must not be shipped in its current form.

The fundamental design error is that one logical note is split into many independent `NSTextView` instances: one per paragraph/heading/list item/task/code block and one per table cell. AppKit selection, marked text, undo, find, copy/paste, and first-responder behavior are scoped to a text system. Splitting a note into many text systems makes native cross-block behavior impossible without building a second, custom document-selection system.

The attempted cross-block selection implementation is a workaround, not a production solution. It combines multiple inactive `NSTextView` selections, a focus registry, a local event monitor, an `NSPanGestureRecognizer`, coordinate conversion, nearest-view hit testing, and custom copy behavior. It still cannot provide a single AppKit selection range and does not cover delete, cut, drag autoscroll, unmounted lazy blocks, non-text blocks, accessibility, or native undo.

The editor also introduces avoidable performance costs:

- Many AppKit text systems and SwiftUI wrappers are created for one note.
- Table size multiplies the number of `NSTextView` instances.
- Structural changes invalidate and rebuild block subtrees.
- Syntax highlighting restyles the full code block on every edit.
- Image loading/decoding can occur synchronously during view construction.
- Markdown parsing and serialization currently run on the main actor.
- Saving is debounced independently by the block editor, `NoteEditorView`, and in some paths the Library integration.
- Persisting a note publishes the full note collection, which can invalidate Deck/Library views while an editor transition is running.

The project currently carries two Markdown implementations:

1. `swift-markdown-engine` 0.12.0, a TextKit 2 editor/styler, plus its code and LaTeX bridge products.
2. `swift-markdown` 0.8.0 plus `swift-cmark`, used by the experimental block parser.

There is no proven package-version collision in the current graph, but there is overlapping responsibility, duplicated parsing behavior, additional binary/build footprint, and no single definition of Markdown semantics. Both systems are still referenced by production code.

Only compilation has been verified. Runtime UX, performance, data fidelity, accessibility, and crash safety have not been demonstrated. Project rules currently forbid adding or running unit tests; that rule is itself a release-validation blocker for a Markdown serializer and editor state machine.

## 2. Evidence classification

### 2.1 Observed regressions reported during manual use

- Mouse selection does not reliably work within or across blocks.
- Cross-block selection feels unnatural and difficult to control.
- Selection can remain visibly highlighted after focus changes.
- The insertion caret/I-beam can disappear.
- Switching notes/tabs while editing has crashed or behaved as if it crashed.
- Opening a note tab and preview animation became slower/less polished after editor integration.
- Overall editor/app performance became materially worse.
- Library layout was changed without an agreed UI specification.
- Pressing Enter can duplicate preceding text, especially around creation/use of fenced code or checkbox/task content.
- Pasting code into a code block can fail.
- Selecting text and then opening formatting controls loses the selection, so bold/italic/other formatting cannot be applied reliably.
- List markers are positioned too far from their text.

These are product failures even when a stack trace or profile is not yet available.

### 2.2 Confirmed directly from the code

- A note is rendered by multiple `WYSIWYGTextView` instances.
- Each table cell creates another `WYSIWYGTextView`.
- Cross-block selection is simulated with `FocusRegistry` and `NSPanGestureRecognizer`.
- Cross-block copy writes plain text assembled from several local ranges.
- `Cmd+A` selects only registered text views, not a single document range.
- `LazyVStack` can unmount blocks; unmounted blocks are absent from the focus/selection registry.
- Markdown parsing and serialization execute through a `@MainActor` editor model.
- Code highlighting processes a full code string after text changes.
- The old `NoteTextView` and the new `BlockEditorView` coexist.
- Both Markdown dependency stacks are linked.
- Block IDs, row IDs, cell IDs, and list-item IDs are regenerated after parsing.
- `EditorBridge` discovers its target through `NSApp.keyWindow?.firstResponder` and concrete type checks.
- The new Library detail implementation and formatting bar are uncommitted changes.
- The experimental `Features/BlockEditor` directory is currently untracked by Git.
- `THIRD-PARTY-NOTICES.txt` only contains a Noty notice and has not been audited for the newly linked packages.
- A click on Library formatting controls is outside every registered editor text view; the local mouse monitor clears selections before the button command executes.
- NoteEditor formatting is hosted in a popover while command lookup depends on `NSApp.keyWindow?.firstResponder`; the popover can make that lookup fail.
- Formatting commands operate on one active `NSTextView`; they cannot apply a format transaction to the simulated multi-view document selection.
- Focused text views intentionally reject model-to-view content updates in `updateIfNeeded`. Structural split can therefore update the model and destination block without trimming the still-focused source view.
- `Cmd+V` is manually intercepted and calls generic rich-text `paste(nil)`; there is no code-block-specific plain-text paste pipeline or paste verification.
- List markers are separate SwiftUI `Text` views with a fixed 24-point width, 7-point HStack gap, outer 16-point editor padding, and AppKit text inset rather than TextKit paragraph tabs/hanging indents.

### 2.3 Suspected but not yet proven with a runtime trace

- Main-thread parsing/view creation is a direct contributor to NoteFan transition frame drops.
- Full-note collection publication after autosave causes broad SwiftUI invalidation during Deck animations.
- The previously reported tab-switch crash is caused by delayed focus/save work targeting dismantled views. The code contains lifecycle hazards consistent with this, but the supplied console text did not include a crash backtrace.
- The AppKit toolbar constraint warnings contribute to visible layout instability. They are real constraint failures, but the supplied log does not prove that they caused the crash.
- Gesture recognition and native `NSTextView` tracking interfere on all supported macOS versions. This behavior needs a reproducible runtime matrix.
- The exact trigger sequence that turns the focused-view split desynchronization into the reported code-fence/task duplication still needs a deterministic reproduction and state capture.
- The exact reason code-block paste fails in the reported workflow is not yet isolated. Manual key-equivalent interception, rich paste attributes, responder routing, and post-paste restyling are all investigation targets; none is yet proven as the sole cause.

## 2A. Newly verified critical task queue

These tasks are above the normal recovery backlog. They are release blockers and must remain open until runtime evidence demonstrates the acceptance criteria.

### CT-001 — Stop Enter/split text duplication

**Severity:** P0 / data-integrity blocker  
**Observed:** Enter can duplicate text before fenced-code or checkbox/task workflows.  
**Confirmed mechanism:** `splitBlock`/`splitListItem` mutates source and destination model content, but `NativeBlockTextView.Coordinator.updateIfNeeded` refuses to install changed source content while the source view remains first responder. The old source view can therefore retain unsplit text while the new block renders the right-hand text.

- [ ] CT-001.1: Record exact minimal reproductions for paragraph → fence, paragraph → task, existing task Enter, and Enter in the middle of text.
- [ ] CT-001.2: Log pre-command text, selected UTF-16 range, model left/right result, source-view text, destination-view text, and serialized Markdown revision.
- [ ] CT-001.3: Confirm whether duplication occurs before persistence, after self-save, after repository publication, or after reopening.
- [ ] CT-001.4: Prohibit structural model/view divergence in the target architecture.
- [ ] CT-001.5: Implement split as one TextKit range transaction in the unified editor.
- [ ] CT-001.6: Register split as one undo operation.
- [ ] CT-001.7: Verify split with emoji, composed Vietnamese text, inline marks, links, code, list, task, quote, start/end/middle positions.
- [ ] CT-001.8: Verify saved Markdown contains every source character exactly once.

**Acceptance:** No source/destination duplication or loss in the full split matrix; one undo restores the exact pre-split document and selection.

### CT-002 — Restore reliable code-block paste

**Severity:** P0 / core editing blocker  
**Observed:** Code cannot reliably be pasted into a code block.  
**Confirmed gap:** `WYSIWYGTextView.performKeyEquivalent` manually intercepts `Cmd+V` and calls generic rich-text `paste(nil)`. There is no explicit code-block paste policy, no plain-text normalization, no multi-line/fence handling contract, and no verification. The exact failing stage remains unproven.

- [ ] CT-002.1: Reproduce with plain text, attributed text, tabs, LF, CRLF, emoji, long code, and code containing triple/multiple backticks.
- [ ] CT-002.2: Verify whether `performKeyEquivalent`, responder-chain validation, `readSelection`, `shouldChangeText`, text storage mutation, restyling, or serialization rejects/changes the paste.
- [ ] CT-002.3: Remove unnecessary manual interception of standard copy/cut/paste shortcuts from the target editor.
- [ ] CT-002.4: Define code-block paste as plain text unless an explicit richer format is supported.
- [ ] CT-002.5: Normalize line endings without changing tabs/indentation.
- [ ] CT-002.6: Ensure embedded backtick runs select a safe Markdown fence during serialization.
- [ ] CT-002.7: Keep paste and syntax highlighting in separate phases so highlighting cannot cancel the edit.
- [ ] CT-002.8: Register paste as one undo transaction and restore the expected selection/caret.

**Acceptance:** All paste fixtures appear immediately, remain editable, survive save/reopen, serialize to valid fenced Markdown, and undo in one step.

### CT-003 — Preserve selection while invoking formatting

**Severity:** P0 / mandatory feature blocker  
**Observed:** Opening formatting controls clears the selected range; bold, italic, underline, strikethrough, link, and inline code cannot be applied reliably.

**Confirmed mechanisms:**

1. `FocusRegistry` installs a local left-mouse monitor and clears selection for clicks outside registered `WYSIWYGTextView` instances. Formatting controls are outside those views, so selection is cleared before the action.
2. `EditorBridge.activeTextView()` depends on `NSApp.keyWindow?.firstResponder`. A formatting popover may become the key window or move focus away from the editor, leaving no command target.
3. `handleEditorCommand` receives only one `NSTextView`; even a simulated cross-block selection cannot be formatted as one range.

- [ ] CT-003.1: Remove window-global first-responder discovery from the target editor command path.
- [ ] CT-003.2: Give each visible toolbar an explicit editor-session reference.
- [ ] CT-003.3: Store the native document selection in the unified text system while toolbar controls are used.
- [ ] CT-003.4: Prevent toolbar/popup interaction from destroying the editing selection.
- [ ] CT-003.5: Support mixed-state toolbar feedback for bold/italic/underline/strike/code/link.
- [ ] CT-003.6: Apply inline formatting across paragraph/block boundaries as one attributed-range transaction.
- [ ] CT-003.7: Restore selection after dismissing a link/math metadata editor when appropriate.
- [ ] CT-003.8: Verify mouse, keyboard shortcut, menu command, Touch Bar-equivalent command routing if applicable, and multiple windows.

**Acceptance:** A selection remains visible and semantically active while controls open; every format applies to the exact original range and undoes in one step.

### CT-004 — Correct list marker geometry

**Severity:** P1 / visible quality blocker  
**Observed:** Bullet/number markers are too far from list text.  
**Confirmed mechanism:** Markers and text are separate views. Layout uses a fixed marker frame (`24`), explicit gap (`7`), block-stack horizontal padding (`16`), and text-container inset, rather than paragraph tab stops/hanging indentation. Baseline alignment also crosses SwiftUI `Text` and AppKit `NSTextView` implementations.

- [ ] CT-004.1: Capture expected marker/text geometry for bullet, dash, plus, 1-digit, 2-digit, and 3-digit ordered markers.
- [ ] CT-004.2: Define first-line head indent, head indent, tab stop, and nesting increment tokens.
- [ ] CT-004.3: Render list markers through TextKit paragraph/list-marker layout in the unified editor.
- [ ] CT-004.4: Make wrapped lines align to the text column, not the marker.
- [ ] CT-004.5: Verify custom fonts and font sizes.
- [ ] CT-004.6: Verify nested lists, RTL, accessibility text sizes, and task checkbox alignment.

**Acceptance:** Marker-to-text spacing is visually consistent across marker widths; wrapped lines and nested levels align without hard-coded per-marker frames.

### CT-005 — Resolve engine ownership before further editor implementation

**Severity:** P0 / architectural blocker  
**Observed assessment:** The project does not have a clear editor engine direction. Markdown has been placed at the center of live editing, producing raw-token UX, duplicated state, parser overlap, and expensive reparsing/serialization pressure.

- [ ] CT-005.1: Freeze additions to both editor paths until ADR completion.
- [ ] CT-005.2: State explicitly that Markdown is the persistence/interchange format, not the per-keystroke UI model.
- [ ] CT-005.3: Inventory every API currently consumed from MarkdownEngine core, code bridge, and LaTeX bridge.
- [ ] CT-005.4: Inventory every AST feature consumed from swift-markdown/cmark.
- [ ] CT-005.5: Prototype unified TextKit selection without either parser in the input loop.
- [ ] CT-005.6: Compare extending/forking MarkdownEngine against owning a focused unified TextKit editor.
- [ ] CT-005.7: Select exactly one parser/serializer authority.
- [ ] CT-005.8: Select renderer dependencies behind internal protocols.
- [ ] CT-005.9: Define the removal plan for the rejected engine path and transitive dependencies.
- [ ] CT-005.10: Approve the ADR before reconnecting the editor to Library or Deck.

**Acceptance:** One documented engine architecture, one editing source of truth, one parser/serializer authority, and no Markdown parse/render cycle on every ordinary text edit.

## 3. Current implementation inventory

### 3.1 Original/legacy editor path

- `Pocket Stack/Features/Editor/NoteTextView.swift`
- Uses `NativeTextViewWrapper` from `MarkdownEngine`.
- Uses one TextKit-backed editor for a note.
- Keeps raw Markdown as the text storage/source of truth.
- Applies live styling and renderer services for code, images, LaTeX, tasks, and extensions.
- Known product mismatch: focus/edit mode exposes raw Markdown markers or changes presentation, causing context switching and layout shift.
- Library originally used `.fitsContent`, as required when nested inside a SwiftUI `ScrollView`.

### 3.2 Experimental block editor path

- `Pocket Stack/Features/BlockEditor/BlockModels.swift`
- `Pocket Stack/Features/BlockEditor/MarkdownBlockCodec.swift`
- `Pocket Stack/Features/BlockEditor/BlockEditorModel.swift`
- `Pocket Stack/Features/BlockEditor/BlockEditorView.swift`
- `Pocket Stack/Features/BlockEditor/NativeBlockTextView.swift`
- `Pocket Stack/Features/Editor/EditorFormattingBar.swift`

This path parses Markdown into `[NoteBlock]` and builds a SwiftUI `LazyVStack` containing many AppKit editors and SwiftUI block views.

### 3.3 Integration changes currently in the working tree

- `NoteEditorView` replaces `NoteTextView` with `BlockEditorView`.
- `LibraryView` replaces its note editor, state ownership, search placement, header, actions, and formatting controls.
- `EditorBridge` supports both the old `NativeTextViewCoordinator` and the experimental `WYSIWYGTextView`.
- The Xcode project directly adds `swift-markdown` and its transitive `swift-cmark` dependency.
- `NoteFan.swift` and `NoteTab.swift` currently have no working-tree diff; prior experimental gesture changes were reverted.

## 4. Architecture failures and technical debt

### A-001 — Multiple text systems for one logical document

**Severity:** P0 / release blocker  
**Location:** `BlockEditorView.swift`, `NativeBlockTextView.swift`  
**Problem:** Every editable block/cell owns an independent `NSTextView`, text storage, selection, first responder, and undo context.  
**Consequences:** Cross-block selection/copy/delete/formatting/undo/find/IME cannot behave like one document. Focus transitions become application logic. Tables amplify cost.  
**Required disposition:** Replace the production editor surface with one unified TextKit document. Do not add more cross-view selection patches.

### A-002 — Visual block boundaries are incorrectly treated as editor boundaries

**Severity:** P0  
**Problem:** A heading, paragraph, quote, list item, and code block should normally be paragraph ranges in one text storage. They were instead modeled as independent controls.  
**Required disposition:** Represent text blocks with paragraph-level attributes and range metadata. Reserve attachment/child-view boundaries for genuinely non-text surfaces.

### A-003 — No authoritative editing source of truth

**Severity:** P0  
**Problem:** Markdown string, `EditorDocument`, multiple `NSTextStorage` values, SwiftUI draft state, and repository snapshots can all act as an authority at different times.  
**Consequences:** Reload loops, stale view updates, last-writer-wins conflicts, selection resets, and data-loss risk.  
**Required disposition:** Define one in-memory document authority during an edit session. Markdown is the persistence/export format, not a second live editor state.

### A-004 — Ephemeral identity after every parse

**Severity:** P1  
**Problem:** `UUID()` is assigned to parsed blocks, rows, columns, cells, and list items. Reparse creates a logically new document tree.  
**Consequences:** SwiftUI identity churn, focus loss, selection loss, attachment recreation, and expensive diffs.  
**Required disposition:** Use stable session identities derived from source ranges plus reconciliation, or mutate a persistent in-memory document without reparsing self-emitted Markdown.

### A-005 — Manual observation invalidation

**Severity:** P1  
**Location:** `BlockEditorModel.document`, `renderRevision`, `renderedBlocks`  
**Problem:** `document` was hidden from Observation to mitigate rerender storms; structural refresh is now driven manually by `renderRevision`.  
**Consequences:** Easy to forget an invalidation, producing stale UI. This is a compensating workaround for an unsuitable view model boundary.  
**Required disposition:** Make the unified text storage authoritative and publish only narrow UI state such as active block, toolbar state, and attachment mutations.

### A-006 — Focus registry as document navigation system

**Severity:** P1  
**Problem:** Cursor navigation searches registered views and schedules asynchronous first-responder changes.  
**Consequences:** Lazy/unmounted targets cannot receive focus; delayed focus can race teardown; caret geometry differs between views; table transitions are special-cased.  
**Required disposition:** Text block navigation must be native range movement in one text view. Keep an explicit coordinator only for entering/exiting attachment sub-editors.

## 4A. Engineering accountability: mistakes made during this implementation

This section records process and judgment failures explicitly. They must not be softened into generic “iteration.”

### AC-001 — The architecture was presented as viable before its hardest invariant was proven

Cross-block selection was a mandatory requirement. The implementation selected multiple independent `NSTextView` instances before proving that one native selection could cross them. A minimal selection prototype should have been the first gate. Building models, parser, table UI, focus navigation, and integrations before that proof created sunk cost on an invalid foundation.

### AC-002 — Compile success was repeatedly described too close to feature success

The target compiled, but selection was not manually demonstrated. Statements that the selection issue was “fixed” were therefore unsupported. Compilation verifies types/linking; it cannot validate mouse tracking, first-responder behavior, perceived animation, or data round-trip.

### AC-003 — Workarounds were added after the architecture had already failed its invariant

The focus registry, multi-view selected ranges, local event monitor, manual mouse tracking loop, delayed post-drag selection, and pan recognizer were successive attempts to conceal the absence of a unified text system. Each patch increased state and lifecycle complexity without making the selection native.

### AC-004 — A manual event-tracking loop temporarily replaced native text interaction

An override consumed mouse events and manually called redraw while tracking. It broke ordinary selection and degraded responsiveness. This was not an acceptable AppKit practice for a production text editor.

### AC-005 — NoteFan/NoteTab interaction was changed without authorization

`Button` was temporarily replaced with a gesture-driven container and drag behavior was made conditional. Those edits changed view/gesture identity and affected preview/open animation. They were outside the editor task and were later reverted. The regression still consumed user time and damaged confidence.

### AC-006 — Library layout was changed together with editor internals

Search placement, sticky controls, detail structure, actions, and state ownership were modified in the same workstream as the editor engine. Even where the resulting direction matches later feedback, it was not isolated behind a reviewed layout change and made diagnosis harder.

### AC-007 — A likely crash cause was stated more strongly than the evidence allowed

The supplied log showed ViewBridge and toolbar Auto Layout warnings, not a crash backtrace. Lifecycle races existed in code and were reasonable suspects, but they were not proven root causes. The correct statement should have remained “hypothesis pending crash report.”

### AC-008 — Performance fixes were applied without baseline measurements

Sharing renderer instances and narrowing Observation invalidation are plausible improvements, but no Time Profiler/SwiftUI trace or before/after metric was collected. They cannot be presented as proof that performance is repaired.

### AC-009 — Dependency expansion happened before architecture validation

`swift-markdown` and `swift-cmark` were added before the editing projection was proven. The project incurred build, maintenance, and compliance surface while the core selection architecture remained invalid.

### AC-010 — The implementation mixed migration scaffolding with production integration

Old and new editors, raw-Markdown bridge commands, block commands, two parser approaches, and multiple save layers coexist. A prototype should have remained isolated until it passed acceptance gates. Instead, incomplete experimental code was wired into `NoteEditorView` and `LibraryView`.

### AC-011 — User-reported UX evidence was initially treated as another patch request

Repeated reports that selection was difficult or impossible should have triggered an immediate architecture stop. Continuing to patch gesture handling prolonged the failure.

### AC-012 — Scope discipline failed

The task was to deliver a native WYSIWYG editor. Changes to unrelated Deck interaction were not necessary to prove or implement that goal. Future work must freeze adjacent surfaces and require an explicit integration gate.

## 5. Workaround and non-best-practice ledger

| ID | Workaround/trick | Why it is not production quality | Known impact | Remove/replace with |
|---|---|---|---|---|
| W-001 | `FocusRegistry` maps block IDs to weak `NSTextView` references | Recreates behavior already provided by one text system | Caret races, missing targets, teardown complexity | Unified `NSTextView` |
| W-002 | Multiple inactive `selectedRange` values simulate one selection | AppKit still sees separate selections | Black/stale highlights; no true range | One native selected range |
| W-003 | `NSPanGestureRecognizer` attempts cross-block drag selection | Competes with AppKit text interaction and must duplicate hit testing | Broken/difficult drag UX | Remove with multi-view editor |
| W-004 | Global/local `NSEvent` mouse monitor clears selections | Broad window-level side effect and lifecycle burden | Unexpected blur behavior; monitor leakage risk | Native first-responder/selection behavior |
| W-005 | Nearest-view Euclidean hit testing on every drag update | O(number of mounted text views), semantically wrong for tables | Jank and surprising destination | Native glyph hit testing in one layout |
| W-006 | Custom cross-block `copy` joins strings with blank lines | Loses rich formatting, Markdown structure, attachments, tables, and exact separators | Incorrect clipboard data | TextKit pasteboard writer/document serializer |
| W-007 | Custom `Cmd+A` selects registered views | Lazy/offscreen/non-text blocks are omitted | “Select all” is not all | One document selection |
| W-008 | `renderRevision` manually forces structural rendering | Hides broad invalidation instead of fixing ownership | Stale UI risk | Narrow observable editor state |
| W-009 | `synchronizedMarkdown` suppresses self-reload | Necessary because binding is both output and external input | Conflict behavior undefined | Explicit edit session + versioned persistence |
| W-010 | Delayed `DispatchQueue.main.async` focus requests with generation counter | Mitigates but does not eliminate mount timing races | Focus can silently fail | Native range focus; explicit attachment transition |
| W-011 | `EditorBridge` finds editor using `NSApp.keyWindow?.firstResponder` | Implicit global routing; wrong with multiple windows/popovers | Commands target nothing or wrong editor | Injected editor command target/session |
| W-012 | Concrete type checks for old/new editor in one bridge | Transitional coupling leaks implementation detail | Dual behavior and fallback ambiguity | One editor protocol and one active session |
| W-013 | Raw-Markdown fallback commands after block command failure | Can insert Markdown syntax into an unintended editor state | Data/presentation inconsistency | Typed editor commands with explicit capability result |
| W-014 | Full attributed-text restyle in `textDidChange` | Reprocesses more content than changed and can disturb IME | Typing latency; marked-text risk | Edited-range styling/text-storage processing |
| W-015 | Full code highlight after each edit | Highlight cost grows with code length | Multiline code typing jank | Debounced/incremental highlighting off critical path |
| W-016 | `TextEditor` swap for display math edit mode | Replaces view identity and uses another independent text system | Focus/layout jump, separate undo | Attachment editor with stable overlay/session |
| W-017 | Synchronous `AttachmentManager.loadImage` from SwiftUI body | File read/decode can happen on main thread | Scroll/open hitch and memory spikes | Async decode + downsample + cache |
| W-018 | `try?` for exports/imports/directory creation | Suppresses actionable failures | Silent data loss/failure | Propagate and present errors |
| W-019 | Force unwrap of Application Support URL | Assumes API always returns a value | Avoidable crash path | Throw/fallback safely |
| W-020 | Compile-only validation treated as completion | Compilation says nothing about editor semantics | Regressions reached manual testing | Ship gates and runtime evidence |
| W-021 | Focused views reject model content updates | Avoids caret disruption by allowing model/view divergence | Enter/split can duplicate text | One text-storage transaction |
| W-022 | Standard `Cmd+C/X/V/A/Z` manually intercepted | Bypasses normal responder-chain behavior without a complete document command system | Paste/cut/undo inconsistencies | Native responder commands on unified text system |
| W-023 | Fixed-width SwiftUI marker column beside AppKit editor | Fakes list typography outside the text layout engine | Excessive gap and baseline/wrap mismatch | TextKit tab stops/hanging indent |
| W-024 | Formatting popover relies on global key-window first responder | Control focus and editor selection cannot coexist reliably | Selected text loses command target | Explicit editor session/selection |

## 6. Cross-block selection: why the current approach cannot be completed safely

The current architecture has no single selection object. A complete cross-block implementation would have to independently implement all of the following:

- Live forward and backward drag selection.
- Autoscroll while dragging above/below the viewport.
- Selection through blocks not currently mounted by `LazyVStack`.
- Selection through paragraphs, list items, task rows, code, table cells, math, images, thematic breaks, and unsupported blocks.
- Shift-click extension.
- Shift-arrow and Option/Command-arrow extension.
- Double-click word selection and triple-click paragraph selection.
- `Cmd+A`, copy, rich copy, cut, delete, replacement typing, drag-and-drop, and paste.
- Formatting commands over heterogeneous ranges.
- Undo/redo as one transaction.
- Accessibility selection ranges and VoiceOver announcements.
- IME marked-text composition.
- Correct active/inactive highlight rendering.

That is effectively a second text editor layered over AppKit. Continuing this route would add code while moving further away from native behavior.

## 7. Markdown parser and serializer gaps

### M-001 — Round-trip fidelity is not established

`parse(markdown) -> serialize(document)` canonicalizes the document. It does not preserve source spelling, blank-line choices, marker choices, indentation, escapes, unsupported constructs, or exact HTML. The product requirement must explicitly choose between semantic Markdown compatibility and byte-for-byte preservation.

### M-002 — Nested and multi-block list items are lost

Only the first paragraph child of a list item becomes `RichText`. Nested lists, continuation paragraphs, quotes, code, and other child blocks are discarded from the editable model.

### M-003 — Unordered marker fidelity is lost

Parsed unordered lists are serialized as dash lists regardless of whether source used `*`, `-`, or `+`.

### M-004 — Block quotes are flattened

Only paragraph children are retained. Nested quotes, lists, headings, code, tables, and other valid content are not faithfully represented.

### M-005 — Inline image handling is incomplete

Only a paragraph containing exactly one image becomes an image block. Images mixed with text are not modeled as inline attachments.

### M-006 — Display math splitting is ad hoc

Only standalone lines equal to `$$` are recognized. Escapes, `$$formula$$`, varying fences, malformed fences, nested contexts, and some code-fence combinations are not robustly handled.

### M-007 — Inline math parsing is ad hoc

The parser pairs the next two `$` characters in text. It does not correctly define escaped dollars, currency, empty formulas, delimiter runs, whitespace rules, or malformed input.

### M-008 — Underline is not standard CommonMark

Underline is represented as `<u>...</u>`. This is an HTML extension, not a standard Markdown emphasis primitive. Storage policy and interoperability expectations must state this explicitly.

### M-009 — Soft line breaks are changed

Soft breaks are converted to spaces, changing source and potentially meaning/layout.

### M-010 — Escaping is incomplete

Serializer escaping does not comprehensively cover Markdown punctuation and context-sensitive cases such as backticks, underscores, headings, block markers, angle brackets, link destinations/titles, parentheses, and line-start syntax.

### M-011 — Annotation serialization is fragile

Overlapping marks are emitted chunk by chunk. Nested marks can be repeatedly opened/closed, creating noisy or ambiguous Markdown. Mixed-state ranges are not normalized.

### M-012 — Table newline round-trip is inconsistent

Cell newlines serialize as `<br>`, but inline HTML handling does not map `<br>` back to a newline in the cell model.

### M-013 — Unsupported-node preservation is not trustworthy

`node.format()` is a reformat, not guaranteed original source preservation. Unknown Markdown may silently change after an unrelated edit.

### M-014 — Reference constructs and broader GFM coverage are undefined

Reference links/images, footnotes, definition lists, HTML, autolinks, escaped constructs, nested tables, and extension compatibility do not have documented behavior or fixtures.

### M-015 — Block IDs are not derived from parser source ranges

The AST-to-model mapping throws away potentially useful source-position information, making reconciliation, incremental parse, diagnostics, and stable identity harder.

## 8. Block feature completeness matrix

| Feature | Current state | Ship gap |
|---|---|---|
| Paragraph | Editable in separate text view | Must move to unified paragraph range |
| H1–H6 | Parser/model supports 1–6; toolbar exposes only H1–H3/body | Missing full UI and unified semantics |
| Quote | Flattened to one rich string | Nested block content lost |
| Bold/italic | Custom attributes | Mixed selection and multi-block formatting incomplete |
| Strikethrough | Custom attribute | Round-trip/overlap normalization unverified |
| Underline | HTML extension | Interoperability contract missing |
| Link | Inserts placeholder `https://` | No destination editor, validation, title UI, or safe activation behavior |
| Inline math | Rendered attachment | No reliable delimiter parser or formula editing UX |
| Bullet/dash/number list | Flat list model | No nesting, continuation blocks, indent/outdent, renumber policy |
| Checklist | One task per block | No nested tasks; task syntax compatibility split between legacy and new code |
| Code block | Multiline editable and highlighted | Full rehighlight, no language picker, no incremental styling |
| Display math | View swaps between render/editor | Focus/layout/undo discontinuity |
| Image | Local attachment filenames render | Remote `http(s)` Markdown images do not render; no async decode/downsample/error retry |
| Table | SwiftUI Grid with editor per cell | Severe scaling/selection/focus issues; no remove/reorder/alignment controls; clipboard semantics absent |
| Thematic break | Display-only divider | No clear caret/selection/delete behavior |
| Unsupported Markdown | Display-only SwiftUI `Text` | Not editable as part of document selection |

## 9. Editing behavior gaps

### E-001 — Split is incomplete

- Splitting a normal block always creates a paragraph on the right.
- Table Enter moves focus instead of applying a documented cell/new-row rule.
- Split behavior for quote/task/code/list boundaries is incomplete or implicit.
- Inline attribute inheritance at the split boundary is not specified.

### E-002 — Merge is incomplete

- Merge only succeeds when adjacent blocks expose `RichText` through a narrow helper.
- Image, table, math, thematic break, unsupported content, and list/block combinations lack defined behavior.
- Merge does not participate in a document-wide undo transaction.

### E-003 — Arrow navigation is mount-dependent

- Movement skips unregistered surfaces.
- Lazy rendering can make the intended destination unavailable.
- Horizontal desired-X preservation is approximate and per-view.
- Attachment entry/exit semantics are incomplete.

### E-004 — Undo/redo is fragmented

Each `NSTextView` can have its own undo manager, while structural model mutations are not registered as cohesive undo operations. Cross-block edit undo cannot be correct.

### E-005 — Find/replace is fragmented

`EditorBridge.showFind()` targets only the active text view. It cannot search/replace an entire note made of many text views.

### E-006 — Clipboard behavior is incomplete

Cross-block copy is plain text only. Cut, delete, rich copy, Markdown copy, attachments, tables, and paste replacement are not implemented as document operations.

### E-007 — Dictation integration is tied to one active text view

The existing dictation bridge assumes one active `NSTextView` and local ranges. Structural/block transitions and attachment editors have no defined dictation policy.

### E-008 — IME safety is unverified

Restyling and model extraction occur during text changes. Behavior with Vietnamese IME, Chinese/Japanese composition, marked text, emoji sequences, and UTF-16 boundary edits has not been validated.

## 10. Performance debt

### P-001 — Text-view count scales with document structure

Approximate editor count is:

`text blocks + list items + task blocks + code blocks + table cells`

A 20×10 table adds 210 text views including its header, before counting the rest of the note. This is not an acceptable scaling model.

### P-002 — Main-actor parse and serialize

`BlockEditorModel` is `@MainActor`; parsing in initialization/reload and serialization in flush/debounce therefore occupy the UI executor. Large notes can delay opening, animation, typing, and switching.

### P-003 — Duplicate save pipelines

- `BlockEditorModel`: approximately 300 ms debounce, then serialization.
- `NoteEditorView`: approximately 250 ms debounce, then `AppModel.updateContent`.
- Library: draft changes call `AppModel.updateBody`.
- Repository upsert reloads and republishes the full note collection.

These layers need one owner and one backpressure policy.

### P-004 — Broad model publication

Every repository publish yields the full `[Note]` array. `AppModel.notes` changes can invalidate computed `activeNotes`, Deck content, Library search results, note previews, and editor-derived properties.

### P-005 — Code styling work is not incremental

The complete attributed string/code block is restyled and highlighted after edits. Large code blocks will have input latency.

### P-006 — Image work is synchronous and not downsampled

`NSImage(contentsOf:)` is called from rendering paths. Full-size images can cause main-thread I/O, decoding cost, and excessive memory.

### P-007 — Selection workaround is O(n) per update

It enumerates registered views, converts frames, finds a nearest destination, computes ordered surfaces, and sets ranges across blocks while dragging.

### P-008 — No performance budgets or trace baseline

There are no documented thresholds for note-open latency, first-keystroke latency, sustained typing, scroll frame rate, memory, table scaling, or Deck animation frame time.

## 11. State, persistence, and data-loss risks

### S-001 — Last-writer-wins across simultaneous surfaces

The same note can potentially be visible in Deck and Library. Each surface can hold its own draft/editor document. No edit-session version or merge/conflict strategy exists.

### S-002 — Save ordering around teardown is fragile

Child editor flush, parent `onDisappear`, delayed save tasks, repository publication, and selection changes can occur close together. Generation checks reduce focus risk but do not define persistence ordering.

### S-003 — Errors are often suppressed

Several import/export/file/database-adjacent operations use `try?` or print-only errors. Users may believe data was saved/exported when it was not.

### S-004 — Attachment lifecycle is incomplete

- No reference counting or garbage collection for deleted image attachments.
- No missing-file recovery workflow.
- No remote image cache policy.
- No export/archive guarantee that attachment files travel with Markdown.
- Filename-only storage needs an explicit portability contract.

### S-005 — Canonical serialization can rewrite untouched content

Opening and saving a note can normalize or lose unsupported Markdown even when the user edits an unrelated block.

### S-006 — Corrupt database/note startup behavior needs product handling

Repository initialization can terminate the app through `fatalError`; corrupt encrypted note handling can fail a load. Recovery/export/support behavior is not defined.

## 12. Dependency and library audit

### D-001 — `swift-markdown-engine` remains both useful and incompatible with the exact goal

Useful capabilities:

- Native macOS/TextKit 2 foundation.
- Existing Markdown styling/input behavior.
- Code highlighting bridge.
- LaTeX renderer with caching.
- Embedded image service.

Goal mismatch/limitations:

- Raw Markdown remains the stored/editable text surface.
- Presentation can expose tokens or change on focus.
- Its table implementation is rendered as an image/attachment rather than an editable native cell grid.
- It is not a Notion-style semantic block editor API.

Decision required: fork/extend its single-text-system implementation, or replace it. Using it only as a bag of renderer bridge types creates coupling without resolving the editor architecture.

### D-002 — Direct `swift-markdown` adds a second parser stack

- Adds `Markdown` 0.8.0.
- Adds transitive `swift-cmark`/GFM C targets.
- Increases dependency resolution, compile/link surface, binary/license review work, and parser semantic divergence.
- It is suitable for AST parsing, but does not supply a WYSIWYG editing projection, selection model, serializer fidelity policy, or table cell editor.

### D-003 — No direct package-version conflict is currently demonstrated

`swift-markdown-engine` core has no Markdown parser package dependency and its optional products bring `HighlighterSwift` and `SwiftMath`. `swift-markdown` independently brings `swift-cmark`. The issue is duplicated responsibility/weight, not a proven SwiftPM version collision.

### D-004 — Renderer dependencies are transitively coupled through MarkdownEngine

The experimental editor imports `MarkdownEngine`, `MarkdownEngineCodeBlocks`, and `MarkdownEngineLatex` for types/bridges while bypassing the engine editor itself. If the engine is removed, the project must either depend directly on `HighlighterSwift`/`SwiftMath` or provide internal renderer abstractions.

### D-005 — Third-party notice coverage is incomplete/unverified

`THIRD-PARTY-NOTICES.txt` currently lists only Noty. Before distribution, verify and include notices/licenses required for all linked dependencies, including MarkdownEngine, HighlighterSwift, SwiftMath, swift-markdown, and swift-cmark. This document does not assert a legal violation; it records an unresolved compliance task.

### D-006 — Dependency strategy is not documented

There is no ADR defining which library owns parsing, editing, syntax highlighting, math rendering, and Markdown serialization. Without that ownership map, overlapping libraries will continue accumulating.

## 13. Library and Deck integration debt

### L-001 — Library was redesigned during editor work

Search placement, detail state ownership, toolbar placement, actions, and editor controls changed in the same patch as the editor. Some requested layout corrections may be directionally valid, but bundling them obscures regression sources and lacks design review.

### L-002 — Editor tools route through global first responder

Sticky formatting controls are visually separated from content, but command routing is not session-safe. Opening menus/popovers or using multiple windows can leave no valid target.

### L-003 — Nested scrolling modes need one owner

Library uses an outer `ScrollView` and configures `BlockEditorView(scrolls: false)`. The legacy engine requires `.fitsContent` in this context. The unified design must explicitly support embedded/non-scrolling and standalone/scrolling hosts without nested scroll views or zero-height collapse.

### L-004 — Deck animation shares main actor with editor startup

Even though `NoteFan.swift` and `NoteTab.swift` currently have no diff, constructing/parsing a heavy editor during the opening transition can degrade the animation. This is integration coupling, not necessarily a defect in NoteFan itself.

### L-005 — No lightweight transition state

There is no measured strategy for when the editor session is prepared relative to Deck animation. Any deferred loading must avoid visible content replacement and must be evidence-driven, not an arbitrary sleep.

## 14. Accessibility, international input, and platform behavior debt

- No document-level accessibility model across block views.
- Cross-block selected range is not exposed as one accessibility selection.
- Table headers/cells lack audited VoiceOver navigation and row/column announcements.
- Images need alt-text accessibility labels and an editing workflow.
- Math needs a readable accessibility representation, not only an image.
- Keyboard-only traversal into/out of table and attachments is incomplete.
- Full Keyboard Access behavior is unverified.
- Vietnamese/Chinese/Japanese/Korean IME marked-text behavior is unverified.
- RTL layout and mixed-direction text are unverified.
- Grapheme clusters versus UTF-16 offset transformations require explicit validation.
- Dynamic font changes and custom font fallback are unverified for selection/caret geometry.
- High Contrast, Reduce Motion, Increase Contrast, and dark appearance behavior are unverified.

## 15. Validation and process debt

### V-001 — Project rules currently prohibit tests

`AGENTS.md` says not to add, modify, or run unit tests and treats successful compilation as validation. That may be acceptable for constrained code-edit automation, but it is not sufficient to ship a parser/serializer/editor.

Before product release, a human owner must explicitly revise or supplement this policy so the project can validate:

- Markdown fixtures and semantic round-trip.
- Range transformations under edits.
- Split/merge/list/table commands.
- Undo/redo transactions.
- Persistence ordering and conflicting sessions.
- Crash regressions.

Until the rule changes, automated test tasks below are documented but must not be executed by an agent.

### V-002 — No reproducible crash artifact

The supplied console output contained ViewBridge and toolbar constraint warnings but no exception backtrace, crash report, or Thread Sanitizer result. A real crash report and exact reproduction must be captured.

### V-003 — No performance evidence

There is no before/after Time Profiler, SwiftUI Instruments, hangs trace, allocations trace, signpost timing, or release-build measurement.

### V-004 — Debug compile is the only completed gate

The macOS target compiled with code signing disabled. This does not validate signed launch, sandbox behavior, attachment permissions, release optimization, app notarization, or runtime UX.

## 16. Target architecture

### 16.1 Core rule

One note editing session owns exactly one primary `NSTextView` and one TextKit text system.

### 16.2 Text representation

- Paragraph, H1–H6, quote, list item, task text, and editable code live in one attributed text storage.
- Paragraph-level attributes describe semantic block kind, indentation, list marker, task state, code language, and stable session block identity.
- Inline attributes describe bold, italic, strikethrough, underline extension, link metadata, inline code, and inline math attachment metadata.
- Newline/paragraph separators are real document characters, so AppKit selection naturally crosses text blocks.

### 16.3 Non-text blocks

- Image, display math, table, and thematic break occupy attachment/object-replacement positions in the unified text storage.
- Document selection treats each attachment atomically.
- Clicking an editable attachment starts a scoped child editing session.
- Table cells may use child text views, but they are not pretending to be part of the primary native selection. Entry/exit, copy, undo, and arrow rules are explicit.

### 16.4 Source of truth and persistence

- During editing: unified attributed document/session model is authoritative.
- On load: Markdown is parsed once into the editing projection.
- During typing: apply range-local mutations; do not serialize/reparse.
- On autosave: snapshot the session revision and serialize outside the input-critical path.
- On repository publication: ignore self-originated versions; detect external conflicting versions.
- On close: flush the latest revision deterministically once.

### 16.5 Command routing

- Toolbar receives an explicit `EditorSession`/command target.
- No `NSApp.keyWindow` lookup for ordinary formatting commands.
- Commands report supported/unsupported state and toolbar reflects mixed selection state.

### 16.6 Dependency boundary

- One component owns Markdown parsing/serialization.
- Syntax highlighting and math rendering sit behind small internal protocols.
- Decide explicitly whether to fork `swift-markdown-engine` or build the unified TextKit layer in-app.
- Remove unused package products after migration; do not keep both full editor paths indefinitely.

## 17. Recovery plan — smallest independently verifiable tasks

No phase may be declared complete solely because it compiles.

### Phase 0 — Contain the regression

- [ ] R-0001: Tag or commit the last known stable pre-block-editor state for comparison.
- [ ] R-0002: Record the exact current working-tree patch separately; experimental BlockEditor files are currently untracked.
- [ ] R-0003: Add a runtime feature boundary between legacy and experimental editor without changing Deck layout.
- [ ] R-0004: Ensure the default release path uses only the last manually verified editor.
- [ ] R-0005: Remove cross-block mouse monitor/gesture code from the release path.
- [ ] R-0006: Confirm `NoteFan.swift` and `NoteTab.swift` remain byte-for-byte unchanged during editor recovery.
- [ ] R-0007: Capture a screen recording and reproduction steps for current selection failure.
- [ ] R-0008: Capture the actual crash report for edit-then-switch-tab.
- [ ] R-0009: Capture Debug and Release baselines for note-open latency and Deck transition frame time.
- [ ] R-0010: Back up a corpus of real Markdown notes before testing serializers.

### Phase 1 — Make architectural decisions with prototypes

- [ ] R-0101: Write ADR: semantic round-trip versus byte-for-byte Markdown preservation.
- [ ] R-0102: Write ADR: fork/extend MarkdownEngine versus internal unified TextKit editor.
- [ ] R-0103: Prototype one `NSTextView` containing differently styled paragraph kinds.
- [ ] R-0104: Verify native drag selection across at least 100 paragraphs in the prototype.
- [ ] R-0105: Verify native `Cmd+A`, copy, cut, replace typing, undo, redo, and find across those paragraphs.
- [ ] R-0106: Verify Vietnamese IME composition in styled ranges.
- [ ] R-0107: Prototype one atomic image attachment in the same text storage.
- [ ] R-0108: Prototype one display-math attachment with an edit overlay.
- [ ] R-0109: Prototype one table attachment with entry/exit to a cell editor.
- [ ] R-0110: Measure prototypes before selecting architecture.
- [ ] R-0111: Record the dependency ownership map in the ADR.
- [ ] R-0112: Obtain explicit design approval before integrating Library or Deck.

### Phase 2 — Define the document contract

- [ ] R-0201: Define supported Markdown dialect and extension list.
- [ ] R-0202: Define underline storage/interoperability policy.
- [ ] R-0203: Define inline/display math delimiter policy.
- [ ] R-0204: Define remote versus local image URL policy.
- [ ] R-0205: Define unsupported-node preservation policy.
- [ ] R-0206: Define whitespace/canonicalization policy.
- [ ] R-0207: Define block/session identity and reconciliation rules.
- [ ] R-0208: Define `DocumentPosition` independent of `NSTextView` instances.
- [ ] R-0209: Define attachment atomic-selection behavior.
- [ ] R-0210: Define table cell selection versus document selection behavior.
- [ ] R-0211: Define one edit-session version and conflict model.
- [ ] R-0212: Define one autosave owner and flush contract.

### Phase 3 — Build the unified TextKit foundation

- [ ] R-0301: Create the single TextKit editor shell with one scroll owner.
- [ ] R-0302: Add a document-level attributed-string builder.
- [ ] R-0303: Add paragraph semantic attributes.
- [ ] R-0304: Add inline semantic attributes.
- [ ] R-0305: Add source/model range mapping.
- [ ] R-0306: Render paragraphs without Markdown tokens.
- [ ] R-0307: Render H1–H6 using paragraph attributes.
- [ ] R-0308: Render quotes using paragraph styling/custom layout drawing.
- [ ] R-0309: Render unordered list markers without storing visible Markdown markers.
- [ ] R-0310: Render ordered list markers with stable renumbering rules.
- [ ] R-0311: Render task checkboxes as semantic controls/attachments.
- [ ] R-0312: Render code block background and language metadata in the unified layout.
- [ ] R-0313: Implement range-local restyling after edits.
- [ ] R-0314: Preserve marked text during IME composition.
- [ ] R-0315: Expose one native document selection.
- [ ] R-0316: Expose selection state to toolbar without global first-responder lookup.
- [ ] R-0317: Implement standalone scrolling host.
- [ ] R-0318: Implement embedded/fits-content host without nested scrolling.

### Phase 4 — Editing semantics

- [ ] R-0401: Enter splits paragraph at selection/caret.
- [ ] R-0402: Enter at heading end creates the documented next block type.
- [ ] R-0403: Enter in empty list item exits list.
- [ ] R-0404: Enter in non-empty list item creates the next item.
- [ ] R-0405: Tab/Shift-Tab indent and outdent list items.
- [ ] R-0406: Backspace at paragraph start merges with previous compatible block.
- [ ] R-0407: Backspace adjacent to attachment selects/removes it atomically.
- [ ] R-0408: Forward Delete at block boundary follows symmetric rules.
- [ ] R-0409: Arrow movement uses native TextKit ranges across text blocks.
- [ ] R-0410: Arrow movement enters/exits attachments according to the contract.
- [ ] R-0411: Bold supports empty caret, range, and mixed state.
- [ ] R-0412: Italic supports empty caret, range, and mixed state.
- [ ] R-0413: Strikethrough supports empty caret, range, and mixed state.
- [ ] R-0414: Underline supports empty caret, range, and mixed state.
- [ ] R-0415: Inline code supports empty caret, range, and escaping.
- [ ] R-0416: Link creation/edit/removal has a destination UI and validation.
- [ ] R-0417: Formatting across multiple paragraphs preserves block semantics.
- [ ] R-0418: All structural and inline commands register cohesive undo operations.
- [ ] R-0419: Find/replace covers the entire note.
- [ ] R-0420: Dictation integrates with unified ranges and undo.

### Phase 5 — Parser/serializer correctness

- [ ] R-0501: Create a fixture inventory for every supported construct.
- [ ] R-0502: Preserve paragraph and hard/soft break semantics.
- [ ] R-0503: Preserve H1–H6.
- [ ] R-0504: Preserve nested block quotes.
- [ ] R-0505: Preserve nested lists and continuation blocks.
- [ ] R-0506: Preserve unordered marker policy as defined by ADR.
- [ ] R-0507: Preserve ordered-list start numbers.
- [ ] R-0508: Preserve task states and nesting.
- [ ] R-0509: Preserve fenced code language and fence-safe content.
- [ ] R-0510: Parse/serialize inline images and image-only blocks.
- [ ] R-0511: Parse/serialize local attachments and remote URLs.
- [ ] R-0512: Parse/serialize table alignment and escaped pipes.
- [ ] R-0513: Define and implement multiline table cell policy.
- [ ] R-0514: Parse/serialize inline math without misreading currency/escapes.
- [ ] R-0515: Parse/serialize display math and malformed delimiters safely.
- [ ] R-0516: Normalize overlapping inline annotations deterministically.
- [ ] R-0517: Escape all supported contexts correctly.
- [ ] R-0518: Preserve unsupported nodes according to ADR.
- [ ] R-0519: Ensure unrelated edits do not rewrite unsupported source regions.
- [ ] R-0520: Fuzz malformed Markdown and guarantee no crash/data truncation.

### Phase 6 — Attachments and tables

- [ ] R-0601: Implement async image load.
- [ ] R-0602: Downsample images to display size.
- [ ] R-0603: Add memory/disk image cache policy.
- [ ] R-0604: Add missing-image placeholder and relink action.
- [ ] R-0605: Add alt-text edit UI and accessibility label.
- [ ] R-0606: Add remote image security/privacy policy.
- [ ] R-0607: Implement display-math attachment rendering cache.
- [ ] R-0608: Implement stable display-math edit overlay without replacing document identity.
- [ ] R-0609: Add accessible plain-text/math representation.
- [ ] R-0610: Implement table attachment layout.
- [ ] R-0611: Implement cell editor activation/deactivation.
- [ ] R-0612: Implement cell arrow navigation.
- [ ] R-0613: Implement add/remove row.
- [ ] R-0614: Implement add/remove column.
- [ ] R-0615: Implement column alignment controls.
- [ ] R-0616: Implement row/column reorder if in product scope.
- [ ] R-0617: Implement table copy/paste as TSV and Markdown.
- [ ] R-0618: Implement table/document undo transaction integration.
- [ ] R-0619: Define document selection passing over a table attachment.
- [ ] R-0620: Verify large-table performance limits and graceful degradation.

### Phase 7 — Persistence and concurrency

- [ ] R-0701: Remove duplicate editor/view autosave timers.
- [ ] R-0702: Add one revisioned autosave coordinator.
- [ ] R-0703: Serialize a value snapshot off the input-critical path.
- [ ] R-0704: Ignore self-originated repository snapshots safely.
- [ ] R-0705: Detect simultaneous Library/Deck edits to the same note.
- [ ] R-0706: Define conflict UI or single-session enforcement.
- [ ] R-0707: Make close/switch flush deterministic.
- [ ] R-0708: Surface persistence failures to the user.
- [ ] R-0709: Make import/export failures visible and recoverable.
- [ ] R-0710: Include attachment assets in archive/export policy.
- [ ] R-0711: Add orphan attachment cleanup with a recoverable grace period.
- [ ] R-0712: Replace avoidable force unwrap/fatal startup paths with recovery UI.

### Phase 8 — Library and Deck integration

- [ ] R-0801: Freeze Deck animation code during editor integration.
- [ ] R-0802: Keep search physically in the Library sidebar.
- [ ] R-0803: Keep editor actions/tools in an approved sticky header.
- [ ] R-0804: Keep note content as the only scrolling content region.
- [ ] R-0805: Route toolbar commands to an explicit editor session.
- [ ] R-0806: Initialize the editor session without parsing twice.
- [ ] R-0807: Prevent repository autosave publication from invalidating unrelated NoteFan subtrees.
- [ ] R-0808: Measure Deck transition with an empty note.
- [ ] R-0809: Measure Deck transition with a large text note.
- [ ] R-0810: Measure Deck transition with images, math, code, and tables.
- [ ] R-0811: Verify switching notes while composing IME text.
- [ ] R-0812: Verify switching notes during pending autosave.
- [ ] R-0813: Verify Library and Deck showing the same note.
- [ ] R-0814: Verify closing/deleting/archiving the active note.

### Phase 9 — Performance and accessibility gates

- [ ] R-0901: Add signposts for session creation, parse, projection, first layout, and save.
- [ ] R-0902: Define target p50/p95 note-open latency.
- [ ] R-0903: Define target keystroke-to-frame latency.
- [ ] R-0904: Define target Deck transition frame budget.
- [ ] R-0905: Define target scroll frame rate and hitch threshold.
- [ ] R-0906: Define memory limits for large notes/images/tables.
- [ ] R-0907: Profile a release build with Time Profiler.
- [ ] R-0908: Profile SwiftUI invalidations.
- [ ] R-0909: Profile allocations/leaks across repeated note switching.
- [ ] R-0910: Profile image decode/memory pressure.
- [ ] R-0911: Audit VoiceOver reading and selection.
- [ ] R-0912: Audit keyboard-only editing.
- [ ] R-0913: Audit IME languages and emoji/grapheme behavior.
- [ ] R-0914: Audit RTL and mixed-direction text.
- [ ] R-0915: Audit accessibility appearance settings.

### Phase 10 — Dependency cleanup and release

- [ ] R-1001: Remove the rejected editor implementation after the replacement passes gates.
- [ ] R-1002: Remove the unused Markdown parser/editor package path.
- [ ] R-1003: Depend directly on renderer libraries only if still required.
- [ ] R-1004: Lock and document package versions/update policy.
- [ ] R-1005: Complete third-party license/notice review.
- [ ] R-1006: Remove dual-path concrete checks from `EditorBridge`.
- [ ] R-1007: Remove dead commands, adapters, and feature flags.
- [ ] R-1008: Build Debug and Release targets.
- [ ] R-1009: Validate signed sandboxed application behavior.
- [ ] R-1010: Run the complete manual regression matrix.
- [ ] R-1011: Run automated parser/editor tests only after project policy explicitly permits them.
- [ ] R-1012: Confirm no P0/P1 issues remain open.

## 18. Mandatory acceptance criteria

The editor is not shippable until all of these are demonstrated:

### Selection and input

- One native selection can be dragged continuously through all text blocks.
- Selection updates live while dragging and autoscrolls.
- `Cmd+A`, copy, cut, delete, replacement typing, undo, and redo operate on the same range.
- Double-click, triple-click, Shift-click, Shift-arrow, Option-arrow, and Command-arrow match macOS conventions.
- Selection clears/dims correctly when focus/window changes.
- IME marked text remains intact.
- Opening editor controls does not clear or replace the active selection.
- Inline formatting applies to the exact selected range, including multi-paragraph ranges.
- Enter never duplicates or drops content when splitting text, code-adjacent content, lists, or tasks.
- Multiline code paste works immediately and survives save/reopen.
- List markers use correct hanging indentation and remain visually adjacent to text.

### Data safety

- Supported Markdown constructs survive the declared round-trip contract.
- Unsupported constructs follow the declared preservation policy.
- Switching/closing during autosave never loses or cross-writes note content.
- Simultaneous note surfaces have a defined conflict policy.
- Persistence/export failures are visible.

### Performance

- One primary text system per note.
- Text-system count does not scale with paragraph/list-item count.
- Opening the editor does not regress Deck animation beyond the agreed budget.
- Typing remains responsive in the agreed large-note/code/table fixtures.
- Images are decoded/downsampled outside the critical render path.
- No unbounded caches, event monitors, tasks, or view registries survive session teardown.

### Product behavior

- No raw Markdown tokens appear during normal WYSIWYG editing except in an explicit source-edit mode.
- Library search stays in the left pane.
- Actions and editor options remain in the approved sticky header.
- Note content scrolls independently of the sticky header.
- Table cells are directly editable with predictable keyboard navigation.
- Image, code, inline math, display math, task, and link workflows are complete.

### Release quality

- No reproducible crash in open/edit/switch/close/delete/archive flows.
- No unresolved P0/P1 issue.
- Dependency ownership and licenses are documented.
- Debug, Release, signed sandbox, accessibility, and manual regression gates pass.
- Compile success alone is never recorded as feature completion.

## 19. Explicit non-goals for interim patches

Until the unified architecture is approved and proven, do not:

- Add another gesture/event-monitor workaround for cross-block selection.
- Add more per-block `NSTextView` types.
- Add cursor-navigation special cases between text blocks.
- Claim selection is fixed based on compilation.
- Change NoteFan/NoteTab animation to hide editor startup cost.
- Add arbitrary delays to make transitions appear smoother.
- Reparse self-emitted Markdown on each edit.
- Route new editor commands through global key-window lookup.
- Expand Library/Deck layout changes without explicit design approval.
- Remove the stable editor path before data fidelity and performance gates pass.

## 20. Recommended immediate decision

The next engineering action should be an architecture prototype, not another production patch:

1. Keep Deck code frozen.
2. Build a standalone unified TextKit prototype with 100 styled paragraphs.
3. Prove native selection, clipboard, undo, IME, and performance.
4. Add one image attachment and one table attachment prototype.
5. Compare extending/forking MarkdownEngine against an internal unified editor using measured evidence.
6. Only after the ADR is accepted, implement the recovery phases above.

This is the shortest path that addresses the actual failure rather than concealing it with additional workarounds.
