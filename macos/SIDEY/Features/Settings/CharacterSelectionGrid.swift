import SwiftUI

struct CharacterSelectionGrid: View {
    let maximumColumns: Int
    let characters: [PixelCharacterDefinition]
    @Binding var selection: String

    init(
        maximumColumns: Int,
        characters: [PixelCharacterDefinition] = PixelCharacterCatalog.free,
        selection: Binding<String>
    ) {
        self.maximumColumns = maximumColumns
        self.characters = characters
        self._selection = selection
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 92, maximum: 132), spacing: 12),
            count: maximumColumns
        )
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(characters) { character in
                CharacterSelectionCard(
                    character: character,
                    isSelected: PixelCharacterCatalog.canonicalID(for: selection) == character.id,
                    onSelect: { selection = character.id }
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("캐릭터 선택")
    }
}

private struct CharacterSelectionCard: View {
    let character: PixelCharacterDefinition
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                Image(nsImage: PixelCharacterPreviewImage.image(for: character))
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Text(character.displayName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isSelected ? Color(red: 0.45, green: 0.49, blue: 0.85).opacity(0.13) : .clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color(red: 0.45, green: 0.49, blue: 0.85) : Color.secondary.opacity(0.28),
                        lineWidth: isSelected ? 3 : 1
                    )
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color(red: 0.45, green: 0.49, blue: 0.85))
                        .background(Circle().fill(.background).padding(2))
                        .padding(8)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(character.displayName)
        .accessibilityValue(isSelected ? "선택됨" : "선택 안 됨")
    }
}
