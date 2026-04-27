import Foundation

struct SkillResult: Sendable {
    let content: String
    let isError: Bool

    static func success(_ s: String) -> SkillResult { .init(content: s, isError: false) }
    static func failure(_ s: String) -> SkillResult { .init(content: s, isError: true) }
}

protocol Skill: Sendable {
    var name: String { get }
    var description: String { get }
    var parametersSchema: String { get }
    func invoke(parameters: [String: AnyCodable]) async -> SkillResult
}
