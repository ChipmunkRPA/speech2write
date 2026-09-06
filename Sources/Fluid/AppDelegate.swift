//
//  AppDelegate.swift
//  Fluid
//
//  Created by Barathwaj Anandan on 9/22/25.
//

import AppKit
import Carbon
import Darwin
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var didRevealMainWindowOnLaunch = false
    private var didRequestMainWindowReopen = false
    private var shouldSuppressNextReopenActivation = false
    private var wasLaunchedAsLoginItem = false
    private var shouldContinueLaunching = true
    private var instanceLockFileDescriptor: Int32 = -1

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard self.acquireSingleInstanceLock(waitingUpTo: 1.5) else {
            self.shouldContinueLaunching = false
            self.activateExistingInstance()
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
            return
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard self.shouldContinueLaunching else { return }
        // Bring up file logging + crash handlers immediately during launch.
        _ = FileLogger.shared
        // Must be read during the launch callback - the current Apple Event identifies
        // login-item launches (used to optionally start silently, see issue #369).
        self.wasLaunchedAsLoginItem = Self.detectLoginItemLaunch()
        DebugLogger.shared.info(
            "Application launched [loginItemLaunch=\(self.wasLaunchedAsLoginItem)]",
            source: "AppDelegate"
        )
        UNUserNotificationCenter.current().delegate = self

        // Initialize app settings (dock visibility, etc.)
        SettingsStore.shared.initializeAppSettings()

        // Keep the persisted pronunciation list aligned with the current product name.
        // This is intentionally best-effort so a malformed user-edited file never blocks launch.
        do {
            try ParakeetVocabularyStore.shared.ensureVocabularyFileExists()
        } catch {
            DebugLogger.shared.warning(
                "Could not initialize the custom pronunciation file",
                source: "AppDelegate"
            )
        }

        // Record first-open synchronously so onboarding initialization is
        // deterministic on brand-new installs.
        let isTrueFirstOpen = Self.ensureFirstOpenRecorded()
        SettingsStore.shared.bootstrapOnboardingState(isTrueFirstOpen: isTrueFirstOpen)

        // 1.1.2: the Apple Intelligence auto-seed is retired — the on-device
        // model rewrites dictation too aggressively for an out-of-box default.
        // Installs still in the seeded state are reverted to raw dictation;
        // Apple Intelligence remains a manual opt-in provider.
        SettingsStore.shared.revertAppleIntelligenceAutoSeedIfActive()

        // 1.1.4: the app is local-only — remove any previously configured cloud
        // AI provider (selection, saved providers, verification fingerprints).
        // Keychain API keys are left in place; they are simply no longer used.
        SettingsStore.shared.removeCloudProvidersIfNeeded()

        // 1.1.5: Apple Intelligence is the only enhancement provider — remove
        // the retired local-server providers (Ollama, LM Studio) the same way.
        SettingsStore.shared.removeLocalServerProvidersIfNeeded()

        // Login Items can launch hidden; reveal the real SwiftUI window so ContentView startup runs.
        self.openMainWindowOnLaunch()

        // Note: App UI is designed with dark color scheme in mind
        // All gradients and effects are optimized for dark mode
    }

    func applicationWillTerminate(_ notification: Notification) {
        DebugLogger.shared.info("Application will terminate", source: "AppDelegate")
        if self.instanceLockFileDescriptor >= 0 {
            close(self.instanceLockFileDescriptor)
            self.instanceLockFileDescriptor = -1
        }
    }

    /// Closing the main window should leave dictation, global shortcuts, and the
    /// menu-bar item running. Users can still terminate explicitly with Command-Q
    /// or the menu-bar Quit command.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        DebugLogger.shared.info(
            "Last window closed; continuing in the menu bar",
            source: "AppDelegate"
        )
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if self.shouldSuppressNextReopenActivation {
            self.shouldSuppressNextReopenActivation = false
            return true
        }

        // Ensure dock-icon reopen always foregrounds the app.
        sender.activate(ignoringOtherApps: true)

        return !self.bringMainWindowToFrontIfPresent()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if userInfo[NotificationService.UserInfoKey.kind] as? String == NotificationService.Kind.aiProcessingFallback {
            DispatchQueue.main.async {
                AppNavigationRouter.shared.request(.history)
                self.bringMainWindowToFront()
            }
        }

        completionHandler()
    }

    /// Whether this launch came from macOS Login Items. Reads the launch Apple Event,
    /// which is only valid during applicationDidFinishLaunching.
    /// FLUID_SIMULATE_LOGIN_LAUNCH=1 forces this on for testing, since real login-item
    /// launches can only be produced by logging in.
    private static func detectLoginItemLaunch() -> Bool {
        if ProcessInfo.processInfo.environment["FLUID_SIMULATE_LOGIN_LAUNCH"] == "1" {
            return true
        }
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == AEEventID(kAEOpenApplication)
            && event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
    }

    /// Records the first-open timestamp (once per install) and reports whether this
    /// launch is the first ever. Keeps the pre-1.1.8 UserDefaults key so installs that
    /// already recorded a first open are not re-onboarded.
    private static func ensureFirstOpenRecorded() -> Bool {
        let key = "AnalyticsFirstOpenAt"
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) == nil {
            defaults.set(Date().timeIntervalSince1970, forKey: key)
            return true
        }
        return false
    }

    /// Prevent separate app copies (for example a development build and the installed build)
    /// from registering two global event taps at once. Launch Services' plist guard covers normal
    /// launches; this advisory file lock also covers `open -n` and direct executable launches.
    private func acquireSingleInstanceLock(waitingUpTo timeout: TimeInterval) -> Bool {
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.raysang.platypusflow.instance.lock", isDirectory: false)
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            // Fail open if the temporary directory is unavailable so a filesystem issue does not
            // make the app impossible to launch.
            return true
        }

        _ = fchmod(descriptor, S_IRUSR | S_IWUSR)
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                self.instanceLockFileDescriptor = descriptor
                return true
            }

            guard errno == EWOULDBLOCK, Date() < deadline else {
                close(descriptor)
                return false
            }
            usleep(100_000)
        } while true
    }

    private func activateExistingInstance() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != currentPID && !$0.isTerminated }
        _ = existing?.activate(options: [.activateAllWindows])
    }

    /// Apply the user's dock-visibility preference ("Hide from dock", issue #162).
    /// Re-applied after operations that can reset the process activation policy - notably the
    /// LaunchServices reopen below, which restores the bundle default (.regular) even when the
    /// app is reopened without activation, so hide-from-dock is honored on login launches (#396).
    private func applyDockVisibilityPolicy() {
        NSApp.setActivationPolicy(SettingsStore.shared.showInDock ? .regular : .accessory)
    }

    private func openMainWindowOnLaunch() {
        self.applyDockVisibilityPolicy()

        // Users can opt out of showing the window for login-item launches (#369).
        // The window must still be CREATED either way - ContentView's appearance
        // bootstraps the menu bar and services - so the silent path realizes it
        // invisibly instead of skipping it.
        let revealWindow = !self.wasLaunchedAsLoginItem || SettingsStore.shared.showMainWindowAtLoginLaunch

        for delay in [0.1, 0.6, 1.2, 2.5, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                guard self.didRevealMainWindowOnLaunch == false else { return }

                if revealWindow {
                    NSApp.unhide(nil)
                    NSApp.activate(ignoringOtherApps: true)

                    if self.bringMainWindowToFrontIfPresent() {
                        self.didRevealMainWindowOnLaunch = true
                        return
                    }
                } else if self.bootMainWindowHiddenIfPresent() {
                    self.didRevealMainWindowOnLaunch = true
                    return
                }

                DebugLogger.shared.debug("Main window not ready during launch reveal retry", source: "AppDelegate")
                if delay >= 0.6 {
                    self.requestMainWindowReopenIfNeeded(activate: revealWindow)
                }
            }
        }
    }

    /// Realize the main window invisibly so ContentView's startup runs, then order it out.
    /// Used for login-item launches when "Show window when launched at login" is off.
    @discardableResult
    private func bootMainWindowHiddenIfPresent() -> Bool {
        guard let mainWindow = NSApp.windows.first(where: self.isMainWindow) else { return false }

        let originalAlpha = mainWindow.alphaValue
        mainWindow.alphaValue = 0
        mainWindow.orderFrontRegardless()

        // Give ContentView.onAppear time to finish its startup work (menu bar setup plus
        // the delayed service initialization), then put the window away. Alpha is restored
        // so opening it later from the menu bar shows it normally.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak mainWindow] in
            guard let mainWindow, mainWindow.alphaValue <= 0.01 else { return }
            mainWindow.orderOut(nil)
            mainWindow.alphaValue = originalAlpha
            DebugLogger.shared.info(
                "Main window booted hidden (show-at-login-launch disabled)",
                source: "AppDelegate"
            )
        }
        return true
    }

    private func requestMainWindowReopenIfNeeded(activate: Bool = true) {
        guard !self.didRequestMainWindowReopen else { return }
        self.didRequestMainWindowReopen = true

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activate
        if !activate {
            self.shouldSuppressNextReopenActivation = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.shouldSuppressNextReopenActivation = false
            }
        }

        DebugLogger.shared.info("Requesting LaunchServices reopen to create SwiftUI main window", source: "AppDelegate")
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] _, error in
            if let error {
                DebugLogger.shared.error("LaunchServices reopen failed: \(error.localizedDescription)", source: "AppDelegate")
            }
            // The reopen restores the app's bundle default activation policy (.regular), which
            // would surface the Dock icon even when the user enabled "Hide from dock". Re-apply
            // the configured policy so login launches honor the setting (#396). The completion
            // runs off the main thread, so hop back before touching NSApp.
            DispatchQueue.main.async {
                self?.applyDockVisibilityPolicy()
            }
        }
    }

    private func bringMainWindowToFront() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)

        if !self.bringMainWindowToFrontIfPresent() {
            DebugLogger.shared.debug("Main window not ready", source: "AppDelegate")
        }
    }

    @discardableResult
    private func bringMainWindowToFrontIfPresent() -> Bool {
        if let mainWindow = NSApp.windows.first(where: self.isMainWindow) {
            if mainWindow.alphaValue <= 0.01 {
                mainWindow.alphaValue = 1
            }
            mainWindow.orderFrontRegardless()
            mainWindow.makeKeyAndOrderFront(nil)
            DebugLogger.shared.debug("Brought main window to front", source: "AppDelegate")
            return true
        }

        return false
    }

    private func isMainWindow(_ window: NSWindow) -> Bool {
        guard window.level == .normal else { return false }
        guard window.styleMask.contains(.titled) else { return false }
        return window.title == AppBundleMetadata.appDisplayName || window.title.contains(AppBundleMetadata.appDisplayName)
    }
}
