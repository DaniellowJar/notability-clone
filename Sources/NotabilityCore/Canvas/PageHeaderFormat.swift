import Foundation

/// Left/center/right placement of the page creation-date header.
public enum PageHeaderAlignment: String, Codable, CaseIterable, Sendable {
    case leading
    case center
    case trailing
}

/// Date + time formatting for the page header. Format strings follow
/// DateFormatter patterns; the app exposes presets plus a custom field.
public struct PageHeaderFormat: Codable, Equatable, Sendable {
    public var alignment: PageHeaderAlignment
    public var dateFormat: String
    public var timeFormat: String

    public init(
        alignment: PageHeaderAlignment = .center,
        dateFormat: String = PageHeaderFormat.defaultDateFormat,
        timeFormat: String = PageHeaderFormat.defaultTimeFormat
    ) {
        self.alignment = alignment
        self.dateFormat = dateFormat
        self.timeFormat = timeFormat
    }

    public static let `default` = PageHeaderFormat()

    /// Built-in patterns used when the Settings fields are blank.
    public static let defaultDateFormat = "MMM d, yyyy"
    public static let defaultTimeFormat = "h:mm a"

    /// Display string for a record's creation date: "<date> · <time>".
    public func formatted(date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        "\(formattedDate(date, locale: locale, timeZone: timeZone)) · \(formattedTime(date, locale: locale, timeZone: timeZone))"
    }

    public func formattedDate(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        format(date, with: dateFormat, locale: locale, timeZone: timeZone)
    }

    public func formattedTime(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        format(date, with: timeFormat, locale: locale, timeZone: timeZone)
    }

    private func format(_ date: Date, with pattern: String, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// Accepts non-empty patterns that produce output on a reference date.
    /// Unknown pattern letters render literally in DateFormatter, so emptiness
    /// is the only reliable rejection without guessing user intent.
    public static func isValidFormat(_ s: String) -> Bool {
        guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let reference = Date(timeIntervalSinceReferenceDate: 0)
        return !PageHeaderFormat(dateFormat: s).formattedDate(reference).isEmpty
    }
}
