//
//  EnvironmentValues+Extensions.swift
//  DynamicNotchKit
//
//  Created by Kai Azim on 2025-03-26.
//

import SwiftUI

private struct NotchStyleEnvironmentKey: EnvironmentKey {
    static let defaultValue: DynamicNotchStyle = .auto
}

private struct NotchSectionEnvironmentKey: EnvironmentKey {
    static let defaultValue: DynamicNotchSection = .expanded
}

extension EnvironmentValues {
    var notchStyle: DynamicNotchStyle {
        get { self[NotchStyleEnvironmentKey.self] }
        set { self[NotchStyleEnvironmentKey.self] = newValue }
    }

    var notchSection: DynamicNotchSection {
        get { self[NotchSectionEnvironmentKey.self] }
        set { self[NotchSectionEnvironmentKey.self] = newValue }
    }
}

enum DynamicNotchSection {
    case expanded
    case compactLeading
    case compactTrailing
    case compactBottom
}
