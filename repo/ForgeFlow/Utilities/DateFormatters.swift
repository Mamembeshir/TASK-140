import Foundation

enum DateFormatters {
    /// Display format: MM/DD/YYYY 12-hour (e.g., "04/13/2026 2:30 PM")
    static let display: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd/yyyy h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Date-only display: MM/DD/YYYY
    static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd/yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// ISO 8601 for storage
    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Relative date display (e.g., "Today", "Yesterday", "3 days ago")
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}
