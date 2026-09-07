//
//  Pocket_StackApp.swift
//  Pocket Stack
//
//  Created by Huy Huỳnh on 1/9/26.
//

import SwiftUI

@main
struct Pocket_StackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let environment = AppEnvironment.shared

    var body: some Scene {
        MenuBarExtra {
            PocketStackMenuContent(environment: environment)
        } label: {
            PocketStackMenuBarLabel()
        }
        .menuBarExtraStyle(.menu)

        Window("Settings", id: "settings") {
            SettingsView(preferences: environment.preferences, environment: environment)
                .background(SettingsWindowRegistration().frame(width: 0, height: 0))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 760, height: 580)
    }
}

private struct PocketStackMenuContent: View {
    let environment: AppEnvironment
    @ObservedObject private var dictation: DictationCoordinator

    init(environment: AppEnvironment) {
        self.environment = environment
        self._dictation = ObservedObject(wrappedValue: environment.dictation)
    }

    var body: some View {
        if dictation.isRecording {
            Button {
                environment.noteWindows.stopDictation()
            } label: {
                Label("Stop Dictation", systemImage: "stop.fill")
            }
            .keyboardShortcut(".", modifiers: [.command])

            Divider()
        }

        Button("New Note", systemImage: "square.and.pencil") {
            environment.deckCoordinator.createAndExpand()
        }
        .keyboardShortcut("n", modifiers: [.command, .option])

        Button("All Notes", systemImage: "note.text") {
            environment.libraryWindow.show(archive: false)
        }
        Button("Archive", systemImage: "archivebox") {
            environment.libraryWindow.show(archive: true)
        }

        Divider()

        PocketStackSettingsButton {
            Label("Settings…", systemImage: "gearshape")
        }

        Divider()

        Button("Quit Pocket Stack", systemImage: "power") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
