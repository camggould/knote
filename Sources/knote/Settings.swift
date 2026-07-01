import AppKit
import SwiftUI
import Carbon.HIToolbox

/// A "click to record" shortcut field. While recording it captures keys via a
/// local event monitor (not the first-responder chain, which routes unreliably
/// through SwiftUI's hosting view), so the keystroke is caught regardless of focus.
final class KeyRecorderView: NSView {
    var onCapture: ((Hotkey) -> Void)?
    var onBeginRecording: (() -> Void)?
    var onEndRecording: (() -> Void)?
    var currentLabel: String = "" { didSet { needsDisplay = true } }

    private var recording = false { didSet { needsDisplay = true } }
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 170, height: 28) }

    override func mouseDown(with event: NSEvent) {
        recording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard monitor == nil else { return }
        recording = true
        window?.makeFirstResponder(self)
        onBeginRecording?()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Esc (no hard modifier) cancels.
            if event.keyCode == UInt32(kVK_Escape),
               event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
                self.stopRecording()
                return nil
            }
            if let hk = Hotkey(event: event) {
                self.onCapture?(hk)
                self.stopRecording()
            } else {
                NSSound.beep() // needs a Cmd/Opt/Ctrl (or a function key)
            }
            return nil // consume — don't let the combo leak into the UI
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        onEndRecording?()
    }

    override func resignFirstResponder() -> Bool {
        if recording { stopRecording() }
        return true
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15)
                   : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = recording ? 2 : 1
        path.stroke()

        let text = recording ? "Type shortcut… (⎋ cancels)" : currentLabel
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor,
            .paragraphStyle: style,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let rect = NSRect(x: bounds.minX, y: bounds.midY - size.height / 2,
                          width: bounds.width, height: size.height)
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }
}

struct KeyRecorder: NSViewRepresentable {
    var label: String
    var onCapture: (Hotkey) -> Void
    var onBeginRecording: () -> Void = {}
    var onEndRecording: () -> Void = {}

    func makeNSView(context: Context) -> KeyRecorderView {
        let v = KeyRecorderView()
        v.currentLabel = label
        v.onCapture = onCapture
        v.onBeginRecording = onBeginRecording
        v.onEndRecording = onEndRecording
        return v
    }

    func updateNSView(_ v: KeyRecorderView, context: Context) {
        v.currentLabel = label
        v.onCapture = onCapture
        v.onBeginRecording = onBeginRecording
        v.onEndRecording = onEndRecording
    }
}

struct SettingsView: View {
    @ObservedObject var hotkeys: HotkeyController
    let encoderName: String

    @State private var mcpStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("knote Settings").font(.title2).bold()

            HStack {
                Text("Global shortcut").frame(width: 120, alignment: .leading)
                KeyRecorder(
                    label: hotkeys.hotkey.label,
                    onCapture: { hotkeys.update(to: $0) },
                    onBeginRecording: { hotkeys.suspend() },
                    onEndRecording: { hotkeys.resume() })
                    .frame(width: 170, height: 28)
                Button("Reset") { hotkeys.resetToDefault() }
                Spacer()
            }

            if let err = hotkeys.errorMessage {
                Text(err).font(.callout).foregroundStyle(.red)
            } else {
                Text("Click the field, then press the combination you want. Include ⌘, ⌥, or ⌃.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text("Search model").frame(width: 120, alignment: .leading)
                Text(encoderName).foregroundStyle(.secondary)
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Connect an AI assistant (MCP)").font(.headline)

                Text(MCPIntegration.helperPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Button("Add to Codex") {
                        mcpStatus = nil
                        switch MCPIntegration.addToCodex() {
                        case .added:
                            mcpStatus = "Added to Codex — restart Codex to pick it up."
                        case .alreadyPresent:
                            mcpStatus = "Already configured."
                        case .failed(let msg):
                            mcpStatus = "Error: \(msg)"
                        case .needsManual:
                            break
                        }
                    }

                    Button("Add to Claude Code") {
                        mcpStatus = nil
                        switch MCPIntegration.addToClaudeCode() {
                        case .added:
                            mcpStatus = "Added to Claude Code."
                        case .alreadyPresent:
                            mcpStatus = "Already configured."
                        case .needsManual:
                            mcpStatus = "Claude CLI not found — command copied; run it in your terminal."
                        case .failed(let msg):
                            mcpStatus = "Error: \(msg)"
                        }
                    }

                    Button("Copy Codex config") {
                        MCPIntegration.copyCodexSnippet()
                        mcpStatus = "Codex TOML snippet copied to clipboard."
                    }

                    Spacer()
                }

                if let status = mcpStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 440, height: 380)
    }
}

/// Lazily builds and shows the Settings window; keeps it alive across closes.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let hotkeys: HotkeyController
    private let encoderName: String

    init(hotkeys: HotkeyController, encoderName: String) {
        self.hotkeys = hotkeys
        self.encoderName = encoderName
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            w.title = "knote Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(
                rootView: SettingsView(hotkeys: hotkeys, encoderName: encoderName))
            w.center()
            window = w
        }
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
        window?.makeKey()
    }
}
