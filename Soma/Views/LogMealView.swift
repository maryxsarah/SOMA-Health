import SwiftUI

/// Quick manual food entry -- a plain number-entry form, no photo/AI
/// parsing (that's a genuinely separate, bigger feature). Calories and
/// protein are required (the two numbers most people actually know
/// off-hand); carbs/fat are optional.
struct LogMealView: View {
    let date: String
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var calories: Int? { Int(caloriesText) }
    private var protein: Int? { Int(proteinText) }
    private var canSave: Bool { calories != nil && protein != nil && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What did you eat? (optional)", text: $label)
                }
                Section("Required") {
                    LabeledContent("Calories") {
                        TextField("kcal", text: $caloriesText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Protein") {
                        TextField("g", text: $proteinText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section("Optional") {
                    LabeledContent("Carbs") {
                        TextField("g", text: $carbsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Fat") {
                        TextField("g", text: $fatText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() async {
        guard let calories, let protein else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await SupabaseClient.shared.logMeal(
                date: date,
                label: label,
                calories: calories,
                proteinG: protein,
                carbsG: Int(carbsText),
                fatG: Int(fatText)
            )
            dismiss()
        } catch {
            errorMessage = "Couldn't save that entry. Try again."
        }
    }
}

#Preview {
    LogMealView(date: "2026-08-06")
}
