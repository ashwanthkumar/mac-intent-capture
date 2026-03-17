import Foundation

struct ActivityRecord: Identifiable {
    let id: Int64?
    let timestamp: Date
    let appName: String
    let bundleId: String
    let windowTitle: String
    let focusedRole: String
    let focusedTitle: String
    let focusedValue: String
    let selectedText: String
    let documentPath: String
    let url: String
    let windowHierarchy: String  // JSON dump of the full AX tree
}

struct WindowContext {
    var windowTitle: String = ""
    var focusedRole: String = ""
    var focusedTitle: String = ""
    var focusedValue: String = ""
    var selectedText: String = ""
    var documentPath: String = ""
    var url: String = ""
    var windowHierarchy: String = ""
}

/// Represents a single node in the AX element tree.
struct AXNode: Codable {
    let role: String
    let subrole: String
    let title: String
    let description: String
    let value: String
    let roleDescription: String
    let children: [AXNode]
}
