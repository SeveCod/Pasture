import AppKit

public enum DOCXConverter {

    public enum ConversionError: Error, LocalizedError {
        case cannotReadFile
        case emptyDocument

        public var errorDescription: String? {
            switch self {
            case .cannotReadFile: return "Cannot read document file"
            case .emptyDocument: return "Document contains no extractable text"
            }
        }
    }

    public static func convert(url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()
        let docType: NSAttributedString.DocumentType = ext == "doc" ? .docFormat : .officeOpenXML

        let attrString: NSAttributedString
        do {
            attrString = try NSAttributedString(
                data: data,
                options: [.documentType: docType],
                documentAttributes: nil
            )
        } catch {
            throw ConversionError.cannotReadFile
        }

        guard !attrString.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConversionError.emptyDocument
        }

        return attributedStringToMarkdown(attrString)
    }

    public static func convertAttributedString(_ attrStr: NSAttributedString) throws -> String {
        guard !attrStr.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConversionError.emptyDocument
        }
        return attributedStringToMarkdown(attrStr)
    }

    static func attributedStringToMarkdown(_ attrStr: NSAttributedString) -> String {
        let text = attrStr.string
        let fullRange = NSRange(location: 0, length: attrStr.length)

        var sizeWeights: [CGFloat: Int] = [:]
        attrStr.enumerateAttribute(.font, in: fullRange, options: []) { val, range, _ in
            if let font = val as? NSFont {
                sizeWeights[font.pointSize, default: 0] += range.length
            }
        }
        let bodySize = sizeWeights.max(by: { $0.value < $1.value })?.key ?? 12

        var output: [String] = []
        var pos = 0

        for paragraph in text.components(separatedBy: "\n") {
            let len = paragraph.utf16.count
            defer { pos += len + 1 }

            let trimmed = paragraph.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                output.append("")
                continue
            }

            let safeLen = min(len, max(0, attrStr.length - pos))
            guard safeLen > 0 && pos < attrStr.length else {
                output.append(trimmed)
                continue
            }
            let paraRange = NSRange(location: pos, length: safeLen)

            let heading = headingLevel(attrStr, range: paraRange, bodySize: bodySize)
            let prefix = heading > 0 ? String(repeating: "#", count: heading) + " " : ""
            let md = inlineMarkdown(attrStr, range: paraRange, bodySize: bodySize, isHeading: heading > 0)

            output.append(prefix + md)
        }

        var result: [String] = []
        var prevEmpty = false
        for line in output {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !prevEmpty { result.append("") }
                prevEmpty = true
            } else {
                result.append(line)
                prevEmpty = false
            }
        }

        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func headingLevel(_ attrStr: NSAttributedString, range: NSRange, bodySize: CGFloat) -> Int {
        guard range.length > 0 else { return 0 }

        var maxSize: CGFloat = 0
        var allBold = true

        attrStr.enumerateAttribute(.font, in: range, options: []) { val, _, _ in
            guard let font = val as? NSFont else { return }
            maxSize = max(maxSize, font.pointSize)
            if !font.fontDescriptor.symbolicTraits.contains(.bold) { allBold = false }
        }

        let ratio = maxSize / bodySize
        if ratio >= 1.8 { return 1 }
        if ratio >= 1.4 { return 2 }
        if ratio >= 1.15 && allBold { return 3 }
        return 0
    }

    static func inlineMarkdown(_ attrStr: NSAttributedString, range: NSRange, bodySize: CGFloat, isHeading: Bool) -> String {
        var parts: [String] = []

        attrStr.enumerateAttributes(in: range, options: []) { attrs, subRange, _ in
            let text = (attrStr.string as NSString).substring(with: subRange)
            guard !text.isEmpty else { return }

            var bold = false
            var italic = false

            if let font = attrs[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                bold = !isHeading && traits.contains(.bold) && font.pointSize <= bodySize * 1.15
                italic = traits.contains(.italic)
            }

            var md = text
            if bold && italic {
                md = "***\(md)***"
            } else if bold {
                md = "**\(md)**"
            } else if italic {
                md = "*\(md)*"
            }

            if let link = attrs[.link] {
                let urlString: String
                if let url = link as? URL {
                    urlString = url.absoluteString
                } else if let str = link as? String {
                    urlString = str
                } else {
                    parts.append(md)
                    return
                }
                md = "[\(md)](\(urlString))"
            }

            parts.append(md)
        }

        return parts.joined()
    }
}
