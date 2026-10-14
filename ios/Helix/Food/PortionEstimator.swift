import Foundation
import simd
import CoreVideo

/// Turns a LiDAR depth map plus per-food masks into volumes.
///
/// Method:
/// 1. Back-project every confident depth pixel to a 3-D point using the camera intrinsics.
/// 2. Fit the table/plate plane to the pixels that are *not* food (least squares, two passes
///    with outlier rejection).
/// 3. For each food pixel, height above the plane × the pixel's footprint on the plane = a
///    small column of volume. Summing columns gives the food's volume in cm³.
///
/// Grams = volume × the food's density from `foods.json`.
struct PortionEstimator {
    struct Input {
        var depth: CVPixelBuffer           // Float32 metres, e.g. 256×192
        var confidence: CVPixelBuffer?     // UInt8 ARConfidenceLevel
        var intrinsics: simd_float3x3      // for the full camera image
        var imageSize: CGSize              // full camera image size, e.g. 1920×1440
    }

    enum EstimateError: Error { case noTablePlane }

    /// Returns one volume (cm³) per mask, in the same order.
    func volumes(_ input: Input, masks: [CVPixelBuffer]) throws -> [Double] {
        let depth = input.depth
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        if let c = input.confidence { CVPixelBufferLockBaseAddress(c, .readOnly) }
        defer { if let c = input.confidence { CVPixelBufferUnlockBaseAddress(c, .readOnly) } }
        masks.forEach { CVPixelBufferLockBaseAddress($0, .readOnly) }
        defer { masks.forEach { CVPixelBufferUnlockBaseAddress($0, .readOnly) } }

        let dw = CVPixelBufferGetWidth(depth), dh = CVPixelBufferGetHeight(depth)
        let dRow = CVPixelBufferGetBytesPerRow(depth)
        guard let dBase = CVPixelBufferGetBaseAddress(depth) else { return masks.map { _ in 0 } }

        // Scale intrinsics from camera-image resolution to depth resolution.
        let sx = Float(dw) / Float(input.imageSize.width), sy = Float(dh) / Float(input.imageSize.height)
        let fx = input.intrinsics[0][0] * sx, fy = input.intrinsics[1][1] * sy
        let cx = input.intrinsics[2][0] * sx, cy = input.intrinsics[2][1] * sy

        func depthAt(_ x: Int, _ y: Int) -> Float {
            dBase.advanced(by: y * dRow).assumingMemoryBound(to: Float32.self)[x]
        }
        func confident(_ x: Int, _ y: Int) -> Bool {
            guard let c = input.confidence, let base = CVPixelBufferGetBaseAddress(c) else { return true }
            return base.advanced(by: y * CVPixelBufferGetBytesPerRow(c)).assumingMemoryBound(to: UInt8.self)[x] >= 1
        }
        func point(_ x: Int, _ y: Int) -> SIMD3<Float> {
            let z = depthAt(x, y)
            return SIMD3((Float(x) - cx) * z / fx, (Float(y) - cy) * z / fy, z)
        }
        // Which mask (if any) covers depth pixel (x, y)? Masks are at camera-image resolution.
        func maskIndex(_ x: Int, _ y: Int) -> Int? {
            for (i, m) in masks.enumerated() {
                let mw = CVPixelBufferGetWidth(m), mh = CVPixelBufferGetHeight(m)
                let mx = min(mw - 1, Int(Float(x) / Float(dw) * Float(mw)))
                let my = min(mh - 1, Int(Float(y) / Float(dh) * Float(mh)))
                guard let base = CVPixelBufferGetBaseAddress(m) else { continue }
                let v = base.advanced(by: my * CVPixelBufferGetBytesPerRow(m)).assumingMemoryBound(to: Float32.self)[mx]
                if v > 0.5 { return i }
            }
            return nil
        }

        // Classify pixels once.
        var owner = [Int?](repeating: nil, count: dw * dh)
        var background: [SIMD3<Float>] = []
        background.reserveCapacity(dw * dh / 2)
        for y in 0..<dh {
            for x in 0..<dw {
                let z = depthAt(x, y)
                guard z.isFinite, z > 0.1, z < 1.5, confident(x, y) else { continue }
                if let i = maskIndex(x, y) { owner[y * dw + x] = i } else { background.append(point(x, y)) }
            }
        }

        guard var plane = Plane.fit(background) else { throw EstimateError.noTablePlane }
        // Second pass: drop points more than 1.5 cm off the first fit (cutlery, plate rims, crumbs).
        let inliers = background.filter { abs(plane.signedDistance($0)) < 0.015 }
        if let refined = Plane.fit(inliers) { plane = refined }

        var volumes = [Double](repeating: 0, count: masks.count)
        for y in 0..<dh {
            for x in 0..<dw {
                guard let i = owner[y * dw + x] else { continue }
                let p = point(x, y)
                // Positive towards the camera; clamp to a sane food height (0–12 cm).
                let h = min(0.12, max(0, plane.heightTowardsCamera(p)))
                guard h > 0.002 else { continue }
                // Pixel footprint at this depth, projected onto the plane.
                let ray = simd_normalize(p)
                let cosTheta = max(0.3, abs(simd_dot(ray, plane.normal)))
                let footprint = (p.z / fx) * (p.z / fy) / cosTheta
                volumes[i] += Double(h * footprint)
            }
        }
        return volumes.map { $0 * 1_000_000 }   // m³ → cm³
    }
}

/// Plane z = a·x + b·y + c, fitted by least squares (camera looks roughly down at the table,
/// so z is never parallel to the plane).
struct Plane {
    var a: Float, b: Float, c: Float

    var normal: SIMD3<Float> { simd_normalize(SIMD3(a, b, -1)) }

    func signedDistance(_ p: SIMD3<Float>) -> Float {
        (a * p.x + b * p.y - p.z + c) / sqrt(a * a + b * b + 1)
    }

    /// Food sits between the camera and the table, so its z is smaller than the plane's.
    func heightTowardsCamera(_ p: SIMD3<Float>) -> Float { signedDistance(p) }

    static func fit(_ pts: [SIMD3<Float>]) -> Plane? {
        guard pts.count >= 50 else { return nil }
        var sxx: Double = 0, sxy: Double = 0, syy: Double = 0, sx: Double = 0, sy: Double = 0
        var sxz: Double = 0, syz: Double = 0, sz: Double = 0
        for p in pts {
            let x = Double(p.x), y = Double(p.y), z = Double(p.z)
            sxx += x * x; sxy += x * y; syy += y * y; sx += x; sy += y
            sxz += x * z; syz += y * z; sz += z
        }
        let n = Double(pts.count)
        let m = simd_double3x3(rows: [
            SIMD3(sxx, sxy, sx),
            SIMD3(sxy, syy, sy),
            SIMD3(sx, sy, n),
        ])
        guard abs(m.determinant) > 1e-12 else { return nil }
        let sol = m.inverse * SIMD3(sxz, syz, sz)
        return Plane(a: Float(sol.x), b: Float(sol.y), c: Float(sol.z))
    }
}
