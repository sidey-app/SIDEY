import SwiftUI

struct ConnectionBadge: View {
    let state: BackendConnectionState

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(state.label).font(.caption.weight(.medium))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .clipShape(Capsule())
        .glassEffect(in: Capsule())
    }

    private var color: Color {
        switch state {
        case .online: .green
        case .connecting: .orange
        case .idle: .gray
        case .failed: .red
        }
    }
}

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).lineLimit(3)
            Spacer()
            Button(action: onDismiss) { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: 620)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SuccessBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(message).lineLimit(2)
            Spacer()
            Button(action: onDismiss) { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: 620)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String?
    let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title2.bold())
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 18) { content }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.primary.opacity(0.025),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.primary.opacity(0.05), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.025), radius: 12, y: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            SettingsRowLabel(title: title, description: description)
            Spacer(minLength: 16)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.large)
                .tint(.accentColor)
                .frame(width: 240, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

struct SettingsControlRow<Control: View>: View {
    let title: String
    let description: String
    let control: Control

    init(
        title: String,
        description: String,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.description = description
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            SettingsRowLabel(title: title, description: description)
            Spacer(minLength: 16)
            control
                .frame(width: 240, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SettingsRowLabel: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
