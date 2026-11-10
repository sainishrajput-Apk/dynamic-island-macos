import AppKit

final class CatchView: NSView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onClick?() }
}

/// Sits just below the open panel and covers the area around it. A click there closes the panel.
/// (Clicks farther away are caught by a global mouse monitor in the controller.)
final class ClickCatcher: NSPanel {
    private let catchView = CatchView()
    var onClick: (() -> Void)? {
        get { catchView.onClick }
        set { catchView.onClick = newValue }
    }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        contentView = catchView
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.02)   // tiny alpha so the window can receive clicks
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
