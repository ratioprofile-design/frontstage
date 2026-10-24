import Foundation
import XCTest
@testable import FrontstageCore

final class WorkspaceParityTests: XCTestCase {
    func testBrowserTimelineSettingsRoundTrip() throws {
        guard let path = ProcessInfo.processInfo.environment["FRONTSTAGE_PARITY_DOCUMENT"] else { throw XCTSkip("Run browser parity first") }
        let file = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("timeline-edited.frontstage")
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("Timeline fixture is unavailable") }
        let project = try Project(data: Data(contentsOf: file))
        XCTAssertEqual(project.timelineMinutesPerPage, 2)
        XCTAssertTrue(project.storyMilestones.contains { $0.kind == .episode })
        XCTAssertEqual(try Project(data: project.encoded()), project)
    }

    func testBrowserEditedDocumentRetainsAllWorkspaceChanges() throws {
        guard let path = ProcessInfo.processInfo.environment["FRONTSTAGE_PARITY_DOCUMENT"] else {
            throw XCTSkip("Run the browser parity test first and set FRONTSTAGE_PARITY_DOCUMENT")
        }
        let project = try Project(data: Data(contentsOf: URL(fileURLWithPath: path)))
        let role = try XCTUnwrap(project.characters.first { $0.name == "LENA" })
        XCTAssertEqual(role.artists.first?.email, "leela@example.test")
        XCTAssertEqual(role.confirmedArtistID, role.artists.first?.id)
        XCTAssertTrue(project.breakdownItems(for: 1).contains { $0.name == "Lantern" && $0.count == 3 })
        XCTAssertTrue(project.revisions(for: 1).contains { $0.label == "Browser revision" })
        XCTAssertTrue(project.scenes.first?.html.contains("Browser screenplay text.") == true)
        XCTAssertEqual(project.scriptLayout.fontSize, 14)
        XCTAssertEqual(project.parallelScript(sceneID: 1).last?.right, "வணக்கம்")
        XCTAssertTrue(try project.studio().records.contains { $0.title == "Browser research" })
        XCTAssertTrue(try project.studio().assets.contains { $0.data == Data("Portable attachment".utf8) })
        let hierarchyURL = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("hierarchy-edited.frontstage")
        if FileManager.default.fileExists(atPath: hierarchyURL.path) {
            let hierarchy = try Project(data: Data(contentsOf: hierarchyURL))
            let board = try hierarchy.whiteboard(), group = try XCTUnwrap(board.blocks.first { $0.containerKind == "beatGroup" })
            XCTAssertNotNil(group.parentID)
            XCTAssertEqual(board.beats.filter { $0.blockID == group.id }.count, 2)
            XCTAssertEqual(try Project(data: hierarchy.encoded()), hierarchy)
        }
        XCTAssertEqual(project.productionDays.last?.fields["locationName"], "Old Station")
        XCTAssertEqual(project.productionDays.last?.castCalls["LENA"]?["onSetTime"], "08:00")
        XCTAssertEqual(try Project(data: project.encoded()), project)
    }
    func testBrowserWorkspaceFixtureOpensNativelyWithoutLosingReferences() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/workspace-parity.frontstage")
        let project = try Project(data: Data(contentsOf: url))
        XCTAssertEqual(project.name, "The Invitation")
        XCTAssertEqual(project.characters.first?.name, "MAYA")
        XCTAssertEqual(project.characters.first?.artists.first?.email, "anika@example.test")
        XCTAssertEqual(project.characters.first?.confirmedArtistID, project.characters.first?.artists.first?.id)
        XCTAssertEqual(project.breakdownItems(for: 1).first?.name, "Invitation")
        XCTAssertEqual(project.breakdownItems(for: 1).first?.count, 2)
        XCTAssertEqual(project.revisions(for: 1).first?.label, "Before the reply")
        XCTAssertEqual(project.productionDays.first?.sceneIDs, [1, 2])
        XCTAssertEqual(project.productionDays.first?.castCalls["MAYA"]?["onSetTime"], "07:00")
        XCTAssertEqual(try project.studio().records.first?.title, "Station reference")
        XCTAssertEqual(try project.studio().assets.first?.data, Data("Reference text".utf8))
        XCTAssertEqual(project.parallelScript(sceneID: 1).first?.right, "அழைப்பு")
        XCTAssertEqual(project.scriptLayout.fontSize, 12)
        XCTAssertEqual(try project.orderedScript().map(\.scene.id), [1, 2])
        XCTAssertTrue(try project.orderedScript()[0].scene.html.contains("தமிழ்"))
        XCTAssertEqual(try Project(data: project.encoded()), project)
        var restored = project
        try restored.restoreRevision(sceneID: 1, revisionID: try XCTUnwrap(project.revisions(for: 1).first?.id))
        XCTAssertEqual(try restored.orderedScript()[0].scene.html, try project.orderedScript()[0].scene.html)
        XCTAssertEqual(restored.revisions(for: 1).count, 2)
    }
}
