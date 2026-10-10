import Foundation
import ImageIO
import PDFKit
import Vision

enum ClipboardTextExtractor {
    static let maximumTextBytes = 32_000
    private static let maximumFileBytes = 32_000_000
    private static let maximumPages = 64
    private static let maximumDimension = 4096
    private static let tileDimension = 2048
    private static let tileOverlap = 256
    private static let maximumPixels = tileDimension * tileDimension

    enum Failure: Error { case unreadable }

    static func extract(at url: URL, isPDF: Bool) async throws -> String {
        try Task.checkCancellation()
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize,
            size <= maximumFileBytes
        else { return "" }
        if isPDF { return try await extractPDF(url) }
        guard let image = autoreleasepool(invoking: { image(at: url) }) else { throw Failure.unreadable }
        return bounded(try await recognize(image))
    }

    private static func image(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Double,
            let height = properties[kCGImagePropertyPixelHeight] as? Double,
            width.isFinite, height.isFinite, width > 0, height > 0
        else { return nil }
        let scale = min(1, sqrt(Double(maximumPixels) / width / height))
        let dimension = Int(min(Double(maximumDimension), max(1, max(width, height) * scale)))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: dimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func recognize(_ image: CGImage) async throws -> String {
        var text = ""
        for y in stride(from: 0, to: max(1, image.height - tileOverlap), by: tileDimension - tileOverlap) {
            for x in stride(from: 0, to: max(1, image.width - tileOverlap), by: tileDimension - tileOverlap) {
                try Task.checkCancellation()
                let rect = CGRect(
                    x: x, y: y, width: min(tileDimension, image.width - x),
                    height: min(tileDimension, image.height - y))
                guard let tile = image.cropping(to: rect) else { continue }
                let content = try await recognizeTile(tile)
                if !text.isEmpty, !content.isEmpty { text += "\n" }
                text += bounded(content, bytes: maximumTextBytes - text.utf8.count)
                if text.utf8.count >= maximumTextBytes - 4 { return text }
            }
        }
        return text
    }

    private static func recognizeTile(_ image: CGImage) async throws -> String {
        try Task.checkCancellation()
        // Sonoma port: Vision's `RecognizeTextRequest` / `perform(on:)` are macOS 15+, and this
        // helper tool has to run on 14. The older `VNRecognizeTextRequest` pair below is the same
        // recognition engine behind a pre-15 API, so the behaviour is unchanged. It is synchronous,
        // which is fine here: the helper runs one request in its own process and exits.
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // `minimumTextHeightFraction` is the new API's spelling; the pre-15 request calls it
        // `minimumTextHeight` (0 = accept any height, same as before).
        request.minimumTextHeight = 0
        request.automaticallyDetectsLanguage = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        try Task.checkCancellation()
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    private static func extractPDF(_ url: URL) async throws -> String {
        guard let document = PDFDocument(url: url), !document.isLocked else {
            throw Failure.unreadable
        }
        var text = ""
        for index in 0..<min(document.pageCount, maximumPages) {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }
            var content = autoreleasepool { page.string ?? "" }
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty, let image = autoreleasepool(invoking: { render(page) }) {
                content = try await recognize(image)
            }
            if !text.isEmpty, !content.isEmpty { text += "\n" }
            text += bounded(content, bytes: maximumTextBytes - text.utf8.count)
            if text.utf8.count >= maximumTextBytes - 4 { break }
        }
        return text
    }

    private static func render(_ page: PDFPage) -> CGImage? {
        guard let reference = page.pageRef else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width.isFinite, bounds.height.isFinite,
            bounds.width > 0, bounds.height > 0
        else { return nil }
        let scale = min(
            2, CGFloat(maximumDimension) / max(bounds.width, bounds.height),
            sqrt(CGFloat(maximumPixels) / bounds.width / bounds.height))
        let width = max(1, Int(bounds.width * scale))
        let height = max(1, Int(bounds.height * scale))
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.concatenate(
            reference.getDrawingTransform(
                .mediaBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(reference)
        return context.makeImage()
    }

    private static func bounded(_ text: String, bytes: Int = maximumTextBytes) -> String {
        var prefix = text.utf8.prefix(max(0, bytes))
        while !prefix.isEmpty, String(bytes: prefix, encoding: .utf8) == nil {
            prefix = prefix.dropLast()
        }
        return String(bytes: prefix, encoding: .utf8) ?? ""
    }
}
