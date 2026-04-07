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
    /// `true` on first frame so the grid does not flash empty before `onAppear` runs.
    private(set) var isLoading = true

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

        while service.currentUser == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let userID = service.currentUser?.id else {
            days = Self.buildDays(entryRows: [])
            return
        }

        let calendar = Calendar.current
        let now = Date()
        guard let windowStart = calendar.date(byAdding: .day, value: -10, to: now) else {
            days = Self.buildDays(entryRows: [])
            return
        }

        let formatter = ISO8601DateFormatter()
        let nowISOFormatter = ISO8601DateFormatter()
        nowISOFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let nowISO = nowISOFormatter.string(from: now)
        let unexpiredOrHasGem = "expires_at.gt.\(nowISO),has_gem.eq.true"

        let rows: [EntryCalendarRow]
        do {
            rows = try await service.client
                .from("entries")
                .select("id, created_at, has_gem")
                .eq("user_id", value: userID.uuidString)
                .gte("created_at", value: formatter.string(from: windowStart))
                .or(unexpiredOrHasGem)
                .execute()
                .value
        } catch {
            print("[DayPicker] Failed to load entries: \(error)")
            rows = []
        }

        days = Self.buildDays(entryRows: rows)
    }

    private static func buildDays(entryRows: [EntryCalendarRow]) -> [DayPickerDay] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        return (0..<7).map { index in
            let daysAgo = 6 - index
            let dayStart = calendar.date(byAdding: .day, value: -daysAgo, to: todayStart) ?? todayStart

            let sameDay = entryRows.filter { calendar.isDate($0.createdAt, inSameDayAs: dayStart) }
            let best = sameDay.max(by: { $0.createdAt < $1.createdAt })

            return DayPickerDay(
                calendarDay: dayStart,
                daysAgo: daysAgo,
                entryID: best?.id,
                hasGem: best?.hasGem ?? false
            )
        }
    }
}

// MARK: - Day model

struct DayPickerDay: Identifiable {
    let calendarDay: Date
    let daysAgo: Int
    let entryID: UUID?
    let hasGem: Bool

    var id: Date { calendarDay }

    var hasEntry: Bool { entryID != nil }

    /// Today closes the calendar sheet (returns to Home); past days only when an entry exists.
    var isTappable: Bool { daysAgo == 0 || entryID != nil }
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

            if viewModel.isLoading {
                SiftSkeletonShimmer {
                    DayPickerWeekSkeleton()
                }
                .padding(.horizontal, DS.Spacing.md)
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: DS.Spacing.xs) {
                    ForEach(viewModel.days) { day in
                        dayCell(day)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                .transaction { $0.animation = nil }
                .padding(.horizontal, DS.Spacing.md)
            }

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
        let content = cellContent(day)
        if day.isTappable {
            Button {
                if day.daysAgo == 0 {
                    dismiss()
                } else if day.entryID != nil {
                    daySummaryToken = DaySummaryToken(calendarDay: day.calendarDay, knownEntryID: day.entryID)
                }
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func cellContent(_ day: DayPickerDay) -> some View {
        let calendar = Calendar.current
        let dayNumber = calendar.component(.day, from: day.calendarDay)
        let monthAbbrev = monthAbbreviation(for: day.calendarDay)

        let fill: Color
        let labelColor: Color

        if day.hasGem {
            fill = Color.siftGem
            labelColor = Color.siftContrastLight
        } else if day.hasEntry {
            fill = Color.siftInk.opacity(DS.calendarDayOpacity(daysAgo: day.daysAgo))
            labelColor = Color.siftContrastLight
        } else {
            fill = Color.siftInk.opacity(0.06)
            labelColor = .siftSubtle
        }

        let cell = ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(fill)

            VStack(spacing: DS.Spacing.xs) {
                Text("\(dayNumber)")
                    .font(.siftCaption)
                    .foregroundStyle(labelColor)

                if day.daysAgo == 0 {
                    Circle()
                        .fill(labelColor)
                        .frame(width: DS.Spacing.xs, height: DS.Spacing.xs)
                }

                Text(monthAbbrev)
                    .font(.siftMicroBold)
                    .kerning(SiftTracking.microBold)
                    .foregroundStyle(labelColor)
            }
        }
        .opacity(emptyPastDayOpacity(for: day))
        return cell
    }

    private func emptyPastDayOpacity(for day: DayPickerDay) -> Double {
        if day.daysAgo > 0, !day.hasEntry {
            return 0.35
        }
        return 1.0
    }

    private func monthAbbreviation(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date)
    }
}

#Preview {
    DayPickerView()
}
