import Foundation
import UIKit

enum ThumbnailGenerator {
    static let thumbnailSize: CGFloat = 200

    /// Generates a 200px thumbnail from image data.
    /// Returns JPEG data of the thumbnail, or nil on failure.
    static func generate(from imageData: Data, maxDimension: CGFloat = thumbnailSize) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }
        let size = image.size
        let longEdge = max(size.width, size.height)
        let scale = min(maxDimension / longEdge, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let thumbnail = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return thumbnail.jpegData(compressionQuality: 0.7)
    }
}
