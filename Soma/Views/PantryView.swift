import SwiftUI

/// Persistent "what I have at home" list -- a lightweight running list the
/// user keeps up to date as the fridge/pantry actually changes through the
/// week, not a form to refill each time. Feeds generate-meal-
/// recommendation's daily autopilot plan (NutritionView's "Today's meal
/// plan" card) and prefills the on-demand "What can I make?" flow
/// (MealRecommendationView). Adds/edits/removes are optimistic against
/// local state, same immediate-feel shape as NutritionView's own logRow
/// delete -- errors surface inline rather than blocking the row.
struct PantryView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var items: [PantryItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var newName = ""
    @State private var newQuantityText = ""
    @State private var newUnit = ""
    @State private var isAdding = false
    @FocusState private var nameFieldFocused: Bool

    @State private var editingItem: PantryItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isLoading {
                        SomaLoadingBar(barWidth: 200)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    } else {
                        addRow
                        listSection
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(SomaTokens.danger)
                    }
                }
                .padding(20)
            }
            .somaBackground()
            .navigationTitle(String(localized: "pantry.title", defaultValue: "Pantry", comment: "Navigation title for the persistent pantry/fridge list"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
        .sheet(item: $editingItem) { item in
            PantryItemEditView(item: item, onSave: { updated in
                await save(updated)
            })
        }
    }

    // MARK: - Add row

    private var addRow: some View {
        CardView {
            Text(String(localized: "pantry.add.heading", defaultValue: "Add what you have", comment: "Heading over the inline pantry add row"))
                .font(.subheadline.bold())
            HStack(spacing: 8) {
                TextField(String(localized: "pantry.add.namePlaceholder", defaultValue: "e.g. chicken breast", comment: "Placeholder for the pantry item name field"), text: $newName)
                    .focused($nameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { Task { await addItem() } }
                TextField(String(localized: "pantry.add.quantityPlaceholder", defaultValue: "Qty", comment: "Placeholder for the pantry item quantity field, e.g. '2'"), text: $newQuantityText)
                    .keyboardType(.decimalPad)
                    .frame(width: 52)
                TextField(String(localized: "pantry.add.unitPlaceholder", defaultValue: "Unit", comment: "Placeholder for the pantry item unit field, e.g. 'cups'"), text: $newUnit)
                    .frame(width: 64)
                Button {
                    Task { await addItem() }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(canAdd ? SomaTokens.accent : SomaTokens.ink4)
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
            }
        }
    }

    private var canAdd: Bool {
        !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAdding
    }

    // MARK: - List

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "pantry.list.title", defaultValue: "In your pantry", comment: "Title above the pantry item list"))
                .font(.subheadline.bold())
            if items.isEmpty {
                Text(String(localized: "pantry.list.empty", defaultValue: "Nothing here yet -- add what's in your fridge and pantry to get a daily meal plan automatically.", comment: "Empty state shown when the pantry has no items"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    itemRow(item)
                }
            }
        }
    }

    private func itemRow(_ item: PantryItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                editingItem = item
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(SomaTokens.ink)
                        if let caption = quantityCaption(item) {
                            Text(caption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Task { await delete(item) }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .glassCardFlat(cornerRadius: SomaTokens.rXL)
    }

    private func quantityCaption(_ item: PantryItem) -> String? {
        guard let quantity = item.quantity else { return item.unit }
        let quantityText = quantity.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(quantity)) : String(quantity)
        return [quantityText, item.unit].compactMap { $0 }.joined(separator: " ")
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        errorMessage = nil
        items = (try? await SupabaseClient.shared.fetchPantryItems()) ?? []
        isLoading = false
    }

    private func addItem() async {
        guard canAdd else { return }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let quantity = Double(newQuantityText.trimmingCharacters(in: .whitespacesAndNewlines))
        let unit = newUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        isAdding = true
        errorMessage = nil
        defer { isAdding = false }
        do {
            let created = try await SupabaseClient.shared.addPantryItem(name: name, quantity: quantity, unit: unit.isEmpty ? nil : unit)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                items.insert(created, at: 0)
            }
            newName = ""
            newQuantityText = ""
            newUnit = ""
            nameFieldFocused = true
        } catch {
            errorMessage = String(localized: "pantry.error.addFailed", defaultValue: "Couldn't add that item. Try again.", comment: "Error shown when adding a pantry item fails")
        }
    }

    private func save(_ updated: PantryItem) async {
        errorMessage = nil
        do {
            try await SupabaseClient.shared.updatePantryItem(id: updated.id, name: updated.name, quantity: updated.quantity, unit: updated.unit)
            if let index = items.firstIndex(where: { $0.id == updated.id }) {
                items[index] = updated
            }
        } catch {
            errorMessage = String(localized: "pantry.error.saveFailed", defaultValue: "Couldn't save that change. Try again.", comment: "Error shown when editing a pantry item fails")
        }
    }

    private func delete(_ item: PantryItem) async {
        errorMessage = nil
        do {
            try await SupabaseClient.shared.deletePantryItem(id: item.id)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                items.removeAll { $0.id == item.id }
            }
        } catch {
            errorMessage = String(localized: "pantry.error.deleteFailed", defaultValue: "Couldn't remove that item. Try again.", comment: "Error shown when deleting a pantry item fails")
        }
    }
}

/// Small edit sheet for one pantry item -- separate from the inline add
/// row since editing an existing item (as opposed to appending a new one)
/// benefits from a focused, deliberate "Save" step rather than firing a
/// PATCH per keystroke.
private struct PantryItemEditView: View {
    let item: PantryItem
    let onSave: (PantryItem) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var quantityText: String
    @State private var unit: String
    @State private var isSaving = false

    init(item: PantryItem, onSave: @escaping (PantryItem) async -> Void) {
        self.item = item
        self.onSave = onSave
        _name = State(initialValue: item.name)
        _quantityText = State(initialValue: item.quantity.map { $0.truncatingRemainder(dividingBy: 1) == 0 ? String(Int($0)) : String($0) } ?? "")
        _unit = State(initialValue: item.unit ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "pantry.edit.namePlaceholder", defaultValue: "Name", comment: "Placeholder for the pantry item name field in the edit sheet"), text: $name)
                    TextField(String(localized: "pantry.add.quantityPlaceholder", defaultValue: "Qty", comment: "Placeholder for the pantry item quantity field, e.g. '2'"), text: $quantityText)
                        .keyboardType(.decimalPad)
                    TextField(String(localized: "pantry.add.unitPlaceholder", defaultValue: "Unit", comment: "Placeholder for the pantry item unit field, e.g. 'cups'"), text: $unit)
                }
            }
            .navigationTitle(String(localized: "pantry.edit.title", defaultValue: "Edit item", comment: "Navigation title for the pantry item edit sheet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            isSaving = true
                            let updated = PantryItem(
                                id: item.id,
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                quantity: Double(quantityText.trimmingCharacters(in: .whitespacesAndNewlines)),
                                unit: unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : unit,
                                updatedAt: item.updatedAt
                            )
                            await onSave(updated)
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }
}

#Preview {
    PantryView()
}
