import AppKit
import GhosttyKit
import QuartzCore

/// Composites the trail above the split tree, in the tab's coordinate space.
final class CursorTrailView: NSView {
    private let trail = ghostty_cursor_trail_new()
    private let shape = CAShapeLayer()
    private let cursorMask = CAShapeLayer()
    private var timer: Timer?
    private weak var source: Ghostty.SurfaceView?
    private var sourceID: UInt64 = 0
    private var sample = ghostty_cursor_trail_sample_s()
    private var cursorRect: CGRect = .null
    private var geometry: CGSize = .zero
    private var scale: CGFloat = 1

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        shape.isHidden = true
        shape.mask = cursorMask
        cursorMask.fillRule = .evenOdd
        layer?.masksToBounds = true
        layer?.addSublayer(shape)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.invalidate()
        if let trail { ghostty_cursor_trail_free(trail) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { reset() }
    }

    func reset() {
        if let trail { ghostty_cursor_trail_reset(trail) }
        source = nil
        cursorRect = .null
        stop()
    }

    func update(_ newSample: ghostty_cursor_trail_sample_s, from view: Ghostty.SurfaceView) {
        guard let trail, let window, window.isKeyWindow, !inLiveResize else {
            reset()
            return
        }

        let backingScale = window.backingScaleFactor
        if geometry != bounds.size || scale != backingScale {
            reset()
            geometry = bounds.size
            scale = backingScale
        }
        sample = newSample
        if source !== view {
            source = view
            sourceID &+= 1
        }

        if sample.cursor_visible && sample.width > 0 && sample.height > 0 {
            let backing = view.convertToBacking(view.bounds)
            let rect = NSRect(
                x: backing.minX + CGFloat(sample.x),
                y: backing.maxY - CGFloat(sample.y + sample.height),
                width: CGFloat(sample.width),
                height: CGFloat(sample.height))
            cursorRect = view.convert(view.convertFromBacking(rect), to: self)
            ghostty_cursor_trail_observe(
                trail, sourceID,
                Float(cursorRect.minX * scale), Float(cursorRect.minY * scale),
                Float(cursorRect.width * scale), Float(cursorRect.height * scale))
        } else {
            cursorRect = .null
        }

        advance()
    }

    private func advance() {
        guard let trail, window?.isKeyWindow == true, !inLiveResize, geometry == bounds.size else {
            reset()
            return
        }

        let width = Float(bounds.width * scale)
        let height = Float(bounds.height * scale)
        guard width > 0, height > 0 else { return }

        var frame = ghostty_cursor_trail_output_s()
        ghostty_cursor_trail_step(trail, &sample, width, height, &frame)
        if frame.active {
            draw(frame)
        } else {
            stop()
        }
        if (frame.active || frame.pending) && timer == nil {
            let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.advance() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.isHidden = true
        CATransaction.commit()
    }

    private func draw(_ frame: ghostty_cursor_trail_output_s) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: CGFloat(frame.x1) / scale, y: CGFloat(frame.y1) / scale))
        path.addLine(to: CGPoint(x: CGFloat(frame.x3) / scale, y: CGFloat(frame.y3) / scale))
        path.addLine(to: CGPoint(x: CGFloat(frame.x2) / scale, y: CGFloat(frame.y2) / scale))
        path.addLine(to: CGPoint(x: CGFloat(frame.x0) / scale, y: CGFloat(frame.y0) / scale))
        path.closeSubpath()

        let clip = CGMutablePath()
        clip.addRect(bounds)
        if !cursorRect.isNull { clip.addRect(cursorRect) }
        let space = CGColorSpace(name: sample.display_p3 ? CGColorSpace.displayP3 : CGColorSpace.sRGB)
        let color = space.flatMap {
            CGColor(colorSpace: $0, components: [
                CGFloat(sample.red) / 255, CGFloat(sample.green) / 255, CGFloat(sample.blue) / 255,
                CGFloat(sample.alpha) / 255,
            ])
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = bounds
        shape.path = path
        shape.fillColor = color
        shape.opacity = frame.opacity
        cursorMask.frame = shape.bounds
        cursorMask.path = clip
        shape.isHidden = false
        CATransaction.commit()
    }
}
