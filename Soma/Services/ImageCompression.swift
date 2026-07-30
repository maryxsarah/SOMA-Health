import UIKit

/// Shared resize/compress logic -- extracted from GymPhotoWorkoutView (the
/// first place this was needed) so the body-photo upload feature doesn't
/// carry a second silent copy of the same resize/compress code.
enum ImageCompression {
    static func jpeg(_ image: UIImage, maxDimension: CGFloat = 1024, quality: CGFloat = 0.6) -> Data? {
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
