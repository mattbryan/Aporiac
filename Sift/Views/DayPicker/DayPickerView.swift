import Foundation
import Observation
import SwiftUI
import Supabase

/// Forces `fullScreenCover` to build a fresh `CalendarDayHomeView` on every tap (new `id` each init).
struct DaySummaryToken: Identifiable {
    let id = UUID()
    let calendarDay: Date
    let knownEntryID: UUID?
}

// MARK: - View model

@MainActor
@Observable
final class DayPickerViewModel {

    private(set) var days: [DayPickerDay] = []
    private(set) var isLoading = true
    var displayMonth: Date = Calendar.current.startOfMonth(for: Date())

    private let service: SupabaseService = .shared

    private struct EntryCalendarRow: Decodable, Sendable {
        let id: UUID
        let createdAt: Date
        let hasGem: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case createdAt = "created_at"
            case hasGem = "has_gem"
        }
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }

        await service.waitForCurrentUser()
        guard let userID = service.currentUser?.id else {
            days = []
            return
        }

        let calendar = Calendar.current
        let monthStart = displayMonth
        guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            days = []
            return
        }

        let formatter = ISO8601DateFormatter()
        let rows: [EntryCalendarRow]
        do {
            rows = try await service.client
                .from("entries")
                .select("id, created_at, has_gem")
                .eq("user_id", value: userID.uuidString)
                .gte("created_at", value: formatter.string(from: monthStart))
                .lt("created_at", value: formatter.string(from: monthEnd))
                .execute()
                .value
        } catch {
            print("[DayPicker] Failed to load entries: \(error)")
            rows = []
        }

        days = buildDays(entryRows: rows, month: monthStart)
    }

    func changeMonth(by value: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: value, to: displayMonth) else { return }
        let currentMonth = Calendar.current.startOfMonth(for: Date())
        if value > 0 && next > currentMonth { return }
        displayMonth = Calendar.current.startOfMonth(for: next)
        Task { await reload() }
    }

    var isCurrentMonth: Bool {
        Calendar.current.isDate(displayMonth, equalTo: Date(), toGranularity: .month)
    }

    var gridDays: [DayPickerDay?] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: displayMonth) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: displayMonth)
        let padding = firstWeekday - 1
        var result: [DayPickerDay?] = Array(repeating: nil, count: padding)
        for dayNum in range {
            let date = calendar.date(byAdding: .day, value: dayNum - 1, to: displayMonth) ?? displayMonth
            let match = days.first(where: { calendar.isDate($0.calendarDay, inSameDayAs: date) })
            result.append(match ?? DayPickerDay(calendarDay: date, entryID: nil, hasGem: false))
        }
        return result
    }

    private func buildDays(entryRows: [EntryCalendarRow], month: Date) -> [DayPickerDay] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap { dayNum -> DayPickerDay? in
            guard let date = calendar.date(byAdding: .day, value: dayNum - 1, to: month) else { return nil }
            let sameDay = entryRows.filter { calendar.isDate($0.createdAt, inSameDayAs: date) }
            let best = sameDay.max(by: { $0.createdAt < $1.createdAt })
            return DayPickerDay(calendarDay: date, entryID: best?.id, hasGem: best?.hasGem ?? false)
        }
    }
}

// MARK: - Day model

struct DayPickerDay: Identifiable {
    let calendarDay: Date
    let entryID: UUID?
    let hasGem: Bool

    var id: Date { calendarDay }

    var hasEntry: Bool { entryID != nil }

    var daysAgo: Int {
        let today = Calendar.current.startOfDay(for: Date())
        let day = Calendar.current.startOfDay(for: calendarDay)
        return Calendar.current.dateComponents([.day], from: day, to: today).day ?? 0
    }

    var isToday: Bool { daysAgo == 0 }
    var isFuture: Bool { daysAgo < 0 }

    /// Today dismisses the sheet back to home; past days only when an entry exists.
    var isTappable: Bool { isToday || hasEntry }
}

// MARK: - View

struct DayPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = DayPickerViewModel()
    @State private var daySummaryToken: DaySummaryToken?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Calendar")
                .siftTextStyle(.h1Medium)
                .foregroundStyle(Color.siftInk)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.top, DS.Spacing.lg)

            Spacer(minLength: DS.Spacing.lg)

            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                // Month navigation
                HStack {
                    Button {
                        viewModel.changeMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.siftSubtle)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(viewModel.displayMonth, format: .dateTime.month(.wide).year())
                        .font(.siftCallout)
                        .foregroundStyle(Color.siftInk)
                    Spacer()
                    Button {
                        viewModel.changeMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(viewModel.isCurrentMonth ? Color.siftSubtle.opacity(0.3) : Color.siftSubtle)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isCurrentMonth)
                }

                // Day of week labels
                HStack(spacing: 0) {
                    ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, d in
                        Text(d)
                            .font(.siftCaption)
                            .foregroundStyle(Color.siftSubtle)
                            .frame(maxWidth: .infinity)
                    }
                }

                // Calendar grid
                if viewModel.isLoading {
                    SiftSkeletonShimmer {
                        HabitHeatMapSkeleton()
                    }
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.xs), count: 7),
                        spacing: DS.Spacing.xs
                    ) {
                        ForEach(Array(viewModel.gridDays.enumerated()), id: \.offset) { _, day in
                            if let day {
                                dayCell(day)
                            } else {
                                Color.clear
                                    .aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.md)

            Spacer(minLength: DS.Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.siftSurface.ignoresSafeArea())
        .onAppear {
            Task { await viewModel.reload() }
        }
        .fullScreenCover(item: $daySummaryToken) { token in
            CalendarDayHomeView(calendarDay: token.calendarDay, knownEntryID: token.knownEntryID)
                .id(token.id)
        }
    }

    @ViewBuilder
    private func dayCell(_ day: DayPickerDay) -> some View {
        let cell = dayCellContent(day)
        if day.isTappable {
            Button {
                if day.isToday {
                    dismiss()
                } else if let entryID = day.entryID {
                    daySummaryToken = DaySummaryToken(calendarDay: day.calendarDay, knownEntryID: entryID)
                }
            } label: {
                cell
            }
            .buttonStyle(.plain)
        } else {
            cell
        }
    }

    private func dayCellContent(_ day: DayPickerDay) -> some View {
        let fill: Color
        if day.isFuture {
            fill = Color.siftInk.opacity(0.04)
        } else if day.hasGem {
            fill = Color.siftGem
        } else if day.hasEntry {
            fill = Color.siftInk.opacity(DS.calendarDayOpacity(daysAgo: day.daysAgo))
        } else {
            fill = Color.siftInk.opacity(0.06)
        }

        let labelColor: Color = (day.hasGem || day.hasEntry) ? Color.siftContrastLight : Color.siftSubtle
        let dayNumber = Calendar.current.component(.day, from: day.calendarDay)

        return ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
                .fill(fill)
            VStack(spacing: 2) {
                Text("\(dayNumber)")
                    .font(.siftCaption)
                    .foregroundStyle(labelColor)
                if day.isToday {
                    Circle()
                        .fill(labelColor)
                        .frame(width: DS.Spacing.xs, height: DS.Spacing.xs)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .opacity(day.isFuture || (!day.hasEntry && !day.isToday) ? 0.35 : 1.0)
    }
}

#Preview {
    DayPickerView()
}
