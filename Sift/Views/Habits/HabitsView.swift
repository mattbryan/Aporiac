import SwiftUI

/// List of habits with create, edit, archive, and today’s log status.
struct HabitsView: View {
    @State private var viewModel = HabitViewModel()
    @State private var showCreateSheet = false
    @State private var selectedHabit: Habit? = nil
    @State private var editingHabit: Habit? = nil
    @State private var showArchived = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Habits")
                    .siftTextStyle(.h1Medium)
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
                LazyVStack(spacing: 0) {
                    if viewModel.isLoading {
                        SiftSkeletonShimmer {
                            ForEach(0..<5, id: \.self) { _ in
                                SiftListRowSkeleton()
                                Rectangle()
                                    .fill(Color.siftDivider)
                                    .frame(height: 1)
                                    .padding(.horizontal, 20)
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
                            Rectangle()
                                .fill(Color.siftDivider)
                                .frame(height: 1)
                                .padding(.horizontal, 20)
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
                        .padding(.horizontal, 20)
                        .padding(.vertical, DS.Spacing.md)
                        .buttonStyle(.plain)
                    }

                    if showArchived {
                        ForEach(viewModel.archivedHabits) { habit in
                            HabitRow(habit: habit, log: nil, archived: true)
                            Rectangle()
                                .fill(Color.siftDivider)
                                .frame(height: 1)
                                .padding(.horizontal, 20)
                        }
                    }
                }
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
                viewModel: viewModel,
                onEdit: { editingHabit = habit }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingHabit) { habit in
            HabitFormSheet(mode: .edit(habit)) { title, full, partial in
                Task { try? await viewModel.update(habit: habit, title: title, fullCriteria: full, partialCriteria: partial) }
            } onArchive: {
                Task { try? await viewModel.archive(habit) }
            }
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
                if !archived {
                    Self.creditDot(for: log)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, DS.Spacing.md)
            .contentShape(Rectangle())
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

        private static func dotColor(for log: HabitLog?) -> Color {
            guard let log else {
                return Color.siftInk.opacity(0.12)
            }
            if abs(log.credit - 0.5) < 0.01 {
                return Color.siftAccent.opacity(0.5)
            }
            if abs(log.credit - 1.0) < 0.01 {
                return Color.siftAccent
            }
            return Color.siftInk.opacity(0.12)
        }

        @ViewBuilder
        private static func creditDot(for log: HabitLog?) -> some View {
            Circle()
                .frame(width: 10, height: 10)
                .foregroundStyle(dotColor(for: log))
        }
    }
}

#if DEBUG
#Preview {
    HabitsView()
}
#endif
