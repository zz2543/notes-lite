import AppKit
import MetalKit
import SwiftUI

struct GlassBackdrop {
    let image: CGImage
    let size: CGSize
    @MainActor static func capture() -> GlassBackdrop? {
        let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey })
        guard let content = window?.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return nil }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let image = rep.cgImage else { return nil }
        return GlassBackdrop(image: image, size: content.bounds.size)
    }
}

struct GlassImpulse: Equatable {
    var sequence = 0
    var point = CGPoint(x: 255, y: 80)
}

/// Metal decorates only the surface below controls. Text and hit testing stay native.
struct GlassSurface: NSViewRepresentable {
    let backdrop: GlassBackdrop?
    let impulse: GlassImpulse
    @Environment(\.colorScheme) private var scheme
    func makeCoordinator() -> Renderer { Renderer() }
    func makeNSView(context: Context) -> MTKView {
        let device = ProcessInfo.processInfo.environment["NOTESLITE_NO_METAL"] == "1" ? nil : MTLCreateSystemDefaultDevice()
        let view = MTKView(frame: .zero, device: device)
        view.layer?.isOpaque = false
        view.clearColor = MTLClearColorMake(0,0,0,0)
        view.colorPixelFormat = .bgra8Unorm
        view.isPaused = true; view.enableSetNeedsDisplay = false; view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        context.coordinator.configure(view)
        return view
    }
    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.update(view, backdrop: backdrop, impulse: impulse, dark: scheme == .dark)
    }
    static func dismantleNSView(_ view: MTKView, coordinator: Renderer) { view.isPaused = true; view.delegate = nil; coordinator.writeDiagnostics(active: false) }

    @MainActor final class Renderer: NSObject, MTKViewDelegate {
        private var queue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var texture: MTLTexture?
        private var sourceSize = CGSize(width: 1, height: 1)
        private var imageIdentity: ObjectIdentifier?
        private var sequence = -1
        private var start = CACurrentMediaTime()
        private var point = CGPoint(x: 255, y: 80)
        private var dark = false
        private var frameCount = 0
        private var lastFrame: Double?
        private var intervals: [Double] = []
        private var deviceName = "unavailable"
        private var failure: String?
        struct Uniforms {
            var size: SIMD2<Float>
            var sourceSize: SIMD2<Float>
            var origin: SIMD2<Float>
            var point: SIMD2<Float>
            var elapsed: Float
            var dark: Float
            var strength: Float = 1
            var reserved: Float = 0
        }
        func configure(_ view: MTKView) {
            guard let device = view.device else { failure = "Metal unavailable"; writeDiagnostics(active: false); return }
            deviceName = device.name
            do {
                guard let sourceURL = resources?.appendingPathComponent("Glass.metal") else { throw CocoaError(.fileReadNoSuchFile) }
                let library = try device.makeLibrary(source: String(contentsOf: sourceURL, encoding: .utf8), options: nil)
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.label = "NotesLite refracted glass"
                descriptor.vertexFunction = library.makeFunction(name: "glassVertex")
                descriptor.fragmentFunction = library.makeFunction(name: "glassFragment")
                let color = descriptor.colorAttachments[0]!
                color.pixelFormat = view.colorPixelFormat; color.isBlendingEnabled = true
                color.sourceRGBBlendFactor = .one; color.destinationRGBBlendFactor = .oneMinusSourceAlpha
                color.sourceAlphaBlendFactor = .one; color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
                queue = device.makeCommandQueue()
            } catch { failure = error.localizedDescription }
            writeDiagnostics(active: false)
        }
        private var resources: URL? {
            let name = "NotesLite_NotesLite.bundle"
            for base in [Bundle.main.resourceURL, Bundle.main.bundleURL, Bundle.main.executableURL?.deletingLastPathComponent()].compactMap({ $0 }) {
                for suffix in ["Shaders", "Contents/Resources/Shaders"] {
                    let url = base.appendingPathComponent(name).appendingPathComponent(suffix)
                    if FileManager.default.fileExists(atPath: url.appendingPathComponent("Glass.metal").path) { return url }
                }
            }
            return nil
        }
        func update(_ view: MTKView, backdrop: GlassBackdrop?, impulse: GlassImpulse, dark: Bool) {
            self.dark = dark
            guard let device = view.device, pipeline != nil else { return }
            if let backdrop, imageIdentity != ObjectIdentifier(backdrop.image) {
                do {
                    texture = try MTKTextureLoader(device: device).newTexture(cgImage: backdrop.image, options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft])
                    sourceSize = backdrop.size; imageIdentity = ObjectIdentifier(backdrop.image); failure = nil
                } catch { failure = error.localizedDescription }
            }
            guard texture != nil else { failure = "Window backdrop unavailable; using native material"; writeDiagnostics(active: false); return }
            if sequence != impulse.sequence {
                sequence = impulse.sequence; point = impulse.point; start = CACurrentMediaTime(); lastFrame = nil
                view.isPaused = false
            }
        }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { if pipeline != nil, texture != nil { view.draw() } }
        func draw(in view: MTKView) {
            guard let pipeline, let texture, let queue, let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
                  let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
            let now = CACurrentMediaTime(), elapsed = now-start
            if let lastFrame { intervals.append((now-lastFrame)*1000); if intervals.count > 200 { intervals.removeFirst() } }
            lastFrame = now
            var origin = CGPoint.zero
            if let content = view.window?.contentView {
                let region = content.convert(view.bounds, from: view)
                origin = CGPoint(x: region.minX, y: content.isFlipped ? region.minY : content.bounds.height-region.maxY)
            }
            var uniforms = Uniforms(size: SIMD2(Float(view.bounds.width),Float(view.bounds.height)), sourceSize: SIMD2(Float(sourceSize.width),Float(sourceSize.height)), origin: SIMD2(Float(origin.x),Float(origin.y)), point: SIMD2(Float(point.x),Float(point.y)), elapsed: Float(elapsed), dark: dark ? 1 : 0)
            encoder.label = "NotesLite glass refraction and damped ripple"
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding(); command.present(drawable); command.commit()
            frameCount += 1
            if elapsed > 0.9 { view.isPaused = true; writeDiagnostics(active: false) }
        }
        func writeDiagnostics(active: Bool) {
            #if DEBUG
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("local.noteslite.desktop")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let sorted = intervals.sorted()
            let data: [String: Any] = ["device":deviceName, "pipelineReady":pipeline != nil, "backdropReady":texture != nil, "frames":frameCount, "active":active, "medianIntervalMs":sorted.isEmpty ? 0 : sorted[sorted.count/2], "maxIntervalMs":sorted.last ?? 0, "failure":failure ?? "", "note":"CPU callback intervals, not GPU frame time"]
            if let encoded = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted,.sortedKeys]) { try? encoded.write(to: directory.appendingPathComponent("metal-debug.json"), options: .atomic) }
            #endif
        }
    }
}
