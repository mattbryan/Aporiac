import SwiftUI

/// Detail surface for a habit: criteria, today’s log controls, and a monthly heat map.
extension Calendar {
    func startOfMonth(for referenceDate: Date) -> Date {
        let comps = dateComponents([.year, .month], from: referenceDate)
        return date(from: comps) ?? referenceDate
    }
}

struct HabitDetailView: View {
    let habit: Habit
    let viewModel: HabitViewModel

    @State private var logs: [HabitLog] = []
    @State private var displayMonth: Date = Calendar.current.startOfMonth(for: Date())
    @State private var isLoadingCalendar = true
    @State private var isInitialCalendarLoad = true
    @State private var editTitle: String = ""
    @State private var editFullCriteria: String = ""
    @State private var editPartialCriteria: String = ""
    @State private var isArchiving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                titleBlock
                criteriaBlock
                siftDividerLine
                todaySection
                siftDividerLine
                calendarSection
                archiveButton
                Color.clear.frame(height: 120)
            }
        }
        .background(Color.siftSurface.ignoresSafeArea())
        .onDisappear {
            guard !isArchiving else { return }
            let t = editTitle.trimmingCharacters(in: .whitespaces)
            let f = editFullCriteria.trimmingCharacters(in: .whitespaces)
            let p = editPartialCriteria.trimmingCharacters(in: .whitespaces)
            let changed = t != habit.title || f != habit.fullCriteria || p != habit.partialCriteria
            if changed && !t.isEmpty {
                Task {
                    try? await viewModel.update(habit: habit, title: t, fullCriteria: f, partialCriteria: p)
                }
            }
        }
        .task {
            editTitle = habit.title
            editFullCriteria = habit.fullCriteria
            editPartialCriteria = habit.partialCriteria
            await loadLogs()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.siftSubtle)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.leading, DS.Spacing.md)
        .padding(.trailing, DS.Spacing.md)
        .padding(.top, DS.Spacing.sm)
    }

    private var titleBlock: some View {
        TextField("Habit name", text: $editTitle)
            .font(.siftH1Medium)
            .kerning(SiftTracking.h1Medium)
            .foregroundStyle(Color.siftInk)
            .submitLabel(.done)
            .padding(.horizontal, 20)
            .padding(.top, DS.Spacing.sm)
            .padding(.bottom, DS.Spacing.xs)
    }

    private var siftDividerLine: some View {
        Rectangle()
            .fill(Color.siftDivider)
            .frame(height: 1)
            .padding(.horizontal, 20)
    }

    private var criteriaBlock: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                Text("Full credit")
                    .font(.siftCaption)
                    .foregroundStyle(Color.siftSubtle)
                    .frame(width: 80, alignment: .leading)
                TextField("Full credit criteria", text: $editFullCriteria, axis: .vertical)
                    .font(.siftCallout)
                    .foregroundStyle(Color.siftInk)
            }
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                Text("Partial credit")
                    .font(.siftCaption)
                    .foregroundStyle(Color.siftSubtle)
                    .frame(width: 80, alignment: .leading)
                TextField("Partial credit criteria", text: $editPartialCriteria, axis: .vertical)
                    .font(.siftCallout)
                    .foregroundStyle(Color.siftInk)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, DS.Spacing.md)
    }

    private var todayLogCredit: Float? {
        viewModel.todayLogs[habit.id]?.credit
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Today")
                .font(.siftCaption)
                .foregroundStyle(Color.siftSubtle)

            HStack(spacing: DS.Spacing.sm) {
                logButton(label: "None", credit: 0, current: todayLogCredit)
                logButton(label: "Partial", credit: 0.5, current: todayLogCredit)
                logButton(label: "Full", credit: 1.0, current: todayLogCredit)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, DS.Spacing.md)
    }

    private func logButton(label: String, credit: Float, current: Float?) -> some View {
        let isSelected = logButtonSelected(credit: credit, current: current)
        return Button {
            Task {
                try? await viewModel.setLog(habitID: habit.id, credit: credit)
                await loadLogs()
            }
        } label: {
            Text(label)
                .font(.siftCallout)
                .foregroundStyle(isSelected ? Color.siftContrastLight : Color.siftInk)
                .frame(maxWidth: .infinity)
                .frame(height: DS.ButtonHeight.medium)
                .background(
                    isSelected ? Color.siftAccent : Color.siftInk.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: DS.Radius.sm)
                )
        }
        .buttonStyle(.plain)
    }

    private func logButtonSelected(credit: Float, current: Float?) -> Bool {
        let epsilon: Float = 0.01
        if abs(credit) < epsilon {
            guard let current else { return true }
            return abs(current) < epsilon
        }
        if abs(credit - 0.5) < epsilon {
            guard let current else { return false }
            return abs(current - 0.5) < epsilon
        }
        if abs(credit - 1.0) < epsilon {
            guard let current else { return false }
            return abs(current - 1.0) < epsilon
        }
        return false
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.siftSubtle)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(displayMonth, format: .dateTime.month(.wide).year())
                    .font(.siftCallout)
                    .foregroundStyle(Color.siftInk)
                Spacer()
                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isCurrentMonth ? Color.siftSubtle.opacity(0.3) : Color.siftSubtle)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(isCurrentMonth)
            }

            HStack(spacing: 0) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, d in
                    Text(d)
                        .font(.siftCaption)
                        .foregroundStyle(Color.siftSubtle)
                        .frame(maxWidth: .infinity)
                }
            }

            if isLoadingCalendar {
                SiftSkeletonShimmer {
                    HabitHeatMapSkeleton()
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.xs), count: 7), spacing: DS.Spacing.xs) {
                    ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                        if let day {
                            heatCell(for: day)
                        } else {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, DS.Spacing.md)
    }

    private var archiveButton: some View {
        Button {
            isArchiving = true
            Task {
                try? await viewModel.archive(habit)
                dismiss()
            }
        } label: {
            Text("Archive habit")
                .font(.siftCallout)
                .foregroundStyle(Color.siftSubtle)
                .frame(maxWidth: .infinity)
                .frame(height: DS.ButtonHeight.medium)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, DS.Spacing.lg)
    }

    private func heatCell(for date: Date) -> some View {
        let credit = creditForDay(date)
        return RoundedRectangle(cornerRadius: DS.Radius.xs)
            .fill(cellColor(credit: credit))
            .aspectRatio(1, contentMode: .fit)
    }

    private func cellColor(credit: Float?) -> Color {
        let epsilon: Float = 0.01
        guard let credit else {
            return Color.siftInk.opacity(0.08)
        }
        if abs(credit) < epsilon {
            return Color.siftInk.opacity(0.08)
        }
        if abs(credit - 0.5) < epsilon {
            return Color.siftAccent.opacity(0.45)
        }
        if abs(credit - 1.0) < epsilon {
            return Color.siftAccent
        }
        return Color.siftInk.opacity(0.08)
    }

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(displayMonth, equalTo: Date(), toGranularity: .month)
    }

    private func changeMonth(by value: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: value, to: displayMonth) else { return }
        if value > 0 && next > Calendar.current.startOfMonth(for: Date()) { return }
        displayMonth = Calendar.current.startOfMonth(for: next)
        Task { await loadLogs() }
    }

    /// Returns optional dates for the grid — `nil` is padding before the first day of the month.
    private var gridDays: [Date?] {
        let calendar = Calendar.current
        let monthStart = calendar.startOfMonth(for: displayMonth)
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let padding = firstWeekday - 1
        var days: [Date?] = Array(repeating: nil, count: padding)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                days.append(date)
            }
        }
        return days
    }

    private func creditForDay(_ date: Date) -> Float? {
        let str = HabitLog.dateFormatter.string(from: date)
        return logs.first(where: { $0.date == str })?.credit
    }

    private func loadLogs() async {
        if isInitialCalendarLoad {
            isLoadingCalendar = true
        }
        defer {
            isLoadingCalendar = false
            isInitialCalendarLoad = false
        }
        let cal = Calendar.current
        let monthStart = cal.startOfMonth(for: displayMonth)
        let year = cal.component(.year, from: monthStart)
        let month = cal.component(.month, from: monthStart)
        logs = (try? await viewModel.fetchLogs(habitID: habit.id, month: month, year: year)) ?? []
    }
}

