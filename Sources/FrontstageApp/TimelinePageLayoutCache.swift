#if os(macOS)
import FrontstageCore

struct TimelinePageLayoutInput: Equatable {
    var segments: [ScriptSegment]
    var settings: ScriptLayoutSettings
    var paper: ScreenplayPaper
    var revised: [Bool]
    init(project: Project, paper: ScreenplayPaper) {
        segments = (try? project.orderedScript()) ?? []
        settings = project.scriptLayout; self.paper = paper
        revised = segments.map { project.productionSceneChanged($0.scene.id) }
    }
}
@MainActor
final class TimelinePageLayoutCache {
    private var input: TimelinePageLayoutInput?
    private var measured: [String: Double]?
    func pages(project: Project, paper: ScreenplayPaper) throws -> [String: Double]? {
        let next = TimelinePageLayoutInput(project: project, paper: paper)
        if input == next { return measured }
        let result = try ScreenplayPDF.timelinePageCounts(project: project, paper: paper)
        input = next; measured = result; return result
    }
}
#endif
