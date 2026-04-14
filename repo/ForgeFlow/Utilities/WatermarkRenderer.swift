import Foundation
import UIKit

enum WatermarkRenderer {
    /// Renders a watermarked preview of an image.
    /// Overlays a semi-transparent diagonal text stamp: "ForgeFlow / [username] / [date]"
    static func render(imageData: Data, username: String, date: Date = Date()) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }
        let size = image.size

        let renderer = UIGraphicsImageRenderer(size: size)
        let watermarked = renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: size))

            let stampText = "ForgeFlow / \(username) / \(DateFormatters.dateOnly.string(from: date))"
            let fontSize = max(size.width, size.height) * 0.03
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.4),
            ]

            let textSize = stampText.size(withAttributes: attributes)

            // Draw diagonal stamps across the image
            let ctx = context.cgContext
            ctx.saveGState()

            // Rotate -30 degrees
            let centerX = size.width / 2
            let centerY = size.height / 2
            ctx.translateBy(x: centerX, y: centerY)
            ctx.rotate(by: -.pi / 6)
            ctx.translateBy(x: -centerX, y: -centerY)

            let spacing = textSize.height * 4
            let diagonal = sqrt(size.width * size.width + size.height * size.height)
            let numRows = Int(diagonal / spacing) + 2
            let numCols = Int(diagonal / (textSize.width + 50)) + 2

            for row in -numRows...numRows {
                for col in -numCols...numCols {
                    let x = CGFloat(col) * (textSize.width + 50)
                    let y = centerY + CGFloat(row) * spacing
                    stampText.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
                }
            }

            ctx.restoreGState()
        }

        return watermarked.jpegData(compressionQuality: 0.85)
    }
}
