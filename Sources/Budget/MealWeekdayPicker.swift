import SwiftUI

/// Sept pastilles L M M J V S D pour choisir les jours de la semaine (numérotation `Calendar`, 1 = dimanche).
struct MealWeekdayPicker: View {
    @Environment(\.theme) private var theme
    @Binding var weekdays: Set<Int>

    private static let days: [(weekday: Int, letter: String, name: String)] = [
        (2, "L", "lundi"), (3, "M", "mardi"), (4, "M", "mercredi"), (5, "J", "jeudi"),
        (6, "V", "vendredi"), (7, "S", "samedi"), (1, "D", "dimanche")
    ]

    var body: some View {
        HStack(spacing: theme.spacing / 2) {
            ForEach(Self.days, id: \.weekday) { day in
                let selected = weekdays.contains(day.weekday)
                Button {
                    if selected { weekdays.remove(day.weekday) } else { weekdays.insert(day.weekday) }
                } label: {
                    Text(day.letter)
                        .font(theme.captionFont)
                        .foregroundStyle(selected ? theme.onAccent : theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(selected ? theme.accent : theme.surfaceSecondary, in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.name)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
