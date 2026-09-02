import Foundation
import Testing
@testable import JieJuLanguage

@Suite struct CLIOptionsTests {
    @Test func parsesSentenceAndOverrides() throws {
        let options = try CLIOptions(arguments: ["explain", "--text", "Hello", "--before", "Before", "--after", "After", "--raw", "--model", "custom", "--url", "http://localhost:9999"])
        #expect(options.request?.targetText == "Hello")
        #expect(options.request?.precedingContext == "Before")
        #expect(options.request?.followingContext == "After")
        #expect(options.command == .explain)
        #expect(options.raw)
        #expect(options.model == "custom")
        #expect(options.baseURL.port == 9999)
    }

    @Test func parsesDeepCommand() throws {
        let options = try CLIOptions(arguments: ["deep", "--text", "私は本を読みます。", "--source-language", "Japanese", "--explanation-language", "Chinese"])
        #expect(options.command == .deep)
        #expect(options.request?.targetText == "私は本を読みます。")
        #expect(options.request?.sourceLanguage == "Japanese")
        #expect(options.request?.explanationLanguage == "Chinese")
    }

    @Test func parsesStreamCommand() throws {
        let options = try CLIOptions(arguments: ["stream", "--text", "She continued."])
        #expect(options.command == .stream)
        #expect(options.request?.targetText == "She continued.")
    }

    @Test func rejectsUnknownMissingAndConflictingArguments() {
        #expect(throws: ReadingAIError.self) { try CLIOptions(arguments: []) }
        #expect(throws: ReadingAIError.self) { try CLIOptions(arguments: ["--text"]) }
        #expect(throws: ReadingAIError.self) { try CLIOptions(arguments: ["--wat"]) }
        #expect(throws: ReadingAIError.self) { try CLIOptions(arguments: ["--text", "x", "--json", "x.json"]) }
        #expect(throws: ReadingAIError.self) { try CLIOptions(arguments: ["--text", "x", "--url", "relative"]) }
    }

    @Test func loadsJSONRequest() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "request.json")
        let expected = ExplanationRequest(targetText: "From JSON", precedingContext: "Before")
        try JSONEncoder().encode(expected).write(to: file)
        let options = try CLIOptions(arguments: ["--json", file.path])
        #expect(try options.loadRequest() == expected)
    }

    @Test func reportsMissingAndInvalidJSONFile() throws {
        let missing = try CLIOptions(arguments: ["--json", "/definitely/missing.json"])
        #expect(throws: ReadingAIError.self) { try missing.loadRequest() }
    }
}
