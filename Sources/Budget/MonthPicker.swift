import SwiftUI

/// Sélecteur de période : titre cliquable (popover) encadré de flèches précédent / suivant.
struct MonthPicker: View {
    enum Mode { case month, year }

    @Environment(\.theme) private var theme
    @Binding var selection: Date
    var mode: Mode = .month
    /// Débuts de mois ayant des opérations.
    var monthsWithData: Set<Date> = []

    @State private var showPopover = false

    private var cal: Calendar { Calendar.current }
    private var locale: Locale { Locale(identifier: "fr_FR") }
    private var step: Int { mode == .month ? 1 : 12 }
    private var currentStart: Date { Date.now.startOfMonth.normalized(for: mode) }

    private var title: String {
        switch mode {
        case .month:
            return selection.formatted(Date.FormatStyle().month(.wide).year().locale(locale)).capitalized
        case .year:
            return selection.formatted(Date.FormatStyle().year().locale(locale))
        }
    }

    var body: some View {
        HStack(spacing: theme.spacing) {
            arrow("chevron.left", label: "Précédent", disabled: false) { selection = selection.addingMonths(-step) }

            Button { showPopover = true } label: {
                HStack(spacing: 6) {
                    Text(title)
                        .font(theme.titleFont)
                    Image(systemName: "chevron.down")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                }
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, theme.spacing)
                .padding(.vertical, theme.spacing / 2)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choisir la période, \(title)")
            .popover(isPresented: $showPopover) {
                MonthPickerPopover(
                    selection: $selection, mode: mode,
                    monthsWithData: monthsWithData, isPresented: $showPopover
                )
                #if os(iOS)
                .presentationCompactAdaptation(.popover)
                #endif
            }

            arrow("chevron.right", label: "Suivant",
                  disabled: selection.addingMonths(step) > currentStart) {
                selection = selection.addingMonths(step)
            }
        }
    }

    private func arrow(_ icon: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(theme.bodyFont)
                .frame(width: theme.iconSize, height: theme.iconSize)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? theme.textTertiary : theme.accent)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}

private extension Date {
    /// Début de mois, ou début d'année selon le mode.
    func normalized(for mode: MonthPicker.Mode) -> Date {
        mode == .month ? startOfMonth : (Calendar.current.dateInterval(of: .year, for: self)?.start ?? self)
    }
}

// MARK: - Contenu du popover

private struct MonthPickerPopover: View {
    @Environment(\.theme) private var theme
    @Binding var selection: Date
    let mode: MonthPicker.Mode
    let monthsWithData: Set<Date>
    @Binding var isPresented: Bool

    /// Année affichée dans la grille des mois.
    @State private var shownYear: Int

    init(selection: Binding<Date>, mode: MonthPicker.Mode, monthsWithData: Set<Date>, isPresented: Binding<Bool>) {
        _selection = selection
        self.mode = mode
        self.monthsWithData = monthsWithData
        _isPresented = isPresented
        _shownYear = State(initialValue: Calendar.current.component(.year, from: selection.wrappedValue))
    }

    private var cal: Calendar { Calendar.current }
    private var currentYear: Int { cal.component(.year, from: .now) }
    private var currentMonthStart: Date { Date.now.startOfMonth }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: theme.spacing / 2), count: 3)
    }

    private func date(year: Int, month: Int = 1) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
    }

    /// Années disponibles : de la plus ancienne ayant des données jusqu'à l'année courante.
    private var years: [Int] {
        let oldest = monthsWithData.map { cal.component(.year, from: $0) }.min() ?? currentYear
        let first = min(oldest, cal.component(.year, from: selection), currentYear)
        return Array(first...currentYear)
    }

    var body: some View {
        VStack(spacing: theme.spacing) {
            switch mode {
            case .month: monthsContent
            case .year: yearsContent
            }

            Button("Ce mois-ci") {
                selection = mode == .month ? currentMonthStart : date(year: currentYear)
                isPresented = false
            }
            .buttonStyle(.plain)
            .font(theme.captionFont)
            .foregroundStyle(theme.accent)
            .padding(.top, theme.spacing / 2)
        }
        .padding(theme.padding)
        .frame(width: 260)
        .background(theme.background)
    }

    // MARK: Mois

    private var monthsContent: some View {
        VStack(spacing: theme.spacing) {
            HStack {
                yearArrow("chevron.left", label: "Année précédente", disabled: false) { shownYear -= 1 }
                Text(String(shownYear))
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textPrimary)
                    .frame(maxWidth: .infinity)
                yearArrow("chevron.right", label: "Année suivante", disabled: shownYear >= currentYear) { shownYear += 1 }
            }

            LazyVGrid(columns: columns, spacing: theme.spacing / 2) {
                ForEach(1...12, id: \.self) { m in
                    let d = date(year: shownYear, month: m)
                    cell(
                        label: d.formatted(Date.FormatStyle().month(.abbreviated).locale(Locale(identifier: "fr_FR"))),
                        isSelected: d == selection.startOfMonth,
                        isCurrent: d == currentMonthStart,
                        isFuture: d > currentMonthStart,
                        hasData: monthsWithData.contains(d)
                    ) {
                        selection = d
                        isPresented = false
                    }
                }
            }
        }
    }

    // MARK: Années

    private var yearsContent: some View {
        LazyVGrid(columns: columns, spacing: theme.spacing / 2) {
            ForEach(years, id: \.self) { y in
                let d = date(year: y)
                cell(
                    label: String(y),
                    isSelected: cal.component(.year, from: selection) == y,
                    isCurrent: y == currentYear,
                    isFuture: y > currentYear,
                    hasData: monthsWithData.contains { cal.component(.year, from: $0) == y }
                ) {
                    selection = d
                    isPresented = false
                }
            }
        }
    }

    // MARK: Éléments

    private func cell(label: String, isSelected: Bool, isCurrent: Bool, isFuture: Bool,
                      hasData: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(label)
                    .font(theme.bodyFont)
                Circle()
                    .fill(hasData ? (isSelected ? theme.surface : theme.accent) : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .foregroundStyle(isSelected ? theme.surface : (isFuture ? theme.textTertiary : theme.textPrimary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, theme.spacing / 2)
            .background(isSelected ? theme.accent : Color.clear,
                        in: RoundedRectangle(cornerRadius: theme.smallCornerRadius))
            .overlay {
                if isCurrent && !isSelected {
                    RoundedRectangle(cornerRadius: theme.smallCornerRadius)
                        .strokeBorder(theme.accent, lineWidth: 1)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }

    private func yearArrow(_ icon: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(theme.bodyFont)
                .frame(width: theme.iconSize, height: theme.iconSize)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? theme.textTertiary : theme.accent)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}
