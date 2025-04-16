// Sources/Errors.swift

import Foundation
import ArgumentParser // Needed for OutputFormat conformance
// import SwiftDiagnostics - Not directly needed here anymore

// MARK: - Output Format Enum
// Placed here for global module access without cluttering main.swift top level.

/// Defines the supported LLM schema output formats.
enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    /// Format suitable for OpenAI's Chat Completions API (tools parameter).
    case openai
    /// Format suitable for Grok's function calling (currently identical to OpenAI).
    case grok
    /// Format suitable for Google Gemini's Function Calling (FunctionDeclaration).
    case gemini

    // Provides case names for shell completion scripts (via ArgumentParser).
    static var defaultCompletionKind: CompletionKind { .list(Self.allCases.map { $0.rawValue }) }
}


// MARK: - Parsing Errors

/// Defines errors that can occur during the Swift source file reading and parsing phase
/// using SwiftSyntax.
enum ParsingError: Error, LocalizedError {
    /// The specified input file path could not be found on the filesystem.
    case fileNotFound(path: String)

    /// An OS-level error occurred while trying to read the content of the input file.
    case fileReadError(path: String, underlyingError: Error)

    /// SwiftSyntax failed to effectively parse the source code into a usable syntax tree,
    /// potentially due to major syntax errors.
    case swiftParsingFailed(path: String, reason: String? = nil)

    /// None of the specific struct names provided via `--type-name` were found in the parsed file(s).
    case targetStructNotFound(names: [String], path: String)

    /// Provides user-friendly descriptions for parsing errors.
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Input file not found at path: \(path)"
        case .fileReadError(let path, let underlyingError):
            return "Failed to read input file '\(path)'. Error: \(underlyingError.localizedDescription)"
        case .swiftParsingFailed(let path, let reason):
            let reasonDesc = reason.map { " Reason: \($0)." } ?? " Check Swift syntax."
            return "Failed to parse Swift syntax in file: \(path).\(reasonDesc)"
        case .targetStructNotFound(let names, let path):
            return "Target struct(s) [\(names.joined(separator: ", "))] not found in file: \(path)"
        }
    }
}


// MARK: - Generation Errors

/// Defines errors that can occur during the generation of JSON schema components
/// from the intermediate representation (IR) created by the parser.
enum GenerationError: Error, LocalizedError {
    /// A Swift type (property type, array element type, dictionary value type)
    /// could not be mapped to a supported JSON Schema type/format.
    case unsupportedType(typeName: String, context: String? = nil)

    /// Failed to parse the structural components of a complex type string (e.g., malformed Array `[T]` or Dictionary `[K:V]`).
    case nestedTypeParsingFailed(fullType: String, reason: String)

    /// A property references a nested struct type, but that struct's definition
    /// was not requested via `--type-name` and thus its schema information is unavailable for nesting.
    case nestedStructNotRequested(typeName: String, referencingStruct: String, propertyName: String)

    /// An unexpected internal logic error occurred during schema generation,
    /// such as a detected cyclical dependency between structs.
    case internalParsingError(reason: String)

    /// Provides user-friendly descriptions for generation errors.
    var errorDescription: String? {
        switch self {
        case .unsupportedType(let typeName, let context):
            let contextInfo = context.map { " (Context: \($0))" } ?? ""
            return "Unsupported Swift type for schema generation: \(typeName)\(contextInfo)"
        case .nestedTypeParsingFailed(let fullType, let reason):
            return "Failed to parse components of complex type '\(fullType)': \(reason)"
        case .nestedStructNotRequested(let typeName, let referencingStruct, let propertyName):
            return "Cannot generate nested schema for property '\(propertyName)' in '\(referencingStruct)' because type '\(typeName)' was not explicitly requested via --type-name or could not be parsed."
        case .internalParsingError(let reason):
            return "Internal schema generation error: \(reason)"
        }
    }
}


// MARK: - Formatting Errors

/// Defines errors that can occur during the final formatting stage, when converting
/// the generated schema components into the specific structure required by an LLM API.
enum FormattingError: Error, LocalizedError {
    /// The output format specified via `--format` (e.g., "grok", "gemini")
    /// is recognized but not yet fully implemented in the formatter.
    case unsupportedFormat(format: String) // Keeps the original meaning better

    /// An unexpected condition or logic error occurred within the formatting code
    /// for a specific, supposedly supported LLM format.
    case formattingLogicError(format: String, reason: String)

    /// Provides user-friendly descriptions for formatting errors.
    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            // This error should ideally only be hit if the format is defined but implementation is missing/stubbed.
            return "The requested output format '\(format)' is defined but not fully implemented."
        case .formattingLogicError(let format, let reason):
            return "Internal error during schema formatting for '\(format)': \(reason)"
        }
    }
}
