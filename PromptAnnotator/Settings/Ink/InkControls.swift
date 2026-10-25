import SwiftUI

// MARK: - Radio group

/// Square Paint radio list. Replaces `Picker(.radioGroup)` so options draw in
/// Departure Mono with 2pt ink boxes instead of the stock blue AppKit radios.
struct InkRadioGroup<Selection: Hashable>: View {
    var title: String
    @Binding var selection: Selection
    var options: [(Selection, String)]
    var axis: Axis = .vertical

    var body: some View {
        let layout = axis == .vertical
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Ink.space2))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Ink.space4))
        layout {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.0 == selection
                Button {
                    if !selected { selection = option.0 }
                } label: {
                    HStack(spacing: Ink.space2) {
                        InkRadio(selected: selected)
                        Text(option.1)
                            .font(Ink.optionFont)
                            .foregroundStyle(Ink.label)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    // The radio box takes the tint (InkRadio reads the hover), not the text.
                    .retroHover(tint: nil)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.1)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

// MARK: - Stepper

/// Paint stepper: [ - | value | + ] in one 2pt ink box with the hard bevel.
/// Replaces the stock `Stepper` (system arrows, system font).
struct InkStepper: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 1
    var format: (Int) -> String = { "\($0)" }
    var valueWidth: CGFloat = 64

    var body: some View {
        HStack(spacing: 0) {
            stepButton("-", delta: -step, enabled: value > range.lowerBound)
            Rectangle().fill(Ink.label).frame(width: Ink.stroke)
            Text(format(value))
                .font(Ink.optionFont)
                .monospacedDigit()
                .foregroundStyle(Ink.label)
                .lineLimit(1)
                .frame(width: valueWidth, height: 22)
                .background(Ink.field)
            Rectangle().fill(Ink.label).frame(width: Ink.stroke)
            stepButton("+", delta: step, enabled: value < range.upperBound)
        }
        .padding(Ink.stroke)
        .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: Ink.stroke))
        .background(
            Rectangle()
                .fill(Ink.bevel)
                .offset(x: Ink.bevelOffset, y: Ink.bevelOffset)
        )
        .padding(.trailing, Ink.bevelOffset)
        .padding(.bottom, Ink.bevelOffset)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: bump(step)
            case .decrement: bump(-step)
            @unknown default: break
            }
        }
    }

    private func stepButton(_ glyph: String, delta: Int, enabled: Bool) -> some View {
        Button {
            bump(delta)
        } label: {
            Text(glyph)
                .font(Ink.labelFont)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(InkStepperButtonStyle(enabled: enabled))
        .disabled(!enabled)
        .buttonRepeatBehavior(.enabled)
    }

    private func bump(_ delta: Int) {
        let next = min(range.upperBound, max(range.lowerBound, value + delta))
        if next != value { value = next }
    }
}

private struct InkStepperButtonStyle: ButtonStyle {
    var enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Ink.window : (enabled ? Ink.label : Ink.tertiary))
            .background(configuration.isPressed ? Ink.label : Ink.window)
            .retroHover(enabled: enabled)
    }
}

// MARK: - Slider row

/// `InkSlider` plus a fixed-width value readout, for settings rows.
struct InkValueSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double? = nil
    var format: (Double) -> String
    var width: CGFloat = 140

    var body: some View {
        HStack(spacing: Ink.space2) {
            InkSlider(
                value: $value,
                range: range,
                step: step,
                accessibilityText: format
            )
            .frame(width: width)
            .accessibilityLabel(title)
            Text(format(value))
                .font(Ink.optionFont)
                .monospacedDigit()
                .foregroundStyle(Ink.label)
                .frame(width: 52, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}
