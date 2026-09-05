import SwiftUI

struct OnboardingVocabularyStepView<Footer: View>: View {
    @Binding var selectedPresetIDs: Set<String>

    let progressValue: Double
    let glowCenter: UnitPoint
    let onEnableBoosting: () -> Void
    let onGlowMove: (CGPoint, CGSize) -> Void
    let onGlowExit: () -> Void
    let footer: Footer

    @State private var hoveredPresetID: String?

    init(
        selectedPresetIDs: Binding<Set<String>>,
        progressValue: Double,
        glowCenter: UnitPoint,
        onEnableBoosting: @escaping () -> Void,
        onGlowMove: @escaping (CGPoint, CGSize) -> Void,
        onGlowExit: @escaping () -> Void,
        @ViewBuilder footer: () -> Footer
    ) {
        self._selectedPresetIDs = selectedPresetIDs
        self.progressValue = progressValue
        self.glowCenter = glowCenter
        self.onEnableBoosting = onEnableBoosting
        self.onGlowMove = onGlowMove
        self.onGlowExit = onGlowExit
        self.footer = footer()
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                FluidOnboardingLandingBackdrop(glowCenter: self.glowCenter)

                VStack(spacing: 0) {
                    FluidOnboardingCompactProgress(value: self.progressValue)
                        .padding(.top, 28)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            FluidOnboardingCompactAppIconMark(size: 62)
                                .padding(.bottom, 18)

                            Text("Tune recognition to your work")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.bottom, 10)

                            Text("Choose any optional vocabulary packs. Everything stays on this Mac, and you can change them later in Custom Dictionary.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.60))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 620)
                                .padding(.bottom, 22)

                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12),
                                ],
                                spacing: 12
                            ) {
                                ForEach(VocabularyPresetCatalog.all) { preset in
                                    self.presetCard(preset)
                                }
                            }
                            .frame(width: 650)

                            Text(self.selectionSummary)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(
                                    self.selectedPresetIDs.isEmpty
                                        ? Color.white.opacity(0.44)
                                        : FluidOnboardingLandingColors.blue.opacity(0.92)
                                )
                                .padding(.top, 16)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                        .padding(.bottom, 18)
                    }

                    self.footer
                }

                FluidOnboardingLandingHoverTracker(
                    onMove: self.onGlowMove,
                    onExit: self.onGlowExit
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .accessibilityHidden(true)
            }
        }
    }

    private var selectionSummary: String {
        let count = self.selectedPresetIDs.count
        if count == 0 {
            return "No packs selected — your own custom words still work."
        }
        return "\(count) \(count == 1 ? "pack" : "packs") selected · vocabulary boosting enabled"
    }

    private func presetCard(_ preset: VocabularyPreset) -> some View {
        let isEnabled = self.selectedPresetIDs.contains(preset.id)
        let isHovered = self.hoveredPresetID == preset.id
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)

        return Button {
            self.toggle(preset)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            isEnabled
                                ? FluidOnboardingLandingColors.blue.opacity(0.20)
                                : Color.white.opacity(0.06)
                        )

                    Image(systemName: preset.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(
                            isEnabled
                                ? FluidOnboardingLandingColors.blue
                                : Color.white.opacity(0.58)
                        )
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(preset.description)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.48))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        isEnabled
                            ? FluidOnboardingLandingColors.blue
                            : Color.white.opacity(0.22)
                    )
            }
            .padding(.horizontal, 13)
            .frame(height: 58)
            .background(
                shape
                    .fill(Color.white.opacity(isEnabled ? 0.080 : (isHovered ? 0.060 : 0.040)))
                    .overlay(
                        shape.stroke(
                            isEnabled
                                ? FluidOnboardingLandingColors.blue.opacity(0.44)
                                : Color.white.opacity(isHovered ? 0.14 : 0.07),
                            lineWidth: 1
                        )
                    )
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            self.hoveredPresetID = hovered ? preset.id : nil
        }
        .accessibilityLabel("\(preset.title) vocabulary")
        .accessibilityValue(isEnabled ? "Enabled" : "Disabled")
        .help("\(preset.terms.count) included terms")
    }

    private func toggle(_ preset: VocabularyPreset) {
        if self.selectedPresetIDs.contains(preset.id) {
            self.selectedPresetIDs.remove(preset.id)
        } else {
            self.selectedPresetIDs.insert(preset.id)
            self.onEnableBoosting()
        }
    }
}
