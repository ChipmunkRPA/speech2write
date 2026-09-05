//
//  NotchOverlayManager.swift
//  Fluid
//
//  Created by Assistant
//

import AppKit
import Combine
import DynamicNotchKit
import SwiftUI

// MARK: - Overlay Mode

enum OverlayMode: String {
    case dictation = "Dictation"
    case edit = "Edit"
    case rewrite = "Rewrite"
    case write = "Write"
}

@MainActor
final class NotchOverlayManager {
    static let shared = NotchOverlayManager()

    struct NotchPresentationPolicy: Equatable {
        let usesCompactPresentation: Bool
        let showsPromptSelector: Bool
        let showsStreamingPreview: Bool
        let showsModeLabel: Bool
    }

    private var notch: DynamicNotch<NotchExpandedView, NotchCompactLeadingView, NotchCompactTrailingView, NotchCompactBottomView>?
    private var currentMode: OverlayMode = .dictation

    /// Store last audio publisher for re-showing during processing
    private var lastAudioPublisher: AnyPublisher<CGFloat, Never>?

    /// Current audio publisher (can be updated for expanded notch recording)
    @Published private(set) var currentAudioPublisher: AnyPublisher<CGFloat, Never>?

    /// State machine to prevent race conditions
    private enum State {
        case idle
        case showing
        case visible
        case hiding
    }

    private var state: State = .idle

    /// Track if bottom overlay is visible
    private(set) var isBottomOverlayVisible: Bool = false
    var isOverlayVisible: Bool { self.state == .visible }

    // Generation counter to track show/hide cycles and prevent race conditions
    // Uses UInt64 to avoid overflow concerns in long-running sessions
    private var generation: UInt64 = 0

    /// Track pending retry task for cancellation
    private var pendingRetryTask: Task<Void, Never>?

    // Cancel shortcut monitors for dismissing notch / overlay
    private var globalEscapeMonitor: Any?
    private var localEscapeMonitor: Any?

    private(set) var currentNotchPresentationMode: SettingsStore.NotchPresentationMode = .standard
    private(set) var currentNotchPresentationPolicy = NotchPresentationPolicy.standard
    private(set) var currentScreenSupportsCompactPresentation = false
    private var presentationPolicyScreen: NSScreen?
    private static let transientOverlayStatusTexts: Set<String> = [
        "Transcribing",
        "Refining",
        "Thinking",
        "Working",
        "Transcribing...",
        "Refining...",
        "Thinking...",
        "Working...",
        "Reprocessing...",
    ]

    private init() {
        self.refreshNotchPresentationPolicy()
        self.setupEscapeKeyMonitors()
    }

    deinit {
        if let monitor = globalEscapeMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localEscapeMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// Setup cancel shortcut monitors - both global (other apps) and local (our app)
    private func setupEscapeKeyMonitors() {
        let escapeHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            guard SettingsStore.shared.cancelRecordingHotkeyShortcut.matches(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags
            ) else { return event }

            Task { @MainActor in
                guard self != nil else { return }
                NotchContentState.shared.onCancelRequested?()
            }
            return nil // Consume the event
        }

        // Global monitor - catches the cancel shortcut when OTHER apps have focus
        self.globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            _ = escapeHandler(event)
        }
    }

    func show(audioLevelPublisher: AnyPublisher<CGFloat, Never>, mode: OverlayMode) {
        self.refreshNotchPresentationPolicy()
        Self.overlayBench("show_called mode=\(mode.rawValue) state=\(self.state)")

        // Cancel any pending retry operations
        self.pendingRetryTask?.cancel()
        self.pendingRetryTask = nil

        // If already visible or in transition, wait for cleanup to complete
        if self.notch != nil || self.state != .idle {
            Self.overlayBench("show_retry_after_cleanup state=\(self.state) notchExists=\(self.notch != nil)")

            // Increment generation to invalidate stale operations
            self.generation &+= 1
            let targetGeneration = self.generation

            // Start async cleanup and retry
            self.pendingRetryTask = Task { [weak self] in
                guard let self = self else { return }

                // Perform cleanup synchronously first
                await self.performCleanup()

                // Small delay to ensure cleanup completes
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

                // Check if we're still the active operation
                guard !Task.isCancelled, self.generation == targetGeneration else { return }

                // Retry show
                self.showInternal(audioLevelPublisher: audioLevelPublisher, mode: mode)
            }
            return
        }

        self.showInternal(audioLevelPublisher: audioLevelPublisher, mode: mode)
    }

    private func showInternal(audioLevelPublisher: AnyPublisher<CGFloat, Never>, mode: OverlayMode) {
        Self.overlayBench("show_internal_enter mode=\(mode.rawValue) state=\(self.state)")
        guard self.state == .idle else { return }

        // Store for potential re-show during processing
        self.lastAudioPublisher = audioLevelPublisher

        // Start monitoring active app changes (updates icon in real-time)
        ActiveAppMonitor.shared.startMonitoring()
        let targetScreen = OverlayScreenResolver.screenForCurrentPointer()

        // Route to bottom overlay if user preference is set
        if SettingsStore.shared.overlayPosition == .bottom {
            Self.overlayBench("show_internal_route target=bottom")
            self.showBottomOverlay(audioLevelPublisher: audioLevelPublisher, mode: mode)
            return
        }

        // Otherwise show notch overlay (original behavior)
        Self.overlayBench("show_internal_route target=notch")
        self.showNotchOverlay(audioLevelPublisher: audioLevelPublisher, mode: mode, screen: targetScreen)
    }

    /// Show bottom overlay (alternative to notch)
    private func showBottomOverlay(audioLevelPublisher: AnyPublisher<CGFloat, Never>, mode: OverlayMode) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        Self.overlayBench("bottom_route_start mode=\(mode.rawValue)")

        // Hide any existing notch first
        if self.notch != nil {
            Task { await self.performCleanup() }
        }

        self.lastAudioPublisher = audioLevelPublisher
        self.currentMode = self.normalizedOverlayMode(mode)

        BottomOverlayWindowController.shared.show(audioPublisher: audioLevelPublisher, mode: self.currentMode)
        self.isBottomOverlayVisible = true
        Self.overlayBench("bottom_route_return elapsedMs=\(Self.elapsedMs(since: startedAt))")
    }

    /// Show notch overlay (original behavior)
    private func showNotchOverlay(audioLevelPublisher: AnyPublisher<CGFloat, Never>, mode: OverlayMode, screen: NSScreen?) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let targetScreen = screen ?? self.preferredPresentationScreen()
        self.presentationPolicyScreen = targetScreen
        self.refreshNotchPresentationPolicy(for: targetScreen)
        self.currentAudioPublisher = audioLevelPublisher
        // Hide bottom overlay if it was visible
        if self.isBottomOverlayVisible {
            BottomOverlayWindowController.shared.hide()
            self.isBottomOverlayVisible = false
        }

        // Increment generation for this operation
        self.generation &+= 1
        let currentGeneration = self.generation

        self.state = .showing
        self.currentMode = self.normalizedOverlayMode(mode)

        // Update shared content state immediately
        NotchContentState.shared.mode = self.currentMode
        self.syncPromptPickerMode(for: self.currentMode)
        NotchContentState.shared.updateTranscription("")

        // Create notch with SwiftUI views
        let newNotch = DynamicNotch(
            hoverBehavior: [], // Recording overlays should dismiss even if hover state gets stale.
            style: .auto
        ) {
            NotchExpandedView(audioPublisher: audioLevelPublisher)
        } compactLeading: {
            NotchCompactLeadingView()
        } compactTrailing: {
            NotchCompactTrailingView(audioPublisher: audioLevelPublisher)
        } compactBottom: {
            NotchCompactBottomView()
        }

        self.notch = newNotch
        let shouldUseCompactPresentation = self.currentNotchPresentationPolicy.usesCompactPresentation
        let presentation = shouldUseCompactPresentation ? "compact" : "expanded"
        Self.overlayBench("notch_task_scheduled mode=\(self.currentMode.rawValue) presentation=\(presentation) screen=\(targetScreen.localizedName)")

        // Resolve presentation from policy so future notch modes don't require call-site changes.
        Task { [weak self] in
            Self.overlayBench("notch_animation_start presentation=\(presentation)")
            if shouldUseCompactPresentation {
                await newNotch.compact(on: targetScreen)
            } else {
                await newNotch.expand(on: targetScreen)
            }
            Self.overlayBench("notch_animation_complete presentation=\(presentation) elapsedMs=\(Self.elapsedMs(since: startedAt))")
            // Only update state if we're still the active generation
            guard let self = self, self.generation == currentGeneration else {
                Self.overlayBench("notch_visible_drop reason=stale_generation")
                return
            }
            self.state = .visible
            Self.overlayBench("state_visible target=notch presentation=\(presentation)")
        }
    }

    func hide() {
        let startedAt = ProcessInfo.processInfo.systemUptime
        Self.overlayBench("hide_called state=\(self.state) bottomVisible=\(self.isBottomOverlayVisible)")

        // Stop monitoring active app changes
        ActiveAppMonitor.shared.stopMonitoring()

        // Hide bottom overlay if visible
        if self.isBottomOverlayVisible {
            BottomOverlayWindowController.shared.hide()
            self.isBottomOverlayVisible = false
        }

        // Cancel any pending retry operations
        self.pendingRetryTask?.cancel()
        self.pendingRetryTask = nil

        // Safety: reset processing state when hiding
        NotchContentState.shared.setProcessing(false)

        // Increment generation to invalidate any pending show tasks
        self.generation &+= 1
        let currentGeneration = self.generation

        // Handle visible or showing states (can hide while still expanding)
        guard self.state == .visible || self.state == .showing, let currentNotch = notch else {
            // Force cleanup if stuck or in inconsistent state
            Self.overlayBench("hide_return reason=not_visible state=\(self.state) notchExists=\(self.notch != nil)")
            Task { [weak self] in await self?.performCleanup() }
            return
        }

        self.state = .hiding

        Task { [weak self] in
            Self.overlayBench("hide_animation_start")
            await currentNotch.hide()
            Self.overlayBench("hide_animation_complete elapsedMs=\(Self.elapsedMs(since: startedAt))")
            // Only clear if we're still the active operation
            guard let self = self, self.generation == currentGeneration else { return }
            self.notch = nil
            self.state = .idle
            Self.overlayBench("state_idle target=notch")
        }
    }

    /// Async cleanup that properly waits for hide to complete
    private func performCleanup() async {
        let startedAt = ProcessInfo.processInfo.systemUptime
        Self.overlayBench("cleanup_start state=\(self.state) notchExists=\(self.notch != nil)")

        // Cancel any pending retry operations
        self.pendingRetryTask?.cancel()
        self.pendingRetryTask = nil

        if let existingNotch = notch {
            await existingNotch.hide()
        }
        self.notch = nil
        self.state = .idle
        Self.overlayBench("cleanup_complete elapsedMs=\(Self.elapsedMs(since: startedAt))")
    }

    func setMode(_ mode: OverlayMode) {
        self.refreshNotchPresentationPolicy()
        Self.overlayBench("set_mode mode=\(mode.rawValue)")

        // Always update NotchContentState to ensure UI stays in sync
        // (can get out of sync during show/hide transitions)
        let normalized = self.normalizedOverlayMode(mode)
        self.currentMode = normalized
        NotchContentState.shared.mode = normalized
        self.syncPromptPickerMode(for: normalized)
    }

    func switchLiveOverlayMode(to promptMode: SettingsStore.PromptMode) {
        guard !NotchContentState.shared.isProcessing else { return }
        switch promptMode.normalized {
        case .dictate:
            self.setMode(.dictation)
        case .edit:
            self.setMode(.edit)
        case .write, .rewrite:
            self.setMode(.edit)
        }
    }

    func updateTranscriptionText(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty || Self.transientOverlayStatusTexts.contains(trimmedText) {
            Self.overlayBench("text_update status=\(trimmedText.isEmpty ? "empty" : trimmedText)")
        }

        guard self.shouldShowOrTrackLivePreviewText else {
            if trimmedText.isEmpty || Self.transientOverlayStatusTexts.contains(trimmedText) {
                NotchContentState.shared.updateTranscription(text)
            } else if !NotchContentState.shared.transcriptionText.isEmpty {
                NotchContentState.shared.updateTranscription("")
            }
            return
        }
        NotchContentState.shared.updateTranscription(text)
    }

    func setProcessing(_ processing: Bool) {
        Self.overlayBench("set_processing processing=\(processing) state=\(self.state) bottomVisible=\(self.isBottomOverlayVisible)")
        NotchContentState.shared.setProcessing(processing)

        // If bottom overlay is visible, update its processing state
        if self.isBottomOverlayVisible {
            BottomOverlayWindowController.shared.setProcessing(processing)
            Self.overlayBench("set_processing_forwarded target=bottom")
            return
        }

        if processing {
            // If notch isn't visible, re-show it for processing state
            if self.state == .idle || self.state == .hiding {
                Self.overlayBench("set_processing_reshow state=\(self.state)")
                // Use stored publisher or create empty one
                let publisher = self.lastAudioPublisher ?? Empty<CGFloat, Never>().eraseToAnyPublisher()
                self.show(audioLevelPublisher: publisher, mode: self.currentMode)
            }
        }
    }

    private static func overlayBench(_ message: String) {
        DebugLogger.shared.benchmark("OVERLAY_BENCH", message: "notch \(message)", source: "OverlayBenchmark")
    }

    private static func elapsedMs(since start: TimeInterval) -> Int {
        Int(((ProcessInfo.processInfo.systemUptime - start) * 1000).rounded())
    }

    private func syncPromptPickerMode(for mode: OverlayMode) {
        switch mode {
        case .dictation:
            NotchContentState.shared.promptPickerMode = .dictate
        case .edit, .write, .rewrite:
            NotchContentState.shared.promptPickerMode = .edit
        }
    }

    private func normalizedOverlayMode(_ mode: OverlayMode) -> OverlayMode {
        switch mode {
        case .write, .rewrite:
            return .edit
        case .dictation, .edit:
            return mode
        }
    }

    var shouldShowOrTrackLivePreviewText: Bool {
        guard SettingsStore.shared.enableStreamingPreview else { return false }
        if SettingsStore.shared.overlayPosition == .bottom {
            return true
        }

        self.refreshNotchPresentationPolicy()
        return self.currentNotchPresentationPolicy.showsStreamingPreview
    }

    /// Check if any notch is visible
    var isAnyNotchVisible: Bool {
        return self.state == .visible || self.state == .showing
    }

    /// Update audio publisher for expanded notch (when recording starts within it)
    func updateAudioPublisher(_ publisher: AnyPublisher<CGFloat, Never>) {
        self.lastAudioPublisher = publisher
        self.currentAudioPublisher = publisher
    }

    private func preferredPresentationScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        if let screenUnderMouse = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screenUnderMouse
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private func supportsCompactPresentation(on screen: NSScreen) -> Bool {
        screen.auxiliaryTopLeftArea?.width != nil && screen.auxiliaryTopRightArea?.width != nil
    }

    private func refreshNotchPresentationPolicy(for screen: NSScreen? = nil) {
        let mode = SettingsStore.shared.notchPresentationMode
        self.currentNotchPresentationMode = mode
        let resolvedScreen = screen ?? self.presentationPolicyScreen ?? self.preferredPresentationScreen()
        self.currentScreenSupportsCompactPresentation = self.supportsCompactPresentation(on: resolvedScreen)
        self.currentNotchPresentationPolicy = .forMode(
            mode,
            supportsCompactPresentation: self.currentScreenSupportsCompactPresentation
        )
    }
}

private extension NotchOverlayManager.NotchPresentationPolicy {
    static let standard = Self(
        usesCompactPresentation: false,
        showsPromptSelector: true,
        showsStreamingPreview: true,
        showsModeLabel: true
    )

    static let minimal = Self(
        usesCompactPresentation: true,
        showsPromptSelector: false,
        showsStreamingPreview: true,
        showsModeLabel: true
    )

    static func forMode(_ mode: SettingsStore.NotchPresentationMode, supportsCompactPresentation: Bool) -> Self {
        switch mode {
        case .standard:
            return .standard
        case .minimal:
            return supportsCompactPresentation ? .minimal : .standard
        }
    }
}
