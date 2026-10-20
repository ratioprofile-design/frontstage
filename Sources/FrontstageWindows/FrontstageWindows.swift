#if os(Windows)
import Foundation
import WinSDK
import FrontstageCore

private nonisolated(unsafe) var state = WindowsWorkspace()

private func wide<T>(_ string: String, _ action: (UnsafePointer<WCHAR>) -> T) -> T {
    (Array(string.utf16) + [0]).withUnsafeBufferPointer { action($0.baseAddress!) }
}
private func color(_ hex: String) -> COLORREF {
    let n = UInt32(hex.hasPrefix("#") ? String(hex.dropFirst()) : hex, radix: 16) ?? 0x777777
    return ((n >> 16) & 255) | (n & 0xff00) | ((n & 255) << 16)
}
private func text(_ window: HWND?) -> String {
    let count = Int(GetWindowTextLengthW(window))
    var buffer = [WCHAR](repeating: 0, count: count + 1)
    _ = buffer.withUnsafeMutableBufferPointer { GetWindowTextW(window, $0.baseAddress, Int32($0.count)) }
    return String(decoding: buffer.prefix(count), as: UTF16.self)
}
private func htmlText(_ html: String) -> String {
    html.replacingOccurrences(of: "(?i)<br\\s*/?>|</(?:div|p)>", with: "\n", options: .regularExpression)
        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&")
        .trimmingCharacters(in: .newlines)
}

private final class WindowsWorkspace {
    var project = Project()
    var checkpoint = Project()
    var history = ProjectHistory()
    var window: HWND?
    var popup: HWND?
    var titleField: HWND?
    var bodyField: HWND?
    var popupBeat: String?
    var originalPopupText = ""
    var loadingPopup = false
    var selected: String?
    var pendingCause: String?
    var saveURL: URL?
    var status = "Double-click a beat to open its popup editor."
    var dragBlock: String?
    var dragStart = BoardPoint()
    var dragDelta = BoardPoint()
    var board: Whiteboard { (try? project.whiteboard()) ?? Whiteboard() }
    var geometry: WhiteboardLayout { WhiteboardLayout(board) }
    var zoom: Double { board.viewport.zoom }

    func edit(_ label: String, key: String? = nil, _ action: (inout Project) throws -> Void) {
        let old = project
        do { try action(&project); if project != old { history.record(old, label: label, key: key) }; status = project == checkpoint ? "Saved" : "Unsaved project changes" }
        catch { project = old; message(error.localizedDescription) }
        InvalidateRect(window, nil, false)
    }
    func message(_ value: String) { wide(value) { value in wide("Frontstage") { title in _ = MessageBoxW(window, value, title, UINT(MB_OK | MB_ICONINFORMATION)) } } }
    func world(_ x: Int, _ y: Int) -> BoardPoint { BoardPoint(x: Double(x) / zoom + board.viewport.origin.x, y: Double(y - 44) / zoom + board.viewport.origin.y) }
    func frame(_ rect: BoardRect) -> RECT {
        RECT(left: LONG((rect.x - board.viewport.origin.x) * zoom), top: LONG((rect.y - board.viewport.origin.y) * zoom + 44),
             right: LONG((rect.maxX - board.viewport.origin.x) * zoom), bottom: LONG((rect.maxY - board.viewport.origin.y) * zoom + 44))
    }
    func addBeat(newBlock: Bool) {
        let owner = newBlock ? nil : board.beats.first { $0.id == selected }
        var id: String?
        let position = BoardPoint(x: max(20, board.viewport.origin.x + 50), y: max(45, board.viewport.origin.y + 65))
        edit("Add Beat") { id = try $0.addBoardBeat(blockID: owner?.blockID, position: position) }
        if let id { selected = id; openPopup(id) }
    }
    func openPopup(_ id: String) {
        guard let beat = board.beats.first(where: { $0.id == id }) else { return }
        if let popup, popupBeat == id { ShowWindow(popup, SW_SHOW); SetForegroundWindow(popup); return }
        if let popup { DestroyWindow(popup) }
        popupBeat = id; originalPopupText = htmlText(beat.html); loadingPopup = true
        popup = wide("FrontstageWindow") { className in wide("Edit Beat") { title in
            CreateWindowExW(DWORD(WS_EX_TOOLWINDOW), className, title, DWORD(WS_OVERLAPPEDWINDOW) | DWORD(WS_VISIBLE), 180, 160, 610, 530, window, nil, GetModuleHandleW(nil), UnsafeMutableRawPointer(bitPattern: 1))
        } }
        loadingPopup = false
    }
    func popupChanged() {
        guard !loadingPopup, let id = popupBeat, let titleField, let bodyField else { return }
        let title = text(titleField), body = text(bodyField), original = originalPopupText
        edit("Edit Beat", key: "popup-\(id)") { project in
            try project.updateBoardBeat(id) { beat in
                beat.title = title
                if body != original { beat.html = body.components(separatedBy: .newlines).map { "<div class=\"sc-line sc-action\">\(OfficeArchive.xml($0))</div>" }.joined() }
            }
        }
    }
    func chooseFile(save: Bool) -> URL? {
        var result: String?
        var buffer = [WCHAR](repeating: 0, count: 32768)
        let filter = "Frontstage Projects\0*.frontstage;*.backstage;*.json\0All Files\0*.*\0\0"
        wide(filter) { filter in wide("frontstage") { ext in buffer.withUnsafeMutableBufferPointer { file in
            var options = OPENFILENAMEW(); options.lStructSize = DWORD(MemoryLayout<OPENFILENAMEW>.size)
            options.hwndOwner = window; options.lpstrFilter = filter; options.lpstrFile = file.baseAddress; options.nMaxFile = DWORD(file.count)
            options.lpstrDefExt = ext; options.Flags = DWORD(OFN_EXPLORER | OFN_PATHMUSTEXIST | (save ? OFN_OVERWRITEPROMPT : OFN_FILEMUSTEXIST))
            if (save ? GetSaveFileNameW(&options) : GetOpenFileNameW(&options)) {
                result = String(decoding: file.prefix { $0 != 0 }, as: UTF16.self)
            }
        } } }
        return result.map { URL(fileURLWithPath: $0) }
    }
    @discardableResult func save() -> Bool {
        guard let url = saveURL ?? chooseFile(save: true) else { return false }
        do { try project.save(to: url); saveURL = url; checkpoint = project; status = "Saved \(url.lastPathComponent)"; InvalidateRect(window, nil, false); return true }
        catch { message(error.localizedDescription); return false }
    }
    func confirmReplace() -> Bool {
        if project == checkpoint { return true }
        let answer = wide("Save changes before replacing this project?") { value in wide("Frontstage") { title in MessageBoxW(window, value, title, UINT(MB_YESNOCANCEL | MB_ICONQUESTION)) } }
        if answer == IDYES { return save() }; return answer == IDNO
    }
    func action(_ id: Int) {
        switch id {
        case 1:
            guard confirmReplace() else { return }; if let popup { DestroyWindow(popup) }
            project = Project(); checkpoint = project; history = ProjectHistory(); saveURL = nil; selected = nil
        case 2:
            guard confirmReplace(), let url = chooseFile(save: false) else { return }
            do { let loaded = try Project.load(from: url); _ = try loaded.whiteboard(); if let popup { DestroyWindow(popup) }; project = loaded; checkpoint = Project(); history = ProjectHistory(); saveURL = nil; selected = board.orderedBeats.first?.id; status = "Imported copy; choose a new save destination" }
            catch { message(error.localizedDescription) }
        case 3: _ = save()
        case 4: addBeat(newBlock: true)
        case 5: addBeat(newBlock: false)
        case 6: pendingCause = selected; status = "Click the effect beat to create a dependency."
        case 7: edit("Resolve Causes") { try $0.editWhiteboard { try $0.resolveCauses() } }
        case 8: if let old = history.undo(current: project) { project = old; refreshPopup() }
        case 9: if let next = history.redo(current: project) { project = next; refreshPopup() }
        case 10: if let id = selected { openPopup(id) }
        case 11: if let id = selected { edit("Delete Beat") { try $0.removeBoardBeats([id]) }; selected = nil }
        case 12: if let id = selected { edit("Cause Requirement") { try $0.updateBoardBeat(id) { $0.mustBeCaused.toggle() } } }
        default: break
        }
        InvalidateRect(window, nil, false)
    }
    func refreshPopup() { if let id = popupBeat { if let popup { DestroyWindow(popup) }; openPopup(id) } }

    func paint(_ dc: HDC?, client: RECT) {
        var background = client
        let gray = CreateSolidBrush(color("#797a7d")); FillRect(dc, &background, gray); DeleteObject(gray)
        let white = color("#ffffff"); SetBkMode(dc, TRANSPARENT)
        _ = SelectObject(dc, GetStockObject(DEFAULT_GUI_FONT))
        func fill(_ rect: RECT, hex: String) { var r = rect; let brush = CreateSolidBrush(color(hex)); FillRect(dc, &r, brush); DeleteObject(brush) }
        func draw(_ value: String, _ rect: RECT, foreground: COLORREF = color("#ffffff")) { var r = rect; SetTextColor(dc, foreground); wide(value) { _ = DrawTextW(dc, $0, -1, &r, UINT(DT_LEFT | DT_WORDBREAK | DT_NOPREFIX)) } }
        let board = self.board, geometry = self.geometry
        let visible = BoardRect(x: board.viewport.origin.x, y: board.viewport.origin.y, width: Double(client.right) / zoom, height: Double(client.bottom - 44) / zoom)
        for (index, layer) in board.layers.enumerated() {
            if let rect = geometry.layerRects[layer.id], rect.intersects(visible) {
                fill(frame(BoardRect(x: visible.x, y: rect.y, width: visible.width, height: rect.height)), hex: index % 2 == 0 ? "#7d7e80" : "#747577")
                draw("▾ \(layer.name)", frame(BoardRect(x: visible.x + 5, y: rect.y + 10, width: 100, height: 20)))
            }
        }
        for edge in board.dependencies {
            guard let a = geometry.beatRects[edge.cause], let b = geometry.beatRects[edge.effect] else { continue }
            let start = frame(a), end = frame(b), middle = max(35, abs(end.left - start.right) / 2)
            let pen = CreatePen(PS_SOLID, 1, color(selected == edge.cause || selected == edge.effect ? "#8ee6ee" : "#d1d1d3"))
            let previous = SelectObject(dc, pen)
            let sy = (start.top + start.bottom) / 2, ey = (end.top + end.bottom) / 2
            let points = [POINT(x: start.right, y: sy), POINT(x: start.right + middle, y: sy), POINT(x: end.left - middle, y: ey), POINT(x: end.left, y: ey)]
            _ = points.withUnsafeBufferPointer { PolyBezier(dc, $0.baseAddress, DWORD($0.count)) }
            _ = SelectObject(dc, previous); DeleteObject(pen)
        }
        for block in board.blocks {
            guard var rect = geometry.blockRects[block.id], rect.intersects(visible) else { continue }
            if dragBlock == block.id { rect.x += dragDelta.x; rect.y += dragDelta.y }
            fill(frame(rect), hex: "#9e9ea1")
            fill(frame(BoardRect(x: rect.x + 12, y: rect.y - 18, width: min(rect.width - 24, 180), height: 21)), hex: "#56575b")
            draw(block.name, frame(BoardRect(x: rect.x + 17, y: rect.y - 15, width: rect.width - 25, height: 18)))
        }
        let issues = Set(board.issues.flatMap(\.beatIDs)), byID = Dictionary(uniqueKeysWithValues: board.beats.map { ($0.id, $0) })
        for id in geometry.beats(in: visible) {
            guard let beat = byID[id], var rect = geometry.beatRects[id] else { continue }
            if dragBlock == beat.blockID { rect.x += dragDelta.x; rect.y += dragDelta.y }
            let r = frame(rect); fill(r, hex: beat.color)
            if selected == id { var edge = r; let brush = CreateSolidBrush(white); FrameRect(dc, &edge, brush); DeleteObject(brush) }
            draw(beat.title, frame(BoardRect(x: rect.x + 6, y: rect.y + 4, width: rect.width - 12, height: rect.height - 6)))
            if issues.contains(id) { fill(frame(BoardRect(x: rect.maxX - 12, y: rect.y - 5, width: 16, height: 16)), hex: "#cb2742"); draw("!", frame(BoardRect(x: rect.maxX - 8, y: rect.y - 4, width: 10, height: 16))) }
        }
        fill(RECT(left: 0, top: client.bottom - 26, right: client.right, bottom: client.bottom), hex: "#38393b")
        draw("\(status) · \(board.beats.count) beats · \(Int(zoom * 100))% · Ctrl+wheel zooms", RECT(left: 8, top: client.bottom - 22, right: client.right - 8, bottom: client.bottom))
    }
}

private func control(_ parent: HWND?, className: String, title: String, id: Int, x: Int32, y: Int32, width: Int32, height: Int32, style: DWORD = 0) -> HWND? {
    wide(className) { cls in wide(title) { name in
        CreateWindowExW(0, cls, name, DWORD(WS_CHILD | WS_VISIBLE) | style, x, y, width, height, parent, HMENU(bitPattern: id), GetModuleHandleW(nil), nil)
    } }
}

private func procedure(_ hwnd: HWND?, _ message: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {
    if message == UINT(WM_NCCREATE), let creation = UnsafePointer<CREATESTRUCTW>(bitPattern: Int(truncatingIfNeeded: lParam)) {
        _ = SetWindowLongPtrW(hwnd, GWLP_USERDATA, creation.pointee.lpCreateParams == UnsafeMutableRawPointer(bitPattern: 1) ? 1 : 0)
    }
    let popup = GetWindowLongPtrW(hwnd, GWLP_USERDATA) == 1
    switch message {
    case UINT(WM_CREATE):
        if popup {
            let beat = state.board.beats.first { $0.id == state.popupBeat }
            state.titleField = control(hwnd, className: "EDIT", title: beat?.title ?? "", id: 101, x: 12, y: 12, width: 560, height: 28, style: DWORD(WS_BORDER | ES_AUTOHSCROLL))
            _ = control(hwnd, className: "STATIC", title: "Snippet text (plain-text editing; original HTML is preserved until changed)", id: 0, x: 12, y: 48, width: 560, height: 22)
            state.bodyField = control(hwnd, className: "EDIT", title: htmlText(beat?.html ?? ""), id: 102, x: 12, y: 76, width: 560, height: 340, style: DWORD(WS_BORDER | WS_VSCROLL | ES_MULTILINE | ES_AUTOVSCROLL))
            _ = control(hwnd, className: "BUTTON", title: "Done", id: 103, x: 490, y: 430, width: 80, height: 28)
        } else {
            state.window = hwnd
            for (index, title) in ["New", "Open…", "Save…", "+ Block", "+ Beat", "Cause →", "Resolve", "Undo", "Redo"].enumerated() {
                _ = control(hwnd, className: "BUTTON", title: title, id: index + 1, x: Int32(6 + index * 78), y: 6, width: 72, height: 28)
            }
        }
        return 0
    case UINT(WM_COMMAND):
        let id = Int(wParam & 0xffff), notification = Int((wParam >> 16) & 0xffff)
        if popup {
            if id == 103 { DestroyWindow(hwnd); return 0 }
            if (id == 101 || id == 102) && notification == Int(EN_CHANGE) { state.popupChanged(); return 0 }
        } else { state.action(id); return 0 }
    case UINT(WM_PAINT):
        if !popup { var paint = PAINTSTRUCT(), client = RECT(); let dc = BeginPaint(hwnd, &paint); GetClientRect(hwnd, &client); state.paint(dc, client: client); EndPaint(hwnd, &paint); return 0 }
    case UINT(WM_LBUTTONDOWN):
        if !popup {
            let point = state.world(Int(Int16(truncatingIfNeeded: lParam)), Int(Int16(truncatingIfNeeded: lParam >> 16)))
            if let beat = state.geometry.hitBeat(point) {
                if let cause = state.pendingCause, cause != beat { state.edit("Create Dependency") { try $0.connectBoardBeats(cause: cause, effect: beat) }; state.pendingCause = nil }
                state.selected = beat
            } else if let block = state.geometry.blockRects.filter({ $0.value.contains(point) || BoardRect(x: $0.value.x, y: $0.value.y - 18, width: $0.value.width, height: 20).contains(point) }).min(by: { $0.value.width * $0.value.height < $1.value.width * $1.value.height }) {
                state.dragBlock = block.key; state.dragStart = point; state.dragDelta = .init(); SetCapture(hwnd)
            }
            InvalidateRect(hwnd, nil, false); return 0
        }
    case UINT(WM_MOUSEMOVE):
        if !popup && state.dragBlock != nil { let point = state.world(Int(Int16(truncatingIfNeeded: lParam)), Int(Int16(truncatingIfNeeded: lParam >> 16))); state.dragDelta = BoardPoint(x: point.x - state.dragStart.x, y: point.y - state.dragStart.y); InvalidateRect(hwnd, nil, false); return 0 }
    case UINT(WM_LBUTTONUP):
        if let block = state.dragBlock, !popup { let delta = state.dragDelta; state.dragBlock = nil; ReleaseCapture(); state.edit("Move Block") { try $0.moveBoardBlocks([block], delta: delta) }; return 0 }
    case UINT(WM_LBUTTONDBLCLK):
        if !popup, let id = state.selected { state.openPopup(id); return 0 }
    case UINT(WM_MOUSEWHEEL):
        if !popup {
            let amount = Double(Int16(truncatingIfNeeded: wParam >> 16))
            let zooming = GetKeyState(Int32(VK_CONTROL)) < 0
            state.edit("Whiteboard View", key: "viewport") { try $0.editWhiteboard { board in
                if zooming { board.viewport.zoom = max(0.15, min(3, board.viewport.zoom * (amount > 0 ? 1.15 : 0.87))) }
                else { board.viewport.origin.y = max(-1000, board.viewport.origin.y - amount / board.viewport.zoom) }
            } }; return 0
        }
    case UINT(WM_RBUTTONUP):
        if !popup {
            let menu = CreatePopupMenu()
            for (name, id) in [("Edit Beat…", 10), ("Create Dependency From", 6), ("Must Be Caused", 12), ("Delete Beat", 11)] { wide(name) { _ = AppendMenuW(menu, UINT(MF_STRING), UINT_PTR(id), $0) } }
            var point = POINT(); GetCursorPos(&point); TrackPopupMenu(menu, UINT(TPM_RIGHTBUTTON), point.x, point.y, 0, hwnd, nil); DestroyMenu(menu); return 0
        }
    case UINT(WM_KEYDOWN):
        if !popup && wParam == WPARAM(VK_RETURN), let id = state.selected { state.openPopup(id); return 0 }
        if !popup && wParam == WPARAM(VK_DELETE) { state.action(11); return 0 }
        if popup && wParam == WPARAM(VK_ESCAPE) { DestroyWindow(hwnd); return 0 }
    case UINT(WM_CLOSE):
        if !popup && !state.confirmReplace() { return 0 }; DestroyWindow(hwnd); return 0
    case UINT(WM_DESTROY):
        if popup { state.popup = nil; state.popupBeat = nil; state.titleField = nil; state.bodyField = nil }
        else { PostQuitMessage(0) }; return 0
    default: break
    }
    return DefWindowProcW(hwnd, message, wParam, lParam)
}

@main
struct FrontstageWindows {
    static func main() {
        if CommandLine.arguments.count > 2 && CommandLine.arguments[1] == "--verify" {
            do { let project = try Project.load(from: URL(fileURLWithPath: CommandLine.arguments[2])); let board = try project.whiteboard(); print("Verified \(board.beats.count) beats and \(board.dependencies.count) dependencies"); return }
            catch { FileHandle.standardError.write(Data("Project verification failed\n".utf8)); exit(1) }
        }
        _ = SetProcessDPIAware()
        let instance = GetModuleHandleW(nil)
        let hwnd = wide("FrontstageWindow") { name -> HWND? in
            var cls = WNDCLASSEXW(); cls.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
            cls.style = UINT(CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS); cls.lpfnWndProc = procedure; cls.hInstance = instance
            cls.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512)); cls.lpszClassName = name
            guard RegisterClassExW(&cls) != 0 else { return nil }
            return wide("Frontstage — Whiteboard") { title in CreateWindowExW(0, name, title, DWORD(WS_OVERLAPPEDWINDOW) | DWORD(WS_VISIBLE), 80, 80, 1280, 850, nil, nil, instance, nil) }
        }
        guard let hwnd else { return }
        ShowWindow(hwnd, SW_SHOW); UpdateWindow(hwnd)
        var message = MSG()
        while GetMessageW(&message, nil, 0, 0) { TranslateMessage(&message); DispatchMessageW(&message) }
    }
}
#else
import Foundation
@main struct FrontstageWindows {
    static func main() { print("FrontstageWindows requires Windows and the Swift Windows SDK.") }
}
#endif
