// Sources/LLMFormatter.swift

import Foundation

// Uses FormattingError from Errors.swift

/// Responsible for taking the generated schema components (properties, required array)
/// and wrapping them into the final JSON structure expected by specific LLM APIs (OpenAI, Grok, Gemini).
class LLMFormatter {

    // MARK: Type Aliases
    // Assumes SchemaComponents = (properties: JSONSchemaObject, required: [String]) is defined elsewhere or understood contextually
    /// Represents the combined input needed for formatting: original struct info + generated schema parts.
    typealias InputComponent = (info: FunctionSchemaInfo, components: SchemaComponents)

    // MARK: Public Interface

    /// Formats the generated schema components into the structure for a specified LLM.
    func format(components generatedComponents: [InputComponent], as format: OutputFormat) throws -> Any {
        print("Formatting \(generatedComponents.count) schemas for target: \(format.rawValue)")
        switch format {
        case .openai:
            return formatForOpenAI(components: generatedComponents)
        case .grok:
            return formatForGrok(components: generatedComponents)
        case .gemini:
            return try formatForGemini(components: generatedComponents)
        }
    }

    // MARK: Formatting Functions - OpenAI & Grok

    /// Formats the components according to the OpenAI Tools / Grok Function structure.
    private func formatForOpenAI(components: [InputComponent]) -> [[String: Any]] {
        var openAITools: [[String: Any]] = []
        for component in components {
            let info = component.info
            let schema = component.components
            print("  Formatting for OpenAI/Grok: \(info.structName)")

            var parametersObject: JSONSchemaObject = ["type": "object", "properties": schema.properties]
            parametersObject["required"] = schema.required // Assigns empty array if needed

            var functionDefinition: [String: Any] = ["name": info.structName, "parameters": parametersObject]
            if let description = info.description, !description.isEmpty {
                functionDefinition["description"] = description
            }
            let toolObject: [String: Any] = ["type": "function", "function": functionDefinition]
            // print("    Formatted OpenAI Tool Object: \(toolObject)") // Reduced verbosity
            openAITools.append(toolObject)
        }
        return openAITools
    }

    /// Formats the components according to the Grok API structure.
    private func formatForGrok(components: [InputComponent]) -> [[String: Any]] {
         print("INFO: Grok format using identical structure to OpenAI.")
         return formatForOpenAI(components: components)
    }

    // MARK: Formatting Function - Gemini

    /// Formats the components according to the Google Gemini API structure (`FunctionDeclaration`).
    private func formatForGemini(components: [InputComponent]) throws -> [[String: Any]] {
         print("Formatting for Gemini API (FunctionDeclaration)...")
         var geminiDeclarations: [[String: Any]] = []
         for component in components {
             let info = component.info
             let schema = component.components
             print("  Processing for Gemini: \(info.structName)")

             var geminiProperties: JSONSchemaObject = [:]
             for (key, value) in schema.properties {
                 guard var propertySchema = value as? JSONSchemaObject else {
                     print("    WARNING: Could not process property '\(key)' as dictionary schema. Skipping.")
                     continue
                 }
                 geminiProperties[key] = convertSchemaTypesToUppercase(&propertySchema)
             }

             let parametersObject: JSONSchemaObject = [
                 "type": "OBJECT",
                 "properties": geminiProperties,
                 "required": schema.required
             ]

             let functionDeclaration: [String: Any] = [
                 "name": info.structName,
                 "description": info.description ?? "", // Default to empty string if nil
                 "parameters": parametersObject
             ]
             geminiDeclarations.append(functionDeclaration)
        }
        return geminiDeclarations
    }

    // MARK: Private Helpers

    /// **Gemini Specific Helper:** Recursively converts schema type values to uppercase and removes "format". Modifies in-place.
    @discardableResult
    private func convertSchemaTypesToUppercase(_ schema: inout JSONSchemaObject) -> JSONSchemaObject {
        if let typeValue = schema["type"] as? String { schema["type"] = typeValue.uppercased() }
        schema.removeValue(forKey: "format")
        if var itemsSchema = schema["items"] as? JSONSchemaObject { schema["items"] = convertSchemaTypesToUppercase(&itemsSchema) }
        if var additionalPropsSchema = schema["additionalProperties"] as? JSONSchemaObject { schema["additionalProperties"] = convertSchemaTypesToUppercase(&additionalPropsSchema) }
        // Fixed Warning: Changed 'var propertiesMap' to 'let propertiesMap'
        if let propertiesMap = schema["properties"] as? JSONSchemaObject {
            var updatedProperties: JSONSchemaObject = [:]
            for (key, value) in propertiesMap {
                 if var nestedPropSchema = value as? JSONSchemaObject {
                     updatedProperties[key] = convertSchemaTypesToUppercase(&nestedPropSchema)
                 } else {
                     updatedProperties[key] = value
                 }
            }
            schema["properties"] = updatedProperties
        }
        return schema
    }

} // End of LLMFormatter class
