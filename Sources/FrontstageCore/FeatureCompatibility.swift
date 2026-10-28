import Foundation

extension Project {
    public static let supportedWriteFeatures: Set<String> = ["elementTypography", "productionBaselines", "dualDialogue", "scriptAnnotations"]
    public var requiredWriteFeatures: Set<String> {
        var result = Set<String>()
        if state["frontstageScriptLayout"]?.object?["elements"]?.object?.isEmpty == false || state["frontstageScriptLayout"]?.object?["frontstageInactiveElementTypography"]?.object?.isEmpty == false { result.insert("elementTypography") }
        if state["productionRevision"]?.object != nil || state["productionRevisionHistory"]?.array?.isEmpty == false { result.insert("productionBaselines") }
        let boardHTML = (state["frontstageWhiteboard"]?.object?["beats"]?.array ?? []).compactMap { $0.object?["html"]?.string }
        let archivedHTML = (state["frontstagePullouts"]?.array ?? []).compactMap { $0.object?["beat"]?.object?["html"]?.string }
        if (archivedHTML + boardHTML).contains(where: { $0.contains("sc-dual-") || $0.contains("data-dual-pair") }) || scenes.contains(where: { $0.html.contains("sc-dual-") || $0.html.contains("data-dual-pair") }) { result.insert("dualDialogue") }
        if (archivedHTML + boardHTML + scenes.map(\.html)).contains(where: { $0.contains("data-dot-") }) || (state["beats"]?.array ?? []).contains(where: { $0.object?["frontstageHeadingMarkup"]?.string?.contains("data-dot-") == true }) { result.insert("scriptAnnotations") }
        return result
    }
    public func validateWriterCompatibility(previous: Project, supported: Set<String>) throws {
        let required = requiredWriteFeatures.union(previous.requiredWriteFeatures)
        guard required.isSubset(of: supported) else {
            throw ProjectError.invalidProject("Update DOT before editing this shared project; this client cannot preserve: \(required.subtracting(supported).sorted().joined(separator: ", "))")
        }
        try scriptLayout.validate()
    }
}
