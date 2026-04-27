# 2026-04-25 — Markdown Response Rendering

## Context

User reported that model output was showing raw Markdown markers in chat, e.g. `**bold**`
and `## headings`, instead of formatted text.

## Changes

- Added `MarkdownText`, a lightweight local SwiftUI Markdown renderer for model output.
- Handles headings, paragraphs, unordered lists, numbered lists, fenced code blocks, and inline emphasis.
- Wired renderer into assistant chat bubbles, streaming responses, the fallback `MessageBubble`, and Home digest text.
- Added `MarkdownBlockParserTests` covering headings, bullets, numbered lists, wrapped paragraphs, and fenced code.
- Regenerated `Eidos.xcodeproj` so the new app/test files are registered.
- Updated documented test count from 174 to 187 after the regenerated project and new tests passed.

## Verification

- `xcodebuild test -scheme Eidos -destination 'platform=iOS Simulator,name=iPhone 17' -skipMacroValidation`
- Result: 187 tests, 0 failures.

## Open Items

- Real-device visual QA still needed after sideload: confirm long formatted answers, streaming partial Markdown, and code blocks look acceptable in the chat bubble width.
