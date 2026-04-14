import Foundation

enum MagicBytesValidator {
    /// Validates file content against known magic bytes for allowed types.
    /// Returns the detected MIME type, or nil if unrecognized.
    static func detectMimeType(from data: Data) -> AttachmentMimeType? {
        guard data.count >= 12 else { return nil }

        let bytes = [UInt8](data.prefix(12))

        // PDF: %PDF
        if bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46 {
            return .pdf
        }

        // JPEG: FF D8 FF
        if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return .jpg
        }

        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47
            && bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A {
            return .png
        }

        // HEIC: ftyp at offset 4, then heic/heix/hevc/hevx
        if data.count >= 12 {
            let ftypBytes = [UInt8](data[4..<8])
            if ftypBytes == [0x66, 0x74, 0x79, 0x70] { // "ftyp"
                let brandBytes = [UInt8](data[8..<12])
                let brandString = String(bytes: brandBytes, encoding: .ascii) ?? ""
                if ["heic", "heix", "hevc", "hevx", "mif1"].contains(brandString) {
                    return .heic
                }
            }
        }

        // MOV: ftyp at offset 4, then qt
        if data.count >= 8 {
            let ftypBytes = [UInt8](data[4..<8])
            if ftypBytes == [0x66, 0x74, 0x79, 0x70] { // "ftyp"
                if data.count >= 12 {
                    let brandBytes = [UInt8](data[8..<12])
                    let brandString = String(bytes: brandBytes, encoding: .ascii) ?? ""
                    if brandString.hasPrefix("qt") {
                        return .mov
                    }
                }
            }
            // Also check for older MOV: "moov" or "mdat" at offset 4
            let altBytes = [UInt8](data[4..<8])
            let altString = String(bytes: altBytes, encoding: .ascii) ?? ""
            if ["moov", "mdat", "wide", "free", "skip", "pnot"].contains(altString) {
                return .mov
            }
        }

        return nil
    }

    /// Validates that the file data matches one of the allowed MIME types.
    static func validate(data: Data) -> Bool {
        return detectMimeType(from: data) != nil
    }
}
