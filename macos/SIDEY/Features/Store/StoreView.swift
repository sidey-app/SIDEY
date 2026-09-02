import SwiftUI

struct StoreView: View {
    @Bindable var model: AppModel
    let actions: SettingsActions
    let availability: StoreAvailability

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
            spacing: 18,
            alignment: .top
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("꾸미기·상점")
                            .font(.title2.bold())
                        Text("새로운 캐릭터를 만나보세요.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(model.commerceProducts) { productState in
                        switch availability {
                        case .comingSoon:
                            StoreLockedProductCard(product: productState.product)
                        case .enabled:
                            StoreProductCard(productState: productState, actions: actions)
                        }
                    }
                }
            }

            Spacer(minLength: StoreCardLayout.footerMinimumSpacing)

            VStack(alignment: .center, spacing: 8) {
                Label(footerHeadline, systemImage: "lock.shield")
                .font(.callout)

                if availability == .enabled {
                    Text("결제 승인과 서버 소유권 확인이 끝나면 디지털 캐릭터 사용권 제공이 즉시 시작됩니다.")
                        .font(.caption)

                    Text("구매 승인 후 7일 이내에는 사용 여부와 관계없이 전액 환불합니다. 그 이후에도 미제공·계약 내용 불일치·중복 또는 무단 결제 등 법정 사유가 확인되면 전액 환불합니다.")
                        .font(.caption)
                }
            }
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: StoreCardLayout.footerMaximumWidth, alignment: .center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            if availability.allowsCommerceActions {
                actions.onRefreshCommerceState(nil)
            }
        }
    }

    private var footerHeadline: String {
        availability == .enabled
            ? "표시 가격은 부가세 포함 금액입니다. 구매 전 Google 계정 연결이 필요합니다."
            : "현재 상점은 준비 중입니다. 보유 중인 캐릭터는 계속 사용할 수 있습니다."
    }
}

private struct StoreLockedProductCard: View {
    let product: CommerceProduct

    private var definition: PixelCharacterDefinition {
        PixelCharacterCatalog.definition(for: product.characterID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
                Image(nsImage: PixelCharacterPreviewImage.image(for: definition, frame: definition.previewFrame))
                    .interpolation(.none)
                    .resizable()
                    .frame(width: StoreReactionPreviewStyle.characterSize, height: StoreReactionPreviewStyle.characterSize)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: StoreCardLayout.minimumPreviewHeight)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(product.displayName).font(.title3.bold())
                Spacer(minLength: 8)
                Text(product.formattedPrice)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(product.description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Color.clear.frame(height: 28)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .aspectRatio(StoreCardLayout.aspectRatio, contentMode: .fit)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.68))
        }
        .overlay {
            VStack(spacing: 12) {
                PixelLockIcon()
                Text("추후 오픈 예정입니다.")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(product.displayName), 추후 오픈 예정입니다.")
    }
}

private struct PixelLockIcon: View {
    private let rows = [
        "00111100",
        "01100110",
        "11000011",
        "11000011",
        "11111111",
        "11111111",
        "11100111",
        "11100111",
        "11111111",
        "11111111",
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Rectangle()
                            .fill(cell == "1" ? Color.white : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct StoreProductCard: View {
    let productState: CommerceProductState
    let actions: SettingsActions
    @Environment(\.colorScheme) private var colorScheme
    @State private var previewScale: CGFloat = 1
    @State private var previewSparkleGeneration = 0
    @State private var previewAnimationTask: Task<Void, Never>?

    private var definition: PixelCharacterDefinition {
        PixelCharacterCatalog.definition(for: productState.product.characterID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            animatedPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: StoreCardLayout.minimumPreviewHeight)
                .layoutPriority(1)
                .overlay(alignment: .topLeading) {
                    CommerceStatusBadge(state: productState.purchaseState)
                        .padding(10)
                }
                .overlay(alignment: .topTrailing) {
                    reactionPreviewButton
                        .padding(10)
                }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(productState.product.displayName)
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(productState.product.formattedPrice)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            if case .error(let message) = productState.purchaseState {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(productState.product.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            purchaseButton
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .aspectRatio(StoreCardLayout.aspectRatio, contentMode: .fit)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.primary.opacity(0.07), lineWidth: 1)
        }
        .onDisappear {
            previewAnimationTask?.cancel()
            previewAnimationTask = nil
        }
    }

    private var animatedPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.pink.opacity(0.16), .purple.opacity(0.12), .mint.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            if let effect = definition.sparkleEffect {
                StoreAmbientSparkles(effect: effect)
                    .allowsHitTesting(false)
                StorePulseSparkles(
                    generation: previewSparkleGeneration,
                    effect: effect
                )
                    .allowsHitTesting(false)
            }
            TimelineView(.animation(minimumInterval: 0.16)) { context in
                let idleFrames = definition.frames.idle
                let frameOffset = Int(context.date.timeIntervalSinceReferenceDate / 0.55)
                    % max(1, idleFrames.count)
                let frame = idleFrames.lowerBound + frameOffset
                Image(nsImage: PixelCharacterPreviewImage.image(for: definition, frame: frame))
                    .interpolation(.none)
                    .resizable()
                    .frame(
                        width: StoreReactionPreviewStyle.characterSize,
                        height: StoreReactionPreviewStyle.characterSize
                    )
                    .scaleEffect(previewScale, anchor: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var reactionPreviewButton: some View {
        Button(action: playReactionPreview) {
            Image(systemName: "hand.tap")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .foregroundStyle(buttonForegroundColor)
        .accessibilityLabel("반응 미리보기")
        .help("반응 미리보기")
    }

    @ViewBuilder
    private var purchaseButton: some View {
        if productState.isWorking,
           productState.purchaseState != .openingCheckout,
           productState.purchaseState != .confirming {
            disabledProgressButton(workingLabel)
        } else {
            switch productState.purchaseState {
            case .googleConnectionRequired:
                fullWidthButton("Google 계정 연결", action: requestPurchase)
            case .available:
                fullWidthButton("\(productState.product.formattedPrice)에 구매", action: requestPurchase)
            case .openingCheckout, .confirming:
                disabledProgressButton(productState.purchaseState.label)
            case .owned:
                EmptyView()
            case .error:
                fullWidthButton("상태 다시 확인") {
                    actions.onRefreshCommerceState(productState.id)
                }
            case .refunded:
                fullWidthButton("다시 구매", action: requestPurchase)
            }
        }
    }

    private var workingLabel: String {
        productState.purchaseState == .googleConnectionRequired
            ? "Google 연결 여는 중"
            : "상태 확인 중"
    }

    @ViewBuilder
    private func fullWidthButton(
        _ title: String,
        action: @escaping () -> Void,
        disabled: Bool = false
    ) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .foregroundStyle(buttonForegroundColor)
        }
        .buttonStyle(.glassProminent)
        .foregroundStyle(buttonForegroundColor)
        .disabled(disabled)
    }

    private func disabledProgressButton(_ title: String) -> some View {
        Button(action: {}) {
            HStack(spacing: 8) {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(spinnerRotation(at: context.date))
                }
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
                Text(title)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(buttonForegroundColor)
        }
        .buttonStyle(.glassProminent)
        .foregroundStyle(buttonForegroundColor)
        .disabled(true)
    }

    private var buttonForegroundColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private func spinnerRotation(at date: Date) -> Angle {
        let cycle = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9)
        return .degrees(cycle / 0.9 * 360)
    }

    func requestPurchase() {
        actions.onPurchase(productState.id)
    }

    private func playReactionPreview() {
        previewAnimationTask?.cancel()
        previewSparkleGeneration += 1
        withTransaction(Transaction(animation: nil)) {
            previewScale = 1
        }
        previewAnimationTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: PixelCharacterPulseStyle.growDuration)) {
                previewScale = StoreReactionPreviewStyle.peakScale
            }
            do {
                try await Task.sleep(for: .seconds(PixelCharacterPulseStyle.growDuration))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: PixelCharacterPulseStyle.settleDuration)) {
                previewScale = 1
            }
        }
    }
}

enum StoreReactionPreviewStyle {
    static let characterSize: CGFloat = 96
    static let peakScale: CGFloat = 1.45
    static let maximumRenderedCharacterSize = characterSize * peakScale
}

enum StoreCardLayout {
    static let aspectRatio: CGFloat = 1
    static let minimumWidth: CGFloat = 300
    static let maximumWidth: CGFloat = 360
    static let minimumPreviewHeight: CGFloat = 144
    static let footerMinimumSpacing: CGFloat = 28
    static let footerMaximumWidth: CGFloat = 520
}

private struct CommerceStatusBadge: View {
    let state: CommercePurchaseState

    var body: some View {
        Text(state.label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.11), in: Capsule())
    }

    private var color: Color {
        switch state {
        case .owned: .green
        case .error: .orange
        case .refunded: .secondary
        case .openingCheckout, .confirming: .blue
        case .available, .googleConnectionRequired: .purple
        }
    }
}

private struct StoreAmbientSparkles: View {
    let effect: PixelSparkleEffect

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let cycleDuration = (effect.ambientDelay.lowerBound + effect.ambientDelay.upperBound) / 2
            let localTime = elapsed.truncatingRemainder(dividingBy: cycleDuration)
            ZStack {
                ForEach(0..<effect.ambientCount.upperBound, id: \.self) { index in
                    let start = Double(index) * 0.06
                    let progress = (localTime - start) / effect.ambientDuration
                    let isVisible = progress >= 0 && progress <= 1
                    Image(systemName: "sparkle")
                        .font(.system(size: ambientSize(index), weight: .semibold))
                        .foregroundStyle(sparkleColor(index))
                        .offset(ambientOffset(index, progress: max(0, progress)))
                        .scaleEffect(isVisible ? CGFloat(0.7 + sin(.pi * progress) * 0.3) : 0.45)
                        .opacity(isVisible ? sin(.pi * progress) * 0.68 : 0)
                }
            }
        }
    }

    private func ambientSize(_ index: Int) -> CGFloat {
        let progress = effect.ambientCount.upperBound > 1
            ? CGFloat(index) / CGFloat(effect.ambientCount.upperBound - 1)
            : 0.5
        return interpolated(in: effect.ambientRadius, progress: progress) * 2.7
    }

    private func ambientOffset(_ index: Int, progress: Double) -> CGSize {
        let position = effect.ambientCount.upperBound > 1
            ? CGFloat(index) / CGFloat(effect.ambientCount.upperBound - 1)
            : 0.5
        let verticalPosition = CGFloat((index * 3) % max(1, effect.ambientCount.upperBound))
            / CGFloat(max(1, effect.ambientCount.upperBound - 1))
        return CGSize(
            width: interpolated(in: effect.ambientHorizontalPosition, progress: position),
            height: interpolated(in: effect.ambientVerticalPosition, progress: verticalPosition)
                - CGFloat(progress) * effect.ambientRise
        )
    }

    private func sparkleColor(_ index: Int) -> Color {
        guard !effect.colors.isEmpty else { return .yellow }
        return color(effect.colors[index % effect.colors.count])
    }

    private func interpolated(in range: ClosedRange<CGFloat>, progress: CGFloat) -> CGFloat {
        range.lowerBound + (range.upperBound - range.lowerBound) * progress
    }

    private func color(_ sparkle: PixelSparkleColor) -> Color {
        Color(red: sparkle.red, green: sparkle.green, blue: sparkle.blue)
    }
}

private struct StorePulseSparkles: View {
    let generation: Int
    let effect: PixelSparkleEffect

    var body: some View {
        ZStack {
            if generation > 0 {
                StoreCentralFlash(
                    generation: generation,
                    duration: effect.centralFlashDuration,
                    color: effect.colors.last.map(color) ?? .yellow
                )
                ForEach(Array(effect.pulseWaves.enumerated()), id: \.offset) { waveIndex, wave in
                    ForEach(0..<wave.count, id: \.self) { index in
                        StoreBurstParticle(
                            generation: generation,
                            wave: wave,
                            waveIndex: waveIndex,
                            index: index,
                            color: sparkleColor(waveIndex + index)
                        )
                    }
                }
            }
        }
    }

    private func color(_ sparkle: PixelSparkleColor) -> Color {
        Color(red: sparkle.red, green: sparkle.green, blue: sparkle.blue)
    }

    private func sparkleColor(_ index: Int) -> Color {
        guard !effect.colors.isEmpty else { return .yellow }
        return color(effect.colors[index % effect.colors.count])
    }
}

private struct StoreCentralFlash: View {
    let generation: Int
    let duration: TimeInterval
    let color: Color
    @State private var expanded = false
    @State private var visible = false

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: 30, weight: .black))
            .foregroundStyle(color)
            .scaleEffect(expanded ? 1.35 : 0.2)
            .opacity(visible ? (expanded ? 0 : 0.95) : 0)
            .offset(y: 12)
            .task(id: generation) {
                reset()
                guard generation > 0, !Task.isCancelled else { return }
                visible = true
                withAnimation(.easeOut(duration: duration)) {
                    expanded = true
                }
            }

    }

    private func reset() {
        withTransaction(Transaction(animation: nil)) {
            expanded = false
            visible = false
        }
    }
}

private struct StoreBurstParticle: View {
    let generation: Int
    let wave: PixelSparklePulseWave
    let waveIndex: Int
    let index: Int
    let color: Color
    @State private var expanded = false
    @State private var visible = false

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: particleSize, weight: .bold))
            .foregroundStyle(color)
            .offset(expanded ? targetOffset : CGSize(width: 0, height: 12))
            .scaleEffect(expanded ? 0.35 : 1)
            .opacity(visible ? (expanded ? 0 : 1) : 0)
            .task(id: generation) {
                reset()
                guard generation > 0 else { return }
                do {
                    try await Task.sleep(for: .seconds(wave.delay))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                visible = true
                withAnimation(.easeOut(duration: wave.duration)) {
                    expanded = true
                }
            }

    }

    private var targetOffset: CGSize {
        CGSize(
            width: cos(angle) * distance,
            height: sin(angle) * distance
        )
    }

    private var angle: CGFloat {
        let stagger = waveIndex.isMultiple(of: 2) ? CGFloat.zero : .pi / CGFloat(max(1, wave.count))
        return CGFloat(index) / CGFloat(wave.count) * .pi * 2 + stagger
    }

    private var distance: CGFloat {
        interpolated(in: wave.distance, progress: progress)
    }

    private var particleSize: CGFloat {
        let radius = index.isMultiple(of: 3)
            ? wave.radius.upperBound
            : interpolated(in: wave.radius, progress: 1 - progress)
        return radius * 3.4
    }

    private var progress: CGFloat {
        wave.count > 1 ? CGFloat(index) / CGFloat(wave.count - 1) : 0.5
    }

    private func interpolated(in range: ClosedRange<CGFloat>, progress: CGFloat) -> CGFloat {
        range.lowerBound + (range.upperBound - range.lowerBound) * progress
    }

    private func reset() {
        withTransaction(Transaction(animation: nil)) {
            expanded = false
            visible = false
        }
    }
}
