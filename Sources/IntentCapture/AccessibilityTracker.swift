import AppKit
import ApplicationServices
import Combine

/// Bundle IDs of known browsers for URL extraction.
private let kBrowserBundleIds: Set<String> = [
    "com.apple.Safari",
    "com.google.Chrome",
    "com.google.Chrome.canary",
    "org.chromium.Chromium",
    "com.brave.Browser",
    "com.microsoft.edgemac",
    "company.thebrowser.Browser",  // Arc
    "org.mozilla.firefox",
    "org.mozilla.nightly",
    "com.operasoftware.Opera",
    "com.vivaldi.Vivaldi",
]

/// Max depth for AX tree traversal to avoid runaway recursion.
private let kMaxTreeDepth = 15

@MainActor
final class AccessibilityTracker: ObservableObject {
    @Published var isTracking = false
    @Published var lastAppName: String = ""
    @Published var lastWindowTitle: String = ""
    @Published var lastFocusedElement: String = ""

    private var pollTimer: Timer?
    private var purgeTimer: Timer?
    private let dbManager: DatabaseManager

    nonisolated init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    // MARK: - Accessibility Permission

    func checkAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        return false
    }

    // MARK: - Tracking Control

    func startTracking() {
        guard !isTracking else { return }

        if !checkAccessibilityPermission() {
            return
        }

        isTracking = true
        poll()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }

        purgeTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.dbManager.purgeOldRecords()
        }
    }

    func stopTracking() {
        isTracking = false
        pollTimer?.invalidate()
        pollTimer = nil
        purgeTimer?.invalidate()
        purgeTimer = nil
    }

    // MARK: - Polling

    private func poll() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }

        let appName = frontApp.localizedName ?? "Unknown"
        let bundleId = frontApp.bundleIdentifier ?? "unknown"
        let pid = frontApp.processIdentifier

        var ctx = captureWindowContext(pid: pid)

        if kBrowserBundleIds.contains(bundleId) {
            ctx.url = extractBrowserURL(pid: pid) ?? ""
        }

        lastAppName = appName
        lastWindowTitle = ctx.windowTitle
        lastFocusedElement = [ctx.focusedRole, ctx.focusedTitle].filter { !$0.isEmpty }.joined(separator: ": ")

        if dbManager.shouldInsert(
            appName: appName, bundleId: bundleId, windowTitle: ctx.windowTitle,
            focusedRole: ctx.focusedRole, focusedTitle: ctx.focusedTitle
        ) {
            let record = ActivityRecord(
                id: nil,
                timestamp: Date(),
                appName: appName,
                bundleId: bundleId,
                windowTitle: ctx.windowTitle,
                focusedRole: ctx.focusedRole,
                focusedTitle: ctx.focusedTitle,
                focusedValue: ctx.focusedValue,
                selectedText: ctx.selectedText,
                documentPath: ctx.documentPath,
                url: ctx.url,
                windowHierarchy: ctx.windowHierarchy
            )
            dbManager.insertRecord(record)
        }
    }

    // MARK: - Full Window Context Capture

    private func captureWindowContext(pid: pid_t) -> WindowContext {
        var ctx = WindowContext()
        let appElement = AXUIElementCreateApplication(pid)

        // Get focused window
        guard let window = axValue(of: appElement, attribute: kAXFocusedWindowAttribute) as! AXUIElement? else {
            if let mainWin = axValue(of: appElement, attribute: kAXMainWindowAttribute) as! AXUIElement? {
                ctx.windowTitle = axString(of: mainWin, attribute: kAXTitleAttribute)
                ctx.documentPath = axString(of: mainWin, attribute: kAXDocumentAttribute)
                ctx.windowHierarchy = serializeTree(root: mainWin)
            }
            return ctx
        }

        ctx.windowTitle = axString(of: window, attribute: kAXTitleAttribute)
        ctx.documentPath = axString(of: window, attribute: kAXDocumentAttribute)

        // Capture the full AX tree of the window
        ctx.windowHierarchy = serializeTree(root: window)

        // Get the focused UI element within the window
        guard let focused = axValue(of: appElement, attribute: kAXFocusedUIElementAttribute) as! AXUIElement? else {
            return ctx
        }

        ctx.focusedRole = axString(of: focused, attribute: kAXRoleAttribute)
        ctx.focusedTitle = axString(of: focused, attribute: kAXTitleAttribute)

        if ctx.focusedTitle.isEmpty {
            ctx.focusedTitle = axString(of: focused, attribute: kAXDescriptionAttribute)
        }
        if ctx.focusedTitle.isEmpty {
            ctx.focusedTitle = axString(of: focused, attribute: kAXRoleDescriptionAttribute)
        }

        // Skip value extraction for secure text fields (passwords)
        if ctx.focusedRole != "AXSecureTextField" {
            ctx.focusedValue = axString(of: focused, attribute: kAXValueAttribute)
        }

        ctx.selectedText = axString(of: focused, attribute: kAXSelectedTextAttribute)

        return ctx
    }

    // MARK: - AX Tree Serialization

    private func serializeTree(root: AXUIElement) -> String {
        let tree = buildNode(element: root, depth: 0)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(tree) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func buildNode(element: AXUIElement, depth: Int) -> AXNode {
        let role = axString(of: element, attribute: kAXRoleAttribute)
        let subrole = axString(of: element, attribute: kAXSubroleAttribute)
        let title = axString(of: element, attribute: kAXTitleAttribute)
        let desc = axString(of: element, attribute: kAXDescriptionAttribute)
        let roleDesc = axString(of: element, attribute: kAXRoleDescriptionAttribute)

        // Get value, but skip secure text fields
        let value: String
        if role == "AXSecureTextField" {
            value = ""
        } else {
            value = axString(of: element, attribute: kAXValueAttribute)
        }

        // Recurse into children up to max depth
        var childNodes: [AXNode] = []
        if depth < kMaxTreeDepth {
            if let children = axValue(of: element, attribute: kAXChildrenAttribute) as? [AXUIElement] {
                childNodes = children.map { buildNode(element: $0, depth: depth + 1) }
            }
        }

        return AXNode(
            role: role,
            subrole: subrole,
            title: title,
            description: desc,
            value: value,
            roleDescription: roleDesc,
            children: childNodes
        )
    }

    // MARK: - Browser URL Extraction

    private func extractBrowserURL(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)

        guard let window = axValue(of: appElement, attribute: kAXFocusedWindowAttribute) as! AXUIElement? else {
            return nil
        }

        return findURLInChildren(of: window, depth: 0, maxDepth: 6)
    }

    private func findURLInChildren(of element: AXUIElement, depth: Int, maxDepth: Int) -> String? {
        guard depth < maxDepth else { return nil }

        let role = axString(of: element, attribute: kAXRoleAttribute)

        if role == "AXTextField" || role == "AXComboBox" {
            let value = axString(of: element, attribute: kAXValueAttribute)
            if looksLikeURL(value) {
                return value
            }
        }

        guard let children = axValue(of: element, attribute: kAXChildrenAttribute) as? [AXUIElement] else {
            return nil
        }

        for child in children {
            if let url = findURLInChildren(of: child, depth: depth + 1, maxDepth: maxDepth) {
                return url
            }
        }

        return nil
    }

    private func looksLikeURL(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.hasPrefix("http://") || value.hasPrefix("https://") ||
               value.contains(".com") || value.contains(".org") || value.contains(".io") ||
               value.contains(".dev") || value.contains(".net") || value.contains("localhost")
    }

    // MARK: - AX Helpers

    private func axValue(of element: AXUIElement, attribute: String) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return result == .success ? value : nil
    }

    private func axString(of element: AXUIElement, attribute: String) -> String {
        guard let value = axValue(of: element, attribute: attribute) else { return "" }
        if let str = value as? String { return str }
        if let url = value as? URL { return url.absoluteString }
        if CFGetTypeID(value) == CFURLGetTypeID() {
            return (value as! CFURL as URL).absoluteString
        }
        return ""
    }
}
