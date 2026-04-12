import XCTest
@testable import Eidos

final class TextChunkerTests: XCTestCase {

    func testShortTextReturnsSingleChunk() {
        let chunker = TextChunker(chunkSize: 500, stride: 400)
        let text = "Hello, world."
        XCTAssertEqual(chunker.chunk(text), [text])
    }

    func testTextEqualToChunkSizeReturnsSingleChunk() {
        let chunker = TextChunker(chunkSize: 10, stride: 8)
        let text = "abcdefghij" // 10 chars
        // Length is not strictly greater than chunkSize, so the early-exit
        // returns the input unchanged.
        XCTAssertEqual(chunker.chunk(text), [text])
    }

    func testChunksOverlap() {
        let chunker = TextChunker(chunkSize: 10, stride: 8)
        let text = "abcdefghijklmnopqrstuvwxy" // 25 chars
        let chunks = chunker.chunk(text)

        XCTAssertEqual(chunks.first, "abcdefghij")
        XCTAssertGreaterThanOrEqual(chunks.count, 3)

        // Adjacent chunks should overlap by (chunkSize - stride) = 2 chars.
        for i in 0..<(chunks.count - 1) {
            let left = chunks[i]
            let right = chunks[i + 1]
            // The last 2 characters of `left` should appear at the start
            // of `right` (whenever both have at least 2 characters).
            if left.count >= 2 && right.count >= 2 {
                let leftTail = left.suffix(2)
                let rightHead = right.prefix(2)
                XCTAssertEqual(String(leftTail), String(rightHead),
                               "chunks[\(i)] and chunks[\(i+1)] failed to overlap")
            }
        }
    }

    func testChunksCoverAllInput() {
        let chunker = TextChunker(chunkSize: 10, stride: 8)
        let text = "abcdefghijklmnopqrstuvwxy"
        let chunks = chunker.chunk(text)

        // The union of chunks must reconstruct every character in `text`.
        // Reconstruct by walking the chunks and tracking forward progress.
        var reconstructed = ""
        var cursor = 0
        for chunk in chunks {
            // The chunk starts at `cursor - overlap` (after the first one).
            let overlap = max(0, reconstructed.count - cursor)
            let newSlice = chunk.dropFirst(overlap)
            reconstructed += newSlice
            cursor = reconstructed.count
        }
        XCTAssertEqual(reconstructed, text)
    }
}
