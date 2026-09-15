import NotabilityCore
import SwiftUI

/// Font size controls for the selected text block: down arrow, a tappable
/// number (menu of presets), and an up arrow — clamped to the HIG-ish range.
struct FontSizeStepper: View {
    let value: Double
    let onChanged: (Double) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                onChanged(TextBlockLayout.clampedFontSize(value - 1))
            } label: {
                Image(systemName: "minus")
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("fontDown")

            Menu {
                ForEach(TextBlockLayout.presetFontSizes, id: \.self) { size in
                    Button("\(Int(size)) pt") { onChanged(size) }
                }
            } label: {
                Text("\(Int(value.rounded()))")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("fontValue")

            Button {
                onChanged(TextBlockLayout.clampedFontSize(value + 1))
            } label: {
                Image(systemName: "plus")
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("fontUp")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fontSizeStepper")
    }
}
