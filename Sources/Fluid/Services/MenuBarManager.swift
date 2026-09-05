import AppKit
import Combine
import SwiftUI

enum MenuBarNavigationDestination: String {
    case customDictionary
    case preferences
}

@MainActor
final class MenuBarManager: NSObject, ObservableObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var isSetup: Bool = false
    private var hostedWindow: NSWindow?

    // Cached menu items to avoid rebuilding entire menu
    private var statusMenuItem: NSMenuItem?
    private var microphoneMenuItem: NSMenuItem?
    private var microphoneSubmenu: NSMenu?

    // References to app state
    private weak var asrService: ASRService?
    private var cancellables = Set<AnyCancellable>()

    /// Overlay management (persistent, independent of window lifecycle)
    private var overlayVisible: Bool = false

    /// Track when AI processing is active.
    /// When recording stops, ASRService flips `isRunning` to false, which would normally hide the
    /// overlay. During post-processing we want the overlay to stay visible until processing ends.
    private var isProcessingActive: Bool = false

    @Published var isRecording: Bool = false

    /// One-shot navigation requests from the menu bar into the main window UI.
    /// `ContentView` consumes this and clears it.
    @Published var requestedNavigationDestination: MenuBarNavigationDestination? = nil

    /// Track current overlay mode for notch
    private var currentOverlayMode: OverlayMode = .dictation

    // Track pending overlay operations to prevent spam
    private var pendingShowOperation: DispatchWorkItem?
    private var pendingHideOperation: DispatchWorkItem?
    private var pendingProcessingShowOperation: DispatchWorkItem?
    /// Show immediately so users see the processing state right away.
    private let processingVisualDelay: DispatchTimeInterval = .milliseconds(0)
    /// Debounce the hide so a fast transcription doesn't flash the processing
    /// overlay for a single frame. 80ms is under the perception threshold but
    /// long enough to coalesce a quick show->hide cycle.
    private let processingHideDelay: DispatchTimeInterval = .milliseconds(80)

    /// Subscription for forwarding audio levels to expanded command notch

    override init() {
        super.init()
        // Don't setup menu bar immediately - defer until app is ready
    }

    func initializeMenuBar() {
        guard !self.isSetup else { return }

        // Ensure we're on main thread and app is active
        DispatchQueue.main.async { [weak self] in
            self?.setupMenuBarSafely()
        }
    }

    deinit {
        statusItem = nil
    }

    func configure(asrService: ASRService) {
        self.asrService = asrService

        // Subscribe to recording state changes
        asrService.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRunning in
                self?.isRecording = isRunning
                self?.updateMenuBarIcon()
                self?.updateMenu()

                // Handle overlay lifecycle (independent of window state)
                self?.handleOverlayState(isRunning: isRunning, asrService: asrService)
            }
            .store(in: &self.cancellables)

        // Subscribe to partial transcription updates for streaming preview
        asrService.$partialTranscription
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newText in
                guard self != nil else { return }
                if NotchOverlayManager.shared.shouldShowOrTrackLivePreviewText {
                    NotchOverlayManager.shared.updateTranscriptionText(newText)
                }
            }
            .store(in: &self.cancellables)
    }

    private func handleOverlayState(isRunning: Bool, asrService: ASRService) {
        self.overlayBench("handle_state isRunning=\(isRunning) overlayVisible=\(self.overlayVisible) processing=\(self.isProcessingActive) mode=\(self.currentOverlayMode.rawValue)")

        // Don't hide the overlay while AI processing is active.
        // Without this, the notch can disappear during the short "Refining..." phase because
        // `isRunning` becomes false before post-processing completes.
        if !isRunning, self.isProcessingActive {
            self.overlayBench("handle_state_return reason=processing_active")
            return
        }

        // Prevent rapid state changes that could cause cycles
        guard self.overlayVisible != isRunning else {
            self.overlayBench("handle_state_return reason=visibility_unchanged")
            return
        }

        if isRunning {
            // Cancel any pending hide operation
            self.pendingHideOperation?.cancel()
            self.pendingHideOperation = nil

            self.overlayVisible = true
            self.overlayBench("show_request mode=\(self.currentOverlayMode.rawValue)")

            let showItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.overlayVisible else { return }

                // Show notch overlay
                self.overlayBench("show_workitem_execute mode=\(self.currentOverlayMode.rawValue)")
                NotchOverlayManager.shared.show(
                    audioLevelPublisher: asrService.audioLevelPublisher,
                    mode: self.currentOverlayMode
                )
                self.overlayBench("show_workitem_return mode=\(self.currentOverlayMode.rawValue)")

                self.pendingShowOperation = nil
            }
            self.pendingShowOperation = showItem
            DispatchQueue.main.async(execute: showItem)
        } else {
            // Cancel any pending show operation
            self.pendingShowOperation?.cancel()
            self.pendingShowOperation = nil

            self.overlayVisible = false
            self.overlayBench("hide_request delayMs=30")

            let hideItem = DispatchWorkItem { [weak self] in
                guard let self = self, !self.overlayVisible else { return }

                // Hide notch overlay
                self.overlayBench("hide_workitem_execute")
                NotchOverlayManager.shared.hide()
                self.overlayBench("hide_workitem_return")

                self.pendingHideOperation = nil
            }
            self.pendingHideOperation = hideItem
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30), execute: hideItem)
        }
    }

    func showRecordingOverlayImmediately() {
        guard let asrService else {
            self.overlayBench("instant_show_return reason=no_asr_service")
            return
        }

        self.pendingHideOperation?.cancel()
        self.pendingHideOperation = nil
        self.pendingShowOperation?.cancel()
        self.pendingShowOperation = nil

        guard !self.overlayVisible else {
            self.overlayBench("instant_show_return reason=already_visible")
            return
        }

        self.overlayVisible = true
        self.overlayBench("instant_show_request mode=\(self.currentOverlayMode.rawValue)")

        self.overlayBench("show_workitem_execute mode=\(self.currentOverlayMode.rawValue)")
        NotchOverlayManager.shared.show(
            audioLevelPublisher: asrService.audioLevelPublisher,
            mode: self.currentOverlayMode
        )
        self.overlayBench("show_workitem_return mode=\(self.currentOverlayMode.rawValue)")
    }

    func hideRecordingOverlayImmediately(reason: String) {
        self.pendingShowOperation?.cancel()
        self.pendingShowOperation = nil
        self.pendingHideOperation?.cancel()
        self.pendingHideOperation = nil

        guard !self.isProcessingActive else {
            self.overlayBench("instant_hide_return reason=\(reason) processing_active")
            return
        }

        guard self.overlayVisible else {
            self.overlayBench("instant_hide_return reason=\(reason) already_hidden")
            return
        }

        self.overlayVisible = false
        self.overlayBench("instant_hide_request reason=\(reason)")

        NotchOverlayManager.shared.hide()
        self.overlayBench("instant_hide_return")
    }

    // MARK: - Public API for overlay management

    func updateOverlayTranscription(_ text: String) {
        NotchOverlayManager.shared.updateTranscriptionText(text)
    }

    func setOverlayMode(_ mode: OverlayMode) {
        self.overlayBench("set_mode mode=\(mode.rawValue)")
        self.currentOverlayMode = mode
        NotchOverlayManager.shared.setMode(mode)
    }

    func setProcessing(_ processing: Bool) {
        self.overlayBench("set_processing_request processing=\(processing) overlayVisible=\(self.overlayVisible) active=\(self.isProcessingActive)")

        // Track processing state to prevent hide during AI refinement
        self.isProcessingActive = processing

        if processing {
            self.pendingProcessingShowOperation?.cancel()
            // Cancel any pending hide - we want to keep the overlay visible for AI processing
            self.pendingHideOperation?.cancel()
            self.pendingHideOperation = nil
            self.overlayVisible = true

            let showItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.isProcessingActive else { return }
                self.overlayBench("processing_show_workitem_execute delayMs=0")
                NotchOverlayManager.shared.setProcessing(true)
                self.overlayBench("processing_show_workitem_return")
                self.pendingProcessingShowOperation = nil
            }
            self.pendingProcessingShowOperation = showItem
            DispatchQueue.main.asyncAfter(deadline: .now() + self.processingVisualDelay, execute: showItem)
        } else {
            self.pendingProcessingShowOperation?.cancel()
            self.pendingProcessingShowOperation = nil
            // When processing ends, schedule the hide
            self.overlayVisible = false

            let hideItem = DispatchWorkItem { [weak self] in
                guard let self = self, !self.overlayVisible else { return }

                self.overlayBench("processing_hide_workitem_execute delayMs=80")
                NotchOverlayManager.shared.hide()
                self.overlayBench("processing_hide_workitem_return")
                self.pendingHideOperation = nil
            }
            self.pendingHideOperation = hideItem
            DispatchQueue.main.asyncAfter(deadline: .now() + self.processingHideDelay, execute: hideItem)
            NotchOverlayManager.shared.setProcessing(false)
            self.overlayBench("processing_forwarded processing=false hideDelayMs=80")
            return
        }
    }

    private func overlayBench(_ message: String) {
        DebugLogger.shared.benchmark("OVERLAY_BENCH", message: "manager \(message)", source: "OverlayBenchmark")
    }

    private func setupMenuBarSafely() {
        do {
            try self.setupMenuBar()
            self.isSetup = true
        } catch {
            // If setup fails, retry after delay
            DebugLogger.shared.error("MenuBar setup failed, retrying: \(error)", source: "MenuBarManager")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.setupMenuBarSafely()
            }
        }
    }

    private func setupMenuBar() throws {
        // Ensure we're not already set up
        guard !self.isSetup else { return }

        // Create status item with error handling
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let statusItem = statusItem else {
            throw NSError(domain: "MenuBarManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create status item"])
        }

        // Set initial icon
        self.updateMenuBarIcon()

        // Create menu
        self.menu = NSMenu()
        self.menu?.delegate = self
        statusItem.menu = self.menu

        self.updateMenu()
    }

    private func updateMenuBarIcon() {
        guard let statusItem = statusItem else { return }

        // Use MenuBarIcon asset - vectorized from logo
        if let image = NSImage(named: "MenuBarIcon") {
            image.isTemplate = true // Adapts to light/dark mode and tints red when recording
            statusItem.button?.image = image
        }
    }

    private func buildMenuStructure() {
        guard let menu = menu else { return }

        menu.removeAllItems()

        // Status indicator with hotkey info
        self.statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        self.statusMenuItem?.isEnabled = false
        if let statusItem = statusMenuItem {
            menu.addItem(statusItem)
        }

        menu.addItem(.separator())

        // Open Main Window
        let openItem = NSMenuItem(title: "Open Speech2Write", action: #selector(openMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        // Preferences
        let preferencesItem = NSMenuItem(title: "Settings...", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        preferencesItem.keyEquivalentModifierMask = [.command]
        menu.addItem(preferencesItem)

        let customDictionaryItem = NSMenuItem(
            title: "Custom Dictionary",
            action: #selector(openCustomDictionary),
            keyEquivalent: ""
        )
        customDictionaryItem.target = self
        menu.addItem(customDictionaryItem)

        let microphoneSubmenu = NSMenu(title: "Microphone")
        let microphoneMenuItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        microphoneMenuItem.submenu = microphoneSubmenu
        menu.addItem(microphoneMenuItem)
        self.microphoneMenuItem = microphoneMenuItem
        self.microphoneSubmenu = microphoneSubmenu

        // Check for Updates
        let updateItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Speech2Write",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)

        // Now update the text content
        self.updateMenuItemsText()
    }

    private func updateMenu() {
        // If menu structure hasn't been built yet, build it
        if self.statusMenuItem == nil {
            self.buildMenuStructure()
        } else {
            // Just update the text of existing items
            self.updateMenuItemsText()
        }
    }

    private func updateMenuItemsText() {
        // Update status text with hotkey info
        let hotkeyDisplay = SettingsStore.shared.primaryDictationShortcutDisplayString
        let hotkeyInfo = hotkeyDisplay.isEmpty ? "" : " (\(hotkeyDisplay))"
        let statusTitle = self.isRecording ? "Recording...\(hotkeyInfo)" : "Ready to Record\(hotkeyInfo)"
        self.statusMenuItem?.title = statusTitle
        self.microphoneMenuItem?.isEnabled = true
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === self.menu {
            self.updateMenuItemsText()
            self.refreshMicrophoneMenu()
        }
    }

    private func refreshMicrophoneMenu() {
        guard let submenu = self.microphoneSubmenu else { return }

        submenu.removeAllItems()
        let loadingItem = NSMenuItem(title: "Loading...", action: nil, keyEquivalent: "")
        loadingItem.isEnabled = false
        submenu.addItem(loadingItem)

        DispatchQueue.global(qos: .userInitiated).async {
            let inputDevices = AudioDevice.listInputDevices()
            let defaultInputUID = AudioDevice.getDefaultInputDevice()?.uid

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.populateMicrophoneMenu(
                    inputDevices: inputDevices,
                    defaultInputUID: defaultInputUID
                )
            }
        }
    }

    private func populateMicrophoneMenu(inputDevices: [AudioDevice.Device], defaultInputUID: String?) {
        guard let submenu = self.microphoneSubmenu else { return }

        submenu.removeAllItems()

        guard !inputDevices.isEmpty else {
            let emptyItem = NSMenuItem(title: "No microphones found", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
            return
        }

        let currentUID = self.currentPreferredInputUID(defaultInputUID: defaultInputUID)

        for device in inputDevices {
            let isSystemDefault = device.uid == defaultInputUID
            let title = isSystemDefault ? "\(device.name) (System Default)" : device.name
            let item = NSMenuItem(title: title, action: #selector(selectMicrophone(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uid
            item.state = device.uid == currentUID ? .on : .off
            item.isEnabled = !self.isRecording
            submenu.addItem(item)
        }

        if self.isRecording {
            submenu.addItem(.separator())
            let recordingItem = NSMenuItem(title: "Unavailable while recording", action: nil, keyEquivalent: "")
            recordingItem.isEnabled = false
            submenu.addItem(recordingItem)
        }
    }

    private func currentPreferredInputUID(defaultInputUID: String?) -> String? {
        return defaultInputUID
    }

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        guard self.isRecording == false else { return }
        guard let uid = sender.representedObject as? String, !uid.isEmpty else { return }

        SettingsStore.shared.preferredInputDeviceUID = uid

        if SettingsStore.shared.syncAudioDevicesWithSystem {
            _ = AudioDevice.setDefaultInputDevice(uid: uid)
        }

        self.refreshMicrophoneMenu()
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        DebugLogger.shared.info("🔎 Menu action: Check for Updates…", source: "MenuBarManager")
        self.openAllReleasesPage()
    }

    private func openAllReleasesPage() {
        guard let url = URL(string: "\(AppBundleMetadata.repositoryURLString)/releases") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openMainWindow() {
        // First, unhide the app if it's hidden
        if NSApp.isHidden {
            NSApp.unhide(nil)
        }

        // Activate the app and bring it to the front
        NSApp.activate(ignoringOtherApps: true)

        var mainWindows = NSApp.windows.filter(self.isFluidMainWindow)
        if let hostedWindow,
           mainWindows.contains(where: { $0 !== hostedWindow })
        {
            hostedWindow.close()
            self.hostedWindow = nil
            mainWindows = NSApp.windows.filter(self.isFluidMainWindow)
        }

        // Find an existing *non-minimized* primary window.
        // Important: avoid programmatic deminiaturize() — it creates internal window transform animations
        // (NSWindowTransformAnimation) that have been unstable on macOS 26.x for this app.
        if let window = mainWindows.first {
            self.ensureUsableMainWindow(window)
            window.animationBehavior = .none
            self.bringToFront(window)
            if let hostedWindow, window !== hostedWindow {
                self.hostedWindow = nil
            }
        } else if let window = hostedWindow, window.isReleasedWhenClosed == false {
            self.ensureUsableMainWindow(window)
            window.animationBehavior = .none
            self.bringToFront(window)
        } else {
            // If there is no suitable window (or it's minimized), create a fresh one.
            self.createAndShowMainWindow()
        }

        // Final attempt: ensure app is active and visible
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func isFluidMainWindow(_ window: NSWindow) -> Bool {
        guard window.level == .normal else { return false }
        guard window.styleMask.contains(.titled) else { return false }
        guard window.canBecomeKey else { return false }
        guard window.isMiniaturized == false else { return false }
        return window.title == AppBundleMetadata.appDisplayName || window.title.contains(AppBundleMetadata.appDisplayName)
    }

    @objc private func openPreferences() {
        self.openNavigationDestination(.preferences)
    }

    @objc private func openCustomDictionary() {
        self.openNavigationDestination(.customDictionary)
    }

    private func openNavigationDestination(_ destination: MenuBarNavigationDestination) {
        // Ensure a fresh one-shot request every time the menu item is clicked.
        self.requestedNavigationDestination = nil
        self.requestedNavigationDestination = destination

        self.openMainWindow()

        // Nudge again after the window is front-most, so an already-open ContentView
        // will still switch tabs even if it consumed a previous navigation request.
        DispatchQueue.main.async { [weak self] in
            self?.requestedNavigationDestination = nil
            self?.requestedNavigationDestination = destination
        }
    }

    /// Public entry-point for non-menu UI surfaces (e.g. overlay controls) to open Preferences.
    func openPreferencesFromUI() {
        self.openPreferences()
    }

    /// Create and present a fresh main window hosting `ContentView`
    private func createAndShowMainWindow() {
        // Build the SwiftUI root view with required environment
        let rootView = AdaptiveAppTheme(accent: SettingsStore.shared.accentColor) {
            ContentView()
                .environmentObject(self)
                .environmentObject(AppServices.shared)
        }

        // Host inside an AppKit window
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppBundleMetadata.appDisplayName
        window.animationBehavior = .none
        window.minSize = self.mainWindowMinimumSize
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.setFrame(self.defaultWindowFrame(), display: false)
        self.bringToFront(window)
        self.hostedWindow = window

        // Bring app to front in case we're running as an accessory app (no Dock)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func ensureUsableMainWindow(_ window: NSWindow) {
        // If the window is too small (e.g., height collapsed), reset to the default frame.
        let minSize = self.mainWindowMinimumSize
        window.minSize = minSize

        let frame = window.frame
        if frame.height < minSize.height || frame.width < minSize.width {
            window.setFrame(self.defaultWindowFrame(), display: false)
        }
    }

    private func defaultWindowFrame() -> NSRect {
        // Center a sensible default frame on the main screen.
        let size = NSSize(width: 1000, height: 700)
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: size.width, height: size.height)
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )
        return NSRect(origin: origin, size: size)
    }

    private var mainWindowMinimumSize: NSSize {
        let window = AppTheme.dark.metrics.window
        return NSSize(width: window.mainMinWidth, height: window.mainMinHeight)
    }

    private func bringToFront(_ window: NSWindow) {
        // Keep ordering explicit to avoid "opened but behind other apps" behavior.
        if window.alphaValue <= 0.01 {
            window.alphaValue = 1
        }
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}
