// Sources/SchemaGenerator.swift

import Foundation

// MARK: - Type Aliases (Pulled from previous version)
typealias JSONSchemaObject = [String: Any]
typealias SchemaComponents = (properties: JSONSchemaObject, required: [String])

// MARK: - Schema Generator Class

/// Generates core JSON Schema components (properties, required arrays)
/// from the intermediate representations (`FunctionSchemaInfo`, `EnumSchemaInfo`)
/// provided by the parser. Handles nested struct and enum references.
class SchemaGenerator {

    // MARK: Properties
    /// Caches the generated schema components for structs to handle recursion and lookups.
    /// Key: Struct Name, Value: Generated (properties, required) tuple.
    private var processedStructSchemas: [String: SchemaComponents] = [:]

    /// Stores a reference to the cache of parsed Enum information provided by the parser.
    /// Key: Enum Name, Value: EnumSchemaInfo.
    private var enumCache: [String: EnumSchemaInfo] = [:]

    /// Tracks structs currently being processed to detect simple cyclical references.
    private var processingStack: Set<String> = []

    // MARK: Public Interface

    /// Generates schema components for all provided FunctionSchemaInfo objects.
    /// This is the main entry point for the generator.
    ///
    /// - Parameters:
    ///   - infos: An array of `FunctionSchemaInfo` extracted from the target Swift structs.
    ///   - enumCache: A dictionary containing info about String-based enums parsed from the source file(s).
    /// - Returns: A dictionary mapping struct names to their generated schema components (`(properties: JSONSchemaObject, required: [String])`).
    /// - Throws: `GenerationError` if processing fails for any struct or encounters unsupported types/structures.
    func generateSchemas(for infos: [FunctionSchemaInfo], enumCache: [String: EnumSchemaInfo]) throws -> [String: SchemaComponents] {
        // Reset state for this run and store the enum cache
        processedStructSchemas = [:]
        processingStack = []
        self.enumCache = enumCache // Make enum info available to instance methods

        // Dictionary to hold the final results for all successfully processed structs
        var finalResults: [String: SchemaComponents] = [:]

        print("--- Starting Schema Generation (Handles Nesting & Enums) ---")

        // Iterate through each target struct provided by the parser
        for info in infos {
            // If this struct was already processed due to being a nested dependency
            // of another struct earlier in the loop, skip reprocessing.
            if finalResults[info.structName] != nil {
                print("Skipping already processed struct: \(info.structName)")
                continue
            }

            do {
                // Process this struct (potentially triggering recursive processing of dependencies)
                let components = try generateSingleSchema(for: info, allInfos: infos)
                // Store the successful result
                finalResults[info.structName] = components
            } catch {
                // If generation for this struct (or its dependencies) fails, report and rethrow
                let contextError = error as? GenerationError ?? GenerationError.internalParsingError(reason: "Unknown error during generation of \(info.structName)")
                print("ERROR: Failed to generate schema for struct '\(info.structName)': \(contextError.localizedDescription)")
                throw contextError // Propagate the first error encountered
            }
        }

        print("--- Finished Generating All Schemas Successfully ---")
        return finalResults
    }

    // MARK: Internal Generation Logic

    /// Generates components for a *single* struct. This method is called recursively
    /// via `mapSwiftType` when encountering nested structs.
    ///
    /// - Parameters:
    ///   - schemaInfo: The specific `FunctionSchemaInfo` for the struct to process.
    ///   - allInfos: The complete list of *all* `FunctionSchemaInfo` objects originally targeted, used for lookups.
    /// - Returns: The generated `SchemaComponents` (properties, required) for this struct.
    /// - Throws: `GenerationError` if cycle detected or processing fails.
    private func generateSingleSchema(for schemaInfo: FunctionSchemaInfo, allInfos: [FunctionSchemaInfo]) throws -> SchemaComponents {

        print("Generating schema components for: \(schemaInfo.structName)")

        // --- Cycle Detection ---
        // Check if we are already processing this struct higher up the call stack.
        guard !processingStack.contains(schemaInfo.structName) else {
            let cyclePath = processingStack.joined(separator: " -> ") + " -> " + schemaInfo.structName
            print("ERROR: Circular dependency detected! Path: \(cyclePath)")
            throw GenerationError.internalParsingError(reason: "Circular dependency detected involving struct '\(schemaInfo.structName)' via path [\(cyclePath)]")
        }
        // Add current struct to the processing stack
        processingStack.insert(schemaInfo.structName)
        // Ensure we remove it when exiting this scope (normal exit or via error)
        defer {
            print("<- Finished processing scope for \(schemaInfo.structName).")
            processingStack.remove(schemaInfo.structName)
        }
        print("-> Entered processing scope for \(schemaInfo.structName). Stack: \(processingStack)")


        // --- Process Properties ---
        var properties: JSONSchemaObject = [:]
        var requiredProperties: [String] = []

        for param in schemaInfo.parameters {
            print("  Processing parameter: \(schemaInfo.structName).\(param.name), Swift Type: \(param.swiftType)")
            do {
                // Map the Swift type to its JSON schema representation.
                // This method now handles basic types, optionals, arrays, dictionaries,
                // cached enums, and triggers recursive generation for nested structs.
                var parameterSchema = try mapSwiftType(param.swiftType,
                                                       contextStructName: schemaInfo.structName,
                                                       propertyName: param.name,
                                                       allInfos: allInfos) // Pass context for errors/recursion

                // Add parameter description to its schema if present
                if let description = param.description, !description.isEmpty {
                    parameterSchema["description"] = description
                    // print("    Added description.") // Can be noisy
                }

                // Add the generated schema for this property
                properties[param.name] = parameterSchema
                // print("    Mapped schema: \(parameterSchema)") // Can be verbose

                // Add to 'required' list if not optional
                if !param.isOptional {
                    requiredProperties.append(param.name)
                    // print("    Added to 'required' array.") // Can be noisy
                }

            } catch let error as GenerationError {
                // Make sure the error context is clear if it bubbles up
                print("    ERROR generating schema for parameter \(param.name): \(error.localizedDescription)")
                // Simply rethrow - the context will be added by the caller if needed
                throw error
             } catch {
                  // Wrap unexpected errors
                  print("    UNEXPECTED ERROR generating schema for parameter \(param.name): \(error)")
                  throw GenerationError.internalParsingError(reason: "Unexpected error processing \(schemaInfo.structName).\(param.name): \(error.localizedDescription)")
             }
        }

        // --- Cache and Return Results ---
        let finalComponents = (properties: properties, required: requiredProperties)
        // Store the result in the cache *before* returning, making it available for other lookups.
        processedStructSchemas[schemaInfo.structName] = finalComponents
        print("  Successfully generated and cached components for \(schemaInfo.structName). Required count: \(requiredProperties.count)")
        return finalComponents
    }


    // --- Core Type Mapping Function ---
    /// Maps a Swift type string representation to a JSON Schema dictionary object.
    /// This is the core recursive function handling all supported type conversions.
    /// Relies on instance properties `enumCache` and `processedStructSchemas`.
    ///
    /// - Parameters:
    ///   - swiftType: The Swift type string (e.g., "Int", "String?", "[Date]", "[String: Int]?", "TaskStatus", "Address?").
    ///   - contextStructName: The name of the struct containing the property being processed (for error context).
    ///   - propertyName: The name of the property being processed (for error context).
    ///   - allInfos: The complete list of target FunctionSchemaInfo (for nested struct lookup).
    /// - Returns: A `JSONSchemaObject` dictionary representing the schema.
    /// - Throws: `GenerationError` for unsupported types or failures.
    private func mapSwiftType(_ swiftType: String, contextStructName: String, propertyName: String, allInfos: [FunctionSchemaInfo]) throws -> JSONSchemaObject {
        var currentType = swiftType.trimmingCharacters(in: .whitespaces)
        let originalTypeForError = swiftType // Keep original string for error messages

        // --- 1. Handle Optionality ---
        // Optionality doesn't affect the schema type itself, only the 'required' array status (handled by caller).
        // We just need to map the underlying non-optional type.
        if currentType.hasSuffix("?") {
            currentType = String(currentType.dropLast())
            print("      Mapping underlying type for Optional: '\(currentType)'")
        }

        // --- 2. Dictionary Check ([String: T]) ---
        // Check for dictionary syntax: starts/ends with [], contains exactly one ':' not inside inner <> () etc.
        if currentType.hasPrefix("["), currentType.hasSuffix("]"), currentType.count > 2 {
            let innerContent = String(currentType.dropFirst().dropLast())
            // Simple split is okay for non-generic K/V types
            let components = innerContent.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if components.count == 2 { // Looks like K:V
                let keyType = components[0]; let valueType = components[1]
                guard keyType == "String" else {
                    throw GenerationError.unsupportedType(typeName: originalTypeForError, context: "Dictionary keys must be String for JSON object mapping.")
                }
                print("      Detected Dictionary type. Value type: \(valueType)")
                // Recursively map the value type schema
                let valueSchema = try mapSwiftType(valueType,
                                                   contextStructName: contextStructName,
                                                   propertyName: "\(propertyName) value", // Provide context
                                                   allInfos: allInfos)
                return ["type": "object", "additionalProperties": valueSchema] // Standard schema for string-keyed dictionaries
            }
            // Fall through if not 2 components - might be nested array [[T]] etc.
        }

        // --- 3. Array Check ([T]) ---
        // Check after dictionary, as both use brackets.
        if currentType.hasPrefix("["), currentType.hasSuffix("]") {
            let firstIndex = currentType.index(after: currentType.startIndex)
            let lastIndex = currentType.index(before: currentType.endIndex)
            guard lastIndex > firstIndex else {
                throw GenerationError.nestedTypeParsingFailed(fullType: originalTypeForError, reason: "Invalid empty array syntax '[]'")
            }
            let innerType = String(currentType[firstIndex..<lastIndex])
            print("      Detected Array type. Inner type: \(innerType)")
            // Recursively map the inner element type schema
            let itemsSchema = try mapSwiftType(innerType,
                                                contextStructName: contextStructName,
                                                propertyName: "\(propertyName) item", // Provide context
                                                allInfos: allInfos)
            return ["type": "array", "items": itemsSchema]
        }

        // --- 4. Basic & Known Types Check ---
        currentType = currentType.trimmingCharacters(in: .whitespaces) // Ensure clean key for lookup/switch
        switch currentType {
            // Standard JSON Schema primitives
            case "String": return ["type": "string"]
            case "Int", "Int64", "Int32", "Int16", "Int8", "UInt", "UInt64", "UInt32", "UInt16", "UInt8": return ["type": "integer"]
            case "Bool": return ["type": "boolean"]
            case "Float", "Double", "CGFloat": return ["type": "number"]
            // Common formats represented as strings
            case "Date": return ["type": "string", "format": "date-time"]
            case "UUID": return ["type": "string", "format": "uuid"]
            case "Data": return ["type": "string", "format": "byte"] // Base64
            case "URL": return ["type": "string", "format": "uri"]

        default:
            // --- 5. Enum Check (Using Cached Enums) ---
            print("        Type '\(currentType)' not basic/array/dict. Checking Enum cache...")
            if let foundEnumInfo = self.enumCache[currentType] {
                print("        Found String enum '\(currentType)'. Creating schema with cases.")
                var enumSchema: JSONSchemaObject = [
                    "type": "string",
                    // The 'enum' keyword in JSON Schema lists the possible string values.
                    "enum": foundEnumInfo.cases.map { $0.name } // Use the case name
                ]
                // Combine enum description with case details for better documentation.
                var combinedDescription = foundEnumInfo.description ?? ""
                let caseDetails = foundEnumInfo.cases.compactMap { cInfo -> String? in
                    let caseDesc = cInfo.description.map { ": \($0.replacingOccurrences(of: "\n", with: " "))" } ?? ""
                    return "  - `\(cInfo.name)`\(caseDesc)" // Format case details nicely
                }.joined(separator: "\n")

                if !caseDetails.isEmpty {
                    combinedDescription += (combinedDescription.isEmpty ? "" : "\n\n") + "Possible values:\n" + caseDetails
                }
                if !combinedDescription.isEmpty { enumSchema["description"] = combinedDescription }

                return enumSchema
            }

            // --- 6. Nested Struct Check (Using Processed Struct Cache & Recursive Call) ---
            print("        Type '\(currentType)' not enum. Checking Nested Struct...")
            // Has this struct type *already* been processed and cached?
            if let nestedComponents = self.processedStructSchemas[currentType] {
                print("        Found *cached* nested struct '\(currentType)'. Using cached components.")
                // Important: Include properties AND required from the cached components
                return ["type": "object", "properties": nestedComponents.properties, "required": nestedComponents.required]
            } else {
                // It's not cached. Is it one of the structs we *intended* to parse initially?
                if let matchingInfo = allInfos.first(where: { $0.structName == currentType }) {
                    // Yes, it's a target struct, but not processed yet. Process it now recursively.
                    // This handles cases where struct dependencies are encountered before the struct itself in the outer loop.
                    print("        Found target struct '\(currentType)' but not cached. Generating recursively...")
                    do {
                         // This call will populate self.processedStructSchemas[currentType] via its cache mechanism.
                         let nestedComponents = try generateSingleSchema(for: matchingInfo, allInfos: allInfos)
                         print("        Successfully generated nested struct '\(currentType)' recursively.")
                         // Now use the generated components (implicitly from the cache or the return value)
                         return ["type": "object", "properties": nestedComponents.properties, "required": nestedComponents.required]
                    } catch {
                         print("        ERROR: Recursive generation for nested struct '\(currentType)' failed: \(error)")
                         // Wrap error for better context about where the failure occurred.
                         throw GenerationError.internalParsingError(reason: "Failed generating nested struct '\(currentType)' referenced by '\(propertyName)' in '\(contextStructName)': \(error.localizedDescription)")
                    }
                } else {
                    // It's not a basic type, not an enum, not a processed struct, and not a target struct. Unsupported.
                    print("        ERROR: Type '\(currentType)' is not recognized or was not requested via --type-name.")
                    throw GenerationError.nestedStructNotRequested(typeName: currentType, referencingStruct: contextStructName, propertyName: propertyName)
                }
            }
        }
    } // End of mapSwiftType

} // End of SchemaGenerator class
