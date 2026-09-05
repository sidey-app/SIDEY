import AppKit
import SwiftUI

struct StoreView: View {
    @Bindable var model: AppModel
    let actions: SettingsActions
    let availability: StoreAvailability
    @State private var selectedKind: CommerceProductKind = .character
    @State private var selectedProductID: String?

    init(
        model: AppModel,
        actions: SettingsActions,
        availability: StoreAvailability = AppReleaseChannel.resolve().storeAvailability
    ) {
        self.model = model
        self.actions = actions
        self.availability = availability
    }

    private let columns = [
        GridItem(
            .adaptive(
                minimum: StoreCardLayout.minimumWidth,
                maximum: StoreCardLayout.maximumWidth
            ),
            spacing: StoreCardLayout.spacing,
            alignment: .top
        )
    ]

    private var visibleProducts: [CommerceProductState] {
        model.commerceProducts
            .filter { $0.product.kind == selectedKind }
            .sorted { $0.product.sortOrder < $1.product.sortOrder }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if !availability.usesAppStore {
                Picker("상품 종류", selection: $selectedKind) {
                    ForEach(CommerceProductKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("상점 상품 종류")
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: StoreCardLayout.spacing) {
                ForEach(visibleProducts) { state in
                    switch availability {
                    case .comingSoon:
                        StoreLockedProductCard(productState: state) {
                            selectedProductID = state.id
                        }
                    case .direct, .appStore:
                        StoreProductCard(productState: state, actions: actions) {
                            selectedProductID = state.id
                        }
                    }
                }
            }

            Spacer(minLength: StoreCardLayout.footerMinimumSpacing)
            footer
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            if availability.allowsCommerceActions {
                actions.onRefreshCommerceState(nil)
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedProductID != nil },
            set: { if !$0 { selectedProductID = nil } }
        )) {
            if let selectedProductID,
               let state = model.commerceProduct(id: selectedProductID) {
                StoreProductDetailSheet(
                    productState: state,
                    actions: actions,
                    availability: availability
                ) {
                    self.selectedProductID = nil
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("꾸미기·상점").font(.title2.bold())
                Text("캐릭터와 말풍선, 투척물을 골라보세요.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Label(footerHeadline, systemImage: "lock.shield").font(.callout)
            if availability.allowsCommerceActions {
                Text(availability.usesAppStore
                     ? "구매는 Apple이 처리하며 서버 검증 뒤 계정에 사용권이 반영됩니다."
                     : "표시 가격은 부가세 포함이며 서버 확인 뒤 디지털 꾸미기 사용권이 즉시 시작됩니다.")
                    .font(.caption)
                Text(availability.usesAppStore
                     ? "환불과 결제 문의는 Apple의 App Store 정책과 절차를 따릅니다."
                     : "제공 시작 뒤 단순 변심 환불은 불가하며, 미제공·계약 불일치·중복·무단 결제 등 법정 사유는 전액 환불합니다.")
                    .font(.caption)
            }
            if availability.usesAppStore {
                Button("구매 복원", action: actions.onRestorePurchases)
                    .buttonStyle(.link)
                    .disabled(model.accountOperationInProgress)
            }
        }
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: StoreCardLayout.footerMaximumWidth)
        .frame(maxWidth: .infinity)
    }

    private var footerHeadline: String {
        switch availability {
        case .comingSoon: "현재 상점은 준비 중입니다. 보유 상품은 계속 사용할 수 있습니다."
        case .direct: "구매 전 Google 계정 연결이 필요합니다."
        case .appStore: "가격과 결제는 App Store에서 표시하고 처리합니다."
        }
    }
}

struct StoreProductCard: View {
    let productState: CommerceProductState
    let actions: SettingsActions
    var onSelect: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    init(
        productState: CommerceProductState,
        actions: SettingsActions,
        onSelect: @escaping () -> Void = {}
    ) {
        self.productState = productState
        self.actions = actions
        self.onSelect = onSelect
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                StoreProductPreview(product: productState.product, pointSize: 82)
                    .frame(height: StoreCardLayout.previewHeight)
                Text(productState.product.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                status
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: StoreCardLayout.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: StoreCardLayout.cornerRadius, style: .continuous)
                    .stroke(
                        isHovered || isFocused ? Color.accentColor : Color.primary.opacity(0.08),
                        lineWidth: isHovered || isFocused ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .offset(y: isHovered ? -2 : 0)
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .animation(.easeOut(duration: 0.14), value: isFocused)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("상세 보기")
    }

    @ViewBuilder private var status: some View {
        if productState.isWorking {
            ProgressView().controlSize(.small).accessibilityLabel("처리 중")
        } else {
            Text(statusLabel)
        }
    }

    private var statusLabel: String {
        if productState.isEquipped { return "사용 중" }
        if productState.purchaseState == .owned { return "보유 중" }
        if case .error = productState.purchaseState { return "오류" }
        return productState.formattedPrice
    }

    private var statusColor: Color {
        if productState.isEquipped { return .blue }
        if productState.purchaseState == .owned { return .green }
        if case .error = productState.purchaseState { return .orange }
        return .secondary
    }

    private var accessibilityLabel: String {
        "\(productState.product.displayName), \(statusLabel)"
    }

    private var cardBackground: Color {
        switch (colorScheme, isHovered) {
        case (.light, true): Color.black.opacity(0.015)
        case (.light, false): Color.black.opacity(0.035)
        case (.dark, true): Color.white.opacity(0.075)
        case (.dark, false): Color.white.opacity(0.035)
        @unknown default: Color.primary.opacity(0.035)
        }
    }

    func requestPurchase() {
        actions.onPurchase(productState.id)
    }
}

struct StoreLockedProductCard: View {
    let productState: CommerceProductState
    var onSelect: () -> Void
    @FocusState private var isFocused: Bool

    init(
        productState: CommerceProductState,
        onSelect: @escaping () -> Void = {}
    ) {
        self.productState = productState
        self.onSelect = onSelect
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                StoreProductPreview(product: productState.product, pointSize: 82)
                    .frame(height: StoreCardLayout.previewHeight)
                Text(productState.product.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(productState.formattedPrice).font(.caption2)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.035))
            .overlay {
                RoundedRectangle(cornerRadius: StoreCardLayout.cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.68))
            }
            .overlay {
                VStack(spacing: 7) {
                    Image(systemName: "lock.fill")
                    Text("추후 오픈 예정")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: StoreCardLayout.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: StoreCardLayout.cornerRadius, style: .continuous)
                    .stroke(isFocused ? Color.accentColor : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(productState.product.displayName), 추후 오픈 예정")
        .accessibilityHint("상세 미리보기")
    }

    func requestPreview() {
        onSelect()
    }
}

struct StoreProductDetailSheet: View {
    let productState: CommerceProductState
    let actions: SettingsActions
    let availability: StoreAvailability
    let onClose: () -> Void

    init(
        productState: CommerceProductState,
        actions: SettingsActions,
        availability: StoreAvailability = .direct,
        onClose: @escaping () -> Void
    ) {
        self.productState = productState
        self.actions = actions
        self.availability = availability
        self.onClose = onClose
    }

    var displaysCommerceAction: Bool {
        availability.unavailableDetailMessage == nil
    }

    var body: some View {
        VStack(spacing: 10) {
            StorePreviewStage(product: productState.product)
            Text(productState.product.displayName).font(.title2.bold())
            Text(detailDescription)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            detailAction
        }
        .padding(.horizontal, 30)
        .padding(.top, 30)
        .padding(.bottom, 24)
        .frame(width: 600)
        .overlay(alignment: .topTrailing) {
            Button("닫기", systemImage: "xmark", action: onClose)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .padding(10)
                .accessibilityLabel("상품 상세 닫기")
        }
    }

    @ViewBuilder private var detailAction: some View {
        if !displaysCommerceAction,
           let unavailableMessage = availability.unavailableDetailMessage {
            Text(unavailableMessage)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityLabel(unavailableMessage)
        } else if productState.isWorking {
            Button(action: {}) { ProgressView().controlSize(.small) }
                .buttonStyle(.borderedProminent)
                .disabled(true)
                .accessibilityLabel("처리 중")
        } else if case .error = productState.purchaseState {
            Button("상태 다시 확인") { actions.onRefreshCommerceState(productState.id) }
                .buttonStyle(.borderedProminent)
        } else {
            Button(productState.purchaseState == .owned ? "보유 중" : purchaseLabel) {
                actions.onPurchase(productState.id)
            }
                .buttonStyle(.borderedProminent)
                .disabled(productState.purchaseState == .owned)
                .accessibilityLabel(productState.purchaseState == .owned
                                    ? "\(productState.product.displayName) 보유 중"
                                    : "\(productState.product.displayName) \(purchaseLabel)")
        }
    }

    private var purchaseLabel: String {
        productState.purchaseState == .googleConnectionRequired
            ? "Google 계정 연결"
            : "\(productState.formattedPrice)에 구매"
    }

    private var detailDescription: String {
        guard let characterID = productState.product.characterID else {
            return productState.product.description
        }
        return "\(productState.product.description) \(PixelCharacterThrowCatalog.interactionDescription(for: characterID))"
    }
}

struct StoreProductPreview: View {
    let product: CommerceProduct
    let pointSize: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.035))
            switch product.kind {
            case .character:
                if let characterID = product.characterID {
                    let definition = PixelCharacterCatalog.definition(for: characterID)
                    Image(nsImage: PixelCharacterPreviewImage.image(for: definition, frame: definition.previewFrame))
                        .interpolation(.none)
                        .resizable()
                        .frame(width: pointSize * 0.62, height: pointSize * 0.62)
                }
            case .bubble:
                StoreBubblePreview(styleID: product.catalogItemID)
                    .frame(width: pointSize, height: pointSize * 0.44)
            case .throwable:
                StoreThrowablePreview(objectID: product.catalogItemID, pointSize: pointSize)
            }
        }
        .accessibilityHidden(true)
    }
}

struct StoreBubblePreview: View {
    let styleID: String?

    private var theme: PixelBubbleTheme { .resolve(styleID) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: theme.backgroundColor))
            if let assetName = theme.decorationAssetName,
               let image = StoreAssetPreviewImage.image(
                   name: assetName,
                   subdirectory: "Bubbles",
                   cellSize: CGSize(width: 16, height: 16),
                   frame: 0
               ) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .padding(4)
            }
        }
    }
}

struct StoreThrowablePreview: View {
    let objectID: String
    let pointSize: CGFloat

    var body: some View {
        ZStack {
            if objectID == PixelCharacterThrowCatalog.cannonObjectID {
                frameImage(
                    name: "\(objectID)_emitter",
                    subdirectory: "CharacterThrow/EmitterSheets",
                    cellSize: CGSize(width: 24, height: 24),
                    frame: 2,
                    size: pointSize * 0.58
                )
                .offset(x: -pointSize * 0.08)
                frameImage(
                    name: objectID,
                    subdirectory: "CharacterThrow/ObjectSheets",
                    cellSize: CGSize(width: 16, height: 16),
                    frame: 1,
                    size: pointSize * 0.30
                )
                .offset(x: pointSize * 0.25, y: -pointSize * 0.18)
            } else {
                frameImage(
                    name: objectID,
                    subdirectory: "CharacterThrow/ObjectSheets",
                    cellSize: CGSize(width: 16, height: 16),
                    frame: 0,
                    size: pointSize * 0.48
                )
            }
        }
    }

    private func frameImage(
        name: String,
        subdirectory: String,
        cellSize: CGSize,
        frame: Int,
        size: CGFloat
    ) -> some View {
        Group {
            if let image = StoreAssetPreviewImage.image(
                name: name,
                subdirectory: subdirectory,
                cellSize: cellSize,
                frame: frame
            ) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: size, height: size)
            }
        }
    }
}

@MainActor
private enum StoreAssetPreviewImage {
    private static var cache: [String: NSImage] = [:]

    static func image(name: String, subdirectory: String, cellSize: CGSize, frame: Int) -> NSImage? {
        let key = "\(subdirectory)|\(name)|\(Int(cellSize.width))|\(frame)"
        if let cached = cache[key] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: subdirectory)
                ?? Bundle.main.url(forResource: name, withExtension: "png"),
              let source = NSImage(contentsOf: url),
              let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cropped = cgImage.cropping(to: CGRect(
                  x: CGFloat(frame) * cellSize.width,
                  y: 0,
                  width: cellSize.width,
                  height: cellSize.height
              ))
        else { return nil }
        let image = NSImage(cgImage: cropped, size: cellSize)
        cache[key] = image
        return image
    }
}

enum StoreReactionPreviewStyle {
    static let characterSize: CGFloat = 96
    static let peakScale: CGFloat = 1.45
    static let maximumRenderedCharacterSize = characterSize * peakScale
}

enum StoreCardLayout {
    static let minimumWidth: CGFloat = 108
    static let maximumWidth: CGFloat = 118
    static let spacing: CGFloat = 10
    static let cornerRadius: CGFloat = 18
    static let previewHeight: CGFloat = 84
    static let minimumPreviewHeight: CGFloat = 144
    static let aspectRatio: CGFloat = 1
    static let footerMinimumSpacing: CGFloat = 28
    static let footerMaximumWidth: CGFloat = 520
}
