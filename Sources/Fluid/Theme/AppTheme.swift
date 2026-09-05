import SwiftUI

/// Central theme definition for the Fluid app. All colors, spacings and materials
/// should be defined here to keep styling consistent and easy to evolve.
struct AppTheme {
    struct Palette {
        let windowBackground: Color
        let contentBackground: Color
        let sidebarBackground: Color
        let cardBackground: Color
        let elevatedCardBackground: Color
        let toolbarBackground: Color
        let cardBorder: Color
        let separator: Color
        let primaryText: Color
        let secondaryText: Color
        let tertiaryText: Color
        let accent: Color
        let warning: Color
        let success: Color
        let error: Color
        let recording: Color
    }

    struct Typography {
        let displayTitle: Font
        let statement: Font
        let title: Font
        let titleIcon: Font
        let sectionTitle: Font
        let body: Font
        let bodyStrong: Font
        let bodySmall: Font
        let bodySmallStrong: Font
        let caption: Font
        let captionStrong: Font
        let captionSmall: Font
        let tiny: Font
        let tinyStrong: Font
        let badge: Font
        let metricTiny: Font
        let codeCaption: Font
        let sidebarItem: Font
        let sidebarSection: Font
        let chromeCaption: Font

        static let standard = Typography(
            displayTitle: .system(size: 42, weight: .semibold),
            statement: .system(size: 17, weight: .regular),
            title: .system(size: 22, weight: .bold),
            titleIcon: .system(size: 22, weight: .regular),
            sectionTitle: .system(size: 15, weight: .semibold),
            body: .system(size: 14, weight: .regular),
            bodyStrong: .system(size: 14, weight: .medium),
            bodySmall: .system(size: 13, weight: .regular),
            bodySmallStrong: .system(size: 13, weight: .medium),
            caption: .system(size: 12, weight: .regular),
            captionStrong: .system(size: 12, weight: .medium),
            captionSmall: .system(size: 11, weight: .regular),
            tiny: .system(size: 11, weight: .regular),
            tinyStrong: .system(size: 11, weight: .bold),
            badge: .system(size: 11, weight: .semibold),
            metricTiny: .system(size: 11, weight: .bold, design: .rounded),
            codeCaption: .system(size: 12, weight: .medium, design: .monospaced),
            sidebarItem: .system(size: 14, weight: .regular),
            sidebarSection: .system(size: 12, weight: .medium),
            chromeCaption: .system(size: 12, weight: .regular)
        )
    }

    struct Metrics {
        struct Spacing {
            let xs: CGFloat
            let sm: CGFloat
            let md: CGFloat
            let lg: CGFloat
            let xl: CGFloat
            let xxl: CGFloat

            static let standard = Spacing(
                xs: 4,
                sm: 8,
                md: 12,
                lg: 16,
                xl: 20,
                xxl: 28
            )
        }

        struct CornerRadius {
            let sm: CGFloat
            let md: CGFloat
            let lg: CGFloat
            let pill: CGFloat

            static let standard = CornerRadius(
                sm: 6,
                md: 10,
                lg: 16,
                pill: 999
            )
        }

        struct Shadow {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
            let opacity: Double

            static func subtle(color: Color, opacity: Double = 0.45) -> Shadow {
                Shadow(color: color, radius: 12, x: 0, y: 6, opacity: opacity)
            }
        }

        struct FormRow {
            let horizontalPadding: CGFloat
            let verticalPadding: CGFloat
            let cornerRadius: CGFloat
            let materialOpacity: Double
            let borderOpacity: Double

            static let standard = FormRow(
                horizontalPadding: 12,
                verticalPadding: 10,
                cornerRadius: 8,
                materialOpacity: 0.5,
                borderOpacity: 0.8
            )
        }

        struct PickerControl {
            let horizontalPadding: CGFloat
            let verticalPadding: CGFloat
            let cornerRadius: CGFloat
            let borderOpacity: Double
            let searchBorderOpacity: Double
            let disclosureSize: CGFloat
            let disclosureBorderOpacity: Double
            let selectedRowOpacity: Double

            static let standard = PickerControl(
                horizontalPadding: 8,
                verticalPadding: 5,
                cornerRadius: 6,
                borderOpacity: 0.35,
                searchBorderOpacity: 0.3,
                disclosureSize: 20,
                disclosureBorderOpacity: 0.4,
                selectedRowOpacity: 0.15
            )
        }

        struct CardSurface {
            struct Variant {
                let borderOpacity: Double
                let hoverBorderOpacity: Double
                let borderWidth: CGFloat
                let hoverShadowBoost: Double
            }

            let defaultPadding: CGFloat
            let standard: Variant
            let prominent: Variant
            let subtle: Variant

            static let defaults = CardSurface(
                defaultPadding: 14,
                standard: Variant(
                    borderOpacity: 0.28,
                    hoverBorderOpacity: 0.5,
                    borderWidth: 1,
                    hoverShadowBoost: 0.12
                ),
                prominent: Variant(
                    borderOpacity: 0.25,
                    hoverBorderOpacity: 0.55,
                    borderWidth: 1.2,
                    hoverShadowBoost: 0.15
                ),
                subtle: Variant(
                    borderOpacity: 0.18,
                    hoverBorderOpacity: 0.32,
                    borderWidth: 0.8,
                    hoverShadowBoost: 0.08
                )
            )
        }

        struct OnboardingSurface {
            struct Landing {
                let contentWidth: CGFloat
                let heroPadding: CGFloat
                let heroIconSize: CGFloat
                let heroIconFrame: CGFloat
                let tileSpacing: CGFloat
                let sectionSpacing: CGFloat
                let heroCornerRadius: CGFloat
            }

            let normalFillOpacity: Double
            let selectedFillOpacity: Double
            let normalBorderOpacity: Double
            let selectedBorderOpacity: Double
            let editorBorderOpacity: Double
            let editorPadding: CGFloat
            let optionPadding: CGFloat
            let compactOptionPadding: CGFloat
            let optionCornerRadius: CGFloat
            let compactOptionCornerRadius: CGFloat
            let editorCornerRadius: CGFloat
            let landing: Landing

            static let standard = OnboardingSurface(
                normalFillOpacity: 0.55,
                selectedFillOpacity: 0.82,
                normalBorderOpacity: 0.32,
                selectedBorderOpacity: 0.45,
                editorBorderOpacity: 0.6,
                editorPadding: 10,
                optionPadding: 12,
                compactOptionPadding: 10,
                optionCornerRadius: 12,
                compactOptionCornerRadius: 10,
                editorCornerRadius: 8,
                landing: Landing(
                    contentWidth: 820,
                    heroPadding: 28,
                    heroIconSize: 48,
                    heroIconFrame: 68,
                    tileSpacing: 12,
                    sectionSpacing: 16,
                    heroCornerRadius: 18
                )
            )
        }

        struct Window {
            let mainMinWidth: CGFloat
            let mainMinHeight: CGFloat
            let onboardingMinWidth: CGFloat
            let onboardingMinHeight: CGFloat

            static let standard = Window(
                mainMinWidth: 800,
                mainMinHeight: 500,
                onboardingMinWidth: 940,
                onboardingMinHeight: 700
            )
        }

        let spacing: Spacing
        let corners: CornerRadius
        let formRow: FormRow
        let pickerControl: PickerControl
        let cardSurface: CardSurface
        let onboardingSurface: OnboardingSurface
        let window: Window
        let cardShadow: Shadow
        let elevatedCardShadow: Shadow
    }

    struct Materials {
        let window: Material
        let sidebar: Material
        let card: Material
        let elevatedCard: Material
        let formRow: Material
        let toolbar: Material
    }

    let palette: Palette
    let typography: Typography
    let metrics: Metrics
    let materials: Materials

    static func adaptive(accent: Color, colorScheme: ColorScheme) -> AppTheme {
        switch colorScheme {
        case .light:
            return .light(accent: accent)
        case .dark:
            return .dark(accent: accent)
        @unknown default:
            return .dark(accent: accent)
        }
    }

    /// Light theme: paper surfaces with ink text and hairlines.
    static func light(accent: Color) -> AppTheme {
        let ink = Color(red: 17 / 255, green: 17 / 255, blue: 18 / 255)

        return AppTheme(
            palette: Palette(
                windowBackground: Color(red: 250 / 255, green: 250 / 255, blue: 250 / 255),
                contentBackground: .white,
                sidebarBackground: Color(red: 246 / 255, green: 246 / 255, blue: 246 / 255),
                cardBackground: .white,
                elevatedCardBackground: .white,
                toolbarBackground: Color(red: 250 / 255, green: 250 / 255, blue: 250 / 255),

                cardBorder: ink.opacity(0.10),
                separator: ink.opacity(0.12),
                primaryText: ink,
                secondaryText: Color(red: 85 / 255, green: 85 / 255, blue: 85 / 255),
                tertiaryText: Color(red: 148 / 255, green: 148 / 255, blue: 148 / 255),
                accent: accent,
                warning: Color(red: 186 / 255, green: 125 / 255, blue: 23 / 255),
                success: Color(red: 31 / 255, green: 160 / 255, blue: 119 / 255),
                error: Color(red: 216 / 255, green: 61 / 255, blue: 87 / 255),
                recording: Color(red: 244 / 255, green: 78 / 255, blue: 102 / 255)
            ),
            typography: .standard,
            metrics: Metrics(
                spacing: .standard,
                corners: .standard,
                formRow: .standard,
                pickerControl: .standard,
                cardSurface: .defaults,
                onboardingSurface: .standard,
                window: .standard,
                cardShadow: .subtle(color: ink, opacity: 0.06),
                elevatedCardShadow: .subtle(color: ink, opacity: 0.10)
            ),
            materials: Materials(
                window: .thinMaterial,
                sidebar: .ultraThinMaterial,
                card: .thinMaterial,
                elevatedCard: .regularMaterial,
                formRow: .ultraThinMaterial,
                toolbar: .ultraThinMaterial
            )
        )
    }

    /// Default dark-forward theme: ink surfaces where borders carry structure.
    static func dark(accent: Color) -> AppTheme {
        AppTheme(
            palette: Palette(
                windowBackground: Color(red: 17 / 255, green: 17 / 255, blue: 18 / 255),
                contentBackground: Color(red: 22 / 255, green: 22 / 255, blue: 23 / 255),
                sidebarBackground: Color(red: 12 / 255, green: 12 / 255, blue: 13 / 255),
                cardBackground: Color(red: 25 / 255, green: 25 / 255, blue: 26 / 255),
                elevatedCardBackground: Color(red: 32 / 255, green: 32 / 255, blue: 33 / 255),
                toolbarBackground: Color(red: 12 / 255, green: 12 / 255, blue: 13 / 255),

                cardBorder: Color.white.opacity(0.08),
                separator: Color.white.opacity(0.12),
                primaryText: Color(red: 246 / 255, green: 246 / 255, blue: 246 / 255),
                secondaryText: Color(red: 197 / 255, green: 197 / 255, blue: 197 / 255),
                tertiaryText: Color(red: 118 / 255, green: 118 / 255, blue: 118 / 255),
                accent: accent,
                warning: Color(red: 230 / 255, green: 186 / 255, blue: 35 / 255),
                success: Color(red: 35 / 255, green: 208 / 255, blue: 156 / 255),
                error: Color(red: 244 / 255, green: 78 / 255, blue: 102 / 255),
                recording: Color(red: 244 / 255, green: 78 / 255, blue: 102 / 255)
            ),
            typography: .standard,
            metrics: Metrics(
                spacing: .standard,
                corners: .standard,
                formRow: .standard,
                pickerControl: .standard,
                cardSurface: .defaults,
                onboardingSurface: .standard,
                window: .standard,
                cardShadow: .subtle(color: .black, opacity: 0.55),
                elevatedCardShadow: .subtle(color: .black, opacity: 0.65)
            ),
            materials: Materials(
                window: .thinMaterial,
                sidebar: .ultraThinMaterial,
                card: .thinMaterial,
                elevatedCard: .regularMaterial,
                formRow: .ultraThinMaterial,
                toolbar: .ultraThinMaterial
            )
        )
    }

    static let light = AppTheme.light(accent: .fluidGreen)
    static let dark = AppTheme.dark(accent: .fluidGreen)
}

// MARK: - Helpers
