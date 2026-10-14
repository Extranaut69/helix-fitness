import Foundation
import Vision
import CoreML
import CoreImage

/// On-device food recognition. Nothing is uploaded.
///
/// 1. `VNGenerateForegroundInstanceMaskRequest` splits the plate into separate items.
/// 2. Each item is classified by a bundled open-source Core ML model (`FoodClassifier.mlmodel`,
///    see README) or, if none is bundled, by Apple's built-in `VNClassifyImageRequest`.
/// 3. Labels are mapped to the nutrition table by `FoodDatabase.match(label:)`.
final class FoodRecognizer: @unchecked Sendable {
    struct Candidate: Sendable { var label: String; var confidence: Float }

    struct Region: @unchecked Sendable {
        /// Mask in the same pixel space as the input buffer (OneComponent32Float, 0…1).
        var mask: CVPixelBuffer
        var candidates: [Candidate]
        /// Bounding box in normalised image coordinates (origin top-left, sensor orientation).
        var boundingBox: CGRect
    }

    private let customModel: VNCoreMLModel?
    private let ciContext = CIContext()

    init() {
        if let url = Bundle.main.url(forResource: "FoodClassifier", withExtension: "mlmodelc"),
           let ml = try? MLModel(contentsOf: url) {
            customModel = try? VNCoreMLModel(for: ml)
        } else {
            customModel = nil
        }
    }

    var usesCustomModel: Bool { customModel != nil }

    /// - Parameters:
    ///   - buffer: camera image in sensor orientation (ARFrame.capturedImage) or a photo.
    ///   - orientation: how to rotate the buffer upright for classification (`.right` for ARKit portrait).
    func analyze(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) throws -> [Region] {
        // Masks are generated without rotation so they line up pixel-for-pixel with the depth map.
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
        return try analyze(handler: handler, whole: { try self.cgImage(from: buffer) },
                           width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer), orientation: orientation)
    }

    /// For photos picked from the library (no depth): image must already be upright.
    func analyze(photo: CGImage) throws -> [Region] {
        let handler = VNImageRequestHandler(cgImage: photo, orientation: .up)
        return try analyze(handler: handler, whole: { photo }, width: photo.width, height: photo.height, orientation: .up)
    }

    private func analyze(handler: VNImageRequestHandler, whole: () throws -> CGImage, width: Int, height: Int,
                         orientation: CGImagePropertyOrientation) throws -> [Region] {
        let maskRequest = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([maskRequest])

        guard let observation = maskRequest.results?.first, !observation.allInstances.isEmpty else {
            // Nothing separable: classify the whole frame as one item.
            let mask = try fullMask(width: width, height: height)
            return [Region(mask: mask, candidates: try classify(try whole(), orientation: orientation), boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1))]
        }

        var regions: [Region] = []
        for instance in observation.allInstances {
            let set = IndexSet(integer: instance)
            let mask = try observation.generateScaledMaskForImage(forInstances: set, from: handler)
            let crop = try observation.generateMaskedImage(ofInstances: set, from: handler, croppedToInstancesExtent: true)
            let candidates = try classify(try cgImage(from: crop), orientation: orientation)
            regions.append(Region(mask: mask, candidates: candidates, boundingBox: Self.bounds(of: mask)))
        }
        // Largest items first; the plate itself sometimes comes back as an instance with no food label.
        return regions.sorted { $0.boundingBox.width * $0.boundingBox.height > $1.boundingBox.width * $1.boundingBox.height }
    }

    func classify(_ image: CGImage, orientation: CGImagePropertyOrientation) throws -> [Candidate] {
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
        if let customModel {
            let request = VNCoreMLRequest(model: customModel)
            request.imageCropAndScaleOption = .centerCrop
            try handler.perform([request])
            let results = (request.results as? [VNClassificationObservation]) ?? []
            return results.prefix(5).map { Candidate(label: $0.identifier, confidence: $0.confidence) }
        }
        let request = VNClassifyImageRequest()
        try handler.perform([request])
        return (request.results ?? [])
            .filter { $0.confidence > 0.05 }
            .prefix(8)
            .map { Candidate(label: $0.identifier, confidence: $0.confidence) }
    }

    // MARK: - Pixel helpers

    private func cgImage(from buffer: CVPixelBuffer) throws -> CGImage {
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { throw CocoaError(.featureUnsupported) }
        return cg
    }

    private func fullMask(width: Int, height: Int) throws -> CVPixelBuffer {
        var out: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_OneComponent32Float, nil, &out)
        guard let out else { throw CocoaError(.featureUnsupported) }
        CVPixelBufferLockBaseAddress(out, [])
        defer { CVPixelBufferUnlockBaseAddress(out, []) }
        let rowBytes = CVPixelBufferGetBytesPerRow(out), h = CVPixelBufferGetHeight(out), w = CVPixelBufferGetWidth(out)
        let base = CVPixelBufferGetBaseAddress(out)!
        for y in 0..<h {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in 0..<w { row[x] = 1 }
        }
        return out
    }

    static func bounds(of mask: CVPixelBuffer) -> CGRect {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        let w = CVPixelBufferGetWidth(mask), h = CVPixelBufferGetHeight(mask), rowBytes = CVPixelBufferGetBytesPerRow(mask)
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return .zero }
        var minX = w, minY = h, maxX = 0, maxY = 0
        for y in stride(from: 0, to: h, by: 4) {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in stride(from: 0, to: w, by: 4) where row[x] > 0.5 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX > minX, maxY > minY else { return .zero }
        return CGRect(x: Double(minX) / Double(w), y: Double(minY) / Double(h),
                      width: Double(maxX - minX) / Double(w), height: Double(maxY - minY) / Double(h))
    }
}
