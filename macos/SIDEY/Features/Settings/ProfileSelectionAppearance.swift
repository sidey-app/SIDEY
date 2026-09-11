import SwiftUI

struct ProfileSelectionAppearance: ViewModifier {
    let isSelected: Bool
    let isPending: Bool
    var isFocused: Bool = false

    static let selectionColor = Color(red: 0.45, green: 0.49, blue: 0.85)
    private var selectionColor: Color { Self.selectionColor }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isSelected ? selectionColor.opacity(0.13) : .clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        isSelected || isFocused ? selectionColor : Color.secondary.opacity(0.28),
                        lineWidth: isSelected ? 3 : (isFocused ? 2 : 1)
                    )
            }
            .overlay(alignment: .topTrailing) {
                if isPending {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                        .accessibilityHidden(true)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(selectionColor)
                        .background(Circle().fill(.background).padding(2))
                        .padding(8)
                }
            }
    }
}
