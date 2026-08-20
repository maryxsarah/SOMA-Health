import SwiftUI

/// Shared "what's in your gym?" checklist -- used by both
/// GymEquipmentQuestionView (onboarding) and ProfileView's gym-equipment
/// editor sheet, so the search/checklist/custom-add logic lives in one
/// place. 78 fixed items is too many for a flat chip cloud (the shape
/// `equipmentEditor`/`kitchenEquipmentEditor` use for their much shorter
/// lists) -- a searchable, scrollable checklist is the long-list "drop
/// down" behavior actually asked for. Not itself a ScrollView -- both
/// call sites already provide one (KitchenEquipmentQuestionView's own
/// ScrollView for onboarding, DetailSheetContent's for ProfileView),
/// same convention `equipmentEditor`/`kitchenEquipmentEditor` follow.
struct GymEquipmentPicker: View {
    @Binding var selection: Set<GymEquipmentTag>
    @Binding var customItems: [String]

    @State private var searchText = ""
    @State private var newItemText = ""

    private var filteredCatalog: [GymEquipmentTag] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return GymEquipmentTag.allCases }
        return GymEquipmentTag.allCases.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchField

            VStack(spacing: 12) {
                ForEach(filteredCatalog) { tag in
                    SurveyOptionRow(
                        title: tag.displayName,
                        systemImageName: tag.systemImageName,
                        isSelected: selection.contains(tag),
                        style: .checkbox
                    ) {
                        if selection.contains(tag) {
                            selection.remove(tag)
                        } else {
                            selection.insert(tag)
                        }
                    }
                }
                if filteredCatalog.isEmpty {
                    Text(String(localized: "gymEquipmentPicker.noMatches", defaultValue: "No matches", comment: "Shown in the gym-equipment picker when a search filters out every item"))
                        .font(.caption)
                        .foregroundStyle(SomaTokens.ink3)
                        .padding(.vertical, 8)
                }
            }

            if !customItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "gymEquipmentPicker.customSectionTitle", defaultValue: "Added by you", comment: "Section header above the user's own custom-typed gym equipment items"))
                        .font(.caption.bold())
                        .foregroundStyle(SomaTokens.ink3)
                        .padding(.top, 4)
                    ForEach(customItems, id: \.self) { name in
                        customItemRow(name)
                    }
                }
            }

            addOtherRow
        }
    }

    private func customItemRow(_ name: String) -> some View {
        HStack(spacing: 13) {
            // Always shown checked -- presence in customItems IS the
            // selection; there's no separate "added but off" state.
            // Not itself tappable (allowsHitTesting(false)): the row's
            // only interaction is the trailing delete button.
            SurveyOptionRow(title: name, systemImageName: "checkmark.seal.fill", isSelected: true, style: .checkbox) {}
                .allowsHitTesting(false)
            Button {
                customItems.removeAll { $0 == name }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(SomaTokens.ink3)
            }
            .accessibilityLabel(String(localized: "gymEquipmentPicker.removeCustomItem", defaultValue: "Remove", comment: "Accessibility label for the button that removes a user-added custom gym equipment item"))
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SomaTokens.ink3)
            TextField(String(localized: "gymEquipmentPicker.searchPlaceholder", defaultValue: "Search equipment", comment: "Search field placeholder in the gym-equipment picker"), text: $searchText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCardFlat(cornerRadius: SomaTokens.rXL)
    }

    private var addOtherRow: some View {
        HStack(spacing: 8) {
            TextField(String(localized: "gymEquipmentPicker.addPlaceholder", defaultValue: "Something else in your gym?", comment: "Placeholder for the free-text field used to add a custom gym equipment item"), text: $newItemText)
                .onSubmit(confirmAdd)
            Button(action: confirmAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(canAdd ? SomaTokens.accent : SomaTokens.ink3)
            }
            .disabled(!canAdd)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCardFlat(cornerRadius: SomaTokens.rXL)
    }

    private var canAdd: Bool {
        !newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Confirms the typed item: trims, drops if empty, dedupes
    /// case-insensitively against both the existing custom list and every
    /// fixed catalog display name (so typing "Yoga Mats" doesn't create a
    /// shadow duplicate of `.yogaMats`), appends, and clears the field --
    /// repeatable, so several items can be added in a row.
    private func confirmAdd() {
        let trimmed = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let isDuplicate = customItems.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
            || GymEquipmentTag.allCases.contains { $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame }
        if !isDuplicate {
            customItems.append(trimmed)
        }
        newItemText = ""
    }
}

#Preview {
    ScrollView {
        GymEquipmentPicker(selection: .constant([.dumbbells, .treadmills]), customItems: .constant(["Vibration plate"]))
            .padding(24)
    }
}
