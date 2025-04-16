// Sources/SwiftSourceParser.swift

import Foundation
import SwiftSyntax      // Core SwiftSyntax library
import SwiftParser      // For the Parser function
// Note: ParsingError enum is now expected to be defined in Errors.swift

/// Responsible for parsing a Swift source file using SwiftSyntax.
/// Extracts information about specified Codable structs and caches
/// definitions of simple String-based enums found within the file.
class SwiftSourceParser {

    /// Parses the given Swift file.
    func parse(filePath: String, targetStructNames: [String]) throws -> (structs: [FunctionSchemaInfo], enums: [String: EnumSchemaInfo]) {
        let fileURL = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ParsingError.fileNotFound(path: filePath)
        }
        let sourceContent: String
        do { sourceContent = try String(contentsOf: fileURL, encoding: .utf8) }
        catch { throw ParsingError.fileReadError(path: filePath, underlyingError: error) }

        print("Parsing AST for: \(filePath)")
        let sourceFileSyntax: SourceFileSyntax = Parser.parse(source: sourceContent)
        print("AST Parsing complete.")

        if sourceFileSyntax.statements.isEmpty && !sourceContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
             print("Warning: Parsed syntax tree appears empty for non-empty file '\(filePath)'.")
        }

        let visitor = SchemaInfoExtractorVisitor(targetStructNames: targetStructNames)
        print("Starting syntax tree walk...")
        visitor.walk(sourceFileSyntax)
        print("Finished syntax tree walk.")

        if let visitorError = visitor.parsingError {
             print("ERROR: Visitor failed.")
             throw visitorError
        }

        let foundStructs = visitor.extractedStructs
        let foundEnums = visitor.enumCache
        let requestedNames = Set(targetStructNames)
        let foundNames = Set(foundStructs.map { $0.structName })

        if !requestedNames.isEmpty && foundNames.isDisjoint(with: requestedNames) {
             throw ParsingError.targetStructNotFound(names: targetStructNames, path: filePath)
        } else if !requestedNames.isEmpty && !requestedNames.isSubset(of: foundNames) {
             let missing = requestedNames.subtracting(foundNames)
             print("Warning: Could not find or parse target(s): \(missing.joined(separator: ", "))")
        } else if foundStructs.isEmpty && !targetStructNames.isEmpty {
              print("Warning: Requested target(s) (\(targetStructNames.joined(separator: ", "))) but none were extracted.")
        }

        print("Parsing successful. Structs: \(foundStructs.count), Enums cached: \(foundEnums.count).")
        return (structs: foundStructs, enums: foundEnums)
    }
}


// MARK: - Private Syntax Visitor Class
private class SchemaInfoExtractorVisitor: SyntaxVisitor {

    let targetStructNames: Set<String>
    private(set) var extractedStructs: [FunctionSchemaInfo] = []
    private(set) var enumCache: [String: EnumSchemaInfo] = [:]
    private(set) var parsingError: ParsingError? = nil

    private var currentStructIsTarget: Bool = false
    private var currentStructName: String? = nil
    private var currentParameters: [ParameterInfo] = []

    init(targetStructNames: [String]) {
        self.targetStructNames = Set(targetStructNames)
        super.init(viewMode: .sourceAccurate)
        print("Visitor Init. Targets: \(self.targetStructNames.isEmpty ? "None" : self.targetStructNames.joined(separator: ","))")
    }

    // MARK: Visit Methods

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        guard parsingError == nil else { return .skipChildren }
        // Fix warning: Don't extract doc here if only used in visitPost
        _ = extractLeadingDocumentation(from: Syntax(node))
        let structName = node.name.text

        // Add detailed check logging
        let isTarget = targetStructNames.contains(structName)
        print("DEBUG visit(Struct): Checking '\(structName)'. Target? \(isTarget). targetNamesSet = \(targetStructNames)")

        if isTarget {
            // Avoid nesting state issues if visitPost somehow didn't clear state
            if currentStructIsTarget {
                 print("DEBUG visit(Struct): WARNING - Already processing target '\(currentStructName ?? "??")' when entering '\(structName)'. Resetting state forcefully.")
            }
            print("DEBUG visit(Struct): Setting state for TARGET '\(structName)'")
            currentStructIsTarget = true
            currentStructName = structName
            currentParameters = [] // Reset parameters
            return .visitChildren // Visit members
        } else {
            return .skipChildren // Skip non-targets
        }
    }

    override func visitPost(_ node: StructDeclSyntax) {
        guard parsingError == nil else { return }
        let visitedStructName = node.name.text

        print("DEBUG visitPost(Struct): Finished '\(visitedStructName)'. Current State [isTarget:\(currentStructIsTarget), name:\(currentStructName ?? "nil")]")

        // Condition: We must have been tracking this struct (isTarget true) AND the name must match
        if currentStructIsTarget, let targetName = currentStructName, targetName == visitedStructName {
            let finalStructDoc = extractLeadingDocumentation(from: Syntax(node))
            let schemaInfo = FunctionSchemaInfo(
                structName: targetName,
                description: finalStructDoc,
                parameters: currentParameters
            )
            print("DEBUG visitPost(Struct): Appending completed FunctionSchemaInfo for '\(targetName)' (\(currentParameters.count) params).")
            extractedStructs.append(schemaInfo)

            // ----> CRITICAL: Reset state *only* after successful append <----
            print("DEBUG visitPost(Struct): Resetting state after processing '\(targetName)'.")
            currentStructIsTarget = false
            currentStructName = nil
            currentParameters = []
            // -----------------------------------------------------------------

        } else if currentStructIsTarget {
            // This indicates a state inconsistency or unexpected flow
            print("DEBUG visitPost(Struct): WARNING - State indicates a target ('\(currentStructName ?? "??")') but node name '\(visitedStructName)' doesn't match. Resetting state.")
            // Reset state anyway to prevent further issues
            currentStructIsTarget = false
            currentStructName = nil
            currentParameters = []
        }
        // If !currentStructIsTarget, we just finished a non-target struct, do nothing.
        print("DEBUG visitPost(Struct): Exiting scope for '\(visitedStructName)'.")

    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Skip processing if error occurred or not inside a target struct
        guard parsingError == nil, currentStructIsTarget else { return .skipChildren }

        let varDoc = extractLeadingDocumentation(from: Syntax(node))

        for binding in node.bindings {
            guard let identifierPattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeAnnotation = binding.typeAnnotation else {
                // Log skips for clarity
                print("  Skipping binding in \(currentStructName ?? "?"): pattern '\(binding.pattern.trimmedDescription)' / type missing.")
                continue
            }

            let variableName = identifierPattern.identifier.text
            let typeSyntax = typeAnnotation.type

            let rawTypeName: String
            let isOptional: Bool
            if let optionalType = typeSyntax.as(OptionalTypeSyntax.self) {
                rawTypeName = optionalType.wrappedType.trimmedDescription
                isOptional = true
            } else {
                rawTypeName = typeSyntax.trimmedDescription
                isOptional = false
            }
            let finalSwiftTypeString = isOptional ? "\(rawTypeName)?" : rawTypeName

            // Use more standard logging format
            print("  Processing Property: \(currentStructName ?? "").\(variableName) (Type: \(finalSwiftTypeString), Optional: \(isOptional), Doc: \(varDoc != nil))")

            let paramInfo = ParameterInfo(name: variableName, swiftType: finalSwiftTypeString, description: varDoc, isOptional: isOptional)
            currentParameters.append(paramInfo)
        }
        return .skipChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
         guard parsingError == nil else { return .skipChildren }
         let enumName = node.name.text
         print("Visiting enum: \(enumName)")
         var inheritsFromString = false
         if let inheritance = node.inheritanceClause {
             inheritsFromString = inheritance.inheritedTypes.contains { $0.type.as(IdentifierTypeSyntax.self)?.name.text == "String" }
         }
         guard inheritsFromString else { return .skipChildren } // Skip non-String enums silently

         print("  Found String enum: \(enumName). Caching definition.")
         let enumDoc = extractLeadingDocumentation(from: Syntax(node))
         var cases: [EnumCaseInfo] = []
         for member in node.memberBlock.members {
             guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
             for element in caseDecl.elements {
                 let caseName = element.name.text
                 let caseElementDoc = extractLeadingDocumentation(from: Syntax(element))
                 // print("    Found case: \(caseName)") // Reduce noise
                 cases.append(EnumCaseInfo(name: caseName, description: caseElementDoc))
             }
         }
         if !cases.isEmpty { enumCache[enumName] = EnumSchemaInfo(name: enumName, description: enumDoc, cases: cases) }
         return .skipChildren
    }

    // MARK: Helper Methods
    /// Extracts documentation comments.
    private func extractLeadingDocumentation(from node: Syntax) -> String? {
        // ... (Keep the same implementation as before - Step 44.4) ...
        var commentLines: [String] = []
        for triviaPiece in node.leadingTrivia.reversed() {
            switch triviaPiece {
            case .docLineComment(let text): commentLines.append(text.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")))
            case .docBlockComment(let text):
                 let cleaned = text.split(separator:"\n").map { l->String in var t=l.trimmingCharacters(in:.whitespaces); if t.hasSuffix("*/"){t.removeLast(t.hasPrefix("/**")&&t.count<=5 ?0:2)}; if t.hasPrefix("/**"){t.removeFirst(3)}; if t.hasPrefix("* "){t.removeFirst(2)}else if t.hasPrefix("*"){t.removeFirst(1)}; return t.trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty}.joined(separator:"\n"); if !cleaned.isEmpty{commentLines.append(cleaned)}
            case .newlines,.spaces,.tabs,.carriageReturns,.carriageReturnLineFeeds: continue
            default: guard !commentLines.isEmpty else{return nil}; return commentLines.reversed().joined(separator:"\n").trimmingCharacters(in:.whitespacesAndNewlines)
            }
        }
        return commentLines.isEmpty ?nil:commentLines.reversed().joined(separator:"\n").trimmingCharacters(in:.whitespacesAndNewlines)

    }
}

// MARK: - Syntax Extension
extension TypeSyntax {
    /// Clean string representation of type syntax.
    var trimmedDescription: String { return self.trimmed.description }
}
