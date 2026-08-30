import AppKit
import SwiftUI

@MainActor
final class PinMetadataEditorController: NSObject, NSWindowDelegate {
    private var windowController: NSWindowController?
    private var onSave: ((PinMetadata) -> Void)?

    func present(initial: PinMetadata, onSave: @escaping (PinMetadata) -> Void) {
        self.onSave = onSave

        let rootView = PinMetadataEditorView(
            initial: initial,
            save: { [weak self] note, rawTags in
                self?.save(note: note, rawTags: rawTags)
            },
            cancel: { [weak self] in
                self?.cancel()
            }
        )

        let controller: NSWindowController
        if let existingController = windowController, let window = existingController.window {
            window.contentViewController = NSHostingController(rootView: rootView)
            controller = existingController
        } else {
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 520, height: 380),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.text("pin.metadata.editor.title")
            window.minSize = CGSize(width: 480, height: 340)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentViewController = NSHostingController(rootView: rootView)
            window.center()

            controller = NSWindowController(window: window)
            windowController = controller
        }

        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === windowController?.window else { return }
        onSave = nil
    }

    private func save(note: String, rawTags: String) -> String? {
        do {
            let metadata = try PinMetadata.validated(
                note: note,
                tags: Self.parseTags(rawTags)
            )
            let saveAction = onSave
            onSave = nil
            windowController?.close()
            saveAction?(metadata)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func cancel() {
        onSave = nil
        windowController?.close()
    }

    private static func parseTags(_ rawTags: String) -> [String] {
        rawTags.components(separatedBy: CharacterSet(charactersIn: ",，\n\r"))
    }
}

private struct PinMetadataEditorView: View {
    @State private var note: String
    @State private var rawTags: String
    @State private var validationError: String?

    let save: (String, String) -> String?
    let cancel: () -> Void

    init(
        initial: PinMetadata,
        save: @escaping (String, String) -> String?,
        cancel: @escaping () -> Void
    ) {
        _note = State(initialValue: initial.note)
        _rawTags = State(initialValue: initial.tags.joined(separator: ", "))
        self.save = save
        self.cancel = cancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("pin.metadata.editor.note"))
                    .font(.headline)
                TextEditor(text: $note)
                    .font(.body)
                    .padding(4)
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
                    .accessibilityLabel(L10n.text("pin.metadata.editor.note"))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("pin.metadata.editor.tags"))
                    .font(.headline)
                TextField(
                    L10n.text("pin.metadata.editor.tagsPlaceholder"),
                    text: $rawTags,
                    axis: .vertical
                )
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(L10n.text("pin.metadata.editor.tags"))
                Text(L10n.text("pin.metadata.editor.tagsHelp"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let validationError {
                Text(validationError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityLabel(
                        L10n.text("pin.metadata.editor.validationError", validationError)
                    )
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(L10n.text("common.cancel"), action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(L10n.text("common.cancel"))
                Button(L10n.text("common.save"), action: saveChanges)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel(L10n.text("common.save"))
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 340)
    }

    private func saveChanges() {
        validationError = save(note, rawTags)
    }
}
