import SwiftUI

struct HomeView: View {
    @State private var showEntry = false
    @State private var showDayPicker = false
    @State private var showSettings = false
    @State private var homeViewModel = HomeViewModel()
    @State private var actionViewModel = ActionItemViewModel()
    @State private var habitViewModel = HabitViewModel()
    /// Shared with `ActionItemRow` via `@FocusState.Binding` so typing focus can be cleared from parent controls and the keyboard toolbar.
    @FocusState private var focusedActionItemID: UUID?
    @State private var scrollOffset: CGFloat = 0
    /// At most one home-row swipe may stay open; closes others when a new drag starts or another row snaps open.
    @State private var openSwipeRowKey: String?
    @State private var gemNavigationPath = NavigationPath()

    @State private var homeDayGemsShellReady = false
    @State private var homeDayEntryIDs: [UUID] = []
    @State private var homeDayGemsWithThemes: [GemWithThemes] = []
    @State private var isHomeDayGemsLoading = false

    private var homeDayStart: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var homeGemsSectionShown: Bool {
        homeDayGemsShellReady && !homeDayEntryIDs.isEmpty
    }

    private var homeHabitsSectionLabelTop: CGFloat {
        homeGemsSectionShown ? DS.Spacing.lg : 0
    }

    private var homeActionsSectionLabelTop: CGFloat {
        let habitBlockVisible = habitViewModel.isLoading
            || !habitViewModel.activeHabits.isEmpty
            || habitViewModel.lastLoadError != nil
        if habitBlockVisible { return DS.Spacing.lg }
        if homeGemsSectionShown { return DS.Spacing.lg }
        return 0
    }

    // Threshold: roughly the height of the date heading block.
    // When scrollOffset exceeds this, the heading has scrolled off screen.
    private let headingThreshold: CGFloat = 80
    /// Extra height below the bar so the blur can fade out (mask), not end in a hard line.
    private let topBarFeatherExtent: CGFloat = 32
    private var isPastHeading: Bool { scrollOffset > headingThreshold }

    private func dismissTypingFocus() {
        focusedActionItemID = nil
    }

    private func fetchHomeDayEntryIDs() async -> [UUID] {
        do {
            return try await SupabaseService.shared.fetchEntryIDs(on: homeDayStart)
        } catch {
            return []
        }
    }

    var body: some View {
        NavigationStack(path: $gemNavigationPath) {
            mainScrollView
                .overlay(alignment: .top) {
                    topBar
                }
                .background(Color.siftSurface.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showDayPicker) {
                DayPickerView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                }
            }
            .fullScreenCover(isPresented: $showEntry) {
                EntryView()
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissTypingFocus() }
                        .font(.siftBodyMedium)
                        .tint(Color.siftAccent)
                }
            }
            .task(id: homeDayStart) {
                async let actions: () = actionViewModel.load(for: Date())
                async let card: () = homeViewModel.refreshEntryCard()
                async let habits: () = {
                    do {
                        try await habitViewModel.load()
                    } catch {
                        // `lastLoadError` is set on the model for non-auth failures.
                    }
                }()
                await actions; await card; await habits
                do {
                    homeDayEntryIDs = try await SupabaseService.shared.fetchEntryIDs(on: homeDayStart)
                } catch {
                    print("[Home] fetchEntryIDs failed: \(error)")
                    homeDayEntryIDs = []
                }
                homeDayGemsShellReady = true
                await loadHomeDayGems()
            }
            .onChange(of: SupabaseService.shared.currentUser?.id) {
                Task {
                    await actionViewModel.load(for: Date())
                    await homeViewModel.refreshEntryCard()
                    do {
                        try await habitViewModel.load()
                    } catch {}
                    do {
                        homeDayEntryIDs = try await SupabaseService.shared.fetchEntryIDs(on: homeDayStart)
                    } catch {
                        homeDayEntryIDs = []
                    }
                    homeDayGemsShellReady = true
                    await loadHomeDayGems()
                }
            }
            .onChange(of: showEntry) {
                if !showEntry {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        async let card: () = homeViewModel.refreshEntryCard()
                        async let ids: [UUID] = fetchHomeDayEntryIDs()
                        async let actions: () = actionViewModel.load(for: Date())
                        let (_, newIDs, _) = await (card, ids, actions)
                        homeDayEntryIDs = newIDs
                        await loadHomeDayGems()
                    }
                }
            }
            .onChange(of: showDayPicker) {
                if !showDayPicker {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        async let card: () = homeViewModel.refreshEntryCard()
                        async let ids: [UUID] = fetchHomeDayEntryIDs()
                        async let actions: () = actionViewModel.load(for: Date())
                        async let habits: () = {
                            do {
                                try await habitViewModel.load()
                            } catch {}
                        }()
                        let (_, newIDs, _, _) = await (card, ids, actions, habits)
                        homeDayEntryIDs = newIDs
                        await loadHomeDayGems()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .siftJournalEntitiesDidSync)) { _ in
                Task {
                    await actionViewModel.load(for: Date())
                    do {
                        homeDayEntryIDs = try await SupabaseService.shared.fetchEntryIDs(on: homeDayStart)
                    } catch {
                        homeDayEntryIDs = []
                    }
                    await loadHomeDayGems()
                }
            }
                .navigationDestination(for: UUID.self) { gemID in
                    GemDetailView(gemID: gemID, navigationPath: $gemNavigationPath)
                }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
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
                // Calendar — only visible after scrolling past heading
                Group {
                    if isPastHeading {
                        Button {
                            dismissTypingFocus()
                            showDayPicker = true
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

                // "Today" label — only visible after scrolling past heading
                if isPastHeading {
                    Text("Today")
                        .font(.siftBodyMedium)
                        .foregroundStyle(Color.siftInk)
                        .transition(.opacity)
                }

                Spacer()

                // Settings — always visible
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

    // MARK: - Scroll Content

    private var mainScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Pushes content below the floating top bar
                Color.clear.frame(height: 60)

                // Date heading — the anchor for scroll state detection
                dateHeading

                // Entry card (24pt below title block per Figma rhythm)
                entryCard
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.top, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.lg)

                HomeDayGemsSection(
                    sectionLabelTop: 0,
                    showsSection: homeGemsSectionShown,
                    isLoading: isHomeDayGemsLoading,
                    gems: homeDayGemsWithThemes,
                    openSwipeRowKey: $openSwipeRowKey,
                    horizontalInset: DS.Spacing.md,
                    onDeleteGem: { id in await deleteHomeDayGem(id: id) }
                )

                // Habits
                if habitViewModel.isLoading {
                    sectionLabel("Habits", top: homeHabitsSectionLabelTop)
                    SiftSkeletonShimmer {
                        ForEach(0..<3, id: \.self) { _ in
                            HomeHabitRowSkeleton()
                        }
                    }
                } else if !habitViewModel.activeHabits.isEmpty || habitViewModel.lastLoadError != nil {
                    sectionLabel("Habits", top: homeHabitsSectionLabelTop)
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

                // Active actions
                sectionLabel("Actions", top: homeActionsSectionLabelTop)
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
                            actionViewModel.complete(item)
                        },
                        onFullSwipeTrailing: {
                            openSwipeRowKey = nil
                            actionViewModel.delete(item)
                        },
                        leading: {
                            Button {
                                openSwipeRowKey = nil
                                actionViewModel.complete(item)
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
                                openSwipeRowKey = nil
                                actionViewModel.delete(item)
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
                    // New identity when completion changes so swipe offset / row chrome reset (active vs completed).
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
                                actionViewModel.uncomplete(item)
                            },
                            onFullSwipeTrailing: {
                                openSwipeRowKey = nil
                                actionViewModel.delete(item)
                            },
                            leading: {
                                Button {
                                    openSwipeRowKey = nil
                                    actionViewModel.uncomplete(item)
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
                                    openSwipeRowKey = nil
                                    actionViewModel.delete(item)
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

                Color.clear.frame(height: 120) // padding above tab bar
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y
        } action: { _, newValue in
            scrollOffset = max(0, newValue)
        }
    }

    @ViewBuilder
    private func habitLoadFailureCallout(_ message: String) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            Text(message)
                .font(.siftCallout)
                .foregroundStyle(Color.siftSubtle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry") {
                Task {
                    do {
                        try await habitViewModel.load()
                    } catch {}
                }
            }
            .font(.siftCallout)
            .foregroundStyle(Color.siftAccent)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.sm)
    }

    // MARK: - Date Heading

    private var dateHeading: some View {
        Button {
            dismissTypingFocus()
            showDayPicker = true
        } label: {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(Date.now, format: .dateTime.weekday(.wide))
                        .siftMicroSectionLabel()
                        .foregroundStyle(Color.siftAccent)
                    HStack(alignment: .center, spacing: DS.Spacing.sm) {
                        Text("Today, \(Date.now.formatted(.dateTime.month(.abbreviated).day()))")
                            .siftTextStyle(.h1Bold)
                            .foregroundStyle(Color.siftInk)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(Color.siftAccent)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.top, DS.Spacing.xs)
            .padding(.bottom, 0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Entry Card

    private var entryCard: some View {
        Button {
            dismissTypingFocus()
            showEntry = true
        } label: {
            Group {
                switch homeViewModel.entryCardState {
                case .startPrompt:
                    Text("Start today's entry")
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
            .padding(DS.Spacing.md)
            .frame(minHeight: 80, alignment: .center)
            .background(Color.siftCard, in: RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add Action Button

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

    // MARK: - Section Label

    private func sectionLabel(_ title: String, top: CGFloat = DS.Spacing.lg) -> some View {
        Text(title)
            .siftMicroSectionLabel()
            .foregroundStyle(Color.siftAccent)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.top, top)
            .padding(.bottom, DS.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Habit Row

    private func habitRow(_ habit: Habit) -> some View {
        let log = habitViewModel.todayLogs[habit.id]
        let epsilon: Float = 0.01
        let isFull    = log.map { abs($0.credit - 1.0) < epsilon } ?? false
        let isPartial = log.map { abs($0.credit - 0.5) < epsilon } ?? false

        let rowText: String = {
            if isFull    { return habit.fullCriteria }
            if isPartial { return habit.partialCriteria }
            return habit.title
        }()

        return HStack(alignment: .center, spacing: DS.Spacing.sm) {
            creditIndicator(for: log?.credit)
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

    // MARK: - Action Row
    private func actionRow(_ item: ActionItem) -> some View {
        ActionItemRow(
            item: item,
            focusedField: $focusedActionItemID,
            onToggle: {
                dismissTypingFocus()
                actionViewModel.toggle(item)
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

    private func creditIndicator(for credit: Float?) -> some View {
        let epsilon: Float = 0.01
        let isFull = credit.map { abs($0 - 1.0) < epsilon } ?? false
        let isPartial = credit.map { abs($0 - 0.5) < epsilon } ?? false

        return ZStack {
            // Outer diamond — always present
            DiamondShape()
                .stroke(Color.siftAccent, lineWidth: 1.5)
                .opacity(isFull ? 0 : 1)

            // Full state: solid fill
            DiamondShape()
                .fill(Color.siftAccent)
                .opacity(isFull ? 1 : 0)

            // Full state: inset diamond (white, ~40% scale)
            DiamondShape()
                .fill(Color.siftContrastLight)
                .scaleEffect(0.4)
                .opacity(isFull ? 1 : 0)

            // Partial state: small filled center dot
            Circle()
                .fill(Color.siftAccent)
                .frame(width: 7, height: 7)
                .opacity(isPartial ? 1 : 0)
        }
        .frame(width: 40, height: 40)
        .animation(DS.animationFast, value: credit)
    }

    private func loadHomeDayGems(showLoading: Bool = true) async {
        guard !homeDayEntryIDs.isEmpty else {
            homeDayGemsWithThemes = []
            isHomeDayGemsLoading = false
            return
        }

        if showLoading { isHomeDayGemsLoading = true }
        defer { if showLoading { isHomeDayGemsLoading = false } }

        do {
            homeDayGemsWithThemes = try await SupabaseService.shared.fetchGemsWithThemes(forEntryIDs: homeDayEntryIDs)
        } catch {
            print("[Home] loadHomeDayGems failed: \(error)")
            homeDayGemsWithThemes = []
        }
    }

    private func deleteHomeDayGem(id: UUID) async {
        dismissTypingFocus()
        do {
            try await SupabaseService.shared.deleteGem(id: id)
            await loadHomeDayGems()
        } catch {
            print("[Home] deleteHomeDayGem failed: \(error)")
            await loadHomeDayGems()
        }
    }
}

// MARK: - Settings (staging)

/// Placeholder settings surface; expand when subscription and account flows land.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("selectedPhilosophies") private var selectedPhilosophiesRaw: String = "stoicism"

    @AppStorage(AppColorSchemeOverride.storageKey)
    private var colorSchemeRaw: String = AppColorSchemeOverride.system.rawValue

    private var selectedPhilosophies: Set<Philosophy> {
        get {
            Set(selectedPhilosophiesRaw.split(separator: ",").compactMap { Philosophy(rawValue: String($0)) })
        }
        set {
            selectedPhilosophiesRaw = newValue.map(\.rawValue).joined(separator: ",")
        }
    }

    private func togglePhilosophy(_ philosophy: Philosophy) {
        var next = selectedPhilosophies
        if next.contains(philosophy) {
            guard next.count > 1 else { return }
            next.remove(philosophy)
        } else {
            next.insert(philosophy)
        }
        selectedPhilosophiesRaw = next.map(\.rawValue).joined(separator: ",")
    }

    private var appearanceSelection: Binding<AppColorSchemeOverride> {
        Binding(
            get: { AppColorSchemeOverride(rawValue: colorSchemeRaw) ?? .system },
            set: { colorSchemeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section {
                Text("Each day, one of the schools of thought below shapes your entry prompt. Select the ones that resonate — the more you choose, the more variety you'll encounter.")
                    .font(.siftCallout)
                    .foregroundStyle(Color.siftSubtle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(Philosophy.allCases) { philosophy in
                    Button {
                        togglePhilosophy(philosophy)
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: DS.Spacing.xs / 2) {
                                Text(philosophy.title)
                                    .font(.siftBody)
                                    .foregroundStyle(Color.siftInk)
                                Text(philosophy.description)
                                    .font(.siftCallout)
                                    .foregroundStyle(Color.siftSubtle)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: DS.Spacing.sm)
                            if selectedPhilosophies.contains(philosophy) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.siftAccent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Philosophies")
            }

            Section {
                Picker("Appearance", selection: appearanceSelection) {
                    ForEach(AppColorSchemeOverride.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Design system")
            } footer: {
                Text("Override light or dark mode to test adaptive colors. System follows your device setting.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

#Preview {
    HomeView()
}
