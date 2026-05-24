import AppKit
import SwiftUI

/// Three-stage modal for app uninstall:
/// 1. `.preview` — full file list with per-item checkboxes; "Review…" button.
/// 2. `.confirming` — deliberate second action: large "Move N items (X) to
///    Trash?" with Cancel + Move buttons. Visually distinct from the preview.
/// 3. `.result` — outcome summary; "Done".
///
/// The trash call is fired exactly once, between stages 2 and 3, by the
/// `onConfirm` closure. Cancelling at any stage tears down without touching
/// anything.
struct UninstallModal: View {
    enum Stage { case preview, confirming, result }

    @State var set: UninstallSet
    var simulate: Bool
    let onConfirm: (UninstallSet) -> UninstallResult
    let onClose: () -> Void

    @State private var stage: Stage = .preview
    @State private var result: UninstallResult?

    var body: some View {
        Group {
            switch stage {
            case .preview:    previewStage
            case .confirming: confirmStage
            case .result:     resultStage
            }
        }
        .padding(28)
        .frame(width: 640, height: 560)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
        )
    }

    // MARK: Stage 1 — Preview

    private var previewStage: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uninstall \(set.appName)")
                        .font(.title2.weight(.semibold))
                    Text(set.bundleID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if simulate {
                    Text("Simulation")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color.orange.opacity(0.25))
                        )
                        .foregroundStyle(.orange)
                }
            }

            Text("Review every item below. Support files are matched strictly by bundle ID — uncheck anything you want to keep. The app bundle itself is required and can't be deselected.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Bundle row (always included, not toggleable)
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "app.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(set.bundleURL.lastPathComponent)
                        .font(.body.weight(.medium))
                    Text(set.bundleURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(formatBytes(set.bundleSize))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
            )

            HStack {
                Text("Support files")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(set.supportItems.count) found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            if set.supportItems.isEmpty {
                Text("No support files matched the bundle ID.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                Spacer()
            } else {
                List($set.supportItems) { $item in
                    HStack(spacing: 10) {
                        Toggle("", isOn: $item.isSelected)
                            .labelsHidden()
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(item.category)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(item.url.lastPathComponent)
                                    .font(.body)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Text(item.url.path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Text(formatBytes(item.size))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(maxHeight: .infinity)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total selected: \(set.selectedCount) items — \(formatBytes(set.selectedSize))")
                        .font(.body.weight(.medium))
                    Text("Everything is moved to the Trash and can be restored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onClose)
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Review…") { stage = .confirming }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
    }

    // MARK: Stage 2 — Deliberate confirmation

    private var confirmStage: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "trash")
                .font(.system(size: 56))
                .foregroundStyle(.red)

            Text("Move \(set.selectedCount) items to Trash?")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("\(formatBytes(set.selectedSize)) — \(set.appName) (\(set.bundleID))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if simulate {
                Text("Simulation mode is on. Nothing will actually move; the operation will be logged to the system log.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else {
                Text("Items are moved to your Trash and remain restorable until you empty it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            HStack {
                Button("Back") { stage = .preview }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button(simulate ? "Simulate Trash" : "Move to Trash") {
                    let r = onConfirm(set)
                    result = r
                    stage = .result
                }
                .buttonStyle(.borderedProminent)
                .tint(simulate ? .orange : .red)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
    }

    // MARK: Stage 3 — Result

    private var resultStage: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: result?.hasFailures == true ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(result?.hasFailures == true ? .orange : .green)
                VStack(alignment: .leading) {
                    Text(headlineForResult)
                        .font(.title3.weight(.semibold))
                    if let r = result, r.simulated {
                        Text("Nothing was actually moved.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
            }

            if let r = result, !r.trashed.isEmpty {
                Text("Trashed:")
                    .font(.caption.weight(.semibold))
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(r.trashed, id: \.self) { url in
                            Text(url.path)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 140)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08))
                )
            }

            if let r = result, !r.failed.isEmpty {
                Text("Failed:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(r.failed.enumerated()), id: \.offset) { _, fail in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(fail.url.path)
                                    .font(.caption.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(fail.error)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 120)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1))
                )
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done", action: onClose)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
    }

    private var headlineForResult: String {
        guard let r = result else { return "Done" }
        if r.simulated { return "Simulation complete — \(r.trashed.count) items would trash" }
        if r.failed.isEmpty { return "Trashed \(r.trashed.count) items" }
        return "Trashed \(r.trashed.count), \(r.failed.count) failed"
    }
}

/// Pretty byte formatter (1.2 MB style). Local to this file because no other
/// view needs it yet.
func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
