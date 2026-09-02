import Foundation

public struct CLIOptions: Equatable, Sendable {
    public enum Command: Equatable, Sendable { case explain, deep, stream }
    public let command: Command
    public let request: ExplanationRequest?
    public let jsonFile: String?
    public let raw: Bool
    public let model: String
    public let baseURL: URL

    public init(arguments: [String]) throws {
        var args = arguments
        if args.first == "deep" {
            command = .deep
            args.removeFirst()
        } else if args.first == "stream" {
            command = .stream
            args.removeFirst()
        } else {
            command = .explain
            if args.first == "explain" { args.removeFirst() }
        }
        var values: [String: String] = [:]
        var flags = Set<String>()
        var index = 0
        let valueOptions = Set(["--text", "--before", "--after", "--json", "--model", "--url", "--source-language", "--explanation-language"])
        while index < args.count {
            let argument = args[index]
            if argument == "--raw" {
                flags.insert(argument)
                index += 1
            } else if valueOptions.contains(argument) {
                guard index + 1 < args.count, !args[index + 1].hasPrefix("--") else {
                    throw ReadingAIError.invalidInput("missing value for \(argument)")
                }
                values[argument] = args[index + 1]
                index += 2
            } else {
                throw ReadingAIError.invalidInput("unknown argument: \(argument)")
            }
        }

        guard !(values["--text"] != nil && values["--json"] != nil) else {
            throw ReadingAIError.invalidInput("use either --text or --json, not both")
        }
        guard values["--text"] != nil || values["--json"] != nil else {
            throw ReadingAIError.invalidInput("--text or --json is required")
        }
        let urlString = values["--url"] ?? "http://127.0.0.1:11434"
        guard let url = URL(string: urlString), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil else {
            throw ReadingAIError.invalidInput("--url must be an absolute HTTP(S) URL")
        }
        baseURL = url
        model = values["--model"] ?? OllamaDefaults.model
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReadingAIError.invalidInput("--model must not be empty")
        }
        raw = flags.contains("--raw")
        jsonFile = values["--json"]
        if let text = values["--text"] {
            request = ExplanationRequest(
                targetText: text,
                precedingContext: values["--before"],
                followingContext: values["--after"],
                sourceLanguage: values["--source-language"] ?? "English",
                explanationLanguage: values["--explanation-language"] ?? "Chinese"
            )
        } else {
            request = nil
            if values["--before"] != nil || values["--after"] != nil || values["--source-language"] != nil || values["--explanation-language"] != nil {
                throw ReadingAIError.invalidInput("context and language overrides require --text")
            }
        }
    }

    public func loadRequest(fileManager: FileManager = .default) throws -> ExplanationRequest {
        if let request { return try request.validated() }
        guard let jsonFile else { throw ReadingAIError.invalidInput("missing request") }
        guard fileManager.fileExists(atPath: jsonFile) else {
            throw ReadingAIError.invalidInput("JSON file does not exist: \(jsonFile)")
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: jsonFile))
            return try JSONDecoder().decode(ExplanationRequest.self, from: data).validated()
        } catch let error as ReadingAIError { throw error }
        catch { throw ReadingAIError.invalidInput("cannot read request JSON: \(error.localizedDescription)") }
    }
}

public struct BatchCLIOptions: Equatable, Sendable {
    public let input: String
    public let output: String
    public let report: String
    public let model: String
    public let baseURL: URL

    public init(arguments: [String]) throws {
        var args = arguments
        guard args.first == "batch" else { throw ReadingAIError.invalidInput("batch command is required") }
        args.removeFirst()
        let allowed = Set(["--input", "--output", "--report", "--model", "--url"])
        var values: [String: String] = [:]
        var index = 0
        while index < args.count {
            let option = args[index]
            guard allowed.contains(option) else { throw ReadingAIError.invalidInput("unknown batch argument: \(option)") }
            guard index + 1 < args.count, !args[index + 1].hasPrefix("--") else {
                throw ReadingAIError.invalidInput("missing value for \(option)")
            }
            guard values[option] == nil else { throw ReadingAIError.invalidInput("duplicate option: \(option)") }
            values[option] = args[index + 1]
            index += 2
        }
        guard let input = values["--input"], let output = values["--output"], let report = values["--report"] else {
            throw ReadingAIError.invalidInput("batch requires --input, --output, and --report")
        }
        let urlString = values["--url"] ?? "http://127.0.0.1:11434"
        guard let url = URL(string: urlString), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil else {
            throw ReadingAIError.invalidInput("--url must be an absolute HTTP(S) URL")
        }
        self.input = input
        self.output = output
        self.report = report
        model = values["--model"] ?? OllamaDefaults.model
        baseURL = url
    }
}
