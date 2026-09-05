import Foundation
import SwiftUI

struct OnboardingAIEnhancementStepView: View {
    @Binding var finalText: String

    let progressValue: Double
    let glowCenter: UnitPoint
    let language: VoiceEngineLanguage
    let shortcutDisplay: String
    let isTestReady: Bool
    let isRunning: Bool
    let isRecordingShortcut: Bool
    let shortcutRecordingMessage: String?
    let onGlowMove: (CGPoint, CGSize) -> Void
    let onGlowExit: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void
    let onUseAIProvider: () -> Void
    let onFinishSetup: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var settings = SettingsStore.shared

    @State private var hoveredButtonID: String?
    @State private var shouldShowTryout = false
    @State private var selectedExampleID = Self.examples[0].id
    @State private var activeRecordingExampleID: String?
    @State private var playgroundOutputs: [String: String] = [:]
    @Namespace private var exampleMorphNamespace

    private enum ScrollTarget {
        static let top = "ai-enhancement-top"
    }

    private struct EnhancementExample: Identifiable {
        let id: String
        let raw: String
        let polished: String
    }

    private enum ButtonTone {
        case primary
        case secondary
        case destructive
    }

    private struct PillButtonConfiguration {
        let id: String
        let title: String
        let systemImage: String?
        let tone: ButtonTone
        let width: CGFloat
        let height: CGFloat
        let fontSize: CGFloat
        let isEnabled: Bool
    }

    private enum ExampleGridMetrics {
        static let widthInset: CGFloat = 88
        static let maxWidth: CGFloat = 900
        static let headerLeadingInset: CGFloat = 50
        static let columnSpacing: CGFloat = 12
        static let rowSpacing: CGFloat = 8
        static let rowHeight: CGFloat = 102
        static let innerTextHeight: CGFloat = 86
        static let iconSize: CGFloat = 40
        static let arrowSize: CGFloat = 32
        static let rawCornerRadius: CGFloat = 14
        static let innerCornerRadius: CGFloat = 10
        static let heroHeight: CGFloat = 154
    }

    private static let examples = [
        EnhancementExample(
            id: "message-format",
            raw: "Hey John, Newline, how are you doing today?",
            polished: "Hey John,\nHow are you doing today?"
        ),
        EnhancementExample(
            id: "correction",
            raw: "Hey, can we meet at five thirty tomorrow morning? Sorry, can you make it three thirty p.m. today?",
            polished: "Hey, can we meet at 3:30 PM today?"
        ),
        EnhancementExample(
            id: "list",
            raw: "Make a grocery list. First one is banana, second one is apple, third one is orange.",
            polished: "Grocery list:\n- banana\n- apple\n- orange"
        ),
    ]

    /// True when Apple Intelligence is available on this Mac and is already the
    /// verified dictation enhancement provider (normally via the launch auto-seed).
    private var isAppleIntelligenceSelected: Bool {
        AppleIntelligenceService.isAvailable &&
            self.settings.selectedProviderID == "apple-intelligence" &&
            self.settings.verifiedProviderFingerprints["apple-intelligence"] == "apple-intelligence"
    }

    private var canNavigateOrMutate: Bool {
        !self.isRunning && !self.isRecordingShortcut
    }

    private var canFinishSetup: Bool {
        self.shouldShowTryout &&
            self.isTestReady &&
            !self.isRunning &&
            !self.isRecordingShortcut
    }

    private var sectionTransition: AnyTransition {
        if self.reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.992, anchor: .center)),
            removal: .opacity.combined(with: .scale(scale: 1.006, anchor: .center))
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                FluidOnboardingLandingBackdrop(glowCenter: self.glowCenter)

                ScrollViewReader { scrollProxy in
                    VStack(spacing: 0) {
                        FluidOnboardingCompactProgress(value: self.progressValue)
                            .padding(.top, 28)

                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(spacing: 0) {
                                Color.clear
                                    .frame(height: 22)
                                    .id(Self.ScrollTarget.top)

                                self.introSection(scrollProxy: scrollProxy, containerWidth: proxy.size.width)
                            }
                            .frame(maxWidth: .infinity)
                        }

                        self.footer
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .onChange(of: self.finalText) { _, newValue in
                        self.captureCurrentExampleOutput(newValue)
                    }
                    .onChange(of: self.isRunning) { _, isRunning in
                        if isRunning {
                            self.activeRecordingExampleID = self.selectedExampleID
                        }
                    }
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

    private func introSection(scrollProxy: ScrollViewProxy, containerWidth: CGFloat) -> some View {
        Group {
            if self.shouldShowTryout {
                self.playgroundSection(containerWidth: containerWidth)
                    .transition(self.sectionTransition)
            } else {
                self.setupSection(scrollProxy: scrollProxy, containerWidth: containerWidth)
                    .transition(self.sectionTransition)
            }
        }
        .animation(self.reduceMotion ? nil : .easeInOut(duration: 0.28), value: self.shouldShowTryout)
        .frame(maxWidth: .infinity)
    }

    private func setupSection(scrollProxy: ScrollViewProxy, containerWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                FluidOnboardingCompactAppIconMark(size: 52)
                    .padding(.bottom, 18)

                Text("One more thing...")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 10)

                Text(self.setupSubtitleText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.64))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: 700)
                    .padding(.horizontal, 32)
            }
            .frame(height: ExampleGridMetrics.heroHeight, alignment: .top)
            .padding(.bottom, 20)

            self.examplesPanel
                .frame(width: self.exampleGridWidth(containerWidth: containerWidth))
                .padding(.bottom, 18)

            Text(self.setupQuestionText)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.bottom, 12)

            self.setupChoiceCard(scrollProxy: scrollProxy)
                .frame(width: min(containerWidth - 92, 840))
                .padding(.bottom, 12)

            Text(self.setupFootnoteText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.46))
        }
        .frame(maxWidth: .infinity)
    }

    private var setupSubtitleText: String {
        if self.isAppleIntelligenceSelected {
            return "Speech2Write polishes dictation on your Mac with Apple Intelligence."
        }
        return "Optional: polish dictation with Apple Intelligence on this Mac."
    }

    private var setupQuestionText: String {
        if self.isAppleIntelligenceSelected {
            return "AI polishing is ready."
        }
        return "Want AI polishing?"
    }

    private var setupFootnoteText: String {
        if self.shouldShowTryout {
            return "Try it below before finishing setup."
        }
        return "You can change this later in AI Enhancement settings."
    }

    private func playgroundSection(containerWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                FluidOnboardingCompactAppIconMark(size: 52)
                    .padding(.bottom, 18)

                VStack(spacing: 8) {
                    Text("Let's polish your text.")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)

                    Text("Choose an example, press \(self.shortcutDisplay), then dictate it naturally.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }
                .padding(.horizontal, 32)
            }
            .frame(height: ExampleGridMetrics.heroHeight, alignment: .top)
            .padding(.bottom, 22)

            self.playgroundExamplesPanel
                .frame(width: self.exampleGridWidth(containerWidth: containerWidth))
                .padding(.bottom, 12)

            Text(self.isTestReady ? "Looks good. Finish setup when you're ready." : "The polished result will appear on the selected row.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.46))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity)
    }

    private func exampleGridWidth(containerWidth: CGFloat) -> CGFloat {
        min(max(containerWidth - ExampleGridMetrics.widthInset, 360), ExampleGridMetrics.maxWidth)
    }

    private func exampleGridHeader(leftTitle: String, rightTitle: String) -> some View {
        HStack(spacing: ExampleGridMetrics.columnSpacing) {
            Text(leftTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.48))
                .frame(maxWidth: .infinity, alignment: .center)

            Color.clear
                .frame(width: ExampleGridMetrics.arrowSize, height: 1)

            Text(rightTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FluidOnboardingLandingColors.blue.opacity(0.84))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.leading, ExampleGridMetrics.headerLeadingInset)
    }

    private var examplesPanel: some View {
        VStack(spacing: ExampleGridMetrics.rowSpacing) {
            self.exampleGridHeader(leftTitle: "Raw dictation (before)", rightTitle: "Polished (after)")

            ForEach(Self.examples) { example in
                self.exampleRow(example)
            }
        }
    }

    private func exampleRow(_ example: EnhancementExample) -> some View {
        HStack(alignment: .center, spacing: ExampleGridMetrics.columnSpacing) {
            HStack(spacing: ExampleGridMetrics.columnSpacing) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FluidOnboardingLandingColors.blue)
                    .frame(width: ExampleGridMetrics.iconSize, height: ExampleGridMetrics.iconSize)
                    .background(
                        Circle()
                            .fill(FluidOnboardingLandingColors.blue.opacity(0.12))
                            .overlay(
                                Circle()
                                    .stroke(FluidOnboardingLandingColors.blue.opacity(0.22), lineWidth: 1)
                            )
                    )

                Text(example.raw)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.52))
                    .lineLimit(4)
                    .minimumScaleFactor(0.80)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .frame(height: ExampleGridMetrics.innerTextHeight, alignment: .center)
                    .background(
                        RoundedRectangle(cornerRadius: ExampleGridMetrics.innerCornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.040))
                    )
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(height: ExampleGridMetrics.rowHeight)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: ExampleGridMetrics.rawCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.038))
                    .overlay(
                        RoundedRectangle(cornerRadius: ExampleGridMetrics.rawCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.070), lineWidth: 1)
                    )
            )
            .matchedGeometryEffect(
                id: "example-raw-\(example.id)",
                in: self.exampleMorphNamespace,
                properties: .frame,
                isSource: !self.shouldShowTryout
            )

            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.80))
                .frame(width: ExampleGridMetrics.arrowSize, height: ExampleGridMetrics.arrowSize)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.065))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                )
                .matchedGeometryEffect(
                    id: "example-arrow-\(example.id)",
                    in: self.exampleMorphNamespace,
                    properties: .frame,
                    isSource: !self.shouldShowTryout
                )

            self.polishedExampleSurface(example)
                .matchedGeometryEffect(
                    id: "example-output-\(example.id)",
                    in: self.exampleMorphNamespace,
                    properties: .frame,
                    isSource: !self.shouldShowTryout
                )
        }
    }

    private var playgroundExamplesPanel: some View {
        VStack(spacing: ExampleGridMetrics.rowSpacing) {
            self.exampleGridHeader(leftTitle: "Try saying this", rightTitle: "Polished output")

            ForEach(Self.examples) { example in
                self.playgroundExampleRow(example)
            }
        }
    }

    private func polishedExampleSurface(_ example: EnhancementExample) -> some View {
        let shape = RoundedRectangle(cornerRadius: ExampleGridMetrics.rawCornerRadius, style: .continuous)

        return ZStack(alignment: .topLeading) {
            Text(example.polished)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.84))
                .lineLimit(5)
                .minimumScaleFactor(0.80)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(height: ExampleGridMetrics.rowHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            shape
                .fill(FluidOnboardingLandingColors.blue.opacity(0.060))
                .overlay(
                    shape.stroke(FluidOnboardingLandingColors.blue.opacity(0.42), lineWidth: 1.2)
                )
        )
    }

    private func playgroundExampleRow(_ example: EnhancementExample) -> some View {
        let isSelected = example.id == self.selectedExampleID
        let outputText = self.playgroundOutputs[example.id] ?? ""
        let hasOutput = !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isListening = self.activeRecordingExampleID == example.id && self.isRunning
        let allowsDecorativeShadow = !self.reduceMotion
        let rawShadowRadius: CGFloat = allowsDecorativeShadow && isSelected ? 13 : 0
        let arrowShadowRadius: CGFloat = allowsDecorativeShadow && isListening ? 12 : 0
        let outputShadowRadius: CGFloat = allowsDecorativeShadow && (isSelected || isListening) ? (isSelected ? 14 : 8) : 0
        let outputShadowOpacity: Double = allowsDecorativeShadow ? (isListening ? 0.24 : (isSelected ? 0.16 : 0)) : 0
        let rawShape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let outputShape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        return HStack(alignment: .center, spacing: ExampleGridMetrics.columnSpacing) {
            Button {
                self.selectExample(example)
            } label: {
                HStack(spacing: ExampleGridMetrics.columnSpacing) {
                    Image(systemName: isSelected ? "mic.circle.fill" : "mic.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(FluidOnboardingLandingColors.blue)
                        .frame(width: ExampleGridMetrics.iconSize, height: ExampleGridMetrics.iconSize)
                        .background(
                            Circle()
                                .fill(FluidOnboardingLandingColors.blue.opacity(isSelected ? 0.22 : 0.12))
                                .overlay(
                                    Circle()
                                        .stroke(FluidOnboardingLandingColors.blue.opacity(isSelected ? 0.48 : 0.22), lineWidth: 1)
                                )
                        )

                    Text(example.raw)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(isSelected ? 0.76 : 0.52))
                        .lineLimit(4)
                        .minimumScaleFactor(0.80)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .frame(height: ExampleGridMetrics.innerTextHeight, alignment: .center)
                        .background(
                            RoundedRectangle(cornerRadius: ExampleGridMetrics.innerCornerRadius, style: .continuous)
                                .fill(Color.white.opacity(isSelected ? 0.062 : 0.040))
                        )
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(height: ExampleGridMetrics.rowHeight)
                .frame(maxWidth: .infinity)
                .background(
                    rawShape
                        .fill(Color.white.opacity(isSelected ? 0.054 : 0.038))
                        .overlay(
                            rawShape
                                .stroke(isSelected ? FluidOnboardingLandingColors.blue.opacity(0.48) : Color.white.opacity(0.070), lineWidth: isSelected ? 1.2 : 1)
                        )
                        .shadow(color: FluidOnboardingLandingColors.blue.opacity(allowsDecorativeShadow && isSelected ? 0.13 : 0), radius: rawShadowRadius, x: 0, y: 4)
                )
                .contentShape(rawShape)
            }
            .matchedGeometryEffect(
                id: "example-raw-\(example.id)",
                in: self.exampleMorphNamespace,
                properties: .frame,
                isSource: self.shouldShowTryout
            )
            .buttonStyle(.plain)
            .focusable(false)
            .contentShape(rawShape)

            Image(systemName: isSelected && self.isRunning ? "waveform" : "arrow.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.80))
                .frame(width: ExampleGridMetrics.arrowSize, height: ExampleGridMetrics.arrowSize)
                .background(
                    Circle()
                        .fill(isListening ? FluidOnboardingLandingColors.blue.opacity(0.22) : Color.white.opacity(isSelected ? 0.10 : 0.065))
                        .overlay(
                            Circle()
                                .stroke(isSelected ? FluidOnboardingLandingColors.blue.opacity(0.28) : Color.white.opacity(0.10), lineWidth: 1)
                        )
                        .shadow(color: FluidOnboardingLandingColors.blue.opacity(allowsDecorativeShadow && isListening ? 0.30 : 0), radius: arrowShadowRadius, x: 0, y: 0)
                )
                .matchedGeometryEffect(
                    id: "example-arrow-\(example.id)",
                    in: self.exampleMorphNamespace,
                    properties: .frame,
                    isSource: self.shouldShowTryout
                )

            ZStack(alignment: .topLeading) {
                if hasOutput {
                    Text(outputText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .lineLimit(5)
                        .minimumScaleFactor(0.80)
                        .padding(.leading, 16)
                        .padding(.trailing, 42)
                        .padding(.vertical, 12)
                } else if isListening {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(FluidOnboardingLandingColors.blue)

                        Text("Listening...")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.74))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                } else if isSelected {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dictate here.")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.36))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Text("Press \(self.shortcutDisplay) and speak this example.")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.28))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                if hasOutput {
                    Button {
                        self.clearExampleOutput(example)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.42))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .contentShape(Circle())
                    .padding(.top, 5)
                    .padding(.trailing, 6)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                }
            }
            .frame(height: ExampleGridMetrics.rowHeight, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                outputShape
                    .fill(FluidOnboardingLandingColors.blue.opacity(isListening ? 0.105 : (isSelected ? 0.072 : 0.040)))
                    .overlay(
                        outputShape
                            .stroke(FluidOnboardingLandingColors.blue.opacity(isListening ? 0.72 : (isSelected ? 0.54 : 0.22)), lineWidth: isSelected ? 1.3 : 1)
                    )
                    .shadow(color: FluidOnboardingLandingColors.blue.opacity(outputShadowOpacity), radius: outputShadowRadius, x: 0, y: 5)
            )
            .contentShape(outputShape)
            .onTapGesture {
                self.selectExample(example)
            }
            .matchedGeometryEffect(
                id: "example-output-\(example.id)",
                in: self.exampleMorphNamespace,
                properties: .frame,
                isSource: self.shouldShowTryout
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Try example. \(example.raw)")
    }

    @ViewBuilder
    private func setupChoiceCard(scrollProxy: ScrollViewProxy) -> some View {
        if self.isAppleIntelligenceSelected {
            self.appleIntelligenceProviderCard
        } else {
            self.genericAIProviderCard
        }
    }

    private var appleIntelligenceProviderCard: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        return HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Apple Intelligence")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text("Recommended")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(FluidOnboardingLandingColors.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(FluidOnboardingLandingColors.blue.opacity(0.14))
                        )
                }

                Label("Runs on your Mac with Apple Intelligence. No account, no cloud.", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.74))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                HStack(spacing: 13) {
                    self.modelFact("lock.fill", "On-device")
                    self.modelFact("key.fill", "No API key")
                    self.modelFact("slider.horizontal.3", "Configurable later")
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.fluidGreen)

                Text("Selected")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.84))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.07))
                    .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            shape
                .fill(Color.white.opacity(0.052))
                .overlay(shape.stroke(FluidOnboardingLandingColors.blue.opacity(0.26), lineWidth: 1))
                .shadow(color: FluidOnboardingLandingColors.blue.opacity(0.08), radius: 10, x: 0, y: 5)
        )
    }

    private var genericAIProviderCard: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let isHovered = self.hoveredButtonID == "generic-ai-provider" && self.canNavigateOrMutate

        return HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Apple Intelligence")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Label("Use Apple Intelligence to polish dictation.", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.74))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                HStack(spacing: 13) {
                    self.modelFact("lock.fill", "On-device")
                    self.modelFact("key.fill", "No account")
                    self.modelFact("slider.horizontal.3", "Optional")
                }
            }

            Spacer(minLength: 12)

            self.pillButton(
                PillButtonConfiguration(
                    id: "generic-ai-provider",
                    title: "Set up provider",
                    systemImage: "arrow.up.right",
                    tone: .primary,
                    width: 168,
                    height: 40,
                    fontSize: 13,
                    isEnabled: self.canNavigateOrMutate
                ),
                action: {
                    self.onUseAIProvider()
                }
            )
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            shape
                .fill(Color.white.opacity(isHovered ? 0.070 : 0.052))
                .overlay(shape.stroke(FluidOnboardingLandingColors.blue.opacity(isHovered ? 0.42 : 0.26), lineWidth: 1))
                .shadow(color: FluidOnboardingLandingColors.blue.opacity(isHovered ? 0.18 : 0.08), radius: isHovered ? 18 : 10, x: 0, y: 5)
        )
        .onHover { isHovered in
            self.setHoveredButton(isHovered ? "generic-ai-provider" : nil)
        }
    }

    private func modelFact(_ systemImage: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(FluidOnboardingLandingColors.blue.opacity(0.86))

            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.58))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
    }

    private var footer: some View {
        HStack {
            self.pillButton(
                PillButtonConfiguration(
                    id: "back",
                    title: "Back",
                    systemImage: nil,
                    tone: .secondary,
                    width: 132,
                    height: 48,
                    fontSize: 16,
                    isEnabled: self.canNavigateOrMutate
                ),
                action: {
                    self.onBack()
                }
            )
            .keyboardShortcut(.cancelAction)

            Spacer()

            if self.shouldShowTryout {
                HStack(spacing: 12) {
                    self.skipTryoutButton

                    self.finishButton
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                HStack(spacing: 12) {
                    self.providerChoiceButton

                    if self.isAppleIntelligenceSelected {
                        // Advancing keeps the pre-selected Apple Intelligence setup.
                        // The wired skip action would turn the dictation prompt off.
                        self.continueWithAppleIntelligenceButton
                            .keyboardShortcut(.defaultAction)
                    } else {
                        self.skipButton
                    }
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 24)
    }

    private var providerChoiceButton: some View {
        self.pillButton(
            PillButtonConfiguration(
                id: "ai-provider",
                title: self.isAppleIntelligenceSelected
                    ? "Use a local AI provider"
                    : "Set up Apple Intelligence",
                systemImage: "arrow.up.right",
                tone: .secondary,
                width: 280,
                height: 48,
                fontSize: 15,
                isEnabled: self.canNavigateOrMutate
            ),
            action: {
                self.onUseAIProvider()
            }
        )
    }

    private var skipButton: some View {
        self.pillButton(
            PillButtonConfiguration(
                id: "ai-skip",
                title: "Skip for now",
                systemImage: nil,
                tone: .secondary,
                width: 132,
                height: 48,
                fontSize: 16,
                isEnabled: self.canNavigateOrMutate
            ),
            action: {
                self.onSkip()
            }
        )
    }

    private var continueWithAppleIntelligenceButton: some View {
        self.pillButton(
            PillButtonConfiguration(
                id: "ai-continue",
                title: "Continue",
                systemImage: "checkmark",
                tone: .primary,
                width: 164,
                height: 48,
                fontSize: 16,
                isEnabled: self.canNavigateOrMutate
            ),
            action: {
                self.onFinishSetup()
            }
        )
    }

    private var skipTryoutButton: some View {
        self.pillButton(
            PillButtonConfiguration(
                id: "ai-skip-tryout",
                title: "Skip",
                systemImage: nil,
                tone: .secondary,
                width: 132,
                height: 48,
                fontSize: 16,
                isEnabled: self.canNavigateOrMutate
            ),
            action: {
                self.onFinishSetup()
            }
        )
    }

    private var finishButton: some View {
        self.pillButton(
            PillButtonConfiguration(
                id: "ai-finish",
                title: "Finish setup",
                systemImage: "checkmark",
                tone: .primary,
                width: 164,
                height: 48,
                fontSize: 16,
                isEnabled: self.canFinishSetup
            ),
            action: {
                self.onFinishSetup()
            }
        )
    }

    private func pillButton(
        _ configuration: PillButtonConfiguration,
        action: @escaping () -> Void
    ) -> some View {
        let isDisabled = !configuration.isEnabled
        let isHovered = self.hoveredButtonID == configuration.id && !isDisabled
        let shape = Capsule()
        let accentColor = configuration.tone == .destructive ? Color.red : FluidOnboardingLandingColors.blue
        let isPrimary = configuration.tone == .primary
        let isDestructive = configuration.tone == .destructive
        let fillColor: Color = {
            if isPrimary {
                return accentColor.opacity(isDisabled ? 0.34 : 1)
            }
            if isDestructive {
                return Color.red.opacity(isDisabled ? 0.045 : (isHovered ? 0.24 : 0.16))
            }
            return Color.white.opacity(isDisabled ? 0.045 : (isHovered ? 0.11 : 0.07))
        }()
        let borderColor: Color = {
            if isPrimary {
                return Color.white.opacity(isHovered ? 0.30 : 0)
            }
            if isDestructive {
                return Color.red.opacity(isHovered ? 0.48 : 0.24)
            }
            return isHovered ? accentColor.opacity(0.30) : Color.white.opacity(0.07)
        }()
        let foregroundOpacity = isDisabled ? 0.42 : (isPrimary ? 1.0 : (isHovered ? 0.94 : 0.78))
        let shadowOpacity = isDisabled ? 0 : (isPrimary ? (isHovered ? 0.56 : 0.26) : (isHovered ? 0.12 : 0))

        return Button(action: action) {
            HStack(spacing: configuration.systemImage == nil ? 0 : 8) {
                if let systemImage = configuration.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .bold))
                }

                Text(configuration.title)
                    .font(.system(size: configuration.fontSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(.white.opacity(foregroundOpacity))
            .frame(width: configuration.width, height: configuration.height)
            .background(
                shape
                    .fill(fillColor)
                    .overlay(shape.fill(Color.white.opacity(isPrimary && isHovered ? 0.10 : 0)))
                    .overlay(shape.stroke(borderColor, lineWidth: isHovered ? 1.2 : 1))
                    .overlay(
                        shape
                            .stroke(accentColor.opacity(isHovered ? 0.50 : 0), lineWidth: isHovered ? 1.4 : 1)
                            .padding(-2)
                    )
                    .shadow(color: accentColor.opacity(shadowOpacity), radius: isHovered ? 16 : 9, x: 0, y: isHovered ? 6 : 3)
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .contentShape(shape)
        .disabled(isDisabled)
        .onHover { isHovered in
            self.setHoveredButton(isHovered && !isDisabled ? configuration.id : nil)
        }
    }

    private func setHoveredButton(_ buttonID: String?) {
        guard self.hoveredButtonID != buttonID else { return }
        if self.reduceMotion {
            self.hoveredButtonID = buttonID
        } else {
            withAnimation(.easeOut(duration: 0.14)) {
                self.hoveredButtonID = buttonID
            }
        }
    }

    private func selectExample(_ example: EnhancementExample) {
        guard !self.isRunning else { return }
        guard self.selectedExampleID != example.id else { return }
        self.selectedExampleID = example.id
    }

    private func captureCurrentExampleOutput(_ text: String) {
        guard self.shouldShowTryout else { return }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let targetExampleID = self.activeRecordingExampleID ?? self.selectedExampleID
        self.playgroundOutputs[targetExampleID] = text
        self.selectedExampleID = targetExampleID
        self.activeRecordingExampleID = nil
    }

    private func clearExampleOutput(_ example: EnhancementExample) {
        self.playgroundOutputs.removeValue(forKey: example.id)

        if self.selectedExampleID == example.id {
            self.finalText = ""
        }
    }

}
