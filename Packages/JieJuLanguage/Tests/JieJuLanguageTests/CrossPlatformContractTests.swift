import Foundation
import Testing
@testable import JieJuLanguage

@Suite("Cross-platform contracts")
struct CrossPlatformContractTests {
    @Test func explanationRequestCodingKeysMatchV1Schema() throws {
        let request = ExplanationRequest(
            targetText: "The train leaves at six.",
            precedingContext: "Check the timetable.",
            followingContext: "Do not be late.",
            sourceLanguage: "English",
            explanationLanguage: "Chinese"
        )
        let encodedKeys = try keys(in: JSONEncoder().encode(request))
        let schemaKeys = try propertyKeys(in: schema(named: "explanation-request.schema.json"))

        #expect(encodedKeys == schemaKeys)
        let properties = try properties(in: schema(named: "explanation-request.schema.json"))
        #expect((properties["targetText"] as? [String: Any])?["maxLength"] as? Int == InputLimits.default.targetText)
        #expect((properties["precedingContext"] as? [String: Any])?["maxLength"] as? Int == InputLimits.default.context)
    }

    @Test func explanationCodingKeysAndLimitsMatchV1Schema() throws {
        let value = Explanation(
            translation: "火车六点出发。",
            sentenceCore: "The train leaves at six.",
            grammarPoints: [.init(text: "leaves", explanation: "一般现在时")],
            keyPhrases: [.init(text: "at six", meaning: "六点")]
        )
        let encodedKeys = try keys(in: JSONEncoder().encode(value))
        let schema = try schema(named: "explanation.schema.json")
        let schemaKeys = try propertyKeys(in: schema)
        let schemaProperties = try properties(in: schema)

        #expect(encodedKeys == schemaKeys)
        #expect((schemaProperties["grammarPoints"] as? [String: Any])?["maxItems"] as? Int == 3)
        #expect((schemaProperties["keyPhrases"] as? [String: Any])?["maxItems"] as? Int == 4)
    }

    private func schema(named name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: contractsDirectory.appendingPathComponent(name))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func properties(in schema: [String: Any]) throws -> [String: Any] {
        try #require(schema["properties"] as? [String: Any])
    }

    private func propertyKeys(in schema: [String: Any]) throws -> Set<String> {
        Set(try properties(in: schema).keys)
    }

    private func keys(in data: Data) throws -> Set<String> {
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Set(object.keys)
    }

    private var contractsDirectory: URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return root.appendingPathComponent("Shared/Contracts/v1", isDirectory: true)
    }
}
