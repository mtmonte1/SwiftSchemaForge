// Sources/main.swift

import ArgumentParser
import Foundation

// --- Top-Level Enum Definition ---
// OutputFormat enum is defined in Errors.swift

// Use the @main attribute for the entry point

struct SwiftSchemaForge: ParsableCommand {

    // MARK: - Command Configuration
    static var configuration = CommandConfiguration(
        abstract: "Generates LLM function calling JSON schema from Swift Codable structs.",
        discussion: """
        Parses specified Swift file(s) to find definitions of target Codable structs.
        Extracts properties, types, optionality, and doc comments.
        Generates JSON schema suitable for OpenAI, Grok, or Gemini function/tool calling.
        Handles nested structs (if target struct is also specified) and basic String enums.
        """,
        version: "0.3.0 (Alpha)"
    )

    // MARK: - Command Line Arguments & Options
    @Option(name: [.short, .long], help: ArgumentHelp("Path to the input Swift source file.", valueName: "file-path"))
    var inputFile: String

    @Option(name: [.short, .long], parsing: .upToNextOption, help: ArgumentHelp("Name of the Codable Swift struct(s) to generate schema for (repeatable).", valueName: "struct-name"))
    var typeName: [String]

    @Option(name: [.short, .long], help: ArgumentHelp("Path where the output JSON schema file should be written.", valueName: "output-path"))
    var outputFile: String

    @Option(name: .long, help: ArgumentHelp("The output format for the JSON schema.", discussion: "Defaults to 'openai' if not specified."))
    var format: OutputFormat = .openai

    @Flag(name: .long, help: "Output the generated JSON in a human-readable, pretty-printed format.")
    var prettyPrint: Bool = false

    // MARK: - Command Execution Logic
    func run() throws {
        print("--- SwiftSchemaForge Starting ---")
        printArgs()

        // Call helper methods for each step
        let (parsedSchemaInfos, parsedEnumCache) = try parseSource()

        if parsedSchemaInfos.isEmpty && !typeName.isEmpty {
            print("Warning: No target structs specified via --type-name were found in '\(inputFile)'. No output generated.")
            // Exit gracefully if no targets were found, despite being requested.
             // Comment out the line below if you want it to proceed and potentially write an empty file.
             throw ExitCode.success // Indicate success, but nothing to do. Or could be specific exit code.
        } else if parsedSchemaInfos.isEmpty {
            print("Info: No target structs found or specified. No output generated.")
             throw ExitCode.success
        }

        let allGeneratedComponents = try generateSchema(infos: parsedSchemaInfos, enums: parsedEnumCache)
        let finalJsonObject = try formatOutput(components: allGeneratedComponents, structInfos: parsedSchemaInfos)
        let jsonData = try encodeToJson(object: finalJsonObject)
        try writeToFile(data: jsonData)

        print("--- SwiftSchemaForge Task Completed Successfully ---")
    }

    // MARK: - Private Helper Methods for run() Logic

    /// Prints the parsed command-line arguments.
    private func printArgs() {
        print("Input Swift File: \(inputFile)")
        print("Target Struct Names: \(typeName)")
        print("Output JSON File: \(outputFile)")
        print("Output Format: \(format.rawValue)")
        print("Pretty Print JSON: \(prettyPrint)")
        print("-------------------------------")
    }

    /// Handles parsing the source file.
    private func parseSource() throws -> (structs: [FunctionSchemaInfo], enums: [String: EnumSchemaInfo]) {
        let parser = SwiftSourceParser()
        do {
            print("Parsing Swift file: \(inputFile)...")
            let result = try parser.parse(filePath: inputFile, targetStructNames: typeName)
            print("Successfully parsed \(result.structs.count) target struct(s) and cached \(result.enums.count) String enums.")
            return result
        } catch let error as ParsingError {
            throw ValidationError("Parsing failed: \(error.localizedDescription)")
        } catch {
            throw ValidationError("An unexpected error occurred during parsing: \(error.localizedDescription)")
        }
    }

    /// Handles generating schema components from parsed info.
    private func generateSchema(infos: [FunctionSchemaInfo], enums: [String: EnumSchemaInfo]) throws -> [String: SchemaComponents] {
        let generator = SchemaGenerator()
        print("\n--- Generating Schema Components (Handles Nesting & Enums) ---")
        do {
            let generated = try generator.generateSchemas(for: infos, enumCache: enums)
            // Check if generator returned empty results despite having input infos
            if generated.isEmpty && !infos.isEmpty {
                print("Warning: Schema generation resulted in empty component set despite having parsed info.")
            } else if !generated.isEmpty{
                 print("Successfully generated schema components for \(generated.count) target struct(s).")
            }
             // Suppress detailed print unless debugging is needed
             // print("Generated Components Map: \(generated)")
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
        print("--- Formatting for Target LLM API: \(format.rawValue) ---")
        do {
            let formatterInput: [LLMFormatter.InputComponent] = components.compactMap { structName, comps in
                guard let info = structInfos.first(where: { $0.structName == structName }) else {
                    print("Warning: Could not find original FunctionSchemaInfo for '\(structName)' during formatting. Skipping.")
                    return nil
                }
                return (info: info, components: comps)
            }

            // Handle cases where formatting might result in no usable input
            // (e.g., if parsing found structs but generation failed for all, components would be empty)
             if formatterInput.isEmpty && !components.isEmpty {
                 throw ValidationError("Internal Error: Failed to gather components for formatting. Generation results might be inconsistent.")
             } else if formatterInput.isEmpty {
                  print("Info: No valid schema components found to format.")
                  // Return an empty structure appropriate for the format (e.g., empty array)
                  // This allows encoding/writing to proceed gracefully, resulting in empty output file.
                  switch format {
                       case .openai, .grok, .gemini: return [] // All current formats expect an array
                  }
             }

            let formatted = try formatter.format(components: formatterInput, as: format)
            print("Successfully formatted components for \(format.rawValue).")
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
            // Check if object is actually convertible (e.g., it might be empty array)
            guard JSONSerialization.isValidJSONObject(object) else {
                 // If it's an empty array/dict, we can often serialize it anyway or return empty Data
                 if let array = object as? [Any], array.isEmpty {
                     print("Info: Formatted object is an empty array. Encoding empty JSON array.")
                     return try JSONSerialization.data(withJSONObject: [], options: []) // Return "[]" data
                 } else if let dict = object as? [String:Any], dict.isEmpty {
                      print("Info: Formatted object is an empty dictionary. Encoding empty JSON object.")
                     return try JSONSerialization.data(withJSONObject: [:], options: []) // Return "{}" data
                 }
                throw ValidationError("Internal Error: Formatted object is not valid JSON. Type: \(type(of: object))")
            }
            let opts: JSONSerialization.WritingOptions = prettyPrint ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
            let jsonData = try JSONSerialization.data(withJSONObject: object, options: opts)
            print("Successfully encoded final structure to JSON data.")
            print("-----------------------\n")
            return jsonData
        } catch {
            throw ValidationError("Failed to encode the final structure to JSON: \(error.localizedDescription)")
        }
    }

    /// Handles writing the JSON data to the output file.
    private func writeToFile(data: Data) throws {
        // Check for empty data before proceeding
         if data.isEmpty || String(data: data, encoding: .utf8) == "[]" || String(data: data, encoding: .utf8) == "{}" {
             print("Info: Encoded data is empty or represents empty JSON structure. Skipping file write for: \(outputFile)")
             return // Exit without writing empty file
         }

        let outputURL = URL(fileURLWithPath: outputFile)
        print("--- Writing JSON to File ---")
        do {
            let outputDir = outputURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true, attributes: nil)
            try data.write(to: outputURL, options: .atomic)
            print("Successfully wrote JSON schema to: \(outputURL.path)")
            print("---------------------------\n")
        } catch {
            throw ValidationError("Failed to write JSON to output file '\(outputFile)': \(error.localizedDescription)")
        }
    }
} // End of SwiftSchemaForge struct

// --- Program Entry Point ---
// Explicitly call the static main function.
SwiftSchemaForge.main()
