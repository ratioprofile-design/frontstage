#if os(macOS)
import AppKit
import SwiftUI

@MainActor
struct TimelineWheelZoom: NSViewRepresentable {
    @Binding var scale: Double
    func makeNSView(context: Context) -> TimelineWheelView { TimelineWheelView() }
    func updateNSView(_ view: TimelineWheelView, context: Context) { view.zoomScale = scale; view.changed = { scale = $0 } }
    static func dismantleNSView(_ view: TimelineWheelView, coordinator: ()) { view.stop() }
}

@MainActor
final class TimelineWheelView: NSView {
    var zoomScale = 60.0
    var changed: (Double) -> Void = { _ in }
    private var monitor: Any?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); stop()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
    }
    func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    private func handle(_ event: NSEvent) -> Bool {
        guard event.window === window, !event.modifierFlags.contains(.shift), abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX), event.scrollingDeltaY != 0 else { return false }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point), point.y > 42 else { return false }
        var hit = window?.contentView.flatMap { content in content.hitTest(content.convert(event.locationInWindow, from: nil)) }
        while hit != nil && !(hit is NSScrollView) { hit = hit?.superview }
        let scroll = hit as? NSScrollView
        let local = scroll.map { $0.contentView.convert(event.locationInWindow, from: nil).x - $0.contentView.bounds.minX } ?? point.x
        applyZoom(deltaY: event.scrollingDeltaY, localX: local, scroll: scroll)
        return true
    }
    func applyZoom(deltaY: CGFloat, localX: CGFloat, scroll: NSScrollView?) {
        guard deltaY.isFinite, localX.isFinite else { return }
        let previous = zoomScale, value = max(2, min(180, previous * exp(Double(deltaY) * 0.012)))
        guard value != previous else { return }
        let x = max(174, localX), offset = scroll?.contentView.bounds.origin ?? .zero
        let anchor = max(0, (offset.x + x - 174) / previous)
        zoomScale = value; changed(value)
        DispatchQueue.main.async { [weak scroll] in
            guard let scroll else { return }
            scroll.layoutSubtreeIfNeeded()
            let limit = max(0, (scroll.documentView?.bounds.width ?? 0) - scroll.contentView.bounds.width)
            scroll.contentView.scroll(to: NSPoint(x: min(limit, max(0, 174 + anchor * value - x)), y: offset.y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}
#endif
