// Sources/LLMFormatter.swift

import Foundation

/// Responsible for taking the generated schema components (properties, required array)
/// and wrapping them into the final JSON structure expected by specific LLM APIs (OpenAI, Grok, Gemini).
class LLMFormatter {

    // MARK: Type Aliases
    // Use globally defined SchemaComponents typealias
    // typealias SchemaComponents = (properties: JSONSchemaObject, required: [String]) // Assumes global definition or definition in another file

    /// Represents the combined input needed for formatting: original struct info + generated schema parts.
    typealias InputComponent = (info: FunctionSchemaInfo, components: SchemaComponents)

    // MARK: Public Interface

    /// Formats the generated schema components into the structure for a specified LLM.
    ///
    /// - Parameters:
    ///   - generatedComponents: An array containing the original `FunctionSchemaInfo` and the generated `properties` and `required` arrays for each struct.
    ///   - format: The target LLM format (`openai`, `grok`, `gemini`).
    /// - Returns: An `Any` object representing the final JSON structure ready for encoding (typically `[[String: Any]]`).
    /// - Throws: `FormattingError` if the format is unsupported or an internal formatting issue occurs.
    func format(components generatedComponents: [InputComponent], as format: OutputFormat) throws -> Any {

        print("Formatting \(generatedComponents.count) schemas for target: \(format.rawValue)")

        // Delegate to the appropriate format-specific function based on the enum value.
        switch format {
        case .openai:
            // OpenAI and Grok share the same format based on current documentation.
            return formatForOpenAI(components: generatedComponents)
        case .grok:
            // Reuse OpenAI format logic.
            return formatForGrok(components: generatedComponents)
        case .gemini:
            // Use the specific Gemini formatting logic.
            return try formatForGemini(components: generatedComponents)
        // Note: Swift requires switch statements to be exhaustive. If more formats are added
        // to the OutputFormat enum, they must be handled here or a `default` case added.
        }
    }

    // MARK: Formatting Functions - OpenAI & Grok

    /// Formats the components according to the OpenAI Tools / Grok Function structure.
    /// Produces an array of tool definition objects.
    ///
    /// - Parameter components: The array of input components (struct info + generated schema parts).
    /// - Returns: An array of dictionaries `[[String: Any]]` representing the tool definitions.
    private func formatForOpenAI(components: [InputComponent]) -> [[String: Any]] {
        var openAITools: [[String: Any]] = []

        for component in components {
            let info = component.info         // Original FunctionSchemaInfo
            let schema = component.components // Generated (properties, required)

            print("  Formatting for OpenAI/Grok: \(info.structName)")

            // Construct the 'parameters' object based on JSON Schema standard
            var parametersObject: JSONSchemaObject = [
                "type": "object",               // Parameters are represented as an object
                "properties": schema.properties // Embed the generated properties dictionary
            ]
            // Add the 'required' array only if there are required properties
            // Including an empty array is also valid JSON Schema practice.
            parametersObject["required"] = schema.required // Assigns empty array if needed


            // Construct the main function definition part
            var functionDefinition: [String: Any] = [
                "name": info.structName,          // The name the LLM will use to call the function
                "parameters": parametersObject    // The JSON Schema object describing parameters
            ]
            // Add the overall function description if the struct had one
            if let description = info.description, !description.isEmpty {
                functionDefinition["description"] = description
            }

            // Construct the final tool object for the array as expected by OpenAI/Grok
            let toolObject: [String: Any] = [
                "type": "function",            // Specifies this tool definition is for a function
                "function": functionDefinition // Embed the function definition object
            ]

            openAITools.append(toolObject) // Add this function/tool to the list
        }

        return openAITools // Return the complete list of tools
    }

    /// Formats the components according to the Grok API structure.
    /// **Note:** As of latest check (Apr 2025), Grok's format is identical to OpenAI's.
    private func formatForGrok(components: [InputComponent]) -> [[String: Any]] {
         print("INFO: Grok format using identical structure to OpenAI.")
         // Simply delegate to the OpenAI formatter.
         return formatForOpenAI(components: components)
    }


    // MARK: Formatting Function - Gemini

    /// Formats the components according to the Google Gemini API structure (`FunctionDeclaration`).
    /// Produces an array of `FunctionDeclaration` objects.
    /// Requires converting schema types to uppercase and removing 'format'.
    ///
    /// - Parameter components: The array of input components (struct info + generated schema parts).
    /// - Returns: An array of dictionaries `[[String: Any]]` representing function declarations.
    /// - Throws: `FormattingError` if conversion fails (though helper should handle this).
    private func formatForGemini(components: [InputComponent]) throws -> [[String: Any]] {
         print("Formatting for Gemini API (FunctionDeclaration)...")
         var geminiDeclarations: [[String: Any]] = []

         for component in components {
             let info = component.info         // Original FunctionSchemaInfo
             let schema = component.components // Generated (properties, required)
             print("  Processing for Gemini: \(info.structName)")

             // 1. Transform the 'properties' dictionary for Gemini compatibility
             var geminiProperties: JSONSchemaObject = [:]
             for (key, value) in schema.properties {
                 // Ensure the value is a dictionary (schema fragment) before transforming
                 guard var propertySchema = value as? JSONSchemaObject else {
                     print("    WARNING: Could not process property '\(key)' as dictionary schema. Skipping.")
                     continue
                 }
                 // Use helper to convert types/remove format recursively
                 geminiProperties[key] = convertSchemaTypesToUppercase(&propertySchema)
             }

             // 2. Build the 'parameters' schema object for the FunctionDeclaration
             let parametersObject: JSONSchemaObject = [
                 "type": "OBJECT",               // Gemini uses uppercase type names
                 "properties": geminiProperties, // The transformed properties
                 "required": schema.required     // Use the 'required' list directly
             ]

             // 3. Build the final FunctionDeclaration object
             let functionDeclaration: [String: Any] = [
                 "name": info.structName,
                 // Gemini requires description; provide empty string if original was nil
                 "description": info.description ?? "",
                 "parameters": parametersObject
             ]

             geminiDeclarations.append(functionDeclaration)
        }

        // Gemini expects an array of these declarations when passed via the API client
        return geminiDeclarations
    }

    // MARK: Private Helpers

    /// **Gemini Specific Helper:** Recursively traverses a JSON Schema fragment (represented as `[String: Any]`)
    /// and performs modifications needed for Gemini compatibility:
    ///   - Converts `type` values (e.g., "string") to uppercase ("STRING").
    ///   - Removes any `format` keys.
    /// Modifies the dictionary **in-place**.
    ///
    /// - Parameter schema: The schema fragment dictionary to modify (`inout`).
    /// - Returns: The modified dictionary (convenience for potential chaining, not strictly needed as it modifies in-place).
    @discardableResult
    private func convertSchemaTypesToUppercase(_ schema: inout JSONSchemaObject) -> JSONSchemaObject {
        // 1. Convert top-level "type" value to uppercase
        if let typeValue = schema["type"] as? String {
            schema["type"] = typeValue.uppercased()
        }

        // 2. Remove top-level "format" key if it exists
        schema.removeValue(forKey: "format")

        // 3. Recurse for "items" (Array element schemas)
        if var itemsSchema = schema["items"] as? JSONSchemaObject {
            schema["items"] = convertSchemaTypesToUppercase(&itemsSchema) // Modify nested dict in place
        }
        // Handle case where "items" could itself be an Array (less common in basic schemas)
        // else if var itemsArray = schema["items"] as? [JSONSchemaObject] {
        //    schema["items"] = itemsArray.map { convertSchemaTypesToUppercase(&$0) } // Modify each in array
        // }


        // 4. Recurse for "additionalProperties" (Dictionary value schemas)
        if var additionalPropsSchema = schema["additionalProperties"] as? JSONSchemaObject {
            schema["additionalProperties"] = convertSchemaTypesToUppercase(&additionalPropsSchema)
        }

        // 5. Recurse for "properties" (Object property schemas)
        if var propertiesMap = schema["properties"] as? JSONSchemaObject {
            var updatedProperties: JSONSchemaObject = [:]
            for (key, value) in propertiesMap {
                 if var nestedPropSchema = value as? JSONSchemaObject {
                     // Recursively convert the schema for each property
                     updatedProperties[key] = convertSchemaTypesToUppercase(&nestedPropSchema)
                 } else {
                     // Keep non-dictionary values as they are (shouldn't typically happen in valid JSON schema)
                     updatedProperties[key] = value
                 }
            }
            schema["properties"] = updatedProperties // Assign the map with converted sub-schemas
        }

        return schema // Return the modified dictionary
    }

} // End of LLMFormatter class
