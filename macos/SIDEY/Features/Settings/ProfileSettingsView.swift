import SwiftUI

struct ProfileSettingsView: View {
    @Bindable var model: AppModel
    let actions: SettingsActions
    let storeAvailability: StoreAvailability

    private var bubbleProducts: [CommerceProduct] {
        model.ownedProfileCosmeticProducts(for: .bubble)
    }

    private var throwableProducts: [CommerceProduct] {
        model.ownedProfileCosmeticProducts(for: .throwable)
    }

    private var showsCosmeticEquipment: Bool {
        ProfileCosmeticEquipmentPolicy.shouldShow(
            availability: storeAvailability,
            bubbleCount: bubbleProducts.count,
            throwableCount: throwableProducts.count
        )
    }

    var body: some View {
        SettingsSection(
            title: "내 프로필",
            subtitle: "친구들에게 보이는 이름과 캐릭터를 설정할 수 있습니다.",
            systemImage: "person.crop.circle"
        ) {
            SettingsControlRow(
                title: "닉네임",
                description: "친구들의 픽셀 월드와 메시지에 표시되는 이름 · 2~8자"
            ) {
                TextField("2~8자", text: $model.nickname)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .onChange(of: model.nickname) { _, value in
                        let limited = ProfileValidator.limitedNicknameDraft(value)
                        if limited != value { model.nickname = limited }
                    }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("캐릭터")
                    .font(.headline)
                Text("친구 화면에서 나를 나타낼 픽셀 동물을 선택할 수 있습니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            CharacterSelectionGrid(
                maximumColumns: 5,
                characters: model.selectableCharacters,
                confirmedSelection: model.selectedCharacterID,
                pendingSelection: model.pendingCharacterID,
                isDisabled: model.pendingCharacterID != nil || model.groupMutationsDisabled,
                onSelect: actions.onSetCharacter
            )
            Text("캐릭터와 닉네임은 그룹 안에서 중복해서 선택할 수 있습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.hasNicknameChanges {
                HStack {
                    Spacer()
                    Button("닉네임 변경하기") {
                        PendingTextInputCommitter.commitThen(actions.onSaveProfile)
                    }
                        .buttonStyle(.glassProminent)
                        .disabled(model.groupMutationsDisabled || !validNickname)
                }
            }

            if showsCosmeticEquipment {
                Divider()
                if !bubbleProducts.isEmpty {
                    ProfileCosmeticEquipmentSection(
                        kind: .bubble,
                        products: bubbleProducts,
                        selectedCatalogItemID: model.equippedBubbleStyleID,
                        pendingRequest: model.cosmeticEquipmentRequest(for: .bubble),
                        selectedCharacterID: model.selectedCharacterID,
                        onSelect: actions.onSetEquippedCosmetic
                    )
                }
                if !bubbleProducts.isEmpty && !throwableProducts.isEmpty {
                    Divider()
                }
                if !throwableProducts.isEmpty {
                    ProfileCosmeticEquipmentSection(
                        kind: .throwable,
                        products: throwableProducts,
                        selectedCatalogItemID: model.equippedThrowableID,
                        pendingRequest: model.cosmeticEquipmentRequest(for: .throwable),
                        selectedCharacterID: model.selectedCharacterID,
                        onSelect: actions.onSetEquippedCosmetic
                    )
                }
            }
        }

        if !model.preferences.onboardingComplete {
            Label("프로필을 저장한 뒤 그룹을 만들거나 초대 코드로 참여해 주세요.", systemImage: "sparkles")
                .foregroundStyle(.secondary)
                .padding(.top, 18)
        }
    }

    private var validNickname: Bool {
        ProfileValidator.isValidNickname(model.nickname)
    }
}

struct ProfileCosmeticEquipmentSection: View {
    let kind: CommerceProductKind
    let products: [CommerceProduct]
    let selectedCatalogItemID: String?
    let pendingRequest: CosmeticEquipmentRequest?
    let selectedCharacterID: String
    let onSelect: (CommerceProductKind, String?) -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 76), spacing: 10, alignment: .top),
        count: 4
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(kind.title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ProfileCosmeticTile(
                    kind: kind,
                    product: nil,
                    selectedCharacterID: selectedCharacterID,
                    isSelected: selectedCatalogItemID == nil,
                    isPending: pendingRequest?.catalogItemID == nil && pendingRequest != nil,
                    isDisabled: pendingRequest != nil,
                    onSelect: onSelect
                )
                ForEach(products, id: \.id) { product in
                    ProfileCosmeticTile(
                        kind: kind,
                        product: product,
                        selectedCharacterID: selectedCharacterID,
                        isSelected: selectedCatalogItemID == product.catalogItemID,
                        isPending: pendingRequest?.catalogItemID == product.catalogItemID,
                        isDisabled: pendingRequest != nil,
                        onSelect: onSelect
                    )
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(kind.title) 선택")
        }
    }

    private var description: String {
        switch kind {
        case .bubble: "보유한 말풍선을 고르면 모든 그룹에 바로 적용됩니다."
        case .throwable: "보유한 투척물을 고르면 모든 그룹에 바로 적용됩니다."
        case .character: ""
        }
    }
}

struct ProfileCosmeticTile: View {
    let kind: CommerceProductKind
    let product: CommerceProduct?
    let selectedCharacterID: String
    let isSelected: Bool
    let isPending: Bool
    let isDisabled: Bool
    let onSelect: (CommerceProductKind, String?) -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: requestSelection) {
            VStack(spacing: 7) {
                preview
                    .frame(height: 58)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: 112)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.02))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        isSelected || isFocused ? Color.accentColor : Color.secondary.opacity(0.24),
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
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.tint)
                        .background(Circle().fill(.background).padding(2))
                        .padding(7)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .disabled(isDisabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(isSelected ? "현재 사용 중" : "선택하면 모든 그룹에 바로 적용됩니다")
    }

    @ViewBuilder private var preview: some View {
        if let product {
            StoreProductPreview(product: product, pointSize: 56)
        } else {
            switch kind {
            case .bubble:
                StoreBubblePreview(styleID: nil)
                    .frame(width: 56, height: 28)
            case .throwable:
                StoreThrowablePreview(
                    objectID: PixelCharacterThrowCatalog.objectID(for: selectedCharacterID),
                    pointSize: 56
                )
            case .character:
                EmptyView()
            }
        }
    }

    private var label: String {
        if let product { return product.displayName }
        return kind == .bubble ? "기본 말풍선" : "캐릭터 기본 투척물"
    }

    private var accessibilityValue: String {
        if isPending { return "적용 중" }
        return isSelected ? "선택됨" : "선택 안 됨"
    }

    func requestSelection() {
        guard !isDisabled, !isSelected else { return }
        onSelect(kind, product?.catalogItemID)
    }
}

enum ProfileCosmeticEquipmentPolicy {
    static func shouldShow(
        availability: StoreAvailability,
        bubbleCount: Int,
        throwableCount: Int
    ) -> Bool {
        availability.allowsCosmeticEquipment && (bubbleCount > 0 || throwableCount > 0)
    }
}
