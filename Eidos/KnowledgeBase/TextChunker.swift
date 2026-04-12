import Foundation

struct TextChunker: Sendable {
    let chunkSize: Int
    let stride: Int

    init(chunkSize: Int = 500, stride: Int = 400) {
        self.chunkSize = chunkSize
        self.stride = stride
    }

    func chunk(_ text: String) -> [String] {
        guard text.count > chunkSize else { return [text] }
        var chunks: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(String(text[start..<end]))
            guard let next = text.index(start, offsetBy: stride, limitedBy: text.endIndex),
                  next < text.endIndex else { break }
            start = next
        }
        return chunks
    }
}
