import SwiftUI

/// Draggable before/after slider comparing the latest goal-body and
/// current-body photos. Feature-flagged, see Config.enableBodyPhotoUpload
/// -- only reachable from ProfileView's photo section, itself gated behind
/// the same flag.
struct BodyPhotoComparisonView: View {
    let goalImage: UIImage
    let currentImage: UIImage

    @State private var sliderPosition: CGFloat = 0.5
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Image(uiImage: currentImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()

                        Image(uiImage: goalImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .mask(
                                Rectangle()
                                    .frame(width: geometry.size.width * sliderPosition)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            )

                        Rectangle()
                            .fill(.white)
                            .frame(width: 2)
                            .shadow(radius: 2)
                            .overlay(
                                Circle()
                                    .fill(.white)
                                    .frame(width: 32, height: 32)
                                    .overlay(Image(systemName: "arrow.left.and.right").font(.caption).foregroundStyle(.black))
                                    .shadow(radius: 2)
                            )
                            .position(x: geometry.size.width * sliderPosition, y: geometry.size.height / 2)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let fraction = value.location.x / geometry.size.width
                                sliderPosition = min(max(fraction, 0), 1)
                            }
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack {
                    Text(String(localized: "bodyPhotoComparison.goalLabel", defaultValue: "Goal", comment: "Body photo comparison: label under the goal photo"))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(localized: "bodyPhotoComparison.currentLabel", defaultValue: "Current", comment: "Body photo comparison: label under the current photo"))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .somaBackground()
            .navigationTitle(String(localized: "bodyPhotoComparison.navigationTitle", defaultValue: "Goal vs. Current", comment: "Body photo comparison: navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "bodyPhotoComparison.close", defaultValue: "Close", comment: "Body photo comparison: close button in the toolbar")) { dismiss() }
                }
            }
        }
    }
}

#Preview {
    BodyPhotoComparisonView(goalImage: UIImage(systemName: "person.fill")!, currentImage: UIImage(systemName: "person.fill")!)
}
