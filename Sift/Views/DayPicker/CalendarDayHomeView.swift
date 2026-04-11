import SwiftUI

/// Full-screen Today-style layout for a single calendar day (from the week picker): entry card, that day’s habit logs, current actions list.
struct CalendarDayHomeView: View {
    /// Local start-of-day for the selected date.
    let calendarDay: Date
    /// Entry id from the calendar grid (latest that day); used if the card refresh has not run yet.
    let knownEntryID: UUID?

    @Environment(\.dismiss) private var dismiss

    @State private var homeViewModel = HomeViewModel()
    @State private var habitViewModel = HabitViewModel()
    @State private var actionViewModel = ActionItemViewModel()
    @FocusState private var focusedActionItemID: UUID?
    @State private var scrollOffset: CGFloat = 0
    @State private var openSwipeRowKey: String?

    @State private var showEntry = false
    @State private var entryDestination: EntryDestination = .today
    @State private var showSettings = false

    /// Until habits/actions/entry card finish their first load, show a skeleton on the entry card.
    @State private var isEntryCardInitialLoad = true
    /// Set after the first successful load for this view instance; prevents skeleton flash on refresh.
    @State private var hasCompletedInitialLoad = false

    @State private var dayGemsWithThemes: [GemWithThemes] = []
    @State private var isDayGemsLoading = false
    /// Every entry session on this local calendar day (for aggregate gems and section visibility).
    @State private var dayEntryIDs: [UUID] = []
    @State private var gemNavigationPath = NavigationPath()
    /// Match HomeView's top-bar feather so the material fades instead of ending at a hard edge.
    private let topBarFeatherExtent: CGFloat = 32
    /// Match HomeView's heading transition so the floating bar appears only after the date block scrolls off.
    private let headingThreshold: CGFloat = 80

    private var dayStart: Date {
        Calendar.current.startOfDay(for: calendarDay)
    }

    private var isToday: Bool {
        Calendar.current.isDate(dayStart, inSameDayAs: Date())
    }

    private var isPastHeading: Bool {
        scrollOffset > headingThreshold
    }

    /// True when the day is more than 7 days in the past — entry has expired and should not be shown.
    private var isEntryExpired: Bool {
        guard let threshold = Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: Date())) else { return false }
        return dayStart < threshold
    }

    /// Gems appear whenever at least one entry row exists for this calendar day (includes gems on non-latest sessions).
    private var gemsSectionShown: Bool {
        !isEntryCardInitialLoad && !dayEntryIDs.isEmpty
    }

    /// Spacing before Habits when a Gems block is shown above it.
    private var habitsSectionLabelTop: CGFloat {
        gemsSectionShown ? DS.Spacing.lg : 0
    }

    private var actionsSectionLabelTop: CGFloat {
        let habitBlockVisible = habitViewModel.isLoading
            || !habitViewModel.activeHabits.isEmpty
            || habitViewModel.lastLoadError != nil
        if habitBlockVisible { return DS.Spacing.lg }
        if gemsSectionShown { return DS.Spacing.lg }
        return 0
    }

    private func dismissTypingFocus() {
        focusedActionItemID = nil
    }

    private func performAfterClosingSwipe(action: @escaping @MainActor () -> Void) {
        openSwipeRowKey = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(DS.animationFast) {
                action()
            }
        }
    }

    private func fetchDayEntryIDs() async -> [UUID] {
        do {
            return try await SupabaseService.shared.fetchEntryIDs(on: dayStart)
        } catch {
            return []
        }
    }

    var body: some View {
        NavigationStack(path: $gemNavigationPath) {
            scrollContent
                .overlay(alignment: .top) {
                    topBar
                }
                .background(Color.siftSurface.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { gemID in
                GemDetailView(gemID: gemID, navigationPath: $gemNavigationPath)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissTypingFocus() }
                    .font(.siftBodyMedium)
                    .tint(Color.siftAccent)
            }
        }
        .task(id: dayStart) {
            isEntryCardInitialLoad = !hasCompletedInitialLoad
            async let actions: () = actionViewModel.load(for: dayStart)
            async let habits: () = {
                do {
                    try await habitViewModel.load(for: dayStart)
                } catch {}
            }()
            if !isEntryExpired {
                await homeViewModel.refreshEntryCard(for: dayStart)
            }
            await actions
            await habits
            do {
                dayEntryIDs = try await SupabaseService.shared.fetchEntryIDs(on: dayStart)
            } catch {
                print("[CalendarDayHome] fetchEntryIDs failed: \(error)")
                dayEntryIDs = []
            }
            isEntryCardInitialLoad = false
            hasCompletedInitialLoad = true
            await loadDayGems()
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .fullScreenCover(isPresented: $showEntry) {
            EntryView(destination: entryDestination)
        }
        .onChange(of: showEntry) {
            if !showEntry {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    async let card: () = homeViewModel.refreshEntryCard(for: dayStart)
                    async let ids: [UUID] = fetchDayEntryIDs()
                    async let actions: () = actionViewModel.load(for: dayStart, showLoadingState: false)
                    let (_, newIDs, _) = await (card, ids, actions)
                    let idsChanged = newIDs != dayEntryIDs
                    dayEntryIDs = newIDs
                    await loadDayGems(showLoading: idsChanged)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .siftJournalEntitiesDidSync)) { _ in
            Task {
                await actionViewModel.load(for: dayStart, showLoadingState: false)
                do {
                    let newIDs = try await SupabaseService.shared.fetchEntryIDs(on: dayStart)
                    let idsChanged = newIDs != dayEntryIDs
                    dayEntryIDs = newIDs
                    await loadDayGems(showLoading: idsChanged)
                } catch {
                    dayEntryIDs = []
                    await loadDayGems(showLoading: false)
                }
            }
        }
    }

    private var topBar: some View {
        Group {
            if isToday {
                HStack {
                    Button {
                        dismissTypingFocus()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.siftSubtle)
                            .frame(width: 40, height: 40)
                    }
                    .glassEffect(.regular.interactive(), in: Circle())
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.top, DS.Spacing.sm)
            } else {
                pastDayTopToolbar
            }
        }
    }

    /// Matches `HomeView`’s scrolled top bar: calendar, short date, settings.
    private var pastDayTopToolbar: some View {
        let barHeight: CGFloat = DS.ButtonHeight.large
        let fadeTotal = barHeight + topBarFeatherExtent
        let solidThrough = barHeight / fadeTotal

        return ZStack(alignment: .top) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(maxWidth: .infinity)
                .frame(height: fadeTotal)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: solidThrough * 0.92),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .allowsHitTesting(false)
                .ignoresSafeArea(edges: .top)
                .opacity(isPastHeading ? 1 : 0)

            HStack(spacing: 0) {
                Group {
                    if isPastHeading {
                        Button {
                            dismissTypingFocus()
                            dismiss()
                        } label: {
                            Image(systemName: "calendar")
                                .font(.system(size: 18, weight: .medium))
                                .frame(width: 40, height: 40)
                        }
                        .glassEffect(.regular.interactive(), in: Circle())
                        .transition(.opacity.combined(with: .scale(0.85)))
                    }
                }
                .frame(width: 44)

                Spacer()

                if isPastHeading {
                    Text(pastDayToolbarTitle)
                        .font(.siftBodyMedium)
                        .foregroundStyle(Color.siftInk)
                        .transition(.opacity)
                }

                Spacer()

                Button {
                    dismissTypingFocus()
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 40, height: 40)
                }
                .glassEffect(.regular.interactive(), in: Circle())
                .frame(width: 44)
            }
            .padding(.horizontal, DS.Spacing.md)
            .frame(height: barHeight)
        }
        .animation(DS.animationFast, value: isPastHeading)
    }

    private var pastDayToolbarTitle: String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: dayStart)
        let currentYear = calendar.component(.year, from: Date())
        let base = dayStart.formatted(.dateTime.month(.abbreviated).day())
        if year != currentYear {
            return "\(base), \(year)"
        }
        return base
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 60)

                dateHeading

                if !isEntryExpired {
                    entryCard
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.top, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.lg)
                }

                HomeDayGemsSection(
                    sectionLabelTop: isEntryExpired ? DS.Spacing.lg : 0,
                    showsSection: gemsSectionShown,
                    isLoading: isDayGemsLoading,
                    gems: dayGemsWithThemes,
                    openSwipeRowKey: $openSwipeRowKey,
                    horizontalInset: DS.Spacing.md,
                    onDeleteGem: { id in await deleteDayGem(id: id) }
                )

                if habitViewModel.isLoading {
                    sectionLabel("Habits", top: habitsSectionLabelTop)
                    SiftSkeletonShimmer {
                        ForEach(0..<3, id: \.self) { _ in
                            HomeHabitRowSkeleton()
                        }
                    }
                } else if !habitViewModel.activeHabits.isEmpty || habitViewModel.lastLoadError != nil {
                    sectionLabel("Habits", top: habitsSectionLabelTop)
                    if let message = habitViewModel.lastLoadError {
                        habitLoadFailureCallout(message)
                    }
                    ForEach(habitViewModel.activeHabits) { habit in
                        SwipeRevealRow(
                            rowKey: HomeSwipeRowKeys.habit(habit.id),
                            openRowKey: $openSwipeRowKey,
                            leadingWidth: HomeScreenLayout.swipeActionButtonWidth,
                            trailingWidth: HomeScreenLayout.swipeActionButtonWidth,
                            allowsFullSwipeLeading: true,
                            allowsFullSwipeTrailing: true,
                            contentBackdrop: Color.siftSurface,
                            onFullSwipeLeading: {
                                openSwipeRowKey = nil
                                Task { try? await habitViewModel.setLog(habitID: habit.id, credit: 1.0) }
                            },
                            onFullSwipeTrailing: {
                                openSwipeRowKey = nil
                                Task { try? await habitViewModel.setLog(habitID: habit.id, credit: 0) }
                            },
                            leading: {
                                Button {
                                    openSwipeRowKey = nil
                                    Task { try? await habitViewModel.setLog(habitID: habit.id, credit: 1.0) }
                                } label: {
                                    ZStack {
                                        DiamondShape()
                                            .fill(Color.siftContrastLight)
                                        DiamondShape()
                                            .fill(Color.siftAccent)
                                            .scaleEffect(0.42)
                                    }
                                    .frame(width: 24, height: 24)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .background(Color.siftAccent)
                            },
                            trailing: {
                                Button {
                                    openSwipeRowKey = nil
                                    Task { try? await habitViewModel.setLog(habitID: habit.id, credit: 0) }
                                } label: {
                                    DiamondShape()
                                        .stroke(Color.siftContrastLight, lineWidth: 1.5)
                                        .frame(width: 24, height: 24)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .background(Color.siftDelete)
                            }
                        ) {
                            habitRow(habit)
                        }
                        .id(habit.id)
                    }
                }

                sectionLabel("Actions", top: actionsSectionLabelTop)
                if actionViewModel.isLoading {
                    SiftSkeletonShimmer {
                        ForEach(0..<4, id: \.self) { _ in
                            HomeActionRowSkeleton()
                        }
                    }
                } else {
                    ForEach(actionViewModel.activeItems) { item in
                        SwipeRevealRow(
                            rowKey: HomeSwipeRowKeys.action(item.id),
                            openRowKey: $openSwipeRowKey,
                            leadingWidth: HomeScreenLayout.swipeActionButtonWidth,
                            trailingWidth: HomeScreenLayout.swipeActionButtonWidth,
                            allowsFullSwipeLeading: true,
                            allowsFullSwipeTrailing: true,
                            contentBackdrop: Color.siftSurface,
                            onFullSwipeLeading: {
                                openSwipeRowKey = nil
                                withAnimation(DS.animationFast) {
                                    actionViewModel.complete(item)
                                }
                            },
                            onFullSwipeTrailing: {
                                openSwipeRowKey = nil
                                withAnimation(DS.animationFast) {
                                    actionViewModel.delete(item)
                                }
                            },
                            dragGestureMinimumDistance: 36,
                            swipeUsesHighPriorityGesture: false,
                            leading: {
                                Button {
                                    performAfterClosingSwipe {
                                        actionViewModel.complete(item)
                                    }
                                } label: {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(Color.siftContrastLight)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .background(Color.siftAccent)
                            },
                            trailing: {
                                Button {
                                    performAfterClosingSwipe {
                                        actionViewModel.delete(item)
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(Color.siftContrastLight)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .background(Color.siftDelete)
                            }
                        ) {
                            actionRow(item)
                        }
                        .id(HomeSwipeRowKeys.actionIdentity(item))
                    }

                    addActionButton

                    if !actionViewModel.completedItems.isEmpty {
                        sectionLabel("Completed Actions", top: DS.Spacing.lg)
                        ForEach(actionViewModel.completedItems) { item in
                            SwipeRevealRow(
                                rowKey: HomeSwipeRowKeys.action(item.id),
                                openRowKey: $openSwipeRowKey,
                                leadingWidth: HomeScreenLayout.swipeActionButtonWidth,
                                trailingWidth: HomeScreenLayout.swipeActionButtonWidth,
                                allowsFullSwipeLeading: true,
                                allowsFullSwipeTrailing: true,
                                contentBackdrop: Color.siftSurface,
                                onFullSwipeLeading: {
                                    openSwipeRowKey = nil
                                    withAnimation(DS.animationFast) {
                                        actionViewModel.uncomplete(item)
                                    }
                                },
                                onFullSwipeTrailing: {
                                    openSwipeRowKey = nil
                                    withAnimation(DS.animationFast) {
                                        actionViewModel.delete(item)
                                    }
                                },
                                dragGestureMinimumDistance: 36,
                                swipeUsesHighPriorityGesture: false,
                                leading: {
                                    Button {
                                        performAfterClosingSwipe {
                                            actionViewModel.uncomplete(item)
                                        }
                                    } label: {
                                        Image(systemName: "arrow.uturn.left")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundStyle(Color.siftInk)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .background(Color.siftInk.opacity(0.12))
                                },
                                trailing: {
                                    Button {
                                        performAfterClosingSwipe {
                                            actionViewModel.delete(item)
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundStyle(Color.siftContrastLight)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .background(Color.siftDelete)
                                }
                            ) {
                                actionRow(item)
                            }
                            .id(HomeSwipeRowKeys.actionIdentity(item))
                        }
                    }
                }

                Color.clear.frame(height: 120)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y
        } action: { _, newValue in
            scrollOffset = max(0, newValue)
        }
    }

    private var dateHeading: some View {
        Group {
            if isToday {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(dayStart, format: .dateTime.weekday(.wide))
                            .siftMicroSectionLabel()
                            .foregroundStyle(Color.siftAccent)
                        Text(dateHeadingTitle)
                            .siftTextStyle(.h1Bold)
                            .foregroundStyle(Color.siftInk)
                    }
                    Spacer()
                }
            } else {
                Button {
                    dismissTypingFocus()
                    dismiss()
                } label: {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(dayStart, format: .dateTime.weekday(.wide))
                                .siftMicroSectionLabel()
                                .foregroundStyle(Color.siftAccent)
                            HStack(alignment: .center, spacing: DS.Spacing.sm) {
                                Text(dateHeadingTitle)
                                    .siftTextStyle(.h1Bold)
                                    .foregroundStyle(Color.siftInk)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 26, weight: .medium))
                                    .foregroundStyle(Color.siftAccent)
                            }
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.top, DS.Spacing.xs)
    }

    private var dateHeadingTitle: String {
        if isToday {
            return "Today, \(dayStart.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return dayStart.formatted(.dateTime.month(.wide).day().year())
    }

    private var entryCard: some View {
        Button {
            dismissTypingFocus()
            prepareEntryDestination()
            showEntry = true
        } label: {
            Group {
                if isEntryCardInitialLoad {
                    SiftSkeletonShimmer {
                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            SiftSkeletonLine(height: 14, widthFraction: 0.45)
                            SiftSkeletonLine(height: 17, widthFraction: 0.92)
                            SiftSkeletonLine(height: 17, widthFraction: 0.78)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, DS.Spacing.xs)
                    }
                } else {
                    switch homeViewModel.entryCardState {
                    case .startPrompt:
                        Text(isToday ? "Start today's entry" : "Open entry")
                            .font(.siftBodyMedium)
                            .foregroundStyle(Color.siftSubtle)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                    case .loadingBrief:
                        SiftSkeletonShimmer {
                            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                                SiftSkeletonLine(height: 14, widthFraction: 0.45)
                                SiftSkeletonLine(height: 17, widthFraction: 0.92)
                                SiftSkeletonLine(height: 17, widthFraction: 0.78)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, DS.Spacing.xs)
                        }
                    case .brief(let phrase):
                        Text(phrase)
                            .font(.siftBody)
                            .foregroundStyle(Color.siftInk)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .padding(DS.Spacing.md)
            .frame(minHeight: 80, alignment: .center)
            .background(Color.siftCard, in: RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func prepareEntryDestination() {
        if isToday {
            entryDestination = .today
        } else if let id = homeViewModel.displayedEntryID ?? knownEntryID {
            entryDestination = .past(entryID: id, calendarDay: dayStart)
        } else {
            entryDestination = .today
        }
    }

    private func sectionLabel(_ title: String, top: CGFloat = DS.Spacing.lg) -> some View {
        Text(title)
            .siftMicroSectionLabel()
            .foregroundStyle(Color.siftAccent)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.top, top)
            .padding(.bottom, DS.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func habitLoadFailureCallout(_ message: String) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            Text(message)
                .font(.siftCallout)
                .foregroundStyle(Color.siftSubtle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry") {
                Task {
                    do {
                        try await habitViewModel.load(for: dayStart)
                    } catch {}
                }
            }
            .font(.siftCallout)
            .foregroundStyle(Color.siftAccent)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.sm)
    }

    private func habitRow(_ habit: Habit) -> some View {
        let log = habitViewModel.todayLogs[habit.id]
        let epsilon: Float = 0.01
        let isFull = log.map { abs($0.credit - 1.0) < epsilon } ?? false
        let isPartial = log.map { abs($0.credit - 0.5) < epsilon } ?? false

        let rowText: String = {
            if isFull { return habit.fullCriteria }
            if isPartial { return habit.partialCriteria }
            return habit.title
        }()

        return HStack(alignment: .center, spacing: DS.Spacing.sm) {
            habitCreditIndicator(for: log?.credit)
                .frame(width: 40, height: 40)

            Text(rowText)
                .font(.siftCallout)
                .foregroundStyle(Color.siftInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(DS.animationFast, value: rowText)
        }
        .frame(minHeight: DS.ButtonHeight.large, alignment: .center)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.horizontal, DS.Spacing.md)
        .contentShape(Rectangle())
        .onTapGesture {
            dismissTypingFocus()
            Task { try? await habitViewModel.cycleLog(habitID: habit.id) }
        }
        .modifier(SwipeRevealBlocksForegroundWhenSwipeOpen())
    }

    private func habitCreditIndicator(for credit: Float?) -> some View {
        let epsilon: Float = 0.01
        let isFull = credit.map { abs($0 - 1.0) < epsilon } ?? false
        let isPartial = credit.map { abs($0 - 0.5) < epsilon } ?? false

        return ZStack {
            DiamondShape()
                .stroke(Color.siftAccent, lineWidth: 1.5)
                .opacity(isFull ? 0 : 1)

            DiamondShape()
                .fill(Color.siftAccent)
                .opacity(isFull ? 1 : 0)

            DiamondShape()
                .fill(Color.siftContrastLight)
                .scaleEffect(0.4)
                .opacity(isFull ? 1 : 0)

            Circle()
                .fill(Color.siftAccent)
                .frame(width: 7, height: 7)
                .opacity(isPartial ? 1 : 0)
        }
        .frame(width: 40, height: 40)
        .animation(DS.animationFast, value: credit)
    }

    private func actionRow(_ item: ActionItem) -> some View {
        ActionItemRow(
            item: item,
            focusedField: $focusedActionItemID,
            onToggle: {
                dismissTypingFocus()
                withAnimation(DS.animationFast) {
                    actionViewModel.toggle(item)
                }
            },
            onContentChange: { actionViewModel.updateContent(item, content: $0) },
            onReturnCreatesNewItemBelow: item.completed ? nil : { tail in
                Task {
                    if let newItem = await actionViewModel.create(after: item, content: tail) {
                        try? await Task.sleep(for: .milliseconds(200))
                        focusedActionItemID = newItem.id
                    }
                }
            }
        )
    }

    private var addActionButton: some View {
        Button {
            dismissTypingFocus()
            Task {
                if let item = await actionViewModel.create() {
                    try? await Task.sleep(for: .milliseconds(400))
                    focusedActionItemID = item.id
                }
            }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.siftSubtle)
                    .frame(width: 24, height: 24)
                Text("New action")
                    .font(.siftCallout)
                    .foregroundStyle(Color.siftSubtle)
                Spacer()
            }
            .padding(DS.Spacing.sm)
            .padding(.horizontal, DS.Spacing.md)
        }
        .buttonStyle(.plain)
    }

    private func loadDayGems(showLoading: Bool = true) async {
        guard !dayEntryIDs.isEmpty else {
            dayGemsWithThemes = []
            isDayGemsLoading = false
            return
        }

        if showLoading { isDayGemsLoading = true }
        defer { if showLoading { isDayGemsLoading = false } }

        do {
            dayGemsWithThemes = try await SupabaseService.shared.fetchGemsWithThemes(forEntryIDs: dayEntryIDs)
        } catch {
            print("[CalendarDayHome] loadDayGems failed: \(error)")
            dayGemsWithThemes = []
        }
    }

    private func deleteDayGem(id: UUID) async {
        dismissTypingFocus()
        do {
            try await SupabaseService.shared.deleteGem(id: id)
            await loadDayGems()
        } catch {
            print("[CalendarDayHome] deleteDayGem failed: \(error)")
            await loadDayGems()
        }
    }
}
