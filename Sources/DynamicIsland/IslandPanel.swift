import AppKit
import SwiftUI

/// Borderless, non-activating floating panel. Never steals focus from the app you're using.
/// Dragging is handled here manually so it can be locked reliably and so clicks still reach SwiftUI.
final class IslandPanel: NSPanel {
    var isDragAllowed: () -> Bool = { false }
    /// Receives the mouse position (screen coordinates) at mouse-down; lets the controller restrict
    /// where a drag may start (so sliders and wheels inside the open panel keep working).
    var canStartDrag: (NSPoint) -> Bool = { _ in true }
    var onDragBegan: (() -> Void)?
    var onDragEnd: (() -> Void)?
    private(set) var isDragging = false
    private var dragEligible = false
    private var dragStartMouse: NSPoint?
    private var dragStartOrigin = NSPoint.zero

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let m = NSEvent.mouseLocation
            dragStartMouse = m
            dragStartOrigin = frame.origin
            dragEligible = isDragAllowed() && canStartDrag(m)
            isDragging = false
            super.sendEvent(event)
        case .leftMouseDragged:
            guard dragEligible, let start = dragStartMouse else { super.sendEvent(event); return }
            let m = NSEvent.mouseLocation
            let dx = m.x - start.x, dy = m.y - start.y
            if !isDragging {
                if hypot(dx, dy) < 4 { return }
                isDragging = true
                onDragBegan?()
            }
            setFrameOrigin(NSPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy))
        case .leftMouseUp:
            dragStartMouse = nil
            dragEligible = false
            if isDragging {
                isDragging = false
                onDragEnd?()
                return
            }
            super.sendEvent(event)
        default:
            super.sendEvent(event)
        }
    }
}

final class IslandHostingView: NSHostingView<IslandView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
