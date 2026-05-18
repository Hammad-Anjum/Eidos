import Foundation
import SwiftUI

/// Compact Markdown renderer for model output.
///
/// SwiftUI's plain `Text(String)` shows Markdown markers literally. This view
/// handles the subset Gemma commonly emits in chat: headings, bullets, numbered
/// lists, fenced code blocks, and inline emphasis.
struct MarkdownText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlockParser.blocks(from: markdown).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(headingFont(level: level))
                .padding(.top, level <= 2 ? 4 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .paragraph(let text):
            inlineText(text)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .unorderedListItem(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(.body.weight(.semibold))
                inlineText(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .orderedListItem(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                inlineText(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .code(let text):
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: .title3.weight(.bold)
        case 2: .headline.weight(.bold)
        default: .subheadline.weight(.semibold)
        }
    }

    private func inlineText(_ source: String) -> Text {
        do {
            let attributed = try AttributedString(
                markdown: source,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
            return Text(attributed)
        } catch {
            return Text(source)
        }
    }
}

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedListItem(String)
    case orderedListItem(number: String, text: String)
    case code(String)
}

enum MarkdownBlockParser {
    static func blocks(from markdown: String) -> [MarkdownBlock] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var inCodeBlock = false

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func flushCode() {
            blocks.append(.code(codeLines.joined(separator: "\n")))
            codeLines.removeAll(keepingCapacity: true)
        }

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                if inCodeBlock {
                    flushCode()
                }
                inCodeBlock.toggle()
                continue
            }

            if inCodeBlock {
                codeLines.append(rawLine)
                continue
            }

            guard !trimmed.isEmpty else {
                flushParagraph()
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(heading)
            } else if let item = parseUnorderedListItem(trimmed) {
                flushParagraph()
                blocks.append(.unorderedListItem(item))
            } else if let item = parseOrderedListItem(trimmed) {
                flushParagraph()
                blocks.append(item)
            } else {
                paragraphLines.append(trimmed)
            }
        }

        flushParagraph()
        if inCodeBlock || !codeLines.isEmpty {
            flushCode()
        }
        return blocks
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        let markerCount = line.prefix(while: { $0 == "#" }).count
        guard (1...4).contains(markerCount) else { return nil }

        let afterMarkers = line.dropFirst(markerCount)
        guard afterMarkers.first?.isWhitespace == true else { return nil }

        let title = afterMarkers
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard !title.isEmpty else { return nil }
        return .heading(level: markerCount, text: title)
    }

    private static func parseUnorderedListItem(_ line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            let text = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private static func parseOrderedListItem(_ line: String) -> MarkdownBlock? {
        var digits = ""
        var index = line.startIndex

        while index < line.endIndex, line[index].isNumber {
            digits.append(line[index])
            index = line.index(after: index)
        }

        guard !digits.isEmpty, index < line.endIndex else { return nil }
        guard line[index] == "." || line[index] == ")" else { return nil }

        let textStart = line.index(after: index)
        guard textStart < line.endIndex, line[textStart].isWhitespace else { return nil }

        let text = String(line[textStart...]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return .orderedListItem(number: digits, text: text)
    }
}
