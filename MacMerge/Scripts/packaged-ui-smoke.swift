import AppKit
import ApplicationServices
import Darwin
import Foundation

private enum SmokeError: LocalizedError {
    case accessibilityPermissionMissing
    case invalidApplication(String)
    case launchFailed(String)
    case applicationExited(String)
    case timeout(String)
    case assertionFailed(String)
    case accessibilityFailure(String)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            "Accessibility permission is required for the packaged UI smoke driver."
        case .invalidApplication(let message), .launchFailed(let message),
            .applicationExited(let message), .timeout(let message),
            .assertionFailed(let message), .accessibilityFailure(let message):
            message
        }
    }
}

private enum AXReadError: Error {
    case transient(AXError)
    case fatal(AXError, String)
}

private struct AXNode {
    let element: AXUIElement
    let role: String?
    let title: String?
    let description: String?
    let value: String?
    let isEnabled: Bool?

    func hasLabel(_ expected: String) -> Bool {
        title == expected || description == expected || value == expected
    }
}

private final class PackagedUISmoke {
    private static let launchTimeout: TimeInterval = 15
    private static let actionTimeout: TimeInterval = 15
    private static let maximumAXNodes = 10_000
    private static let isolatedBundleIdentifierPrefix = "io.github.egigoka.MacMerge.UISmoke."
    private let applicationURL: URL
    private let bundleIdentifier: String
    private let containerURL: URL
    private let sessionURL: URL
    private let launchedPIDURL: URL
    private let launchIntentURL: URL
    private let completionGuardURL: URL
    private let cancellationURL: URL
    private var launchedApplications: [NSRunningApplication] = []

    init(
        applicationURL: URL,
        launchedPIDURL: URL,
        launchIntentURL: URL,
        completionGuardURL: URL,
        cancellationURL: URL,
        expectedBundleIdentifier: String
    ) throws {
        self.applicationURL = applicationURL
        self.launchedPIDURL = launchedPIDURL
        self.launchIntentURL = launchIntentURL
        self.completionGuardURL = completionGuardURL
        self.cancellationURL = cancellationURL
        guard let bundle = Bundle(url: applicationURL),
            let bundleIdentifier = bundle.bundleIdentifier,
            !bundleIdentifier.isEmpty
        else {
            throw SmokeError.invalidApplication(
                "Could not read bundle identifier from \(applicationURL.path)."
            )
        }
        let suffix = expectedBundleIdentifier.dropFirst(Self.isolatedBundleIdentifierPrefix.count)
        let suffixParts = suffix.split(separator: ".", omittingEmptySubsequences: false)
        guard expectedBundleIdentifier.hasPrefix(Self.isolatedBundleIdentifierPrefix),
            !suffix.isEmpty,
            suffixParts.allSatisfy({ part in
                !part.isEmpty
                    && part.unicodeScalars.allSatisfy { scalar in
                        scalar.isASCII
                            && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-")
                    }
            }),
            bundleIdentifier == expectedBundleIdentifier
        else {
            throw SmokeError.invalidApplication(
                "Refusing to modify unexpected application state for \(bundleIdentifier)."
            )
        }
        self.bundleIdentifier = bundleIdentifier
        containerURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers", directoryHint: .isDirectory)
            .appending(path: bundleIdentifier, directoryHint: .isDirectory)
        sessionURL =
            containerURL
            .appending(path: "Data/Library/Application Support/MacMerge", directoryHint: .isDirectory)
            .appending(path: "ComparisonSession.json")
    }

    func run() async throws {
        do {
            try checkCancellation()
            guard AXIsProcessTrusted() else {
                throw SmokeError.accessibilityPermissionMissing
            }
            try await initializeSandboxContainer()
            try writeSeedSession()

            let firstRestore = try await launch()
            try assertInitialRestore(in: firstRestore)
            let comparisonWindow = try waitForWindow(
                identifier: "comparison",
                in: firstRestore
            )
            let locationPaneEvidence = try verifyLocationPaneInteractions(
                in: firstRestore,
                comparisonWindow: comparisonWindow
            )
            print("Packaged UI smoke stage: Location Pane interactions passed.")
            try await terminate(firstRestore, context: "persisting Location Pane state")
            try assertPersistedLocationPaneState(expectedWidth: locationPaneEvidence.width)

            try writeSeedSession(
                lineCount: 2,
                locationPaneVisible: true,
                locationPaneWidth: locationPaneEvidence.width
            )
            let lifecycleRestore = try await launch()
            try assertInitialRestore(in: lifecycleRestore)
            let lifecycleWindow = try waitForWindow(
                identifier: "comparison",
                in: lifecycleRestore
            )
            try verifySettingsUndoRoutingAndCloseVeto(
                in: lifecycleRestore,
                comparisonWindow: lifecycleWindow
            )
            print("Packaged UI smoke stage: Settings and close-veto checks passed.")
            try press(
                label: "Make left file read-only",
                in: lifecycleRestore,
                root: lifecycleWindow
            )
            try waitForReadOnlyState(in: lifecycleRestore)
            print("Packaged UI smoke stage: read-only transition passed.")
            try await terminate(lifecycleRestore, context: "persisting changed read-only state")
            try assertPersistedReadOnlyState()

            let secondRestore = try await launch()
            try assertSecondRestore(in: secondRestore)
            let restoredComparisonWindow = try waitForWindow(
                identifier: "comparison",
                in: secondRestore
            )
            try assertLocationPaneVisible(
                in: secondRestore,
                comparisonWindow: restoredComparisonWindow,
                expectedSliderSize: locationPaneEvidence.sliderSize
            )
            try await terminate(secondRestore, context: "finishing restored-session verification")
            try removeSandboxData()
            try removeCompletionGuard()

            print(
                "Packaged UI smoke passed: session restore, Location Pane AX/menu interaction and persistence, key-window undo/redo routing, close veto, independent read-only AX action, and relaunch persistence."
            )
        } catch {
            do {
                try terminateAllApplications()
                try removeSandboxData()
                try? FileManager.default.removeItem(at: launchIntentURL)
                try removeCompletionGuard()
            } catch let cleanupError {
                throw SmokeError.assertionFailed(
                    "\(error.localizedDescription) Cleanup also failed: \(cleanupError.localizedDescription)"
                )
            }
            throw error
        }
    }

    private func removeCompletionGuard() throws {
        guard FileManager.default.fileExists(atPath: completionGuardURL.path) else { return }
        try FileManager.default.removeItem(at: completionGuardURL)
    }

    private func removeSandboxData() throws {
        let parent = containerURL.deletingLastPathComponent()
        let parentDescriptor = Darwin.open(
            parent.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard parentDescriptor >= 0 else {
            throw posixFailure("opening isolated container parent")
        }
        defer { Darwin.close(parentDescriptor) }

        let containerDescriptor = bundleIdentifier.withCString {
            Darwin.openat(
                parentDescriptor,
                $0,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        if containerDescriptor < 0, errno == ENOENT { return }
        guard containerDescriptor >= 0 else {
            throw posixFailure("opening isolated container")
        }
        defer { Darwin.close(containerDescriptor) }

        try removeEntry(named: "Data", from: containerDescriptor)
    }

    private func removeDirectoryContents(_ descriptor: Int32) throws {
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0 else { throw posixFailure("duplicating cleanup directory") }
        guard let stream = Darwin.fdopendir(duplicate) else {
            Darwin.close(duplicate)
            throw posixFailure("opening cleanup directory stream")
        }
        defer { Darwin.closedir(stream) }

        while let entry = Darwin.readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
                    String(cString: $0)
                }
            }
            guard name != ".", name != ".." else { continue }
            try removeEntry(named: name, from: descriptor)
        }
    }

    private func removeEntry(named name: String, from descriptor: Int32) throws {
        var initial = stat()
        let readResult = name.withCString {
            Darwin.fstatat(descriptor, $0, &initial, AT_SYMLINK_NOFOLLOW)
        }
        if readResult != 0, errno == ENOENT { return }
        guard readResult == 0 else { throw posixFailure("reading cleanup entry identity") }

        let quarantinedName = ".macmerge-ui-smoke-cleanup-\(UUID().uuidString)"
        guard
            name.withCString({ source in
                quarantinedName.withCString { destination in
                    Darwin.renameat(descriptor, source, descriptor, destination)
                }
            }) == 0
        else {
            throw posixFailure("quarantining cleanup entry")
        }

        var quarantined = stat()
        guard
            quarantinedName.withCString({
                Darwin.fstatat(descriptor, $0, &quarantined, AT_SYMLINK_NOFOLLOW)
            }) == 0,
            sameIdentity(initial, quarantined)
        else {
            throw SmokeError.assertionFailed(
                "Cleanup entry changed identity while being quarantined; preserved \(quarantinedName)."
            )
        }

        let isDirectory = initial.st_mode & S_IFMT == S_IFDIR
        if isDirectory {
            let childDescriptor = quarantinedName.withCString {
                Darwin.openat(
                    descriptor,
                    $0,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                )
            }
            guard childDescriptor >= 0 else { throw posixFailure("opening quarantined directory") }
            do {
                defer { Darwin.close(childDescriptor) }
                var opened = stat()
                guard Darwin.fstat(childDescriptor, &opened) == 0, sameIdentity(initial, opened)
                else {
                    throw SmokeError.assertionFailed(
                        "Quarantined cleanup directory changed identity; preserved \(quarantinedName)."
                    )
                }
                try removeDirectoryContents(childDescriptor)
            }
        }

        var final = stat()
        guard
            quarantinedName.withCString({
                Darwin.fstatat(descriptor, $0, &final, AT_SYMLINK_NOFOLLOW)
            }) == 0,
            sameIdentity(initial, final)
        else {
            throw SmokeError.assertionFailed(
                "Quarantined cleanup entry changed before removal; preserved \(quarantinedName)."
            )
        }
        let flags = isDirectory ? AT_REMOVEDIR : 0
        guard quarantinedName.withCString({ Darwin.unlinkat(descriptor, $0, flags) }) == 0 else {
            throw posixFailure("removing quarantined cleanup entry")
        }
    }

    private func sameIdentity(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev
            && lhs.st_ino == rhs.st_ino
            && lhs.st_mode & S_IFMT == rhs.st_mode & S_IFMT
    }

    private func posixFailure(_ operation: String) -> SmokeError {
        let code = errno
        return .assertionFailed("Failed \(operation): \(String(cString: strerror(code))).")
    }

    private func checkCancellation() throws {
        if FileManager.default.fileExists(atPath: cancellationURL.path) {
            throw CancellationError()
        }
    }

    private func verifyLocationPaneInteractions(
        in application: NSRunningApplication,
        comparisonWindow: AXUIElement
    ) throws -> (sliderSize: CGSize, width: Double) {
        let locationPaneItem = try waitForLocationPaneMenuItem(
            isMarked: false,
            in: application
        )
        try performPress(locationPaneItem, label: "Location Pane")
        _ = try waitForElement(
            label: "Left file location map",
            role: kAXSliderRole as String,
            in: application,
            root: comparisonWindow
        )
        _ = try waitForElement(
            label: "Right file location map",
            role: kAXSliderRole as String,
            in: application,
            root: comparisonWindow
        )

        try setValue(
            1,
            on: "Left file location map",
            in: application,
            root: comparisonWindow
        )
        _ = try waitForElement(
            label: "Left file location map",
            role: kAXSliderRole as String,
            value: "1",
            in: application,
            root: comparisonWindow
        )
        try waitForVisibleElement(
            label: "Left editable line 60",
            role: kAXTextAreaRole as String,
            value: "common 60",
            in: application,
            root: comparisonWindow
        )
        try setValue(
            0,
            on: "Right file location map",
            in: application,
            root: comparisonWindow
        )
        _ = try waitForElement(
            label: "Right file location map",
            role: kAXSliderRole as String,
            value: "0",
            in: application,
            root: comparisonWindow
        )
        try waitForVisibleElement(
            label: "Left editable line 1",
            role: kAXTextAreaRole as String,
            value: "restored left",
            in: application,
            root: comparisonWindow
        )

        _ = try waitForElement(
            label: "Copy selected difference to left",
            role: kAXButtonRole as String,
            isEnabled: true,
            in: application,
            root: comparisonWindow
        )
        let width = try resizeLocationPane(
            in: application,
            comparisonWindow: comparisonWindow
        )
        let sliderSize = try waitForElementSize(
            label: "Right file location map",
            role: kAXSliderRole as String,
            in: application,
            root: comparisonWindow
        )
        return (sliderSize, Double(width))
    }

    private func assertLocationPaneVisible(
        in application: NSRunningApplication,
        comparisonWindow: AXUIElement,
        expectedSliderSize: CGSize
    ) throws {
        _ = try waitForLocationPaneMenuItem(isMarked: true, in: application)
        let restoredSliderSize = try waitForElementSize(
            label: "Right file location map",
            role: kAXSliderRole as String,
            in: application,
            root: comparisonWindow
        )
        guard abs(restoredSliderSize.width - expectedSliderSize.width) < 0.5,
            abs(restoredSliderSize.height - expectedSliderSize.height) < 0.5
        else {
            throw SmokeError.assertionFailed(
                "Restored Location Pane size \(restoredSliderSize) did not match \(expectedSliderSize)."
            )
        }
    }

    private func resizeLocationPane(
        in application: NSRunningApplication,
        comparisonWindow: AXUIElement
    ) throws -> CGFloat {
        let pane = try waitForElement(
            label: "Location Pane",
            role: kAXGroupRole as String,
            in: application,
            root: comparisonWindow
        )
        guard let originalFrame = try copyFrame(from: pane.element) else {
            throw SmokeError.assertionFailed("Location Pane did not expose an AX frame.")
        }
        let handle = try waitForElement(
            label: "Location Pane width",
            in: application,
            root: comparisonWindow
        )
        try performAdjustment(
            kAXIncrementAction,
            on: handle.element,
            label: "Location Pane width"
        )
        _ = try waitForLocationPaneWidth(
            originalFrame.width + 8,
            in: application,
            comparisonWindow: comparisonWindow
        )
        let incrementedHandle = try waitForElement(
            label: "Location Pane width",
            in: application,
            root: comparisonWindow
        )
        try performAdjustment(
            kAXDecrementAction,
            on: incrementedHandle.element,
            label: "Location Pane width"
        )
        _ = try waitForLocationPaneWidth(
            originalFrame.width,
            in: application,
            comparisonWindow: comparisonWindow
        )

        let restoredHandle = try waitForElement(
            label: "Location Pane width",
            in: application,
            root: comparisonWindow
        )
        try performAdjustment(
            kAXIncrementAction,
            on: restoredHandle.element,
            label: "Location Pane width"
        )
        return try waitForLocationPaneWidth(
            originalFrame.width + 8,
            in: application,
            comparisonWindow: comparisonWindow
        )
    }

    private func performAdjustment(
        _ action: String,
        on element: AXUIElement,
        label: String
    ) throws {
        let result = AXUIElementPerformAction(element, action as CFString)
        guard result == .success || result == .cannotComplete else {
            throw SmokeError.accessibilityFailure(
                "AX adjustment failed for \(label) with error \(result.rawValue)."
            )
        }
    }

    private func waitForLocationPaneWidth(
        _ expectedWidth: CGFloat,
        in application: NSRunningApplication,
        comparisonWindow: AXUIElement
    ) throws -> CGFloat {
        var observedWidth: CGFloat?
        try retryingTransientAX(
            timeout: Self.actionTimeout,
            context: "waiting for Location Pane width \(expectedWidth)"
        ) {
            guard
                let pane = try findElement(
                    label: "Location Pane",
                    role: kAXGroupRole as String,
                    processIdentifier: application.processIdentifier,
                    root: comparisonWindow
                ),
                let frame = try copyFrame(from: pane.element),
                abs(frame.width - expectedWidth) < 0.5
            else { return false }
            observedWidth = frame.width
            return true
        }
        return observedWidth!
    }

    private func verifySettingsUndoRoutingAndCloseVeto(
        in application: NSRunningApplication,
        comparisonWindow: AXUIElement
    ) throws {
        try press(
            label: "Copy selected difference to left",
            in: application,
            root: comparisonWindow
        )
        try assertElement(
            label: "Left editable line 1",
            role: kAXTextAreaRole as String,
            value: "restored right",
            in: application,
            root: comparisonWindow
        )

        try activate(application)
        try press(label: "Options", in: application, root: comparisonWindow)
        var settingsWindow = try waitForWindow(
            containingLabel: "Algorithm",
            in: application
        )
        try waitForFocusedWindow(settingsWindow, in: application)
        try sendUndo(to: settingsWindow, in: application)
        try assertMenuItem(
            "Undo",
            in: "Edit",
            isEnabled: false,
            application: application
        )
        try pressWindowButton(kAXCloseButtonAttribute, in: settingsWindow)
        try waitForWindowToDisappear(settingsWindow, in: application)

        var currentComparisonWindow = try waitForWindow(
            identifier: "comparison",
            in: application
        )
        try focus(currentComparisonWindow, in: application)
        try assertElement(
            label: "Left editable line 1",
            role: kAXTextAreaRole as String,
            value: "restored right",
            in: application,
            root: currentComparisonWindow
        )
        print("Packaged UI smoke stage: Settings Undo remained isolated.")
        _ = try waitForElement(
            label: "Undo",
            role: kAXButtonRole as String,
            isEnabled: true,
            in: application,
            root: currentComparisonWindow
        )
        try assertMenuItem(
            "Undo",
            in: "Edit",
            isEnabled: true,
            application: application
        )
        try sendUndo(to: currentComparisonWindow, in: application)
        try assertElement(
            label: "Left editable line 1",
            role: kAXTextAreaRole as String,
            value: "restored left",
            in: application,
            root: currentComparisonWindow
        )
        print("Packaged UI smoke stage: comparison Undo applied.")

        try press(label: "Options", in: application, root: currentComparisonWindow)
        settingsWindow = try waitForWindow(
            containingLabel: "Algorithm",
            in: application
        )
        try focus(settingsWindow, in: application)
        try sendRedo(to: settingsWindow, in: application)
        try assertMenuItem(
            "Redo",
            in: "Edit",
            isEnabled: false,
            application: application
        )
        try pressWindowButton(kAXCloseButtonAttribute, in: settingsWindow)
        try waitForWindowToDisappear(settingsWindow, in: application)

        currentComparisonWindow = try waitForWindow(
            identifier: "comparison",
            in: application
        )
        try focus(currentComparisonWindow, in: application)
        try assertElement(
            label: "Left editable line 1",
            role: kAXTextAreaRole as String,
            value: "restored left",
            in: application,
            root: currentComparisonWindow
        )
        print("Packaged UI smoke stage: Settings Redo remained isolated.")
        try press(label: "Options", in: application, root: currentComparisonWindow)
        settingsWindow = try waitForWindow(
            containingLabel: "Algorithm",
            in: application
        )
        try waitForFocusedWindow(settingsWindow, in: application)

        try focus(currentComparisonWindow, in: application)
        try assertElement(
            label: "Left editable line 1",
            role: kAXTextAreaRole as String,
            value: "restored left",
            in: application,
            root: currentComparisonWindow
        )
        _ = try waitForElement(
            label: "Redo",
            role: kAXButtonRole as String,
            isEnabled: true,
            in: application,
            root: currentComparisonWindow
        )
        try assertMenuItem(
            "Redo",
            in: "Edit",
            isEnabled: true,
            application: application
        )
        try sendRedo(to: currentComparisonWindow, in: application)
        try assertElement(
            label: "Left editable line 1",
            role: kAXTextAreaRole as String,
            value: "restored right",
            in: application,
            root: currentComparisonWindow
        )

        try focus(currentComparisonWindow, in: application)
        try pressWindowButton(
            kAXCloseButtonAttribute,
            in: currentComparisonWindow
        )
        let alert = try waitForModalWindow(
            containingLabel: "Save changes before closing this comparison?",
            in: application
        )
        try assertWindowPresent(settingsWindow, in: application)
        try press(label: "Cancel", in: application, root: alert)
        try waitForWindowToDisappear(alert, in: application)
        try assertWindowPresent(currentComparisonWindow, in: application)
        try waitForFocusedWindow(currentComparisonWindow, in: application)
        try assertWindowPresent(settingsWindow, in: application)
        try assertElement(
            label: "Left editable line 1",
            role: kAXTextAreaRole as String,
            value: "restored right",
            in: application,
            root: currentComparisonWindow
        )
        _ = try waitForElement(
            label: "Undo",
            role: kAXButtonRole as String,
            isEnabled: true,
            in: application,
            root: currentComparisonWindow
        )
        try pressMenuItem("Undo", in: "Edit", application: application)
        try assertElement(
            label: "Left editable line 1",
            role: kAXTextAreaRole as String,
            value: "restored left",
            in: application,
            root: currentComparisonWindow
        )
        try closeWindow(containingLabel: "Algorithm", in: application)
        try waitForWindowToDisappear(settingsWindow, in: application)
    }

    private func activate(_ application: NSRunningApplication) throws {
        try waitUntil(timeout: Self.actionTimeout, context: "activating packaged MacMerge") {
            if application.isActive,
                NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == application.processIdentifier
            {
                return true
            }
            guard application.activate(options: [.activateAllWindows]) else { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            return application.isActive
                && NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == application.processIdentifier
        }
    }

    private func focus(
        _ window: AXUIElement,
        in application: NSRunningApplication
    ) throws {
        try activate(application)
        let result = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        if result == .success || result == .attributeUnsupported {
            try waitForFocusedWindow(window, in: application)
            return
        }
        var lastTransientError: AXError?
        do {
            try waitUntil(timeout: Self.actionTimeout, context: "raising window") {
                let result = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                switch result {
                case .success:
                    lastTransientError = nil
                    return true
                case .cannotComplete:
                    lastTransientError = result
                    return false
                case .invalidUIElement:
                    lastTransientError = result
                    return false
                case .apiDisabled:
                    throw SmokeError.accessibilityPermissionMissing
                default:
                    throw SmokeError.accessibilityFailure(
                        "AX raise failed with error \(result.rawValue)."
                    )
                }
            }
        } catch let error as SmokeError {
            if case .timeout = error, let lastTransientError {
                throw SmokeError.accessibilityFailure(
                    "AX raise remained unavailable with error \(lastTransientError.rawValue)."
                )
            }
            throw error
        }
        try waitForFocusedWindow(window, in: application)
    }

    private func sendUndo(
        to window: AXUIElement,
        in application: NSRunningApplication
    ) throws {
        try sendKey(
            character: "z",
            flags: .maskCommand,
            to: window,
            in: application
        )
    }

    private func sendRedo(
        to window: AXUIElement,
        in application: NSRunningApplication
    ) throws {
        try sendKey(
            character: "z",
            flags: [.maskCommand, .maskShift],
            to: window,
            in: application
        )
    }

    private func sendKey(
        character: Character,
        flags: CGEventFlags,
        to window: AXUIElement,
        in application: NSRunningApplication
    ) throws {
        try focus(window, in: application)
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: character == "z" ? 6 : 0,
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: character == "z" ? 6 : 0,
                keyDown: false
            )
        else {
            throw SmokeError.assertionFailed("Could not create keyboard events.")
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.postToPid(application.processIdentifier)
        keyUp.postToPid(application.processIdentifier)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        guard
            NSWorkspace.shared.frontmostApplication?.processIdentifier
                == application.processIdentifier
        else {
            throw SmokeError.assertionFailed(
                "Packaged MacMerge lost foreground while dispatching a keyboard command."
            )
        }
        try waitForFocusedWindow(window, in: application)
    }

    private func initializeSandboxContainer() async throws {
        let application = try await launch()
        _ = try waitForElement(label: "No left file loaded", in: application)
        try forceTerminate(application, context: "initializing isolated sandbox container")

        let container =
            sessionURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: container.path) else {
            throw SmokeError.assertionFailed(
                "Sandbox container was not created at \(container.path)."
            )
        }
        try validateSessionDestination()
    }

    private func validateSessionDestination() throws {
        let expectedPrefix = containerURL.standardizedFileURL.path + "/"
        guard sessionURL.standardizedFileURL.path.hasPrefix(expectedPrefix) else {
            throw SmokeError.assertionFailed(
                "Session destination escaped isolated container \(containerURL.path)."
            )
        }
        var checkedPath = ""
        for component in sessionURL.pathComponents {
            if component == "/" {
                checkedPath = "/"
                continue
            }
            checkedPath =
                URL(filePath: checkedPath, directoryHint: .isDirectory)
                .appending(path: component)
                .path
            var metadata = stat()
            if lstat(checkedPath, &metadata) == 0 {
                guard metadata.st_mode & S_IFMT != S_IFLNK else {
                    throw SmokeError.assertionFailed(
                        "Refusing symlinked session destination ancestor \(checkedPath)."
                    )
                }
            } else if errno != ENOENT {
                throw SmokeError.assertionFailed(
                    "Could not inspect session destination ancestor \(checkedPath): \(String(cString: strerror(errno)))."
                )
            }
        }
    }

    private func writeSeedSession(
        lineCount: Int = 60,
        locationPaneVisible: Bool = false,
        locationPaneWidth: Double = 120
    ) throws {
        let leftLines = (1...lineCount).map { line in
            line == 1 ? "restored left" : String(format: "common %02d", line)
        }
        let rightLines = (1...lineCount).map { line in
            line == 1 ? "restored right" : String(format: "common %02d", line)
        }
        let state: [String: Any] = [
            "schemaVersion": 1,
            "left": ["kind": "scratchpad", "text": leftLines.joined(separator: "\n") + "\n"],
            "right": ["kind": "scratchpad", "text": rightLines.joined(separator: "\n") + "\n"],
            "rightReadOnly": true,
            "selectedRow": 0,
            "activeSide": "right",
            "windowFrame": ["x": 100, "y": 100, "width": 1180, "height": 720],
            "splitOrientation": "vertical",
            "splitFraction": 0.5,
            "locationPaneVisible": locationPaneVisible,
            "locationPaneWidth": locationPaneWidth
        ]
        let data = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        try validateSessionDestination()
        try FileManager.default.createDirectory(
            at: sessionURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try validateSessionDestination()
        try data.write(to: sessionURL, options: .atomic)
    }

    private func assertInitialRestore(in application: NSRunningApplication) throws {
        try assertElement(
            label: "Make left file read-only",
            role: kAXButtonRole as String,
            value: "Editable",
            in: application
        )
        try assertElement(
            label: "Make right file editable",
            role: kAXButtonRole as String,
            value: "Read-only",
            in: application
        )
        try assertElement(
            label: "Left editable line 1",
            role: kAXTextAreaRole as String,
            value: "restored left",
            in: application
        )
        try assertElement(
            label: "Right read-only line 1",
            role: kAXTextAreaRole as String,
            value: "restored right",
            in: application
        )
    }

    private func waitForReadOnlyState(in application: NSRunningApplication) throws {
        try assertElement(
            label: "Make left file editable",
            role: kAXButtonRole as String,
            value: "Read-only",
            in: application
        )
        try assertElement(
            label: "Make right file editable",
            role: kAXButtonRole as String,
            value: "Read-only",
            in: application
        )
        try assertElement(
            label: "Left read-only line 1",
            role: kAXTextAreaRole as String,
            value: "restored left",
            in: application
        )
        try assertElement(
            label: "Right read-only line 1",
            role: kAXTextAreaRole as String,
            value: "restored right",
            in: application
        )
    }

    private func assertSecondRestore(in application: NSRunningApplication) throws {
        try waitForReadOnlyState(in: application)
    }

    private func assertPersistedLocationPaneState(expectedWidth: Double) throws {
        let data = try Data(contentsOf: sessionURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["locationPaneVisible"] as? Bool == true,
            let width = (object["locationPaneWidth"] as? NSNumber)?.doubleValue,
            abs(width - expectedWidth) < 0.5,
            abs(width - 120) >= 0.5
        else {
            throw SmokeError.assertionFailed(
                "Persisted session did not contain Location Pane state."
            )
        }
    }

    private func assertPersistedReadOnlyState() throws {
        let data = try Data(contentsOf: sessionURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["leftReadOnly"] as? Bool == true,
            object["rightReadOnly"] as? Bool == true
        else {
            throw SmokeError.assertionFailed(
                "Persisted session did not contain independent read-only state."
            )
        }
    }

    private func launch() async throws -> NSRunningApplication {
        try Data().write(to: launchIntentURL, options: .atomic)
        let launchIntentURL = launchIntentURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        let application: NSRunningApplication = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<NSRunningApplication, Error>) in
            NSWorkspace.shared.openApplication(
                at: applicationURL,
                configuration: configuration
            ) { application, error in
                if let error {
                    try? FileManager.default.removeItem(at: launchIntentURL)
                    continuation.resume(
                        throwing: SmokeError.launchFailed(
                            "Could not launch packaged MacMerge: \(error.localizedDescription)"
                        ))
                } else if let application {
                    continuation.resume(returning: application)
                } else {
                    try? FileManager.default.removeItem(at: launchIntentURL)
                    continuation.resume(
                        throwing: SmokeError.launchFailed(
                            "Could not launch packaged MacMerge."
                        ))
                }
            }
        }
        launchedApplications.append(application)
        try recordLaunchedProcess(application.processIdentifier)
        try? FileManager.default.removeItem(at: launchIntentURL)
        var lastTransientError: AXError?
        do {
            try waitUntil(timeout: Self.launchTimeout, context: "waiting for comparison window") {
                guard !application.isTerminated else {
                    throw SmokeError.applicationExited(
                        "Packaged MacMerge exited before exposing its comparison window."
                    )
                }
                let root = AXUIElementCreateApplication(application.processIdentifier)
                do {
                    return !(try copyElements(kAXWindowsAttribute, from: root)?.isEmpty ?? true)
                } catch AXReadError.transient(let error) {
                    lastTransientError = error
                    return false
                } catch AXReadError.fatal(let error, let attribute) {
                    throw accessibilityFailure(error, attribute: attribute)
                }
            }
        } catch let error as SmokeError {
            if case .timeout = error, let lastTransientError {
                throw SmokeError.accessibilityFailure(
                    "AX window lookup remained unavailable with error \(lastTransientError.rawValue)."
                )
            }
            throw error
        }
        return application
    }

    private func recordLaunchedProcess(_ processIdentifier: pid_t) throws {
        let data = Data("\(processIdentifier)\n".utf8)
        if !FileManager.default.fileExists(atPath: launchedPIDURL.path) {
            try data.write(to: launchedPIDURL, options: .atomic)
            return
        }
        let handle = try FileHandle(forWritingTo: launchedPIDURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func rewriteLaunchedProcessRecord() throws {
        let data = Data(
            launchedApplications
                .filter { !$0.isTerminated }
                .map { "\($0.processIdentifier)\n" }
                .joined()
                .utf8
        )
        try data.write(to: launchedPIDURL, options: .atomic)
        if data.isEmpty {
            try? FileManager.default.removeItem(at: launchedPIDURL)
        }
    }

    private func terminate(
        _ application: NSRunningApplication,
        context: String
    ) async throws {
        guard let running = matchingRunningApplication(application) else {
            launchedApplications.removeAll {
                $0.processIdentifier == application.processIdentifier
            }
            try rewriteLaunchedProcessRecord()
            return
        }
        guard running.terminate() else {
            throw SmokeError.assertionFailed("MacMerge rejected termination while \(context).")
        }
        try waitUntil(timeout: Self.launchTimeout, context: context) {
            self.matchingRunningApplication(application) == nil
        }
        launchedApplications.removeAll {
            $0.processIdentifier == application.processIdentifier
        }
        try rewriteLaunchedProcessRecord()
    }

    private func forceTerminate(
        _ application: NSRunningApplication,
        context: String
    ) throws {
        guard let running = matchingRunningApplication(application) else { return }
        guard running.forceTerminate() else {
            throw SmokeError.assertionFailed(
                "MacMerge rejected force termination while \(context)."
            )
        }
        try waitUntil(timeout: Self.launchTimeout, context: context) {
            self.matchingRunningApplication(application) == nil
        }
        launchedApplications.removeAll {
            $0.processIdentifier == application.processIdentifier
        }
        try rewriteLaunchedProcessRecord()
    }

    private func matchingRunningApplication(
        _ application: NSRunningApplication
    ) -> NSRunningApplication? {
        guard
            let running = NSRunningApplication(
                processIdentifier: application.processIdentifier
            ),
            !running.isTerminated,
            running.bundleIdentifier == bundleIdentifier,
            running.bundleURL?.resolvingSymlinksInPath()
                == applicationURL.resolvingSymlinksInPath(),
            running.launchDate == application.launchDate
        else { return nil }
        return running
    }

    private func terminateAllApplications() throws {
        for application in launchedApplications {
            guard let running = matchingRunningApplication(application) else { continue }
            if running.terminate() {
                try? waitUntil(
                    timeout: 2,
                    context: "terminating failed smoke application",
                    checksCancellation: false
                ) {
                    self.matchingRunningApplication(application) == nil
                }
            }
            if let running = matchingRunningApplication(application) {
                _ = running.forceTerminate()
                try waitUntil(
                    timeout: Self.launchTimeout,
                    context: "force-terminating failed smoke application",
                    checksCancellation: false
                ) {
                    self.matchingRunningApplication(application) == nil
                }
            }
        }
        launchedApplications.removeAll {
            matchingRunningApplication($0) == nil
        }
        try rewriteLaunchedProcessRecord()
    }

    private func press(
        label: String,
        role: String? = nil,
        in application: NSRunningApplication,
        root: AXUIElement? = nil
    ) throws {
        var lastTransientError: AXError?
        do {
            try waitUntil(timeout: Self.actionTimeout, context: "pressing AX element \(label)") {
                let node = try waitForElement(
                    label: label,
                    role: role,
                    in: application,
                    root: root
                )
                let result = AXUIElementPerformAction(node.element, kAXPressAction as CFString)
                switch result {
                case .success:
                    lastTransientError = nil
                    return true
                case .cannotComplete:
                    lastTransientError = result
                    return false
                case .invalidUIElement:
                    lastTransientError = result
                    return false
                case .apiDisabled:
                    throw SmokeError.accessibilityPermissionMissing
                default:
                    throw SmokeError.accessibilityFailure(
                        "AX press failed for \(label) with error \(result.rawValue)."
                    )
                }
            }
        } catch let error as SmokeError {
            if case .timeout = error, let lastTransientError {
                throw SmokeError.accessibilityFailure(
                    "AX press for \(label) remained unavailable with error \(lastTransientError.rawValue)."
                )
            }
            throw error
        }
    }

    private func setValue(
        _ value: Double,
        on label: String,
        in application: NSRunningApplication,
        root: AXUIElement? = nil
    ) throws {
        var lastTransientError: AXError?
        do {
            try waitUntil(timeout: Self.actionTimeout, context: "setting AX value for \(label)") {
                let node = try waitForElement(
                    label: label,
                    role: kAXSliderRole as String,
                    isEnabled: true,
                    in: application,
                    root: root
                )
                let result = AXUIElementSetAttributeValue(
                    node.element,
                    kAXValueAttribute as CFString,
                    NSNumber(value: value)
                )
                switch result {
                case .success:
                    lastTransientError = nil
                    return true
                case .cannotComplete:
                    lastTransientError = result
                    return false
                case .invalidUIElement:
                    lastTransientError = result
                    return false
                case .failure:
                    lastTransientError = result
                    return false
                case .apiDisabled:
                    throw SmokeError.accessibilityPermissionMissing
                default:
                    throw SmokeError.accessibilityFailure(
                        "AX value write failed for \(label) with error \(result.rawValue)."
                    )
                }
            }
        } catch AXReadError.transient(let error) {
            throw SmokeError.accessibilityFailure(
                "Window close remained unavailable with AX error \(error.rawValue)."
            )
        } catch let error as SmokeError {
            if case .timeout = error, let lastTransientError {
                throw SmokeError.accessibilityFailure(
                    "AX value write for \(label) remained unavailable with error \(lastTransientError.rawValue)."
                )
            }
            throw error
        }
    }

    private func waitForElementSize(
        label: String,
        role: String,
        in application: NSRunningApplication,
        root: AXUIElement
    ) throws -> CGSize {
        var found: CGSize?
        try retryingTransientAX(timeout: Self.actionTimeout, context: "reading AX size for \(label)") {
            guard
                let node = try findElement(
                    label: label,
                    role: role,
                    processIdentifier: application.processIdentifier,
                    root: root
                ),
                let size = try copySize(kAXSizeAttribute, from: node.element)
            else { return false }
            found = size
            return true
        }
        return found!
    }

    private func waitForVisibleElement(
        label: String,
        role: String,
        value: String,
        in application: NSRunningApplication,
        root: AXUIElement
    ) throws {
        try retryingTransientAX(
            timeout: Self.actionTimeout,
            context: "waiting for visible AX element \(label)"
        ) {
            guard
                let node = try findElement(
                    label: label,
                    role: role,
                    value: value,
                    processIdentifier: application.processIdentifier,
                    root: root
                ),
                let elementFrame = try copyFrame(from: node.element),
                let viewportFrame = try nearestViewportFrame(
                    from: node.element,
                    stoppingAt: root
                )
            else { return false }
            return !elementFrame.isEmpty && viewportFrame.intersects(elementFrame)
        }
    }

    private func nearestViewportFrame(
        from element: AXUIElement,
        stoppingAt root: AXUIElement
    ) throws -> CGRect? {
        var current = element
        var fallback = try copyFrame(from: root)
        while !CFEqual(current, root) {
            guard let parent = try copyElement(kAXParentAttribute, from: current) else { break }
            let role = try copyOptionalString(kAXRoleAttribute, from: parent)
            if role == kAXScrollAreaRole as String || role == kAXTableRole as String {
                if let frame = try copyFrame(from: parent) { fallback = frame }
            }
            current = parent
        }
        return fallback
    }

    private func assertElement(
        label: String,
        role: String,
        value: String,
        in application: NSRunningApplication,
        root: AXUIElement? = nil
    ) throws {
        do {
            _ = try waitForElement(
                label: label,
                role: role,
                value: value,
                in: application,
                root: root
            )
        } catch {
            if let observed = try? waitForElement(
                label: label,
                role: role,
                in: application,
                root: root
            ) {
                if observed.value == value { return }
                throw SmokeError.assertionFailed(
                    "AX element \(label) had value \(observed.value ?? "nil"), expected \(value)."
                )
            }
            throw error
        }
    }

    private func waitForElement(
        label: String,
        role: String? = nil,
        value: String? = nil,
        isEnabled: Bool? = nil,
        isMarked: Bool? = nil,
        in application: NSRunningApplication,
        root: AXUIElement? = nil
    ) throws -> AXNode {
        var found: AXNode?
        var lastTransientError: AXError?
        do {
            try waitUntil(timeout: Self.actionTimeout, context: "waiting for AX element \(label)") {
                guard AXIsProcessTrusted() else {
                    throw SmokeError.accessibilityPermissionMissing
                }
                guard !application.isTerminated else {
                    throw SmokeError.applicationExited(
                        "Packaged MacMerge exited while waiting for AX element \(label)."
                    )
                }
                do {
                    found = try findElement(
                        label: label,
                        role: role,
                        value: value,
                        isEnabled: isEnabled,
                        isMarked: isMarked,
                        processIdentifier: application.processIdentifier,
                        root: root
                    )
                    lastTransientError = nil
                } catch AXReadError.transient(let error) {
                    lastTransientError = error
                    return false
                } catch AXReadError.fatal(let error, let attribute) {
                    throw accessibilityFailure(error, attribute: attribute)
                }
                return found != nil
            }
        } catch let error as SmokeError {
            if case .timeout = error, let lastTransientError, found == nil {
                throw SmokeError.accessibilityFailure(
                    "AX lookup for \(label) remained unavailable with error \(lastTransientError.rawValue)."
                )
            }
            throw error
        }
        return found!
    }

    private func findElement(
        label: String,
        role: String? = nil,
        value: String? = nil,
        isEnabled: Bool? = nil,
        isMarked: Bool? = nil,
        processIdentifier: pid_t,
        root: AXUIElement? = nil
    ) throws -> AXNode? {
        var queue = [root ?? AXUIElementCreateApplication(processIdentifier)]
        var visited: [CFHashCode: [AXUIElement]] = [:]
        var uniqueNodeCount = 0
        var index = 0
        while index < queue.count {
            let element = queue[index]
            index += 1
            let hash = CFHash(element)
            if visited[hash]?.contains(where: { CFEqual($0, element) }) == true {
                continue
            }
            visited[hash, default: []].append(element)
            uniqueNodeCount += 1
            guard uniqueNodeCount <= Self.maximumAXNodes else {
                throw SmokeError.accessibilityFailure(
                    "AX tree exceeded the \(Self.maximumAXNodes)-element safety limit."
                )
            }
            let node = AXNode(
                element: element,
                role: try copyOptionalString(kAXRoleAttribute, from: element),
                title: try copyOptionalString(kAXTitleAttribute, from: element),
                description: try copyOptionalString(kAXDescriptionAttribute, from: element),
                value: try copyOptionalString(kAXValueAttribute, from: element),
                isEnabled: try copyOptionalBool(kAXEnabledAttribute, from: element)
            )
            let matchesCandidate =
                node.hasLabel(label)
                && (role.map { node.role == $0 } ?? true)
                && (value.map { node.value == $0 } ?? true)
                && (isEnabled.map { node.isEnabled == $0 } ?? true)
            if matchesCandidate {
                let hasExpectedMark: Bool
                if let isMarked {
                    let mark = try copyString(kAXMenuItemMarkCharAttribute, from: element)
                    hasExpectedMark = (mark?.isEmpty == false) == isMarked
                } else {
                    hasExpectedMark = true
                }
                if hasExpectedMark {
                    return node
                }
            }
            if let children = try copyTraversalChildren(from: element, role: node.role) {
                queue.append(contentsOf: children)
            }
        }
        return nil
    }

    private func waitForWindow(
        identifier: String,
        in application: NSRunningApplication
    ) throws -> AXUIElement {
        var found: AXUIElement?
        try retryingTransientAX(timeout: Self.actionTimeout, context: "waiting for window \(identifier)") {
            let root = AXUIElementCreateApplication(application.processIdentifier)
            guard let windows = try copyElements(kAXWindowsAttribute, from: root) else { return false }
            found = try windows.first { try copyString(kAXIdentifierAttribute, from: $0) == identifier }
            return found != nil
        }
        return found!
    }

    private func waitForLocationPaneMenuItem(
        isMarked: Bool,
        in application: NSRunningApplication
    ) throws -> AXUIElement {
        var found: AXUIElement?
        try retryingTransientAX(timeout: Self.actionTimeout, context: "waiting for Location Pane menu item") {
            let root = AXUIElementCreateApplication(application.processIdentifier)
            guard let menuBar = try copyElement(kAXMenuBarAttribute, from: root),
                let menuBarItems = try copyElements(kAXChildrenAttribute, from: menuBar),
                let viewItem = try menuBarItems.first(where: {
                    try copyString(kAXTitleAttribute, from: $0) == "View"
                }),
                let menus = try copyElements(kAXChildrenAttribute, from: viewItem),
                let menu = menus.first,
                let items = try copyElements(kAXChildrenAttribute, from: menu),
                let item = try items.first(where: {
                    try copyString(kAXTitleAttribute, from: $0) == "Location Pane"
                })
            else { return false }
            let mark = try copyString(kAXMenuItemMarkCharAttribute, from: item)
            guard (mark?.isEmpty == false) == isMarked else { return false }
            found = item
            return found != nil
        }
        return found!
    }

    private func assertMenuItem(
        _ title: String,
        in menuTitle: String,
        isEnabled: Bool,
        application: NSRunningApplication
    ) throws {
        let root = AXUIElementCreateApplication(application.processIdentifier)
        guard let menuBar = try copyElement(kAXMenuBarAttribute, from: root),
            let menuBarItems = try copyElements(kAXChildrenAttribute, from: menuBar),
            let menuBarItem = try menuBarItems.first(where: {
                try copyString(kAXTitleAttribute, from: $0) == menuTitle
            })
        else {
            throw SmokeError.assertionFailed("Could not find \(menuTitle) menu.")
        }
        let openResult = AXUIElementPerformAction(menuBarItem, kAXPressAction as CFString)
        guard openResult == .success || openResult == .cannotComplete else {
            throw SmokeError.accessibilityFailure(
                "AX press failed for \(menuTitle) menu with error \(openResult.rawValue)."
            )
        }
        defer { AXUIElementPerformAction(menuBarItem, kAXCancelAction as CFString) }
        _ = try waitForElement(
            label: title,
            role: kAXMenuItemRole as String,
            isEnabled: isEnabled,
            in: application,
            root: menuBarItem
        )
    }

    private func pressMenuItem(
        _ title: String,
        in menuTitle: String,
        application: NSRunningApplication
    ) throws {
        let root = AXUIElementCreateApplication(application.processIdentifier)
        guard let menuBar = try copyElement(kAXMenuBarAttribute, from: root),
            let menuBarItems = try copyElements(kAXChildrenAttribute, from: menuBar),
            let menuBarItem = try menuBarItems.first(where: {
                try copyString(kAXTitleAttribute, from: $0) == menuTitle
            })
        else {
            throw SmokeError.assertionFailed("Could not find \(menuTitle) menu.")
        }
        try performPress(menuBarItem, label: "\(menuTitle) menu")
        let item = try waitForElement(
            label: title,
            role: kAXMenuItemRole as String,
            isEnabled: true,
            in: application,
            root: menuBarItem
        )
        try performPress(item.element, label: title)
    }

    private func performPress(_ element: AXUIElement, label: String) throws {
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard result == .success || result == .cannotComplete else {
            throw SmokeError.accessibilityFailure(
                "AX press failed for \(label) with error \(result.rawValue)."
            )
        }
    }

    private func waitForWindow(
        containingLabel label: String,
        in application: NSRunningApplication
    ) throws -> AXUIElement {
        var found: AXUIElement?
        try retryingTransientAX(
            timeout: Self.actionTimeout,
            context: "waiting for window containing \(label)"
        ) {
            let root = AXUIElementCreateApplication(application.processIdentifier)
            guard let windows = try copyElements(kAXWindowsAttribute, from: root) else {
                return false
            }
            for window in windows {
                if try findElement(
                    label: label,
                    processIdentifier: application.processIdentifier,
                    root: window
                ) != nil {
                    found = window
                    return true
                }
            }
            return false
        }
        return found!
    }

    private func waitForWindowToDisappear(
        _ expected: AXUIElement,
        in application: NSRunningApplication
    ) throws {
        try retryingTransientAX(
            timeout: Self.actionTimeout,
            context: "waiting for window to close"
        ) {
            let root = AXUIElementCreateApplication(application.processIdentifier)
            guard let windows = try copyElements(kAXWindowsAttribute, from: root) else { return false }
            return !windows.contains(where: { CFEqual($0, expected) })
        }
    }

    private func waitForFocusedWindow(
        _ expected: AXUIElement,
        in application: NSRunningApplication
    ) throws {
        try retryingTransientAX(timeout: Self.actionTimeout, context: "waiting for key window") {
            let root = AXUIElementCreateApplication(application.processIdentifier)
            guard let focused = try copyElement(kAXFocusedWindowAttribute, from: root) else {
                return false
            }
            return CFEqual(focused, expected)
        }
    }

    private func assertWindowPresent(
        _ expected: AXUIElement,
        in application: NSRunningApplication
    ) throws {
        try retryingTransientAX(timeout: Self.actionTimeout, context: "verifying window remains open") {
            let root = AXUIElementCreateApplication(application.processIdentifier)
            guard let windows = try copyElements(kAXWindowsAttribute, from: root) else {
                return false
            }
            return windows.contains { CFEqual($0, expected) }
        }
    }

    private func waitForModalWindow(
        containingLabel label: String,
        in application: NSRunningApplication
    ) throws -> AXUIElement {
        var found: AXUIElement?
        try retryingTransientAX(
            timeout: Self.actionTimeout,
            context: "waiting for focused close confirmation"
        ) {
            let root = AXUIElementCreateApplication(application.processIdentifier)
            guard let windows = try copyElements(kAXWindowsAttribute, from: root),
                let focused = try copyElement(kAXFocusedWindowAttribute, from: root),
                windows.contains(where: { CFEqual($0, focused) }),
                try copyBool(kAXModalAttribute, from: focused) == true,
                try findElement(
                    label: label,
                    processIdentifier: application.processIdentifier,
                    root: focused
                ) != nil
            else {
                return false
            }
            found = focused
            return true
        }
        return found!
    }

    private func closeWindow(
        containingLabel label: String,
        in application: NSRunningApplication
    ) throws {
        var lastTransientError: AXError?
        do {
            try waitUntil(timeout: Self.actionTimeout, context: "closing window containing \(label)") {
                let window = try waitForWindow(containingLabel: label, in: application)
                let button: AXUIElement
                do {
                    guard let found = try copyElement(kAXCloseButtonAttribute, from: window) else {
                        throw SmokeError.assertionFailed(
                            "Window containing \(label) does not expose a close button."
                        )
                    }
                    button = found
                } catch AXReadError.transient(let error) {
                    lastTransientError = error
                    return false
                } catch AXReadError.fatal(let error, let attribute) {
                    throw accessibilityFailure(error, attribute: attribute)
                }
                let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
                switch result {
                case .success:
                    lastTransientError = nil
                    return true
                case .cannotComplete:
                    lastTransientError = result
                    return false
                case .invalidUIElement:
                    lastTransientError = result
                    return false
                case .apiDisabled:
                    throw SmokeError.accessibilityPermissionMissing
                default:
                    throw SmokeError.accessibilityFailure(
                        "AX close-button press failed with error \(result.rawValue)."
                    )
                }
            }
        } catch let error as SmokeError {
            if case .timeout = error, let lastTransientError {
                throw SmokeError.accessibilityFailure(
                    "Window close remained unavailable with AX error \(lastTransientError.rawValue)."
                )
            }
            throw error
        }
    }

    private func pressWindowButton(
        _ attribute: String,
        in window: AXUIElement
    ) throws {
        var lastTransientError: AXError?
        do {
            try waitUntil(timeout: Self.actionTimeout, context: "pressing window button") {
                let button: AXUIElement
                do {
                    guard let found = try copyElement(attribute, from: window) else {
                        throw SmokeError.assertionFailed("Window does not expose \(attribute).")
                    }
                    button = found
                } catch AXReadError.transient(let error) {
                    lastTransientError = error
                    return false
                } catch AXReadError.fatal(let error, let attribute) {
                    throw accessibilityFailure(error, attribute: attribute)
                }
                let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
                switch result {
                case .success:
                    lastTransientError = nil
                    return true
                case .cannotComplete:
                    // AppKit may present the close sheet while AX reports timeout.
                    // Callers verify the exact resulting window state.
                    lastTransientError = nil
                    return true
                case .invalidUIElement:
                    lastTransientError = result
                    return false
                case .apiDisabled:
                    throw SmokeError.accessibilityPermissionMissing
                default:
                    throw SmokeError.accessibilityFailure(
                        "AX window-button press failed with error \(result.rawValue)."
                    )
                }
            }
        } catch let error as SmokeError {
            if case .timeout = error, let lastTransientError {
                throw SmokeError.accessibilityFailure(
                    "AX window-button press remained unavailable with error \(lastTransientError.rawValue)."
                )
            }
            throw error
        }
    }

    private func copyString(_ attribute: String, from element: AXUIElement) throws -> String? {
        let value = try copyAttribute(attribute, from: element)
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private func copyOptionalString(
        _ attribute: String,
        from element: AXUIElement
    ) throws -> String? {
        do {
            return try copyString(attribute, from: element)
        } catch AXReadError.fatal(let error, _) where error == .failure {
            return nil
        }
    }

    private func copyBool(_ attribute: String, from element: AXUIElement) throws -> Bool? {
        try copyAttribute(attribute, from: element) as? Bool
    }

    private func copyOptionalBool(
        _ attribute: String,
        from element: AXUIElement
    ) throws -> Bool? {
        do {
            return try copyBool(attribute, from: element)
        } catch AXReadError.fatal(let error, _) where error == .failure {
            return nil
        }
    }

    private func copyPoint(_ attribute: String, from element: AXUIElement) throws -> CGPoint? {
        guard let value = try copyAttribute(attribute, from: element),
            CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func copySize(_ attribute: String, from element: AXUIElement) throws -> CGSize? {
        guard let value = try copyAttribute(attribute, from: element),
            CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    private func copyFrame(from element: AXUIElement) throws -> CGRect? {
        guard let position = try copyPoint(kAXPositionAttribute, from: element),
            let size = try copySize(kAXSizeAttribute, from: element)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func copyElements(_ attribute: String, from element: AXUIElement) throws -> [AXUIElement]? {
        try copyAttribute(attribute, from: element) as? [AXUIElement]
    }

    private func copyTraversalChildren(
        from element: AXUIElement,
        role: String?
    ) throws -> [AXUIElement]? {
        do {
            return try copyElements(kAXChildrenAttribute, from: element)
        } catch AXReadError.fatal(let error, _) where error == .failure {
            return nil
        }
    }

    private func copyElement(_ attribute: String, from element: AXUIElement) throws -> AXUIElement? {
        try copyAttribute(attribute, from: element) as! AXUIElement?
    }

    private func copyAttribute(_ attribute: String, from element: AXUIElement) throws -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        switch result {
        case .success:
            return value
        case .noValue, .attributeUnsupported:
            return nil
        case .cannotComplete, .invalidUIElement:
            throw AXReadError.transient(result)
        default:
            throw AXReadError.fatal(result, attribute)
        }
    }

    private func accessibilityFailure(_ error: AXError, attribute: String) -> SmokeError {
        if error == .apiDisabled { return .accessibilityPermissionMissing }
        return .accessibilityFailure(
            "AX read failed for \(attribute) with error \(error.rawValue)."
        )
    }

    private func retryingTransientAX(
        timeout: TimeInterval,
        context: String,
        condition: () throws -> Bool
    ) throws {
        var lastTransientError: AXError?
        do {
            try waitUntil(timeout: timeout, context: context) {
                do {
                    let result = try condition()
                    lastTransientError = nil
                    return result
                } catch AXReadError.transient(let error) {
                    lastTransientError = error
                    return false
                } catch AXReadError.fatal(let error, let attribute) {
                    throw accessibilityFailure(error, attribute: attribute)
                }
            }
        } catch let error as SmokeError {
            if case .timeout = error, let lastTransientError {
                throw SmokeError.accessibilityFailure(
                    "\(context) remained unavailable with AX error \(lastTransientError.rawValue)."
                )
            }
            throw error
        }
    }

    private func waitUntil(
        timeout: TimeInterval,
        context: String,
        checksCancellation: Bool = true,
        condition: () throws -> Bool
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if checksCancellation { try checkCancellation() }
            if try condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        throw SmokeError.timeout("Timed out \(context).")
    }
}

@main
private struct PackagedUISmokeMain {
    static func main() async {
        do {
            guard CommandLine.arguments.count == 7 else {
                throw SmokeError.invalidApplication(
                    "Usage: PackagedUISmoke /path/to/MacMerge.app /path/to/launched-pids /path/to/launch-intent /path/to/completion-guard /path/to/cancellation bundle-id"
                )
            }
            let applicationURL = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
            let launchedPIDURL = URL(filePath: CommandLine.arguments[2])
            let launchIntentURL = URL(filePath: CommandLine.arguments[3])
            let completionGuardURL = URL(filePath: CommandLine.arguments[4])
            let cancellationURL = URL(filePath: CommandLine.arguments[5])
            try await PackagedUISmoke(
                applicationURL: applicationURL,
                launchedPIDURL: launchedPIDURL,
                launchIntentURL: launchIntentURL,
                completionGuardURL: completionGuardURL,
                cancellationURL: cancellationURL,
                expectedBundleIdentifier: CommandLine.arguments[6]
            ).run()
        } catch {
            FileHandle.standardError.write(Data("Packaged UI smoke failed: \(error.localizedDescription)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }
}
