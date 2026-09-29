import AVFoundation
import AppKit
import CoreVideo
import Metal
import SpriteKit

/// Offline video recorder for demo reels: renders the scene with SKRenderer into an off-screen
/// texture frame by frame and encodes H.264 with AVAssetWriter. Never touches the real screen.
final class Recorder {
    let w: Int, h: Int, fps: Int
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private(set) var frames = 0
    private let device = MTLCreateSystemDefaultDevice()!
    private lazy var queue = device.makeCommandQueue()!
    private lazy var target: MTLTexture = {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        return device.makeTexture(descriptor: d)!
    }()
    private(set) var lastFrame: CGImage?

    init(path: String, width: Int, height: Int, fps: Int) throws {
        w = width; h = height; self.fps = fps
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 24_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
        ])
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
    }

    /// Hands a fresh BGRA buffer to `fill` and appends it as the next frame.
    private func append(_ fill: (UnsafeMutableRawPointer, Int) -> Void) {
        guard let pool = adaptor.pixelBufferPool else { return }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        guard let buf = pb else { return }
        CVPixelBufferLockBaseAddress(buf, [])
        fill(CVPixelBufferGetBaseAddress(buf)!, CVPixelBufferGetBytesPerRow(buf))
        CVPixelBufferUnlockBaseAddress(buf, [])
        while !input.isReadyForMoreMediaData { usleep(500) }
        adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(fps)))
        frames += 1
    }

    /// Renders the current scene state into the video.
    func appendScene(_ r: SKRenderer, keep: Bool = false) {
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = target
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rp.colorAttachments[0].storeAction = .store
        let cb = queue.makeCommandBuffer()!
        r.render(withViewport: CGRect(x: 0, y: 0, width: w, height: h), commandBuffer: cb, renderPassDescriptor: rp)
        cb.commit(); cb.waitUntilCompleted()
        append { base, bpr in
            target.getBytes(base, bytesPerRow: bpr, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            if keep { lastFrame = Recorder.image(base, bpr, w, h) }
        }
    }

    /// Draws a frame with CoreGraphics (y up, points = pixels).
    func appendDrawn(_ draw: (CGContext) -> Void) {
        append { base, bpr in
            let ctx = CGContext(data: base, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr, space: sRGB,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            draw(ctx)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private static func image(_ base: UnsafeMutableRawPointer, _ bpr: Int, _ w: Int, _ h: Int) -> CGImage? {
        let data = Data(bytes: base, count: bpr * h) as CFData
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bpr, space: sRGB,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    func finish() async {
        input.markAsFinished()
        await writer.finishWriting()
    }

    // MARK: title cards

    static func drawText(_ s: String, size: CGFloat, weight: NSFont.Weight = .heavy, color: NSColor, center: CGPoint, alpha: CGFloat = 1, mono: Bool = false) {
        let f = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        let a = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: color.withAlphaComponent(alpha), .kern: size * 0.04])
        let b = a.size()
        a.draw(at: CGPoint(x: center.x - b.width / 2, y: center.y - b.height / 2))
    }

    /// A macOS-style keycap.
    static func drawKey(_ label: String, center: CGPoint, size: CGFloat, alpha: CGFloat) {
        let r = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        NSColor(white: 0.08, alpha: 0.9 * alpha).setFill()
        NSBezierPath(roundedRect: r.offsetBy(dx: 0, dy: -size * 0.06), xRadius: size * 0.18, yRadius: size * 0.18).fill()
        NSColor(white: 0.97, alpha: alpha).setFill()
        NSBezierPath(roundedRect: r, xRadius: size * 0.18, yRadius: size * 0.18).fill()
        drawText(label, size: size * 0.5, weight: .semibold, color: NSColor(white: 0.15, alpha: 1), center: center, alpha: alpha)
    }
}
