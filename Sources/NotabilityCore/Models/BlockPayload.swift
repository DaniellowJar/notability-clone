import Foundation

/// The six kinds of blocks a Record can hold. Persisted as a text tag in SQLite.
public enum CanvasBlockKind: String, Codable, CaseIterable, Sendable {
    case stroke
    case text
    case image
    case pdfPage
    case calc
    case mathAI

    public var title: String {
        switch self {
        case .stroke: "Handwriting"
        case .text: "Text"
        case .image: "Image"
        case .pdfPage: "PDF Page"
        case .calc: "Calculator"
        case .mathAI: "Math AI"
        }
    }
}

// MARK: - Per-kind payloads

public struct TextBlockPayload: Codable, Equatable, Sendable {
    public var text: String
    public var fontSize: Double
    public var colorHex: String
    public var bold: Bool

    public init(text: String, fontSize: Double = 17, colorHex: String = "#1A1A1A", bold: Bool = false) {
        self.text = text
        self.fontSize = fontSize
        self.colorHex = colorHex
        self.bold = bold
    }
}

public struct ImageBlockPayload: Codable, Equatable, Sendable {
    /// Reference into the app's documents directory (blob storage).
    public var imageRef: String
    /// Crop rect in normalized (0…1) image coordinates. Nil = no crop.
    public var cropRect: Rect?
    public var backgroundRemoved: Bool

    public init(imageRef: String, cropRect: Rect? = nil, backgroundRemoved: Bool = false) {
        self.imageRef = imageRef
        self.cropRect = cropRect
        self.backgroundRemoved = backgroundRemoved
    }
}

public struct PDFPageBlockPayload: Codable, Equatable, Sendable {
    /// Reference into the app's documents directory for the source PDF.
    public var sourcePDFRef: String
    /// Zero-based page index within that PDF.
    public var pageIndex: Int
    /// Reference (documents dir) to the high-DPI rasterization for drawing on top.
    public var renderedImageRef: String

    public init(sourcePDFRef: String, pageIndex: Int, renderedImageRef: String) {
        self.sourcePDFRef = sourcePDFRef
        self.pageIndex = pageIndex
        self.renderedImageRef = renderedImageRef
    }
}

public struct CalcBlockPayload: Codable, Equatable, Sendable {
    public var expression: String
    /// Display string of the evaluated result; "" until first evaluation.
    public var result: String
    public var isEditable: Bool

    public init(expression: String, result: String = "", isEditable: Bool = true) {
        self.expression = expression
        self.result = result
        self.isEditable = isEditable
    }
}

public struct MathAIBlockPayload: Codable, Equatable, Sendable {
    /// Points at the StrokeBlock whose ink produced this math.
    public var sourceStrokeBlockID: UUID?
    public var latex: String
    /// Worked solution steps, newest insight last (phase 12 LLM).
    public var steps: [String]
    /// Named symbols captured from the AI parse, so retyping one number
    /// recomputes locally without another model call.
    public var variables: [String: Double]

    public init(
        sourceStrokeBlockID: UUID? = nil,
        latex: String,
        steps: [String] = [],
        variables: [String: Double] = [:]
    ) {
        self.sourceStrokeBlockID = sourceStrokeBlockID
        self.latex = latex
        self.steps = steps
        self.variables = variables
    }
}

// MARK: - Discriminated union

/// The typed payload of a CanvasBlock. Encoded as a flat JSON object like
/// `{"type":"text","text":"hi","fontSize":17,...}` so every payload kind is one
/// self-describing JSON document in the SQLite payload column.
public enum BlockPayload: Codable, Equatable, Sendable {
    case stroke([StrokeData], recognizedText: String, corrected: Bool)
    case text(TextBlockPayload)
    case image(ImageBlockPayload)
    case pdfPage(PDFPageBlockPayload)
    case calc(CalcBlockPayload)
    case mathAI(MathAIBlockPayload)

    public var kind: CanvasBlockKind {
        switch self {
        case .stroke: .stroke
        case .text: .text
        case .image: .image
        case .pdfPage: .pdfPage
        case .calc: .calc
        case .mathAI: .mathAI
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum PayloadKeys: String, CodingKey {
        case strokes
        case recognizedText
        case corrected
        case textPayload
        case imagePayload
        case pdfPayload
        case calcPayload
        case mathPayload
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let type = try box.decode(CanvasBlockKind.self, forKey: .type)
        let p = try decoder.container(keyedBy: PayloadKeys.self)
        switch type {
        case .stroke:
            let strokes = try p.decode([StrokeData].self, forKey: .strokes)
            let text = try p.decodeIfPresent(String.self, forKey: .recognizedText) ?? ""
            let corrected = try p.decodeIfPresent(Bool.self, forKey: .corrected) ?? false
            self = .stroke(strokes, recognizedText: text, corrected: corrected)
        case .text:
            self = .text(try p.decode(TextBlockPayload.self, forKey: .textPayload))
        case .image:
            self = .image(try p.decode(ImageBlockPayload.self, forKey: .imagePayload))
        case .pdfPage:
            self = .pdfPage(try p.decode(PDFPageBlockPayload.self, forKey: .pdfPayload))
        case .calc:
            self = .calc(try p.decode(CalcBlockPayload.self, forKey: .calcPayload))
        case .mathAI:
            self = .mathAI(try p.decode(MathAIBlockPayload.self, forKey: .mathPayload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(kind, forKey: .type)
        var p = encoder.container(keyedBy: PayloadKeys.self)
        switch self {
        case let .stroke(strokes, text, corrected):
            try p.encode(strokes, forKey: .strokes)
            try p.encode(text, forKey: .recognizedText)
            try p.encode(corrected, forKey: .corrected)
        case let .text(payload):
            try p.encode(payload, forKey: .textPayload)
        case let .image(payload):
            try p.encode(payload, forKey: .imagePayload)
        case let .pdfPage(payload):
            try p.encode(payload, forKey: .pdfPayload)
        case let .calc(payload):
            try p.encode(payload, forKey: .calcPayload)
        case let .mathAI(payload):
            try p.encode(payload, forKey: .mathPayload)
        }
    }
}