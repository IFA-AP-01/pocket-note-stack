//
//  Pocket_StackTests.swift
//  Pocket StackTests
//
//  Created by Huy Huỳnh on 1/9/26.
//

import AppKit
import AVFoundation
import Testing
@testable import Pocket_Stack

struct Pocket_StackTests {
    @Test func noteDerivesTitlePreviewAndTasks() {
        let note = Note(body: "# Weekly plan\n☑ Ship build\n☐ Write docs")
        #expect(note.title == "Weekly plan")
        #expect(note.preview.contains("Ship build"))
        #expect(note.taskProgress?.done == 1)
        #expect(note.taskProgress?.total == 2)
    }

    @Test func taskMarkdownRoundTrip() {
        let markdown = "- [ ] First\n- [x] Second"
        let internalText = NoteTask.fromMarkdown(markdown)
        #expect(internalText == "☐ First\n☑ Second")
        #expect(NoteTask.toMarkdown(internalText) == markdown)
    }

    @Test func encryptedRepositoryRoundTripDoesNotLeakBody() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("notes.sqlite3")
        let cipher = BodyCipher(rawKey: Data(repeating: 0x7a, count: 32))
        let repository = try SQLiteNoteRepository(url: databaseURL, cipher: cipher)
        let secret = "unique-plaintext-voice-note-73c18d"
        let note = Note(body: secret, colorIndex: 3, customColorHex: "5A7DE1")

        try await repository.upsert(note)
        let loaded = try await repository.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.body == secret)
        #expect(loaded.first?.customColorHex == "5A7DE1")
        let bytes = try Data(contentsOf: databaseURL)
        #expect(bytes.range(of: Data(secret.utf8)) == nil)
    }

    @Test @MainActor func editorDictationReplacesSelectionAndCommitsFinal() {
        let textView = NSTextView()
        textView.string = "Hello old world"
        textView.setSelectedRange(NSRange(location: 6, length: 3))
        let bridge = EditorBridge()
        bridge.textView = textView

        bridge.beginDictation()
        #expect(textView.isEditable == false)
        bridge.applyInterim("new")
        #expect(textView.string == "Hello new world")
        bridge.applyInterim("fresh")
        #expect(textView.string == "Hello fresh world")
        bridge.commitFinal("final")
        bridge.finishDictation(discardInterim: true)
        #expect(textView.string == "Hello final  world")
        #expect(textView.isEditable)
    }

    @Test func pcmEncoderProducesOneHundredMillisecondChunks() {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800)!
        buffer.frameLength = 4_800
        for channel in 0..<2 {
            for frame in 0..<4_800 { buffer.floatChannelData![channel][frame] = 0.25 }
        }
        let chunks = PCM16StreamEncoder().encode(buffer)
        #expect(chunks.count == 1)
        #expect(chunks.first?.count == 3_200)
    }
}
