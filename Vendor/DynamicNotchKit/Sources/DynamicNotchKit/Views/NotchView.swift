//
//  NotchView.swift
//  DynamicNotchKit
//
//  Created by Kai Azim on 2023-08-24.
//

import SwiftUI

struct NotchView<Expanded, CompactLeading, CompactTrailing, CompactBottom>: View where Expanded: View, CompactLeading: View, CompactTrailing: View, CompactBottom: View {
    @ObservedObject private var dynamicNotch: DynamicNotch<Expanded, CompactLeading, CompactTrailing, CompactBottom>
    @State private var compactLeadingWidth: CGFloat = 0
    @State private var compactTrailingWidth: CGFloat = 0
    @State private var compactBottomHeight: CGFloat = 0
    private let safeAreaInset: CGFloat = 15

    init(dynamicNotch: DynamicNotch<Expanded, CompactLeading, CompactTrailing, CompactBottom>) {
        self.dynamicNotch = dynamicNotch
    }

    private var expandedNotchCornerRadii: (top: CGFloat, bottom: CGFloat) {
        if case let .notch(topCornerRadius, bottomCornerRadius) = dynamicNotch.style {
            (top: topCornerRadius, bottom: bottomCornerRadius)
        } else {
            (top: 15, bottom: 20)
        }
    }

    private var compactNotchCornerRadii: (top: CGFloat, bottom: CGFloat) {
        (top: 6, bottom: 14)
    }

    private var minWidth: CGFloat {
        dynamicNotch.notchSize.width + (topCornerRadius * 2)
    }

    private var compactContentHeight: CGFloat {
        dynamicNotch.notchSize.height + compactBottomHeight
    }

    private var topCornerRadius: CGFloat {
        dynamicNotch.state == .expanded ? expandedNotchCornerRadii.top : compactNotchCornerRadii.top
    }

    private var bottomCornerRadius: CGFloat {
        dynamicNotch.state == .expanded ? expandedNotchCornerRadii.bottom : compactNotchCornerRadii.bottom
    }

    private var compactSideWidth: CGFloat {
        max(compactLeadingWidth, compactTrailingWidth)
    }

    private var maskHeight: CGFloat? {
        dynamicNotch.state == .compact ? compactContentHeight : nil
    }

    private var edgeOpacity: Double {
        switch dynamicNotch.state {
        case .hidden:
            0.0
        case .compact:
            dynamicNotch.isHovering ? 0.11 : 0.08
        case .expanded:
            dynamicNotch.isHovering ? 0.08 : 0.05
        }
    }

    @ViewBuilder
    private var notchMaskShape: some View {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
        .padding(.horizontal, 0.5)
        .frame(
            width: dynamicNotch.state != .hidden ? nil : minWidth,
            height: maskHeight
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var body: some View {
        notchContent()
            .background {
                Rectangle()
                    .foregroundStyle(.black)
                    .padding(-50)
            }
            .overlay {
                Color.clear
                    .overlay {
                        NotchShape(
                            topCornerRadius: topCornerRadius,
                            bottomCornerRadius: bottomCornerRadius
                        )
                        .stroke(.white.opacity(edgeOpacity), lineWidth: 0.8)
                        .padding(.horizontal, 0.9)
                        .padding(.vertical, 0.4)
                    }
                    .mask { notchMaskShape }
            }
            .mask { notchMaskShape }
            .animation(.smooth, value: [compactLeadingWidth, compactTrailingWidth, compactBottomHeight])
    }

    private func notchContent() -> some View {
        ZStack {
            compactContent()
                .fixedSize()
                .frame(
                    width: dynamicNotch.state == .compact ? nil : dynamicNotch.notchSize.width,
                    height: dynamicNotch.state == .compact ? compactContentHeight : dynamicNotch.notchSize.height
                )

            expandedContent()
                .fixedSize()
                .frame(
                    maxWidth: dynamicNotch.state == .expanded ? nil : 0,
                    maxHeight: dynamicNotch.state == .expanded ? nil : 0
                )
        }
        .padding(.horizontal, topCornerRadius)
        .fixedSize()
        .frame(minWidth: minWidth, minHeight: dynamicNotch.state == .compact ? compactContentHeight : dynamicNotch.notchSize.height)
        .onHover(perform: dynamicNotch.updateHoverState)
    }

    func compactContent() -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if dynamicNotch.state == .compact, !dynamicNotch.disableCompactLeading {
                    dynamicNotch.compactLeadingContent
                        .environment(\.notchSection, .compactLeading)
                        .safeAreaInset(edge: .leading, spacing: 0) { Color.clear.frame(width: 8) }
                        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 4) }
                        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 8) }
                        .onGeometryChange(for: CGFloat.self, of: \.size.width) { compactLeadingWidth = $0 }
                        .frame(width: compactSideWidth, alignment: .trailing)
                        .transition(.blur(intensity: 10).combined(with: .scale(x: 0, anchor: .trailing)).combined(with: .opacity))
                }

                Spacer()
                    .frame(width: dynamicNotch.notchSize.width)

                if dynamicNotch.state == .compact, !dynamicNotch.disableCompactTrailing {
                    dynamicNotch.compactTrailingContent
                        .environment(\.notchSection, .compactTrailing)
                        .safeAreaInset(edge: .trailing, spacing: 0) { Color.clear.frame(width: 8) }
                        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 4) }
                        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 8) }
                        .onGeometryChange(for: CGFloat.self, of: \.size.width) { compactTrailingWidth = $0 }
                        .frame(width: compactSideWidth, alignment: .leading)
                        .transition(.blur(intensity: 10).combined(with: .scale(x: 0, anchor: .leading)).combined(with: .opacity))
                }
            }
            .frame(height: dynamicNotch.notchSize.height)

            if dynamicNotch.state == .compact, !dynamicNotch.disableCompactBottom {
                dynamicNotch.compactBottomContent
                    .environment(\.notchSection, .compactBottom)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { compactBottomHeight = $0 }
                    .transition(.blur(intensity: 10).combined(with: .scale(y: 0, anchor: .top)).combined(with: .opacity))
            }
        }
        .onChange(of: dynamicNotch.disableCompactLeading) { _ in
            if dynamicNotch.disableCompactLeading {
                compactLeadingWidth = 0
            }
        }
        .onChange(of: dynamicNotch.disableCompactTrailing) { _ in
            if dynamicNotch.disableCompactTrailing {
                compactTrailingWidth = 0
            }
        }
        .onChange(of: dynamicNotch.disableCompactBottom) { _ in
            if dynamicNotch.disableCompactBottom {
                compactBottomHeight = 0
            }
        }
    }

    func expandedContent() -> some View {
        HStack(spacing: 0) {
            if dynamicNotch.state == .expanded {
                dynamicNotch.expandedContent
                    .transition(.blur(intensity: 10).combined(with: .scale(y: 0.6, anchor: .top)).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: dynamicNotch.notchSize.height) }
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: safeAreaInset) }
        .safeAreaInset(edge: .leading, spacing: 0) { Color.clear.frame(width: safeAreaInset) }
        .safeAreaInset(edge: .trailing, spacing: 0) { Color.clear.frame(width: safeAreaInset) }
        .frame(minWidth: dynamicNotch.notchSize.width)
    }
}
