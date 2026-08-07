import SwiftUI

enum SportGoalRoute: Hashable {
    case sports
    case goals(sportID: String)
    case start(goalID: String, prefillBaseline: Double?)
    case custom(sportID: String)
}

/// Full-screen goal flow (TrainingHistoryView presentation pattern):
/// hub when a goal exists, picker otherwise; start/custom push on top.
struct SportGoalFlowView: View {
    @State private var catalog = SportCatalog()
    @State private var activeGoal: UserGoal?
    @State private var history: [UserGoal] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var path: [SportGoalRoute] = []
    /// SomaSnapshotTests only: renders a terminal state (e.g. the dark-
    /// catalog card) without the loading pass.
    private let isSeededForTesting: Bool

    init(seedCatalog: SportCatalog? = nil, seedLoadFailed: Bool = false) {
        isSeededForTesting = seedCatalog != nil || seedLoadFailed
        if isSeededForTesting {
            _catalog = State(initialValue: seedCatalog ?? SportCatalog())
            _isLoading = State(initialValue: false)
            _loadFailed = State(initialValue: seedLoadFailed)
        }
    }

    /// The goal the hub shows: the active one, else the newest paused one
    /// (a paused goal doesn't hold the active slot but stays reachable).
    private var currentGoal: UserGoal? {
        activeGoal ?? history.first { $0.status == .paused }
    }

    var body: some View {
        NavigationStack(path: $path) {
            rootContent
                .somaBackground()
                .navigationTitle("Your goal")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: SportGoalRoute.self) { route in
                    destination(for: route)
                        .somaBackground()
                }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var rootContent: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let currentGoal {
            GoalHubView(
                goal: currentGoal,
                catalog: catalog,
                history: history.filter { $0.id != currentGoal.id },
                onChanged: { Task { await load() } },
                onPickNewGoal: { path.append(.sports) },
                onNextBlock: { goalID, baseline in
                    path.append(.start(goalID: goalID, prefillBaseline: baseline))
                }
            )
        } else if !catalog.isEmpty {
            SportListView(catalog: catalog) { sport in
                path.append(.goals(sportID: sport.id))
            }
        } else {
            unavailableCard
        }
    }

    @ViewBuilder
    private func destination(for route: SportGoalRoute) -> some View {
        switch route {
        case .sports:
            SportListView(catalog: catalog) { sport in
                path.append(.goals(sportID: sport.id))
            }
        case .goals(let sportID):
            if let sport = catalog.sports.first(where: { $0.id == sportID }) {
                GoalPickerView(
                    sport: sport,
                    catalog: catalog,
                    onSelectPreset: { goal in path.append(.start(goalID: goal.id, prefillBaseline: nil)) },
                    onSelectCustom: { path.append(.custom(sportID: sportID)) }
                )
            }
        case .start(let goalID, let prefillBaseline):
            if let goal = catalog.goal(id: goalID) {
                GoalStartView(goal: goal, sport: catalog.sport(for: goal), prefillBaseline: prefillBaseline) {
                    await reloadAndPop()
                }
            }
        case .custom(let sportID):
            if let sport = catalog.sports.first(where: { $0.id == sportID }) {
                CustomGoalFormView(sport: sport) {
                    await reloadAndPop()
                }
            }
        }
    }

    /// Shown only when the flow was opened while the catalog is dark --
    /// a natural "nothing here" state, never an error.
    private var unavailableCard: some View {
        ScrollView {
            CardView {
                Text("Goals aren't available right now")
                    .font(.body.bold())
                Text(loadFailed
                    ? "Couldn't load the goal catalog. Pull down to try again."
                    : "Sport goal programs will appear here when they open up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .refreshable { await load() }
    }

    private func load() async {
        guard !isSeededForTesting else { return }
        loadFailed = false
        do {
            catalog = try await SupabaseClient.shared.fetchSportCatalog()
        } catch {
            catalog = SportCatalog()
            loadFailed = true
        }
        activeGoal = try? await SupabaseClient.shared.fetchActiveGoal()
        history = (try? await SupabaseClient.shared.fetchGoalHistory()) ?? []
        isLoading = false
    }

    private func reloadAndPop() async {
        await load()
        path.removeAll()
    }
}

#Preview {
    SportGoalFlowView()
        .environmentObject(AppState())
}
