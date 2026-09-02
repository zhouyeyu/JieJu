import Foundation
import JieJuLanguage

@main
struct JieJuAILab {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments.first == "batch" {
                try await runBatch(arguments: arguments)
                return
            }
            let options = try CLIOptions(arguments: arguments)
            let request = try options.loadRequest()
            let provider = OllamaReadingAI(baseURL: options.baseURL, model: options.model)
            let clock = ContinuousClock()
            let start = clock.now
            if options.command == .deep {
                let result = try await provider.analyzeDeepWithRawResponse(request)
                let elapsed = start.duration(to: clock.now)
                if options.raw { print(result.rawResponse) }
                else { printDeep(result.analysis) }
                writeStandardError("Model: \(options.model)")
                writeStandardError("Elapsed: \(elapsed)")
                return
            }
            let result = try await provider.explainWithRawResponse(request)
            let elapsed = start.duration(to: clock.now)

            if options.raw {
                print(result.rawResponse)
            } else {
                print("Translation: \(result.explanation.translation)")
                print("Sentence core: \(result.explanation.sentenceCore)")
                print("Grammar:")
                result.explanation.grammarPoints.forEach { print("- \($0.text): \($0.explanation)") }
                print("Key phrases:")
                result.explanation.keyPhrases.forEach { print("- \($0.text): \($0.meaning)") }
            }
            writeStandardError("Model: \(options.model)")
            writeStandardError("Elapsed: \(elapsed)")
        } catch {
            writeStandardError("Error: \(error.localizedDescription)")
            writeStandardError(usage)
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func printDeep(_ analysis: DeepAnalysis) {
        print("Sentence type: \(analysis.sentenceType)")
        print("Pattern: \(analysis.sentencePattern)")
        print("Components:")
        analysis.components.forEach {
            let modifies = $0.modifies.flatMap { $0.isEmpty ? nil : " -> \($0)" } ?? ""
            print("- \($0.text) [\($0.role)]\(modifies): \($0.explanation)")
        }
        print("Clauses:")
        analysis.clauses.forEach { print("- \($0.text) [\($0.type) / \($0.function)]: \($0.explanation)") }
        print("Grammar:")
        analysis.grammarPoints.forEach { print("- \($0.text): \($0.explanation)") }
        print("Interpretation: \(analysis.interpretation)")
    }

    private static func runBatch(arguments: [String]) async throws {
        let options = try BatchCLIOptions(arguments: arguments)
        let inputURL = URL(fileURLWithPath: options.input)
        let inputs = try JSONL.decodeInputs(Data(contentsOf: inputURL))
        let provider = OllamaReadingAI(baseURL: options.baseURL, model: options.model)
        let results = await BatchProcessor(provider: provider).run(inputs)
        try JSONL.encodeResults(results).write(to: URL(fileURLWithPath: options.output), options: .atomic)
        try Data(BatchReport.markdown(results: results).utf8).write(to: URL(fileURLWithPath: options.report), options: .atomic)
        let successful = results.filter(\.jsonValid).count
        print("Processed \(results.count) items; \(successful) succeeded.")
        writeStandardError("Model: \(options.model)")
        writeStandardError("Results: \(options.output)")
        writeStandardError("Report: \(options.report)")
    }
}

private func writeStandardError(_ string: String) {
    FileHandle.standardError.write(Data("\(string)\n".utf8))
}

private let usage = """
Usage:
  JieJuAILab explain --text <sentence> [--before <text>] [--after <text>]
                    [--raw] [--model <name>] [--url <ollama-url>]
  JieJuAILab explain --json <request.json> [--raw] [--model <name>] [--url <ollama-url>]
  JieJuAILab deep --text <sentence> [--before <text>] [--after <text>]
                 [--raw] [--model <name>] [--url <ollama-url>]
  JieJuAILab batch --input <input.jsonl> --output <results.jsonl> --report <report.md>
                  [--model <name>] [--url <ollama-url>]
"""
