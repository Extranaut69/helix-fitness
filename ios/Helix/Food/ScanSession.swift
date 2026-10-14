import Foundation
import ARKit
import UIKit
import Observation

/// One food found on the plate, editable before logging.
struct DetectedFood: Identifiable {
    let id = UUID()
    var food: FoodInfo
    var grams: Double
    var volumeCm3: Double?
    var confidence: Float?
    /// Other plausible foods from the classifier, offered first in the swap menu.
    var alternatives: [FoodInfo] = []
    /// Normalised rect in the upright snapshot, for drawing a label on the photo.
    var box: CGRect = .zero
}

/// Runs ARKit with LiDAR scene depth, captures a frame, and turns it into `DetectedFood`s.
@MainActor
@Observable
final class ScanSession {
    enum Phase {
        case live
        case analyzing
        case results([DetectedFood], snapshot: UIImage?)
        case failed(String)
    }

    let session = ARSession()
    private(set) var phase: Phase = .live
    private let recognizer = FoodRecognizer()

    static var supportsLiDAR: Bool { ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) }

    func start() {
        let config = ARWorldTrackingConfiguration()
        if Self.supportsLiDAR { config.frameSemantics = [.sceneDepth, .smoothedSceneDepth] }
        config.planeDetection = [.horizontal]
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        phase = .live
    }

    func stop() { session.pause() }

    func reset() { start() }

    /// Captures the current frame and runs segmentation, classification and LiDAR volume.
    func capture() async {
        guard let frame = session.currentFrame else { return }
        phase = .analyzing
        let image = frame.capturedImage
        let depth = frame.smoothedSceneDepth ?? frame.sceneDepth
        let input = depth.map {
            PortionEstimator.Input(depth: $0.depthMap, confidence: $0.confidenceMap,
                                   intrinsics: frame.camera.intrinsics, imageSize: frame.camera.imageResolution)
        }
        let upright = CIImage(cvPixelBuffer: image).oriented(.right)
        let snapshot = CIContext().createCGImage(upright, from: upright.extent).map { UIImage(cgImage: $0) }
        session.pause()

        let recognizer = recognizer
        do {
            let (regions, volumes) = try await Task.detached(priority: .userInitiated) {
                let regions = try recognizer.analyze(image, orientation: .right)
                // A missing table plane (e.g. plate fills the frame) falls back to serving sizes.
                let volumes = input.flatMap { try? PortionEstimator().volumes($0, masks: regions.map(\.mask)) }
                return (regions, volumes)
            }.value
            let foods = Self.resolve(regions, volumes: volumes, rotateFromSensor: true)
            phase = foods.isEmpty
                ? .failed("No food recognised. Move closer so the plate fills the frame, then try again.")
                : .results(foods, snapshot: snapshot)
        } catch {
            phase = .failed("Analysis failed: \(error.localizedDescription)")
        }
    }

    /// Photo-library path: no depth, so portions start at a typical serving and the user adjusts.
    func analyze(photo: UIImage) async {
        guard let cg = photo.uprightCGImage else { phase = .failed("Couldn't read that image."); return }
        phase = .analyzing
        let recognizer = recognizer
        do {
            let regions = try await Task.detached(priority: .userInitiated) { try recognizer.analyze(photo: cg) }.value
            let foods = Self.resolve(regions, volumes: nil, rotateFromSensor: false)
            phase = foods.isEmpty ? .failed("No food recognised in that photo.") : .results(foods, snapshot: photo)
        } catch {
            phase = .failed("Analysis failed: \(error.localizedDescription)")
        }
    }

    private static func resolve(_ regions: [FoodRecognizer.Region], volumes: [Double]?, rotateFromSensor: Bool) -> [DetectedFood] {
        let db = FoodDatabase.shared
        var out: [DetectedFood] = []
        for (i, region) in regions.enumerated() {
            var seen = Set<String>()
            let matches = region.candidates.compactMap { c -> (FoodInfo, Float)? in
                guard let f = db.match(label: c.label), seen.insert(f.id).inserted else { return nil }
                return (f, c.confidence)
            }
            guard let top = matches.first else { continue }            // e.g. the plate or a napkin
            let (best, conf) = top
            let volume = volumes.map { $0[i] }
            if let v = volume, v < 5 { continue }                      // flat → not food
            let grams = volume.map { ($0 * best.density / 5).rounded() * 5 } ?? best.serving
            let b = region.boundingBox
            let box = rotateFromSensor ? CGRect(x: 1 - (b.minY + b.height), y: b.minX, width: b.height, height: b.width) : b
            out.append(DetectedFood(food: best, grams: grams, volumeCm3: volume.map { $0.rounded() },
                                    confidence: conf, alternatives: matches.dropFirst().map { $0.0 }, box: box))
        }
        return out
    }
}

private extension UIImage {
    /// Redraws the image so pixel data matches its display orientation.
    var uprightCGImage: CGImage? {
        if imageOrientation == .up, let cg = cgImage { return cg }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }.cgImage
    }
}
