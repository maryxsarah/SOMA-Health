import SwiftUI

/// "Affirmations" sheet (Soma Refresh 16b) -- today's generated line with
/// edit-in-place, the once-a-day "New line" regeneration, keep-to-list,
/// and the user's own list whose hearts toggle lines in and out of the
/// reminder rotation (16c). Reached from the Home affirmation widget's
/// pencil/"List" actions.
struct AffirmationsView: View {
    /// Home's pencil action lands here mid-edit instead of making the
    /// widget grow its own inline editor.
    var startEditing: Bool = false

    @Environment(\.dismiss) private var dismiss

    @State private var today: DailyAffirmation?
    @State private var lines: [AffirmationLine] = []
    /// Past days' lines still inside the 7-day Recent window (16b).
    @State private var recents: [RecentAffirmation] = []
    @State private var isLoading = true
    /// True while the LLM is actually writing (initial generation or
    /// "Generate new") -- swaps the quote for the staged progress bar.
    @State private var isGeneratingToday = false
    /// Sticky once the server reports the day's quota spent -- the footer
    /// flips to "next tomorrow" and New line disables.
    @State private var regenerationSpent = false
    /// Non-nil while editing today's line / writing a new one -- the
    /// drafts themselves, not booleans, so Cancel is a plain nil-out.
    @State private var editingDraft: String?
    @State private var addingDraft: String?
    @State private var errorMessage: String?
    @State private var showReminders = false
    @FocusState private var editorFocused: Bool

    private static func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }

    var body: some View {
        List {
            Group {
                headerRow
                todayCard
                listEyebrow
                ForEach(lines) { line in
                    lineRow(line)
                }
                addRow
                if !visibleRecents.isEmpty {
                    recentEyebrow
                    ForEach(visibleRecents) { recent in
                        recentRow(recent)
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11.5))
                        .foregroundStyle(SomaTokens.danger)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .somaSheetBackground()
        .task { await load() }
        .onDisappear {
            // Rotation/list/today edits all feed the reminder pool --
            // re-resolve today's pending pushes once on the way out
            // instead of after every micro-change.
            Task { await NotificationManager.shared.scheduleAffirmationReminders() }
        }
        .sheet(isPresented: $showReminders) {
            NavigationStack {
                AffirmationRemindersView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "profile.doneButton", defaultValue: "Done", comment: "Toolbar button dismissing a settings screen or sheet")) {
                                showReminders = false
                            }
                        }
                    }
            }
        }
    }

    // MARK: - Header (16b: close / serif title / bell + add)

    private var headerRow: some View {
        HStack(spacing: 10) {
            iconLens("xmark", size: 40) { dismiss() }
                .accessibilityLabel(String(localized: "affirmations.closeAccessibility", defaultValue: "Close", comment: "VoiceOver label for the Affirmations sheet's close button"))
            Spacer(minLength: 0)
            Text(String(localized: "affirmations.title", defaultValue: "Affirmations", comment: "Affirmations sheet title"))
                .font(SomaType.sheetTitle)
                .foregroundStyle(SomaTokens.ink)
            Spacer(minLength: 0)
            iconLens("bell", size: 40) { showReminders = true }
                .accessibilityLabel(String(localized: "affirmations.remindersAccessibility", defaultValue: "Reminder settings", comment: "VoiceOver label for the bell button opening affirmation reminder settings"))
            iconLens("plus", size: 40) { startAdding() }
                .accessibilityLabel(String(localized: "affirmations.addAccessibility", defaultValue: "Add your own line", comment: "VoiceOver label for the plus button adding a custom affirmation"))
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Today card

    @ViewBuilder
    private var todayCard: some View {
        if let editingDraft {
            editorCard(
                eyebrow: String(localized: "affirmations.editing.eyebrow", defaultValue: "Editing", comment: "Eyebrow label on the affirmation edit-in-place card"),
                draft: Binding(get: { editingDraft }, set: { self.editingDraft = $0 }),
                onSave: { Task { await saveTodayEdit() } },
                onCancel: { self.editingDraft = nil }
            )
        } else if let addingDraft {
            editorCard(
                eyebrow: String(localized: "affirmations.adding.eyebrow", defaultValue: "Your own line", comment: "Eyebrow label on the card for writing a custom affirmation"),
                draft: Binding(get: { addingDraft }, set: { self.addingDraft = $0 }),
                onSave: { Task { await saveCustomLine() } },
                onCancel: { self.addingDraft = nil }
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(String(localized: "affirmations.today.eyebrow", defaultValue: "Today", comment: "Eyebrow label on the Affirmations sheet's card showing today's generated line"))
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(SomaTokens.accent)
                    Spacer(minLength: 0)
                    if let time = today?.generatedAtTimeLabel {
                        Text(String(localized: "affirmations.today.generatedAt", defaultValue: "generated \(time)", comment: "Caption showing when today's affirmation was generated, e.g. 'generated 07:30'"))
                            .font(.system(size: 11))
                            .foregroundStyle(SomaTokens.inkPlaceholder)
                    }
                }
                if isGeneratingToday {
                    // 16b "While generating -- swaps into the card": same
                    // staged honest-hold-at-90% pattern as workout plans.
                    GenerationProgressView(
                        stages: [
                            String(localized: "affirmations.generating.stage1", defaultValue: "Reading your day…", comment: "Loading stage while Soma gathers context to write today's affirmation"),
                            String(localized: "affirmations.generating.stage2", defaultValue: "Writing today's line…", comment: "Loading stage while Soma writes today's affirmation"),
                        ],
                        estimatedSeconds: 5
                    )
                    .padding(.vertical, 8)
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else if let today {
                    Text(today.text)
                        .font(SomaType.metric(21))
                        .foregroundStyle(SomaTokens.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(String(localized: "affirmations.today.missing", defaultValue: "No line yet today -- tap Generate new to write one for you.", comment: "Today card placeholder when no affirmation has been generated yet"))
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(SomaTokens.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    actionChip(
                        String(localized: "affirmations.today.edit", defaultValue: "Edit", comment: "Chip rewriting today's affirmation in place"),
                        disabled: today == nil
                    ) {
                        editingDraft = today?.text ?? ""
                        editorFocused = true
                    }
                    generateNewChip
                    actionChip(
                        keptToday
                            ? String(localized: "affirmations.today.kept", defaultValue: "Kept", comment: "Chip state once today's affirmation is already saved to the list")
                            : String(localized: "affirmations.today.keep", defaultValue: "Keep", comment: "Chip saving today's affirmation into the personal list"),
                        icon: keptToday ? "heart.fill" : "heart",
                        disabled: today == nil || keptToday
                    ) {
                        Task { await keepToday() }
                    }
                    Spacer(minLength: 0)
                }
                Text(regenerationExhausted
                    ? String(localized: "affirmations.today.limitReachedFooter", defaultValue: "Today's new line is used up · a fresh one arrives tomorrow morning", comment: "Today card footer once the daily regeneration is spent")
                    : String(localized: "affirmations.today.limitFooter", defaultValue: "1 new generation a day · a fresh line arrives each morning", comment: "Today card footer explaining the daily generation cadence"))
                    .font(.system(size: 11))
                    .foregroundStyle(SomaTokens.inkPlaceholder)
            }
            .padding(18)
            .glassCard(cornerRadius: SomaTokens.rCard + 4)
        }
    }

    /// 16b's gel sparkle chip -- the one PRIMARY action on the card;
    /// burning the day's one regeneration deserves the loudest treatment,
    /// per the mockup's own gel styling.
    private var generateNewChip: some View {
        Button {
            Task { await regenerate() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                Text(String(localized: "affirmations.today.generateNew", defaultValue: "Generate new", comment: "Primary chip requesting a freshly generated affirmation"))
                    .font(.system(size: 12.5, weight: .bold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassGel(.blue)
        }
        .buttonStyle(.plain)
        .disabled(isGeneratingToday || regenerationExhausted)
        .opacity(regenerationExhausted ? 0.45 : 1)
        .accessibilityHint(Text(String(localized: "affirmations.today.generateNewHint", defaultValue: "Uses today's one regeneration", comment: "VoiceOver hint on the Generate new chip")))
    }

    private var keptToday: Bool {
        guard let today else { return false }
        return lines.contains { $0.text == today.text }
    }

    private var regenerationExhausted: Bool {
        regenerationSpent || today?.regenerationAvailable == false
    }

    /// Shared blue-ring editor card -- 16b's EDITING state, reused for
    /// "Write your own" so there's exactly one editing idiom on screen.
    private func editorCard(eyebrow: String, draft: Binding<String>, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow)
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(SomaTokens.accent)
            TextField(
                String(localized: "affirmations.editing.placeholder", defaultValue: "Write a line that sounds like you", comment: "Placeholder in the affirmation text editor"),
                text: draft,
                axis: .vertical
            )
            .font(.system(size: 14))
            .foregroundStyle(SomaTokens.ink)
            .lineLimit(1...4)
            .focused($editorFocused)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(SomaTokens.surface3, in: RoundedRectangle(cornerRadius: SomaTokens.rRow, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: SomaTokens.rRow, style: .continuous).strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
            HStack(spacing: 6) {
                Button(action: onSave) {
                    Text(String(localized: "affirmations.editing.save", defaultValue: "Save", comment: "Save button in the affirmation text editor"))
                        .font(.system(size: 12.5, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassGel(.blue)
                }
                .buttonStyle(.plain)
                .disabled(draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                actionChip(String(localized: "affirmations.editing.cancel", defaultValue: "Cancel", comment: "Cancel button in the affirmation text editor"), action: onCancel)
            }
        }
        .padding(18)
        .glassCard(cornerRadius: SomaTokens.rCard + 4)
        // The mockup's editing state marks the card with an accent ring.
        .overlay(
            RoundedRectangle(cornerRadius: SomaTokens.rCard + 4, style: .continuous)
                .strokeBorder(SomaTokens.accent.opacity(0.35), lineWidth: 1.5)
        )
    }

    // MARK: - The list

    private var listEyebrow: some View {
        Text(String(localized: "affirmations.list.eyebrow", defaultValue: "Your list · in rotation", comment: "Eyebrow label above the user's saved affirmation lines"))
            .font(.system(size: 10.5, weight: .bold))
            .tracking(0.7)
            .textCase(.uppercase)
            .foregroundStyle(SomaTokens.ink4)
            .padding(.leading, 4)
            .padding(.top, 6)
    }

    private func lineRow(_ line: AffirmationLine) -> some View {
        HStack(spacing: 11) {
            Text(line.text)
                .font(.system(size: 13.5))
                .foregroundStyle(line.inRotation ? SomaTokens.ink : SomaTokens.ink4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                Task { await toggleRotation(line) }
            } label: {
                Image(systemName: line.inRotation ? "heart.fill" : "heart")
                    .font(.system(size: 15))
                    .foregroundStyle(line.inRotation ? SomaTokens.accent : SomaTokens.accent.opacity(0.4))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(line.inRotation
                ? String(localized: "affirmations.list.rotationOnAccessibility", defaultValue: "In the reminder rotation. Double-tap to remove.", comment: "VoiceOver label for a heart that is currently on")
                : String(localized: "affirmations.list.rotationOffAccessibility", defaultValue: "Out of the reminder rotation. Double-tap to add.", comment: "VoiceOver label for a heart that is currently off"))
        }
        .padding(.init(top: 13, leading: 14, bottom: 13, trailing: 10))
        .glassCardFlat(cornerRadius: SomaTokens.rRow)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await delete(line) }
            } label: {
                Label(String(localized: "affirmations.list.delete", defaultValue: "Delete", comment: "Swipe action deleting a saved affirmation line"), systemImage: "trash")
            }
        }
    }

    // MARK: - Recent (16b "Recent · kept 7 days")

    /// Old daily lines still in the window, minus anything already in the
    /// list (promoted) and today's own line.
    private var visibleRecents: [RecentAffirmation] {
        recents.filter { recent in
            recent.text != today?.text && !lines.contains { $0.text == recent.text }
        }
    }

    private var recentEyebrow: some View {
        Text(String(localized: "affirmations.recent.eyebrow", defaultValue: "Recent · kept 7 days", comment: "Eyebrow label above past days' affirmations, which expire after 7 days unless kept"))
            .font(.system(size: 10.5, weight: .bold))
            .tracking(0.7)
            .textCase(.uppercase)
            .foregroundStyle(SomaTokens.ink4)
            .padding(.leading, 4)
            .padding(.top, 6)
    }

    /// Quieter than a list row (0.4 fill, gray text, date chip) -- these
    /// are passing by, not kept. Hearting one promotes it to the list for
    /// good; unhearted rows simply age out of the 7-day window.
    private func recentRow(_ recent: RecentAffirmation) -> some View {
        HStack(spacing: 11) {
            Text(recent.text)
                .font(.system(size: 13.5))
                .foregroundStyle(SomaTokens.ink3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let dateLabel = recent.dateLabel {
                Text(dateLabel)
                    .font(.system(size: 10.5))
                    .foregroundStyle(SomaTokens.inkPlaceholder)
            }
            Button {
                Task { await promoteRecent(recent) }
            } label: {
                Image(systemName: "heart")
                    .font(.system(size: 15))
                    .foregroundStyle(SomaTokens.accent.opacity(0.4))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "affirmations.recent.promoteAccessibility", defaultValue: "Keep this line in your list", comment: "VoiceOver label for the heart promoting a recent affirmation into the permanent list"))
        }
        .padding(.init(top: 13, leading: 14, bottom: 13, trailing: 10))
        .background(
            RoundedRectangle(cornerRadius: SomaTokens.rRow, style: .continuous)
                .fill(Color.white.opacity(0.4))
                .overlay(RoundedRectangle(cornerRadius: SomaTokens.rRow, style: .continuous).strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
        )
    }

    private func promoteRecent(_ recent: RecentAffirmation) async {
        errorMessage = nil
        do {
            let line = try await SupabaseClient.shared.addAffirmationLine(text: recent.text, source: "generated")
            lines.insert(line, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private var addRow: some View {
        // While a draft is open the editor card above stands in for this
        // row -- showing both would offer two competing "add" affordances.
        if addingDraft == nil {
            Button {
                startAdding()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SomaTokens.ink4)
                    Text(String(localized: "affirmations.list.addOwn", defaultValue: "Write your own…", comment: "Dashed row adding a custom affirmation line"))
                        .font(.system(size: 13))
                        .foregroundStyle(SomaTokens.inkPlaceholder)
                    Spacer(minLength: 0)
                }
                .padding(.init(top: 13, leading: 14, bottom: 13, trailing: 14))
                .background(
                    RoundedRectangle(cornerRadius: SomaTokens.rRow, style: .continuous)
                        .fill(Color.white.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SomaTokens.rRow, style: .continuous)
                        .strokeBorder(SomaTokens.accentSoft22, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Small pieces

    private func iconLens(_ systemImage: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SomaTokens.accent)
                .frame(width: size, height: size)
                .glassLens()
        }
        .buttonStyle(.plain)
    }

    /// 11c's flat chip recipe (white 0.55 + two rings + one small shadow),
    /// with an optional leading SF Symbol -- SomaChip minus the private
    /// selected-gel material this card never needs.
    private func actionChip(_ label: String, icon: String? = nil, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 12.5, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(SomaTokens.accent)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.55))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                    .overlay(Capsule().stroke(SomaTokens.hairline, lineWidth: 1).padding(-0.5))
                    .shadow(color: SomaTokens.accentSoft14, radius: 2.5, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let date = Self.todayDateString()
        async let linesFetch = (try? SupabaseClient.shared.fetchAffirmationLines()) ?? []
        async let recentsFetch = (try? SupabaseClient.shared.fetchRecentAffirmations(before: date)) ?? []
        if let cached = try? await SupabaseClient.shared.fetchTodaysAffirmation(date: date) {
            today = cached
        } else {
            // Fresh morning before the background pass ran (or first use)
            // -- generate now; the server caches per (user, date).
            isGeneratingToday = true
            defer { isGeneratingToday = false }
            do {
                today = try await SupabaseClient.shared.fetchOrGenerateDailyAffirmation(date: date)
            } catch let error as SupabaseError {
                if case .generationLimitReached = error { regenerationSpent = true } else { errorMessage = error.localizedDescription }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        lines = await linesFetch
        recents = await recentsFetch
        if startEditing, editingDraft == nil, let today {
            editingDraft = today.text
            editorFocused = true
        }
    }

    private func regenerate() async {
        guard !isGeneratingToday else { return }
        isGeneratingToday = true
        defer { isGeneratingToday = false }
        errorMessage = nil
        do {
            today = try await SupabaseClient.shared.fetchOrGenerateDailyAffirmation(date: Self.todayDateString(), forceRegenerate: true)
            // An edited line the server just replaced got auto-promoted
            // into the list server-side -- refresh so it appears at once.
            lines = (try? await SupabaseClient.shared.fetchAffirmationLines()) ?? lines
        } catch let error as SupabaseError {
            if case .generationLimitReached = error { regenerationSpent = true } else { errorMessage = error.localizedDescription }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveTodayEdit() async {
        guard var updated = today, let draft = editingDraft else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        do {
            try await SupabaseClient.shared.updateTodaysAffirmationText(date: Self.todayDateString(), text: trimmed)
            updated.text = trimmed
            today = updated
            editingDraft = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func keepToday() async {
        guard let today, !keptToday else { return }
        errorMessage = nil
        do {
            let line = try await SupabaseClient.shared.addAffirmationLine(text: today.text, source: "generated")
            lines.insert(line, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveCustomLine() async {
        guard let draft = addingDraft else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        do {
            let line = try await SupabaseClient.shared.addAffirmationLine(text: trimmed, source: "custom")
            lines.insert(line, at: 0)
            addingDraft = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startAdding() {
        editingDraft = nil
        addingDraft = ""
        editorFocused = true
    }

    private func toggleRotation(_ line: AffirmationLine) async {
        guard let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
        let newValue = !line.inRotation
        lines[index].inRotation = newValue
        do {
            try await SupabaseClient.shared.setAffirmationLineRotation(id: line.id, inRotation: newValue)
        } catch {
            lines[index].inRotation = !newValue
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ line: AffirmationLine) async {
        let backup = lines
        lines.removeAll { $0.id == line.id }
        do {
            try await SupabaseClient.shared.deleteAffirmationLine(id: line.id)
        } catch {
            lines = backup
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AffirmationsView()
}
