import SwiftUI

/// List of habits with create, edit, archive, and today’s log status.
struct HabitsView: View {
    @State private var viewModel = HabitViewModel()
    @State private var showCreateSheet = false
    @State private var selectedHabit: Habit? = nil
    @State private var showArchived = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Habits")
                    .siftTextStyle(.h1Bold)
                    .foregroundStyle(Color.siftInk)
                Spacer()
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.siftInk)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, DS.Spacing.md)

            ScrollView {
                LazyVStack(spacing: DS.Spacing.sm) {
                    if viewModel.isLoading {
                        SiftSkeletonShimmer {
                            ForEach(0..<5, id: \.self) { _ in
                                SiftListRowSkeleton()
                                    .padding(.horizontal, DS.Spacing.md - 20)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.siftCard, in: RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
                            }
                        }
                    } else if viewModel.activeHabits.isEmpty {
                        Text("No habits yet.\nAdd one to begin tracking.")
                            .font(.siftCallout)
                            .foregroundStyle(Color.siftSubtle)
                            .multilineTextAlignment(.center)
                            .padding(DS.Spacing.xxl)
                    } else {
                        ForEach(viewModel.activeHabits) { habit in
                            HabitRow(habit: habit, log: viewModel.todayLogs[habit.id])
                                .onTapGesture {
                                    selectedHabit = habit
                                }
                        }
                    }

                    if !viewModel.isLoading && !viewModel.archivedHabits.isEmpty {
                        Button {
                            showArchived.toggle()
                        } label: {
                            HStack {
                                Text(showArchived ? "Hide archived" : "Show archived (\(viewModel.archivedHabits.count))")
                                    .font(.siftCallout)
                                    .foregroundStyle(Color.siftSubtle)
                                Spacer()
                                Image(systemName: showArchived ? "chevron.up" : "chevron.down")
                                    .font(.siftCaption)
                                    .foregroundStyle(Color.siftSubtle)
                            }
                        }
                        .padding(.vertical, DS.Spacing.md)
                        .buttonStyle(.plain)
                    }

                    if showArchived {
                        ForEach(viewModel.archivedHabits) { habit in
                            HabitRow(habit: habit, log: nil, archived: true)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, DS.Spacing.md)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.siftSurface.ignoresSafeArea())
        .sheet(isPresented: $showCreateSheet) {
            HabitFormSheet(mode: .create) { title, full, partial in
                Task { try? await viewModel.create(title: title, fullCriteria: full, partialCriteria: partial) }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedHabit) { habit in
            HabitDetailView(
                habit: habit,
                viewModel: viewModel
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .task {
            while SupabaseService.shared.currentUser == nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await viewModel.load()
        }
    }

    private struct HabitRow: View {
        let habit: Habit
        let log: HabitLog?
        var archived: Bool = false

        var body: some View {
            HStack(alignment: .center, spacing: DS.Spacing.md) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(habit.title)
                        .font(.siftBody)
                        .foregroundStyle(archived ? Color.siftSubtle : Color.siftInk)
                    if !archived {
                        Text(Self.logLabel(for: log))
                            .font(.siftCaption)
                            .foregroundStyle(Color.siftSubtle)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.siftCard, in: RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
        }

        private static func logLabel(for log: HabitLog?) -> String {
            guard let log else {
                return "Not logged today"
            }
            if abs(log.credit - 0.5) < 0.01 {
                return "Partial"
            }
            if abs(log.credit - 1.0) < 0.01 {
                return "Full"
            }
            return ""
        }
    }
}

#if DEBUG
#Preview {
    HabitsView()
}
#endif
