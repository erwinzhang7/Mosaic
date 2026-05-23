import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click "Record" → press a combo → it's captured, validated, and live-bound.
///
/// Implementation note for testing: the recorder listens via
/// `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`, so the Settings
/// window must be **key** (frontmost-focused window) for capture to work. If
/// you click into another window mid-recording, the monitor stops seeing
/// events — cancel and try again. While recording, every keyDown event is
/// swallowed so common shortcuts (⌘W, ⌘Q) are temporarily disarmed; this is
/// intentional so you can capture them as a hotkey. The Carbon hotkey itself
/// is temporarily unregistered during recording so the user can re-bind the
/// same combo without it firing the overlay.
struct HotKeyRecorder: View {
    @Bindable private var layout = LayoutStore.shared
    @State private var isRecording = false
    @State private var lastError: String?
    @State private var monitor = MonitorHolder()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(action: toggleRecording) {
                    Text(buttonLabel)
                        .font(.body.monospaced())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(minWidth: 200, alignment: .center)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    isRecording ? Color.accentColor : Color.gray.opacity(0.45),
                                    lineWidth: isRecording ? 2 : 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .help(isRecording ? "Press a combo, or Esc to cancel." : "Click to record a new combo.")

                Button("Reset to Default") {
                    apply(.default)
                }
                .disabled(layout.state.summonHotKey == .default && !isRecording)
            }

            if let error = lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear {
            // If Settings closes mid-recording, cancel cleanly so we don't
            // leave the user with no hotkey and a dangling event monitor.
            if isRecording { cancelRecording() }
        }
    }

    private var buttonLabel: String {
        if isRecording { return "Press combo… (Esc to cancel)" }
        return layout.state.summonHotKey.displayString
    }

    // MARK: Recording lifecycle

    private func toggleRecording() {
        if isRecording {
            cancelRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        lastError = nil
        isRecording = true
        // Temporarily release the Carbon hotkey so the user can press it
        // (or anything else) without triggering the overlay mid-record.
        HotKeyManager.shared.uninstall()
        monitor.start { event in handle(event) }
    }

    private func cancelRecording() {
        monitor.stop()
        isRecording = false
        // Re-install the persisted binding so we don't leave the user with
        // no hotkey after a cancel.
        let saved = layout.state.summonHotKey
        if let appDel = NSApp.delegate as? AppDelegate {
            _ = appDel.applyHotKey(saved)
        }
    }

    private func finishRecording() {
        monitor.stop()
        isRecording = false
    }

    // MARK: Capture handling

    private func handle(_ event: NSEvent) {
        // Bare Esc cancels — only when no modifiers are held, so the user can
        // still bind ⌃Esc, ⌘Esc, etc.
        let plainMods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == UInt16(kVK_Escape) && plainMods.isEmpty {
            cancelRecording()
            return
        }

        let candidate = HotKeyBinding.fromKeyDownEvent(event)
        if let failure = HotKeyBinding.validate(candidate) {
            switch failure {
            case .noModifier:
                lastError = "Combos need at least ⌘, ⌃, or ⌥ as a modifier."
            case .reservedBySystem(let why):
                lastError = "\(why) Pick a different combo."
            }
            return // stay in recording mode so the user can try again
        }

        apply(candidate)
    }

    /// Try to install + persist `binding`. On success, recording ends.
    /// On failure (Carbon refused), the previous binding is still active —
    /// HotKeyManager's try-then-swap guarantees we don't end up with nothing.
    private func apply(_ binding: HotKeyBinding) {
        guard let appDel = NSApp.delegate as? AppDelegate else {
            lastError = "Internal error: AppDelegate unavailable."
            return
        }

        if let error = appDel.applyHotKey(binding) {
            // The combo couldn't be registered. The old binding remains
            // installed (try-then-swap). Stop recording and surface the error
            // so the user can either record again or live with the old one.
            lastError = error
            finishRecording()
            // Re-install the old binding's handler (it's still registered with
            // Carbon, but uninstall() at recording-start nulled our handler).
            _ = appDel.applyHotKey(layout.state.summonHotKey)
            return
        }

        lastError = nil
        finishRecording()
    }
}

/// Holds the opaque `Any?` token returned by `NSEvent.addLocalMonitorForEvents`
/// so the recorder view can store it across body re-evaluations. Lives on the
/// main actor — the local monitor's closure runs on the main thread.
@MainActor
final class MonitorHolder {
    private var token: Any?

    func start(handler: @escaping @MainActor (NSEvent) -> Void) {
        stop()
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handler(event) }
            return nil // swallow every keyDown while recording
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }

    // No deinit cleanup: the holder is owned by @State on the view, which
    // outlives the view's body. The recorder's .onDisappear calls stop()
    // explicitly, so a deinit fallback would require working around
    // Swift 6's non-Sendable-in-nonisolated-deinit rules for no real gain.
}
