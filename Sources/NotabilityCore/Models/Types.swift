import Foundation

/// Platform-pure geometry. The app layer maps these to CGRect/CGPoint/CGSize
/// so NotabilityCore stays testable on any platform (Linux included).

public struct Point: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct Size: Codable, Equatable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let zero = Size(width: 0, height: 0)
}

public struct Rect: Codable, Equatable, Hashable, Sendable {
    public var origin: Point
    public var size: Size

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.origin = Point(x: x, y: y)
        self.size = Size(width: width, height: height)
    }

    public init(origin: Point, size: Size) {
        self.origin = origin
        self.size = size
    }

    public static let zero = Rect(x: 0, y: 0, width: 0, height: 0)

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }
    public var center: Point { Point(x: origin.x + size.width / 2, y: origin.y + size.height / 2) }

    public func contains(_ p: Point) -> Bool {
        // Min-inclusive, max-exclusive — matches CGRect.contains semantics.
        p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY
    }

    public func intersects(_ other: Rect) -> Bool {
        minX < other.maxX && maxX > other.minX && minY < other.maxY && maxY > other.minY
    }

    public static func union(_ a: Rect, _ b: Rect) -> Rect {
        let minX = min(a.minX, b.minX)
        let minY = min(a.minY, b.minY)
        let maxX = max(a.maxX, b.maxX)
        let maxY = max(a.maxY, b.maxY)
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// One captured sample of a stylus stroke. Mirrors the fields of PKStrokePoint
/// so the app layer can copy them losslessly; kept as plain doubles for testability.
public struct StrokePoint: Codable, Equatable, Hashable, Sendable {
    public var location: Point
    /// Seconds offset relative to the stroke's first point.
    public var timestampOffset: TimeInterval
    /// Stroke width (points) at this sample.
    public var width: Double
    public var force: Double
    public var azimuth: Double
    public var altitude: Double

    public init(
        location: Point,
        timestampOffset: TimeInterval,
        width: Double,
        force: Double,
        azimuth: Double,
        altitude: Double
    ) {
        self.location = location
        self.timestampOffset = timestampOffset
        self.width = width
        self.force = force
        self.azimuth = azimuth
        self.altitude = altitude
    }
}

/// An optional per-stroke correction (phase 5: baseline/slant geometric correction).
public struct StrokeTransform: Codable, Equatable, Hashable, Sendable {
    /// Shear (skew) around the y axis in radians.
    public var slant: Double
    /// Vertical snap applied so the baseline aligns to a clean line.
    public var baselineAdjustment: Double
    /// Scale factor normalizing x-height toward the target.
    public var xHeightScale: Double

    public init(slant: Double = 0, baselineAdjustment: Double = 0, xHeightScale: Double = 1) {
        self.slant = slant
        self.baselineAdjustment = baselineAdjustment
        self.xHeightScale = xHeightScale
    }

    public static let identity = StrokeTransform()
}

/// One user stroke: ordered samples plus styling. The geometric correction
/// pass (phase 5) stores corrected points here rather than a nested StrokeData
/// — a struct may not contain itself recursively.
public struct StrokeData: Codable, Equatable, Sendable {
    public var points: [StrokePoint]
    public var colorHex: String
    public var baseWidth: Double
    /// Per-stroke geometric correction applied by "beautify v1".
    public var transform: StrokeTransform?
    /// The shear/snap/x-height corrected point sequence. Present once the
    /// correction pass has run; nil means "render raw points".
    public var correctedPoints: [StrokePoint]?

    public init(
        points: [StrokePoint],
        colorHex: String,
        baseWidth: Double,
        transform: StrokeTransform? = nil,
        correctedPoints: [StrokePoint]? = nil
    ) {
        self.points = points
        self.colorHex = colorHex
        self.baseWidth = baseWidth
        self.transform = transform
        self.correctedPoints = correctedPoints
    }

    public var bounds: Rect {
        guard let first = points.first else { return .zero }
        var r = Rect(x: first.location.x, y: first.location.y, width: 0, height: 0)
        for p in points.dropFirst() {
            r = Rect.union(r, Rect(x: p.location.x, y: p.location.y, width: 0, height: 0))
        }
        return r
    }

    /// Approximate polyline simplification used before rasterizing for
    /// recognition — drops collinear samples above a distance threshold.
    public func simplified(threshold: Double) -> StrokeData {
        guard threshold > 0 else { return self }
        guard points.count > 2 else { return self }
        var kept: [StrokePoint] = [points[0]]
        for p in points.dropFirst() {
            guard let last = kept.last else { continue }
            let dx = p.location.x - last.location.x
            let dy = p.location.y - last.location.y
            if (dx * dx + dy * dy) >= (threshold * threshold) {
                kept.append(p)
            }
        }
        if kept.last != points.last { kept.append(points[points.count - 1]) }
        return StrokeData(
            points: kept,
            colorHex: colorHex,
            baseWidth: baseWidth,
            transform: transform,
            correctedPoints: correctedPoints
        )
    }
}