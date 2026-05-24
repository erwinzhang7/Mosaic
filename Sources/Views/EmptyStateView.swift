import SwiftUI

/// Reusable empty-state for the overlay. Calm, centered, optional CTA.
/// Used by both Apps and Windows modes so the visual language stays
/// consistent — the permission banners in Triggers / Windows are a separate
/// pattern (inline informational, not centered).
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var primaryAction: PrimaryAction?

    struct PrimaryAction {
        let label: String
        let action: () -> Void
    }

    init(icon: String, title: String, message: String, primaryAction: PrimaryAction? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.primaryAction = primaryAction
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 38))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title3.weight(.semibold))

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            if let action = primaryAction {
                Button(action.label, action: action.action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 60)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }
}
