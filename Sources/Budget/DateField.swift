import SwiftUI

/// Champ de date minimaliste : date en clair, raccourcis en pastilles, calendrier repliable.
struct DateField: View {
    @Environment(\.theme) private var theme
    @Binding var date: Date
    @State private var showsCalendar = false

    private static let calendar = Calendar.current
    private static let locale = Locale(identifier: "fr_FR")

    private var today: Date { Self.calendar.startOfDay(for: .now) }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing) {
            Text(title.capitalizedFirst)
                .font(theme.titleFont)
                .foregroundStyle(theme.textPrimary)

            HStack(spacing: theme.spacing / 2) {
                ForEach([0, 1, 2], id: \.self) { offset in
                    chip(offset: offset)
                }
            }

            Divider().overlay(theme.separator)

            Button {
                withAnimation(.smooth(duration: 0.3)) { showsCalendar.toggle() }
            } label: {
                HStack {
                    Image(systemName: "calendar")
                    Text("Choisir une date")
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showsCalendar ? 180 : 0))
                }
                .font(theme.bodyFont)
                .foregroundStyle(theme.textSecondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if showsCalendar {
                DatePicker("Date", selection: pickerBinding, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .environment(\.locale, Self.locale)
                    .tint(theme.accent)
                    .frame(maxWidth: 340)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
    }

    /// Choisir un jour dans le calendrier le replie.
    private var pickerBinding: Binding<Date> {
        Binding(
            get: { date },
            set: { newValue in
                date = newValue
                withAnimation(.smooth(duration: 0.3)) { showsCalendar = false }
            }
        )
    }

    private func chip(offset: Int) -> some View {
        let target = Self.calendar.date(byAdding: .day, value: -offset, to: today) ?? today
        let selected = Self.calendar.isDate(date, inSameDayAs: target)
        let label = ["Aujourd'hui", "Hier", "Avant-hier"][offset]
        return Button {
            withAnimation(.smooth(duration: 0.25)) {
                date = target
                showsCalendar = false
            }
        } label: {
            Text(label)
                .font(theme.captionFont)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(selected ? theme.surface : theme.textSecondary)
                .padding(.horizontal, theme.spacing)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(selected ? theme.accent : theme.surfaceSecondary, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    /// « Aujourd'hui », « Hier » ou « jeudi 15 octobre » (année ajoutée si différente).
    private var title: String {
        if Self.calendar.isDateInToday(date) { return "Aujourd'hui" }
        if Self.calendar.isDateInYesterday(date) { return "Hier" }
        let sameYear = Self.calendar.isDate(date, equalTo: .now, toGranularity: .year)
        let style = sameYear
            ? Date.FormatStyle().weekday(.wide).day().month(.wide)
            : Date.FormatStyle().weekday(.wide).day().month(.wide).year()
        return date.formatted(style.locale(Self.locale))
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
