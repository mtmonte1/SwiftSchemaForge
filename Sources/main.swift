// Sources/main.swift

import ArgumentParser
import Foundation

// Errors.swift should contain: OutputFormat enum, ParsingError, GenerationError, FormattingError
// SchemaInfo.swift should contain: FunctionSchemaInfo, ParameterInfo, EnumSchemaInfo, EnumCaseInfo
// other files: SwiftSourceParser.swift, SchemaGenerator.swift, LLMFormatter.swift

// NO @main attribute
struct SwiftSchemaForge: ParsableCommand {

    // MARK: - Command Configuration
    static var configuration = CommandConfiguration(
        abstract: "Generates LLM function calling JSON schema from Swift Codable structs.",
        discussion: """
        Parses specified Swift file(s) or directories to find definitions of
        target Codable structs. Extracts properties, types, optionality, and doc comments.
        Generates JSON schema suitable for OpenAI, Grok, or Gemini function/tool calling.
        Handles nested structs (if target struct is also specified) and basic String enums.
        """,
        version: "0.4.0 (Alpha)"
    )

    // MARK: - Input Option Group
    struct InputOptions: ParsableArguments {
        @Option(name: [.short, .customLong("input-file")], help: ArgumentHelp("Path to a single input Swift source file.", valueName: "file-path"))
        var inputFile: String?
        @Option(name: [.customShort("d"), .customLong("input-dir")], help: ArgumentHelp("Path to a directory containing Swift source files to process recursively.", valueName: "dir-path"))
        var inputDirectory: String?
        mutating func validate() throws {
            guard (inputFile != nil) != (inputDirectory != nil) else {
                throw ValidationError("Please provide either --input-file (-i) or --input-dir (-d), but not both.")
            }
        }
    }
    @OptionGroup var inputOptions: InputOptions

    // MARK: - Output Option Group
    struct OutputOptions: ParsableArguments {
        @Option(name: [.short, .long], help: ArgumentHelp("Path where the single output JSON schema file should be written.", valueName: "output-path"))
        var outputFile: String // Required single file output
    }
    @OptionGroup var outputOptions: OutputOptions

    // MARK: - Other Options
    @Option(name: [.short, .long], parsing: .upToNextOption, help: ArgumentHelp("Name of the Codable Swift struct(s) to generate schema for (repeatable). Required.", valueName: "struct-name"))
    var typeName: [String]

    @Option(name: .long, help: ArgumentHelp("The output format for the JSON schema.", discussion: "Defaults to 'openai' if not specified."))
    var format: OutputFormat = .openai

    @Flag(name: .long, help: "Output the generated JSON in a human-readable, pretty-printed format.")
    var prettyPrint: Bool = false

    // MARK: - Command Execution Logic
    func run() throws {
        print("--- SwiftSchemaForge Starting ---")
        printArguments() // Calls helper below

        let swiftFilesToProcess = try collectInputFiles() // Calls helper below
        guard !swiftFilesToProcess.isEmpty else {
            print("Info: No Swift files found to process based on input options.")
            throw ExitCode.success
        }
        print("Found \(swiftFilesToProcess.count) Swift file(s) to process.")

        // Call helper, needs typeName from self
        let (uniqueParsedStructs, allParsedEnums) = try parseSourceFiles(swiftFilesToProcess)

        if uniqueParsedStructs.isEmpty && !typeName.isEmpty {
            print("\nWarning: None of the specified target structs [\(typeName.joined(separator: ", "))] were found in the processed file(s). No output generated.")
            throw ExitCode.success
        } else if uniqueParsedStructs.isEmpty {
            print("\nInfo: No target structs found or specified. No output generated.")
            throw ExitCode.success
        }

        let allGeneratedComponents = try generateSchema(infos: uniqueParsedStructs, enums: allParsedEnums) // Calls helper
        // Call helper, needs format from self
        let finalJsonObject = try formatOutput(components: allGeneratedComponents, structInfos: uniqueParsedStructs)
        // Call helper, needs prettyPrint from self
        let jsonData = try encodeToJson(object: finalJsonObject)
        // Call helper, needs outputOptions from self for the path
        try writeToFile(data: jsonData, outputPath: self.outputOptions.outputFile)

        print("\n--- SwiftSchemaForge Task Completed Successfully ---")
        // Use the value directly from the parsed OptionGroup via self
        print("Output written to: \(self.outputOptions.outputFile)")
    }

    // MARK: - Private Helper Methods for run() Logic

    /// Prints the effective arguments based on the parsed OptionGroups.
    private func printArguments() {
        // Access properties via self
        if let file = self.inputOptions.inputFile { print("Input File: \(file)") }
        if let dir = self.inputOptions.inputDirectory { print("Input Directory: \(dir)") }
        print("Target Struct Names: \(self.typeName)")
        print("Output File: \(self.outputOptions.outputFile)")
        print("Output Format: \(self.format.rawValue)")
        print("Pretty Print JSON: \(self.prettyPrint)")
        print("-------------------------------")
    }

    /// Determines the list of Swift file paths to process based on input options.
    private func collectInputFiles() throws -> [String] {
        var filePaths: [String] = []
        let fileManager = FileManager.default
        // Access via self
        if let inputFile = self.inputOptions.inputFile {
            guard fileManager.fileExists(atPath: inputFile) else { throw ValidationError("Input file not found at path: \(inputFile)") }
            guard inputFile.hasSuffix(".swift") else { throw ValidationError("Input file does not have a .swift extension: \(inputFile)") }
            filePaths.append(inputFile)
        // Access via self
        } else if let inputDirectory = self.inputOptions.inputDirectory {
            print("Scanning directory: \(inputDirectory)")
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: inputDirectory, isDirectory: &isDir), isDir.boolValue else { throw ValidationError("Input directory not found or is not a directory: \(inputDirectory)") }
            let url = URL(fileURLWithPath: inputDirectory)
            guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles], errorHandler: nil) else { throw ValidationError("Could not enumerate files in directory: \(inputDirectory)") }
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "swift" { filePaths.append(fileURL.path) }
            }
            if filePaths.isEmpty { print("Warning: No .swift files found in directory: \(inputDirectory)") }
        }
        return filePaths
    }

    /// Parses all specified Swift files and aggregates the results.
    private func parseSourceFiles(_ filePaths: [String]) throws -> (structs: [FunctionSchemaInfo], enums: [String: EnumSchemaInfo]) {
        var allParsedStructs: [FunctionSchemaInfo] = []
        var allParsedEnums: [String: EnumSchemaInfo] = [:]
        let parser = SwiftSourceParser()
        for filePath in filePaths {
            do {
                print("\nParsing file: \(filePath)...")
                 // Pass the instance property `typeName` via self
                let (parsedStructs, parsedEnums) = try parser.parse(filePath: filePath, targetStructNames: self.typeName)
                print("  Parsed \(parsedStructs.count) target struct(s), cached \(parsedEnums.count) String enum(s).")
                allParsedStructs.append(contentsOf: parsedStructs)
                allParsedEnums.merge(parsedEnums) { (_, new) in new }
            } catch let error as ParsingError {
                throw ValidationError("Parsing failed for file '\(filePath)': \(error.localizedDescription)")
            } catch {
                throw ValidationError("An unexpected error occurred parsing '\(filePath)': \(error.localizedDescription)")
            }
        }
        // Deduplicate structs
        let uniqueParsedStructs = Dictionary(allParsedStructs.map { ($0.structName, $0) }, uniquingKeysWith: { (first, _) in first }).values.map{$0}
        print("\nTotal unique target structs found across all files: \(uniqueParsedStructs.count)")
        print("Total unique enums cached across all files: \(allParsedEnums.count)")
        return (structs: Array(uniqueParsedStructs), enums: allParsedEnums) // Ensure Array type cast for safety
    }

    /// Handles generating schema components from aggregated parsed info.
    private func generateSchema(infos: [FunctionSchemaInfo], enums: [String: EnumSchemaInfo]) throws -> [String: SchemaComponents] {
        // No 'self' needed here unless generator needed config passed from self
        let generator = SchemaGenerator()
        print("\n--- Generating Schema Components (Handles Nesting & Enums) ---")
        do {
            let generated = try generator.generateSchemas(for: infos, enumCache: enums)
            if !generated.isEmpty { print("Successfully generated schema components for \(generated.count) unique target struct(s).") }
            else if !infos.isEmpty { print("Warning: Schema generation resulted in empty component set despite having parsed info.") }
            print("---------------------------------------------------\n")
            return generated
        } catch let error as GenerationError {
            throw ValidationError("Schema generation failed: \(error.localizedDescription)")
        } catch {
            throw ValidationError("An unexpected error occurred during schema generation: \(error.localizedDescription)")
        }
    }

    /// Handles formatting the generated components for the target LLM.
    private func formatOutput(components: [String: SchemaComponents], structInfos: [FunctionSchemaInfo]) throws -> Any {
        let formatter = LLMFormatter()
        // Access self.format
        print("--- Formatting for Target LLM API: \(self.format.rawValue) ---")
        do {
            let formatterInput: [LLMFormatter.InputComponent] = components.compactMap { structName, comps in
                guard let info = structInfos.first(where: { $0.structName == structName }) else {
                    print("Warning: Could not find original FunctionSchemaInfo for '\(structName)' during formatting. Skipping.")
                    return nil
                }
                return (info: info, components: comps)
            }
             // Use guard from previous fix
            guard !formatterInput.isEmpty || components.isEmpty else {
                if !structInfos.isEmpty && !components.isEmpty { throw ValidationError("Internal Error: Failed...") }
                 else { print("Info: No schema components found..."); return [] }
            }
            // Pass self.format
            let formatted = try formatter.format(components: formatterInput, as: self.format)
            print("Successfully formatted components for \(self.format.rawValue).") // use self.format
            if let array = formatted as? [Any] { print("Output structure: Array of \(array.count) elements.") }
            else if formatted is [String: Any] { print("Output structure type: Dictionary/Object.") }
            else { print("Output structure type: \(type(of: formatted))") }
            print("------------------------------------------------\n")
            return formatted
        } catch let error as FormattingError {
            throw ValidationError("LLM formatting failed: \(error.localizedDescription)")
        } catch {
            throw ValidationError("An unexpected error occurred during formatting: \(error.localizedDescription)")
        }
    }

    /// Handles encoding the final formatted object to JSON data.
    private func encodeToJson(object: Any) throws -> Data {
        print("--- Encoding to JSON ---")
        do {
            guard JSONSerialization.isValidJSONObject(object) else {
                if let array = object as? [Any], array.isEmpty {
                     print("Info: Formatted object is an empty array. Encoding empty JSON array.")
                     return Data("[]".utf8)
                } else if let dict = object as? [String:Any], dict.isEmpty {
                      print("Info: Formatted object is an empty dictionary. Encoding empty JSON object.")
                     return Data("{}".utf8)
                 }
                throw ValidationError("Internal Error: Formatted object is not valid JSON. Type: \(type(of: object))")
            }
             // Access self.prettyPrint
            let opts: JSONSerialization.WritingOptions = self.prettyPrint ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
            let jsonData = try JSONSerialization.data(withJSONObject: object, options: opts)
            print("Successfully encoded final structure to JSON data.")
            print("-----------------------\n")
            return jsonData
        } catch {
            throw ValidationError("Failed to encode the final structure to JSON: \(error.localizedDescription)")
        }
    }

    /// Handles writing the JSON data to the specified output file path.
    private func writeToFile(data: Data, outputPath: String) throws {
         if data.isEmpty { print("Info: No data generated. Skipping file write for: \(outputPath)"); return }
        let outputURL = URL(fileURLWithPath: outputPath)
        print("--- Writing JSON to File ---")
        do {
            let outputDir = outputURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true, attributes: nil)
            try data.write(to: outputURL, options: .atomic)
            print("Successfully wrote JSON schema to: \(outputURL.path)")
            print("---------------------------\n")
        } catch {
            throw ValidationError("Failed to write JSON to output file '\(outputPath)': \(error.localizedDescription)")
        }
    }
} // End of SwiftSchemaForge struct

// --- Program Entry Point ---
// Explicit call (NO @main attribute on struct)
SwiftSchemaForge.main()
