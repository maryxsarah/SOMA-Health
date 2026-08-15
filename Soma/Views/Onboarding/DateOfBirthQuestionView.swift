import SwiftUI

/// SwiftUI's native wheel DatePicker already renders exactly as a
/// rolling month/day/year picker with the standard iOS distance-fade --
/// no custom control needed to match established market UX here.
struct DateOfBirthQuestionView: View {
    let progress: Double
    @Binding var dateOfBirth: Date
    let onBack: () -> Void
    let onContinue: () -> Void

    private var maxDate: Date {
        Calendar.current.date(byAdding: .year, value: -13, to: Date()) ?? Date()
    }
    private var minDate: Date {
        Calendar.current.date(byAdding: .year, value: -100, to: Date()) ?? Date()
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(progress: progress, onBack: onBack)

            VStack(alignment: .leading, spacing: 6) {
                Text("When were you born?")
                    .font(Theme.display)
                Text("This will be taken into account when generating your daily tailored plan.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer()

            DatePicker(
                "Date of birth",
                selection: $dateOfBirth,
                in: minDate...maxDate,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .tint(SomaTokens.accent)

            Spacer()

            PillButton(title: "Continue", action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .somaBackground()
    }
}
