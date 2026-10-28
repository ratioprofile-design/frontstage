import Foundation

public enum BoardDrawing {
    private static func distance(_ p: BoardPoint, _ a: BoardPoint, _ b: BoardPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy
        let t = length == 0 ? 0 : min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length))
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }
    private static func intersects(_ a: BoardPoint, _ b: BoardPoint, _ c: BoardPoint, _ d: BoardPoint) -> Bool {
        func cross(_ p: BoardPoint, _ q: BoardPoint, _ r: BoardPoint) -> Double { (q.x-p.x)*(r.y-p.y)-(q.y-p.y)*(r.x-p.x) }
        return max(min(a.x,b.x),min(c.x,d.x)) <= min(max(a.x,b.x),max(c.x,d.x)) && max(min(a.y,b.y),min(c.y,d.y)) <= min(max(a.y,b.y),max(c.y,d.y)) && cross(a,b,c)*cross(a,b,d) <= 0 && cross(c,d,a)*cross(c,d,b) <= 0
    }
    public static func hits(_ stroke: BoardStroke, path: [BoardPoint], radius: Double) -> Bool {
        guard !stroke.points.isEmpty, !path.isEmpty, radius.isFinite, radius >= 0 else { return false }
        let limit = radius + stroke.width / 2
        let ink = stroke.points.count == 1 ? [(stroke.points[0],stroke.points[0])] : Array(zip(stroke.points,stroke.points.dropFirst()))
        let eraser = path.count == 1 ? [(path[0],path[0])] : Array(zip(path,path.dropFirst()))
        return ink.contains { a,b in eraser.contains { c,d in intersects(a,b,c,d) || min(distance(a,c,d),distance(b,c,d),distance(c,a,b),distance(d,a,b)) <= limit } }
    }
}
extension Project {
    public mutating func eraseBoardDrawing(path: [BoardPoint], radius: Double = 8) throws {
        guard radius.isFinite, radius > 0, path.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { throw ProjectError.invalidProject("Invalid eraser path") }
        try editWhiteboard { board in board.strokes.removeAll { BoardDrawing.hits($0, path: path, radius: radius) } }
    }
}
