import Foundation
import UIKit

enum ImageCompressor {
    static let maxLongEdge: CGFloat = 2048

    /// Compresses an image to max 2048px on the long edge.
    /// Returns the compressed JPEG data, or nil on failure.
    static func compress(imageData: Data, maxDimension: CGFloat = maxLongEdge) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }
        let size = image.size
        let longEdge = max(size.width, size.height)

        guard longEdge > maxDimension else {
            // Already within limits, just re-encode as JPEG
            return image.jpegData(compressionQuality: 0.85)
        }

        let scale = maxDimension / longEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resized.jpegData(compressionQuality: 0.85)
    }

    /// Returns the dimensions of an image from data.
    static func dimensions(of data: Data) -> CGSize? {
        guard let image = UIImage(data: data) else { return nil }
        return image.size
    }
}
