import SwiftUI

// MARK: - Pasture Design System
// "A garden tool for your AI" — warm, organic, minimal, Apple-native with personality.
// The sage-to-amber gradient is a subtle thread, not a dominating force.

// ============================================================================
// 1. COLOR TOKENS
// ============================================================================

extension Color {

    // MARK: Brand Gradient
    // The diagonal gradient from the app icon — sage/mint green to warm amber-orange.
    // Used sparingly: Feed button, empty state icon, selection accent.

    /// Sage green — top-left of icon gradient. #8BB88A
    static let pastureSageGreen = Color(red: 0.545, green: 0.722, blue: 0.541)

    /// Warm amber-orange — bottom-right of icon gradient. #E8944A
    static let pastureAmber = Color(red: 0.910, green: 0.580, blue: 0.290)

    /// Mid-point of gradient for single-color accent contexts. #B6A369
    /// Derived from the visual midpoint of sage-to-amber.
    static let pastureMidGradient = Color(red: 0.714, green: 0.639, blue: 0.412)

    // MARK: Accent
    // The primary interactive color. A warm olive-sage that feels organic,
    // not the electric blue of default macOS. Accessible on both light/dark.

    /// Primary accent for buttons, links, focus rings. #6B9F6B
    static let pastureAccent = Color(red: 0.420, green: 0.624, blue: 0.420)

    /// Accent hover/pressed — slightly deeper. #5A8C5A
    static let pastureAccentDeep = Color(red: 0.353, green: 0.549, blue: 0.353)

    // MARK: Sidebar Background

    /// Sidebar background — light mode. Very faint warm gray with a green whisper. #F6F5F2
    static let pastureSidebarLight = Color(red: 0.965, green: 0.961, blue: 0.949)

    /// Sidebar background — dark mode. Deep warm charcoal. #1E1E1C
    static let pastureSidebarDark = Color(red: 0.118, green: 0.118, blue: 0.110)

    // MARK: Editor Background

    /// Editor background — light mode. Warm off-white, like good paper. #FDFCFA
    static let pastureEditorLight = Color(red: 0.992, green: 0.988, blue: 0.980)

    /// Editor background — dark mode. Softer than pure black, warm undertone. #232321
    static let pastureEditorDark = Color(red: 0.137, green: 0.137, blue: 0.129)

    // MARK: Text Hierarchy

    /// Primary text — light mode. Warm near-black. #1A1A18
    static let pastureTextPrimaryLight = Color(red: 0.102, green: 0.102, blue: 0.094)

    /// Primary text — dark mode. Warm off-white. #EDEDEB
    static let pastureTextPrimaryDark = Color(red: 0.929, green: 0.929, blue: 0.922)

    /// Secondary text — light mode. Warm medium gray. #6B6B65
    static let pastureTextSecondaryLight = Color(red: 0.420, green: 0.420, blue: 0.396)

    /// Secondary text — dark mode. #9E9E98
    static let pastureTextSecondaryDark = Color(red: 0.620, green: 0.620, blue: 0.596)

    /// Tertiary text — light mode. Lightest readable gray. #9A9A92
    static let pastureTextTertiaryLight = Color(red: 0.604, green: 0.604, blue: 0.573)

    /// Tertiary text — dark mode. #6B6B65
    static let pastureTextTertiaryDark = Color(red: 0.420, green: 0.420, blue: 0.396)

    // MARK: Semantic Colors

    /// Token count badge text and background tint. Muted sage. #7BA57B
    static let pastureTokenBadge = Color(red: 0.482, green: 0.647, blue: 0.482)

    /// Token count badge background — very light sage wash. #EDF5ED (light) / #2A3A2A (dark)
    static let pastureTokenBadgeBgLight = Color(red: 0.929, green: 0.961, blue: 0.929)
    static let pastureTokenBadgeBgDark = Color(red: 0.165, green: 0.227, blue: 0.165)

    /// Template indicator — warm amber from the icon palette. #D4793B
    static let pastureTemplate = Color(red: 0.831, green: 0.475, blue: 0.231)

    /// Template indicator background tint. #FDF3EB (light) / #3A2E22 (dark)
    static let pastureTemplateBgLight = Color(red: 0.992, green: 0.953, blue: 0.922)
    static let pastureTemplateBgDark = Color(red: 0.227, green: 0.180, blue: 0.133)

    /// Selection/highlight in sidebar — warm sage tint. #E2EDDF (light) / #2E3E2C (dark)
    static let pastureSelectionLight = Color(red: 0.886, green: 0.929, blue: 0.875)
    static let pastureSelectionDark = Color(red: 0.180, green: 0.243, blue: 0.173)

    /// Status bar background. Slightly darker than editor. #F2F1EE (light) / #1A1A18 (dark)
    static let pastureStatusBarLight = Color(red: 0.949, green: 0.945, blue: 0.933)
    static let pastureStatusBarDark = Color(red: 0.102, green: 0.102, blue: 0.094)

    /// Divider/separator. Warm, not cold gray. #E0DFD9 (light) / #2E2E2A (dark)
    static let pastureDividerLight = Color(red: 0.878, green: 0.875, blue: 0.851)
    static let pastureDividerDark = Color(red: 0.180, green: 0.180, blue: 0.165)

    /// Grass dark green from icon — for decorative elements only. #2D6B3F
    static let pastureGrassDark = Color(red: 0.176, green: 0.420, blue: 0.247)

    /// Grass medium green from icon. #4A8B5C
    static let pastureGrassMedium = Color(red: 0.290, green: 0.545, blue: 0.361)

    static let pastureGrassOrange = pastureTemplate

    /// Error/destructive. Warm red, not cold. #C94040
    static let pastureError = Color(red: 0.788, green: 0.251, blue: 0.251)

    /// Success. Uses our sage family. #5A9F5A
    static let pastureSuccess = Color(red: 0.353, green: 0.624, blue: 0.353)
}

// MARK: - Adaptive Color Helpers (resolves light/dark automatically)

extension Color {

    /// Sidebar background — adapts to color scheme.
    static func pastureSidebar(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .pastureSidebarDark : .pastureSidebarLight
    }

    /// Editor background — adapts to color scheme.
    static func pastureEditor(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .pastureEditorDark : .pastureEditorLight
    }

    /// Primary text — adapts to color scheme.
    static func pastureTextPrimary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .pastureTextPrimaryDark : .pastureTextPrimaryLight
    }

    /// Secondary text — adapts to color scheme.
    static func pastureTextSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .pastureTextSecondaryDark : .pastureTextSecondaryLight
    }

    /// Tertiary text — adapts to color scheme.
    static func pastureTextTertiary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .pastureTextTertiaryDark : .pastureTextTertiaryLight
    }

    /// Selection highlight — adapts to color scheme.
    static func pastureSelection(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .pastureSelectionDark : .pastureSelectionLight
    }

    /// Status bar — adapts to color scheme.
    static func pastureStatusBar(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .pastureStatusBarDark : .pastureStatusBarLight
    }

    /// Divider — adapts to color scheme.
    static func pastureDivider(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .pastureDividerDark : .pastureDividerLight
    }

    /// Token badge background — adapts to color scheme.
    static func pastureTokenBadgeBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .pastureTokenBadgeBgDark : .pastureTokenBadgeBgLight
    }

    /// Template indicator background — adapts to color scheme.
    static func pastureTemplateBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .pastureTemplateBgDark : .pastureTemplateBgLight
    }
}

// MARK: - Gradients

extension LinearGradient {

    /// The brand gradient — sage green to warm amber. Used on the Feed button
    /// and as a decorative accent. Flows top-leading to bottom-trailing
    /// to mirror the icon's diagonal energy.
    static let pastureBrand = LinearGradient(
        colors: [.pastureSageGreen, .pastureAmber],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Subtle sidebar gradient — nearly invisible warmth. Top is slightly
    /// cooler, bottom slightly warmer. Creates organic depth.
    static func pastureSidebarGradient(_ scheme: ColorScheme) -> LinearGradient {
        let base = scheme == .dark
            ? Color.pastureSidebarDark
            : Color.pastureSidebarLight
        return LinearGradient(
            colors: [base, base.opacity(0.95)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Feed button gradient — the hero gradient. More saturated than the
    /// brand gradient to draw the eye.
    static let pastureFeedButton = LinearGradient(
        colors: [
            Color(red: 0.498, green: 0.753, blue: 0.498), // #7FC07F — lively sage
            Color(red: 0.890, green: 0.557, blue: 0.267), // #E38E44 — warm amber
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Feed button hover — slightly brighter.
    static let pastureFeedButtonHover = LinearGradient(
        colors: [
            Color(red: 0.557, green: 0.800, blue: 0.557), // brighter sage
            Color(red: 0.937, green: 0.612, blue: 0.325), // brighter amber
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// ============================================================================
// 2. TYPOGRAPHY
// ============================================================================

extension Font {

    // Sidebar
    /// File name in sidebar row. System body, medium weight for scanability.
    static let pastureFileName: Font = .system(.body, design: .default, weight: .medium)

    /// File date in sidebar row. Small, secondary.
    static let pastureFileDate: Font = .system(.caption2, design: .default, weight: .regular)

    /// Token count in sidebar row. Tabular figures for alignment.
    static let pastureTokenCount: Font = .system(.caption2, design: .monospaced, weight: .medium)

    /// Token count inside a badge (larger context like summary bar).
    static let pastureTokenBadge: Font = .system(.caption, design: .monospaced, weight: .semibold)

    // Editor
    /// Editor text — monospaced for markdown editing. 13pt base.
    static let pastureEditor: Font = .system(size: 13, weight: .regular, design: .monospaced)

    /// Editor text — alternative proportional option for prose-heavy files.
    static let pastureEditorProse: Font = .system(size: 14, weight: .regular, design: .serif)

    // Status bar
    /// Status bar labels. Small and unobtrusive.
    static let pastureStatusBar: Font = .system(.caption, design: .default, weight: .regular)

    // Sheets
    /// Sheet heading. Clear, not heavy.
    static let pastureSheetHeading: Font = .system(.headline, design: .default, weight: .semibold)

    /// Sheet subheading / description.
    static let pastureSheetSubheading: Font = .system(.subheadline, design: .default, weight: .regular)

    /// Template variable name in sheets. Monospaced for code feel.
    static let pastureTemplateVar: Font = .system(.body, design: .monospaced, weight: .medium)

    // Empty state
    /// Empty state heading. Warm and inviting, slightly larger.
    static let pastureEmptyHeading: Font = .system(.title2, design: .rounded, weight: .medium)

    /// Empty state subtext.
    static let pastureEmptySubtext: Font = .system(.subheadline, design: .default, weight: .regular)

    /// Empty state hint (template syntax, etc.)
    static let pastureEmptyHint: Font = .system(.caption, design: .monospaced, weight: .regular)

    // Toolbar
    /// Toolbar button labels (when text is visible).
    static let pastureToolbarLabel: Font = .system(.callout, design: .default, weight: .medium)

    // Selection summary bar
    /// Summary bar text (file count, token count).
    static let pastureSummary: Font = .system(.caption, design: .default, weight: .medium)

    // Search
    /// Search field text.
    static let pastureSearch: Font = .system(.body, design: .default, weight: .regular)
}

// ============================================================================
// 3. SPACING & LAYOUT
// ============================================================================

enum PastureLayout {

    // MARK: Sidebar
    /// Sidebar width range (NavigationSplitView column).
    static let sidebarMinWidth: CGFloat = 220
    static let sidebarIdealWidth: CGFloat = 260
    static let sidebarMaxWidth: CGFloat = 360

    // MARK: File Row
    /// Vertical padding inside each file row.
    static let fileRowVerticalPadding: CGFloat = 6     // 3pt above + 3pt below the content
    /// Horizontal padding inside each file row (beyond list inset).
    static let fileRowHorizontalPadding: CGFloat = 4
    /// Spacing between file name and date line.
    static let fileRowInternalSpacing: CGFloat = 2
    /// Spacing between template icon and file name.
    static let fileRowIconSpacing: CGFloat = 4
    /// Corner radius for token count badge in row.
    static let tokenBadgeRadius: CGFloat = 4
    /// Padding inside token badge.
    static let tokenBadgeHPadding: CGFloat = 6
    static let tokenBadgeVPadding: CGFloat = 2

    // MARK: Editor
    /// Editor text padding from edges.
    static let editorPadding: CGFloat = 16
    /// Editor top padding (extra breathing room).
    static let editorTopPadding: CGFloat = 12

    // MARK: Status Bar
    /// Status bar total height.
    static let statusBarHeight: CGFloat = 28
    /// Status bar horizontal padding.
    static let statusBarHPadding: CGFloat = 12
    /// Status bar vertical padding.
    static let statusBarVPadding: CGFloat = 6

    // MARK: Search Bar
    /// Search bar total height (including padding).
    static let searchBarHeight: CGFloat = 36
    /// Search bar horizontal padding.
    static let searchBarHPadding: CGFloat = 12
    /// Search bar vertical padding.
    static let searchBarVPadding: CGFloat = 8
    /// Search bar icon-to-text spacing.
    static let searchBarIconSpacing: CGFloat = 8

    // MARK: Selection Summary Bar
    /// Summary bar height.
    static let summaryBarHeight: CGFloat = 28
    /// Summary bar horizontal padding.
    static let summaryBarHPadding: CGFloat = 12
    /// Summary bar vertical padding.
    static let summaryBarVPadding: CGFloat = 6

    // MARK: Sheets
    /// Sheet internal padding.
    static let sheetPadding: CGFloat = 24
    /// Sheet element spacing.
    static let sheetSpacing: CGFloat = 20
    /// Paste/Merge sheet minimum width.
    static let sheetMinWidth: CGFloat = 380
    /// Template sheet minimum width (wider for variable table).
    static let templateSheetMinWidth: CGFloat = 500
    /// Template variable name column width.
    static let templateVarLabelWidth: CGFloat = 160
    /// Template variable input width.
    static let templateVarInputWidth: CGFloat = 260
    /// Sheet button spacing.
    static let sheetButtonSpacing: CGFloat = 12

    // MARK: Toast / Feedback
    /// Toast horizontal padding.
    static let toastHPadding: CGFloat = 16
    /// Toast vertical padding.
    static let toastVPadding: CGFloat = 10
    /// Toast bottom offset from window edge.
    static let toastBottomOffset: CGFloat = 20
    /// Toast corner radius (capsule, so this is large).
    static let toastRadius: CGFloat = 20

    // MARK: Empty State
    /// Empty state icon size.
    static let emptyStateIconSize: CGFloat = 56
    /// Empty state vertical spacing between elements.
    static let emptyStateSpacing: CGFloat = 12

    // MARK: Feed Button (Hero)
    /// Feed button corner radius.
    static let feedButtonRadius: CGFloat = 8
    /// Feed button horizontal padding (when styled as prominent).
    static let feedButtonHPadding: CGFloat = 14
    /// Feed button vertical padding.
    static let feedButtonVPadding: CGFloat = 6
}

// ============================================================================
// 4. VISUAL EFFECTS
// ============================================================================

enum PastureEffects {

    // MARK: Corner Radii
    /// Default corner radius for cards, sheets, popovers.
    static let cornerRadius: CGFloat = 10
    /// Small corner radius for badges, pills.
    static let cornerRadiusSmall: CGFloat = 4
    /// Large corner radius for modal sheets.
    static let cornerRadiusLarge: CGFloat = 14

    // MARK: Shadows
    // Shadows are warm-tinted (not pure black) to maintain the organic feel.

    /// Subtle shadow for file rows on hover.
    static let shadowHover = ShadowSpec(
        color: Color.black.opacity(0.06),
        radius: 4,
        x: 0,
        y: 2
    )

    /// Medium shadow for floating elements (toasts, popovers).
    static let shadowFloat = ShadowSpec(
        color: Color.black.opacity(0.10),
        radius: 12,
        x: 0,
        y: 4
    )

    /// Strong shadow for sheets/modals.
    static let shadowModal = ShadowSpec(
        color: Color.black.opacity(0.15),
        radius: 24,
        x: 0,
        y: 8
    )

    // MARK: Animation Timings

    /// Quick micro-interaction (button press, badge appear). 150ms.
    static let animationQuick: Double = 0.15

    /// Standard transition (sheet present, selection change). 250ms.
    static let animationStandard: Double = 0.25

    /// Slow, deliberate animation (empty state appear, feed success). 400ms.
    static let animationSlow: Double = 0.40

    /// Spring animation for bouncy feedback (toast slide-up).
    static let springResponse: Double = 0.45
    static let springDamping: Double = 0.75

    // MARK: Material / Blur

    /// Toast background material — .regularMaterial provides the frosted glass
    /// effect that feels native on macOS. Tinted slightly warm.
    /// Use: .background(.regularMaterial) on the toast capsule.

    /// Sidebar uses .sidebar material when available (macOS 14+),
    /// falling back to our custom sidebar colors.
    /// The sidebar should feel translucent in the title bar area.
}

/// Helper struct for shadow specifications.
struct ShadowSpec {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension View {
    func pastureShadow(_ spec: ShadowSpec) -> some View {
        self.shadow(color: spec.color, radius: spec.radius, x: spec.x, y: spec.y)
    }
}

