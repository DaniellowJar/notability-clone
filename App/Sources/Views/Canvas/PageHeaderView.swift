import NotabilityCore
import SwiftUI

/// Creation-date header pinned at the top of the page, in canvas coordinates
/// so it scrolls and zooms with the content. Alignment and date/time formats
/// come from Settings (`PageHeaderFormat`).
struct PageHeaderView: View {
    static let height: CGFloat = 36

    let record: Record
    let format: PageHeaderFormat

    var body: some View {
        Text(format.formatted(date: record.createdAt))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(.horizontal, 12)
            .frame(height: Self.height)
            .background(Color(.systemBackground))
            .accessibilityIdentifier("pageHeader")
    }

    private var alignment: Alignment {
        switch format.alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}
