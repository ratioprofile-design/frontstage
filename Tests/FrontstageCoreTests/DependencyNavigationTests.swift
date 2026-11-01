import Foundation
import XCTest
@testable import FrontstageCore

final class DependencyNavigationTests: XCTestCase {
    func testRoutePicksCurveAtMultipleZoomsAndRejectsBackground() {
        for end in [BoardRect(x: 600, y: 380, width: 140, height: 80), BoardRect(x: 30, y: 450, width: 100, height: 40)] {
            let route = BoardDependencyRoute(cause: .init(x: 100, y: 80, width: 150, height: 40), effect: end)
            for zoom in [0.15, 1.0, 3.0] {
                for t in [0.0, 0.1, 0.5, 0.9, 1.0] { XCTAssertTrue(route.contains(route.point(at: t), tolerance: 6 / zoom)) }
                XCTAssertFalse(route.contains(.init(x: 1000, y: 1000), tolerance: 6 / zoom))
            }
            XCTAssertFalse(route.contains(.init(x: .nan, y: 0), tolerance: 6))
        }
    }
    func testConnectionChangesPreserveTextAndRollbackLocksAndCycles() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/write-panels.frontstage")
        var project = try Project(data: Data(contentsOf: url))
        try project.editWhiteboard { $0.dependencies = [.init(id: "forward", cause: "beat-1", effect: "beat-2"), .init(id: "back", cause: "beat-2", effect: "beat-1", reference: true)] }
        let scenes = project.scenes
        try project.editBoardDependency("forward", reason: "Because they met")
        XCTAssertEqual(try project.whiteboard().dependencies[0].reason, "Because they met")
        XCTAssertEqual(project.scenes, scenes)
        let before = project
        XCTAssertThrowsError(try project.editBoardDependency("back", reference: false)); XCTAssertEqual(project, before)
        try project.editWhiteboard { $0.beats[1].locked = true }
        let locked = project
        XCTAssertThrowsError(try project.editBoardDependency("forward", remove: true)); XCTAssertEqual(project, locked)
        XCTAssertThrowsError(try project.editBoardDependency("forward", reason: "Changed")); XCTAssertEqual(project, locked)
        try project.editWhiteboard { $0.beats[1].locked = false }
        try project.editBoardDependency("forward", remove: true)
        XCTAssertEqual(try project.whiteboard().dependencies.map(\.id), ["back"])
        XCTAssertEqual(project.scenes, scenes)
    }
}
