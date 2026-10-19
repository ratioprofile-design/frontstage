#if os(macOS)
import XCTest
@testable import FrontstageApp

final class CharacterDiscoveryTests: XCTestCase {
    func testDiscoveryUsesCharacterElementsAssignsScenesAndIsUndoable() async throws {
        await MainActor.run {
            let workspace = Workspace()
            workspace.addScene()
            let id = workspace.selectedSceneID!
            workspace.updateScene(id: id, html: "<div class='sc-character'>RANGA (V.O.)</div><div class='sc-dialogue'>Do not make me a role</div><div class='sc-character'>RANGA</div>")
            workspace.discoverCharacters()
            XCTAssertEqual(workspace.project.characters.map(\.name), ["RANGA"])
            XCTAssertEqual(workspace.project.sceneCharacters(id), ["RANGA"])
            workspace.undoProject()
            XCTAssertTrue(workspace.project.characters.isEmpty)
            XCTAssertTrue(workspace.project.sceneCharacters(id).isEmpty)
        }
    }
}
#endif
