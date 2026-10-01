import AppKit

/// Short animations played over the text for moments the text itself can't animate. Each one
/// ends looking exactly like what the layout manager draws underneath, then goes away.
@MainActor
enum EditorEffects {
    #if DEBUG
    /// Debug scenarios freeze the check box effect in one state (no animation, not removed).
    static var still: (scale: CGFloat, stroke: CGFloat)?
    /// Debug scenarios keep the cross-fade's picture fully shown (no animation, not removed).
    static var stillFade = false
    #endif

    /// A task was checked. 克制: the box presses in and settles, the check mark draws itself.
    /// 活泼: the box winds up, springs past its size and back, and a few dots fly out.
    /// `box` is the check box's rect in the text view's coordinates, as the layout manager drew it.
    static func taskChecked(in view: NSView, box: CGRect) {
        guard Motion.style != .minimal, !Motion.reduce, let host = view.layer else { return }
        let flipped = host.contentsAreFlipped()
        let paper = color(NSColor.textBackgroundColor, in: view), accent = color(NSColor.controlAccentColor, in: view)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // A patch of paper hides the drawn box while this one animates above it.
        let root = CALayer()
        root.frame = box.insetBy(dx: -4, dy: -4)
        root.backgroundColor = paper
        root.cornerRadius = 7
        root.zPosition = 5
        let fill = CAShapeLayer()
        fill.frame = CGRect(x: 4, y: 4, width: box.width, height: box.height)
        fill.path = CGPath(roundedRect: fill.bounds, cornerWidth: 5.25, cornerHeight: 5.25, transform: nil)
        fill.fillColor = accent
        let check = CAShapeLayer()
        check.frame = fill.bounds
        let w = box.width, h = box.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: flipped ? y : h - y) }
        let path = CGMutablePath()
        path.move(to: pt(4, h / 2))
        path.addLine(to: pt(6.6, h - 4))
        path.addLine(to: pt(w - 3.6, 4))
        check.path = path
        check.strokeColor = .white
        check.fillColor = nil
        check.lineWidth = 1.8
        check.lineCap = .round
        check.lineJoin = .round
        fill.addSublayer(check)
        root.addSublayer(fill)
        host.addSublayer(root)
        CATransaction.commit()
        #if DEBUG
        if let still {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fill.setAffineTransform(CGAffineTransform(scaleX: still.scale, y: still.scale))
            check.strokeEnd = still.stroke
            CATransaction.commit()
            return
        }
        #endif

        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
        draw.fillMode = .backwards
        var total: TimeInterval
        if Motion.style == .calm {
            let press = CAKeyframeAnimation(keyPath: "transform.scale")
            press.values = [1, 0.86, 1]
            press.keyTimes = [0, 0.25, 1]
            press.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)]
            press.duration = 0.3
            fill.add(press, forKey: "press")
            draw.beginTime = CACurrentMediaTime() + 0.06
            draw.duration = 0.2
            total = 0.32
        } else {
            let pop = Motion.windUpAndSpring(from: 1, down: 0.72, response: 0.36, damping: 0.42)
            fill.add(pop, forKey: "pop")
            draw.beginTime = CACurrentMediaTime() + 0.11
            draw.duration = 0.16
            total = max(pop.duration, 0.3)
            let center = CGPoint(x: root.frame.midX, y: root.frame.midY)
            total = max(total, burst(in: host, at: center, flipped: flipped, count: 10, speed: 0.45))
            Motion.feedback(.done)
        }
        check.add(draw, forKey: "draw")
        DispatchQueue.main.asyncAfter(deadline: .now() + total + 0.05) { root.removeFromSuperlayer() }
    }

    /// The view's next redraw cross-fades from what it shows now: for content that arrives on
    /// its own (a rendered formula or diagram, a loaded picture, a folded callout, Tab 续写's
    /// suggestion) rather than from typing. A picture of just the visible part is laid over the
    /// view and faded out while the new content draws underneath, then dropped — a Core
    /// Animation transition would instead rasterize the whole (possibly very tall) document.
    static func fadeNextDraw(of view: NSView, lively: TimeInterval = 0.26, calm: TimeInterval = 0.2) {
        guard Motion.style != .minimal, !Motion.reduce, let host = view.layer else { return }
        let rect = view.visibleRect
        guard rect.width > 1, rect.height > 1, let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return }
        view.cacheDisplay(in: rect, to: rep)
        let shot = CALayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shot.contents = rep.cgImage
        shot.frame = rect
        shot.zPosition = 4
        shot.opacity = 0
        host.addSublayer(shot)
        CATransaction.commit()
        #if DEBUG
        if stillFade { shot.opacity = 1; return }
        #endif
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = Motion.style == .lively ? lively : calm
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { shot.removeFromSuperlayer() }
        shot.add(fade, forKey: "fade")
        CATransaction.commit()
    }

    /// The page you are throwing away, crumpled: a picture of what's on screen shrinks into a
    /// ball, spinning, and is tossed towards the window's bottom-left corner. Lively style only;
    /// drawn on the window's own layer so it outlives the page it shows.
    static func crumple(_ view: NSView) {
        guard Motion.style == .lively, !Motion.reduce, let window = view.window, let root = window.contentView,
              let host = root.layer else { return }
        let rect = view.visibleRect
        guard rect.width > 1, rect.height > 1, let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return }
        view.cacheDisplay(in: rect, to: rep)
        let frame = root.convert(view.convert(rect, to: nil), from: nil)
        let target = CGPoint(x: 44, y: root.isFlipped ? root.bounds.height - 40 : 40)
        let ball = CALayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ball.contents = rep.cgImage
        ball.contentsGravity = .resizeAspectFill
        ball.frame = frame
        ball.masksToBounds = true
        ball.zPosition = 1000
        ball.shadowOpacity = 0
        // Creases: light where the ball bulges towards you, dark in its folds, deepening as it's squeezed.
        let creases = CAGradientLayer()
        creases.type = .radial
        creases.colors = [NSColor.white.withAlphaComponent(0.45).cgColor, NSColor.black.withAlphaComponent(0.05).cgColor,
                          NSColor.black.withAlphaComponent(0.45).cgColor]
        creases.locations = [0, 0.45, 1]
        creases.startPoint = CGPoint(x: 0.36, y: 0.32)
        creases.endPoint = CGPoint(x: 1.1, y: 1.1)
        creases.frame = ball.bounds
        creases.opacity = 0
        ball.addSublayer(creases)
        host.addSublayer(ball)
        CATransaction.commit()

        let d = 0.62 * Motion.slowFactor
        let curve = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.75, 0.4)   // slow crush, fast throw
        func anim(_ key: String, _ values: [Any], _ times: [NSNumber]) -> CAKeyframeAnimation {
            let a = CAKeyframeAnimation(keyPath: key)
            a.values = values
            a.keyTimes = times
            a.duration = d
            a.timingFunction = curve
            return a
        }
        let side = min(frame.width, frame.height)
        let square = NSValue(rect: CGRect(x: 0, y: 0, width: side, height: side))
        let squeeze = CAKeyframeAnimation(keyPath: "opacity")
        squeeze.values = [0, 0.9, 0.9]
        squeeze.keyTimes = [0, 0.45, 1]
        squeeze.duration = d
        squeeze.fillMode = .forwards
        squeeze.isRemovedOnCompletion = false
        let creaseBounds = CAKeyframeAnimation(keyPath: "bounds")
        creaseBounds.values = [NSValue(rect: CGRect(origin: .zero, size: frame.size)), square, square]
        creaseBounds.keyTimes = [0, 0.45, 1]
        creaseBounds.duration = d
        creaseBounds.timingFunction = curve
        creaseBounds.fillMode = .forwards
        creaseBounds.isRemovedOnCompletion = false
        let creaseGroup = CAAnimationGroup()
        let creaseCenter = CAKeyframeAnimation(keyPath: "position")
        creaseCenter.values = [NSValue(point: CGPoint(x: frame.width / 2, y: frame.height / 2)),
                               NSValue(point: CGPoint(x: side / 2, y: side / 2)), NSValue(point: CGPoint(x: side / 2, y: side / 2))]
        creaseCenter.keyTimes = [0, 0.45, 1]
        creaseCenter.duration = d
        creaseCenter.timingFunction = curve
        creaseGroup.animations = [squeeze, creaseBounds, creaseCenter]
        creaseGroup.duration = d
        creaseGroup.fillMode = .forwards
        creaseGroup.isRemovedOnCompletion = false
        creases.add(creaseGroup, forKey: "crease")
        let group = CAAnimationGroup()
        group.animations = [
            // The page gathers into a square, then a ball.
            anim("bounds", [NSValue(rect: CGRect(origin: .zero, size: frame.size)), square, square], [0, 0.45, 1]),
            // Squeezed into a ball first, then thrown.
            anim("transform.scale", [1, 0.16, 0.05], [0, 0.45, 1]),
            anim("transform.rotation.z", [0, -1.2, -5.5], [0, 0.45, 1]),
            anim("cornerRadius", [8, side / 2, side / 2], [0, 0.45, 1]),
            anim("position", [NSValue(point: CGPoint(x: frame.midX, y: frame.midY)),
                              NSValue(point: CGPoint(x: frame.midX, y: frame.midY)),
                              NSValue(point: target)], [0, 0.45, 1]),
            anim("opacity", [1, 1, 0], [0, 0.8, 1]),
        ]
        group.duration = d
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { ball.removeFromSuperlayer() }
        ball.add(group, forKey: "crumple")
        CATransaction.commit()
    }

    /// Dots flying out of `center` and falling away. Returns how long they take.
    @discardableResult
    static func burst(in host: CALayer, at center: CGPoint, flipped: Bool, count: Int, speed: CGFloat = 1) -> TimeInterval {
        let colors: [NSColor] = [.systemGreen, .systemYellow, .controlAccentColor, .systemOrange, .systemPurple]
        let duration: TimeInterval = 0.7, steps = 42, dt = CGFloat(duration) / CGFloat(steps)
        var dots: [CALayer] = []
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for i in 0..<count {
            let dot = CALayer()
            let size = CGFloat.random(in: 3.5...6)
            dot.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            dot.cornerRadius = size / 2
            dot.backgroundColor = colors[i % colors.count].cgColor
            dot.position = center
            dot.zPosition = 6
            dot.opacity = 0
            host.addSublayer(dot)
            dots.append(dot)
            // Screen terms: y grows downwards, gravity pulls down.
            let angle = CGFloat(i) / CGFloat(count) * 2 * .pi + .random(in: 0...0.5)
            let v = CGFloat.random(in: 160...300) * speed
            var vx = cos(angle) * v, vy = sin(angle) * v - 180 * speed, sx: CGFloat = 0, sy: CGFloat = 0
            var points: [NSValue] = []
            for _ in 0...steps {
                points.append(NSValue(point: CGPoint(x: center.x + sx, y: flipped ? center.y + sy : center.y - sy)))
                vy += 520 * dt
                vx *= 0.985
                sx += vx * dt
                sy += vy * dt
            }
            let move = CAKeyframeAnimation(keyPath: "position")
            move.values = points
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, 0.6, 1]
            let group = CAAnimationGroup()
            group.animations = [move, fade]
            group.duration = duration
            dot.add(group, forKey: "fly")
        }
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { dots.forEach { $0.removeFromSuperlayer() } }
        return duration
    }

    private static func color(_ c: NSColor, in view: NSView) -> CGColor {
        var out = c.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { out = c.cgColor }
        return out
    }
}
