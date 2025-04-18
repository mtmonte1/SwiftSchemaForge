// Sources/SwiftSourceParser.swift

import Foundation
import SwiftSyntax
import SwiftParser

// Note: ParsingError enum is now expected to be defined in Errors.swift

/// Responsible for parsing a Swift source file using SwiftSyntax.
/// Extracts information about specified Codable structs and caches
/// definitions of simple String-based enums found within the file.
class SwiftSourceParser {

    /// Parses the given Swift file.
    func parse(filePath: String, targetStructNames: [String]) throws -> (structs: [FunctionSchemaInfo], enums: [String: EnumSchemaInfo]) {
        let fileURL = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { throw ParsingError.fileNotFound(path: filePath) }
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

        // Check if requested targets were actually found
        if !requestedNames.isEmpty {
            let foundNames = Set(foundStructs.map { $0.structName })
             if foundNames.isDisjoint(with: requestedNames) { // None of the requested were found
                  throw ParsingError.targetStructNotFound(names: targetStructNames, path: filePath)
             } else if !requestedNames.isSubset(of: foundNames) { // Some requested were missing
                  let missing = requestedNames.subtracting(foundNames)
                  print("Warning: Could not find or parse target(s): \(missing.joined(separator: ", "))")
             }
        } else if foundStructs.isEmpty {
            // No targets requested, and none found (potentially okay if only used for enum caching)
             print("Info: No target structs requested or found in file.")
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
         // print("DEBUG Visitor Init. Targets: \(self.targetStructNames.isEmpty ? "None" : self.targetStructNames.sorted().joined(separator: ","))") // DEBUG
    }

    // MARK: Visit Methods

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        guard parsingError == nil else { return .skipChildren }
        let structName = node.name.text
        let isTarget = targetStructNames.contains(structName)

         // print("DEBUG visit(Struct): Checking '\(structName)'. Target? \(isTarget).") // DEBUG

        if isTarget {
            if currentStructIsTarget { /* Handle/log potential state inconsistency if needed */ }
             // print("DEBUG visit(Struct): Setting state for TARGET '\(structName)'") // DEBUG
            currentStructIsTarget = true
            currentStructName = structName
            currentParameters = []
            return .visitChildren
        } else {
            return .skipChildren
        }
    }

    override func visitPost(_ node: StructDeclSyntax) {
        guard parsingError == nil else { return }
        let visitedStructName = node.name.text

        // print("DEBUG visitPost(Struct): Finished '\(visitedStructName)'. Current State [isTarget:\(currentStructIsTarget), name:\(currentStructName ?? "nil")]") // DEBUG

        if currentStructIsTarget, let targetName = currentStructName, targetName == visitedStructName {
            let finalStructDoc = extractLeadingDocumentation(from: Syntax(node))
            let schemaInfo = FunctionSchemaInfo(
                structName: targetName, description: finalStructDoc, parameters: currentParameters
            )
             // print("DEBUG visitPost(Struct): Appending completed FunctionSchemaInfo for '\(targetName)' (\(currentParameters.count) params).") // DEBUG
            extractedStructs.append(schemaInfo)
             // print("DEBUG visitPost(Struct): Resetting state after processing '\(targetName)'.") // DEBUG
            currentStructIsTarget = false; currentStructName = nil; currentParameters = [] // Reset state
        } else if currentStructIsTarget { /* Handle/log potential state inconsistency */ }

        // print("DEBUG visitPost(Struct): Exiting scope for '\(visitedStructName)'.") // DEBUG
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard parsingError == nil, currentStructIsTarget else { return .skipChildren }
        let varDoc = extractLeadingDocumentation(from: Syntax(node))
        for binding in node.bindings {
            guard let identifierPattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeAnnotation = binding.typeAnnotation else {
                 // print("  Skipping binding in \(currentStructName ?? "?"): pattern '\(binding.pattern.trimmedDescription)' / type missing.") // DEBUG
                continue
            }
            let variableName = identifierPattern.identifier.text
            let typeSyntax = typeAnnotation.type
            let rawTypeName: String
            let isOptional: Bool
            if let optionalType = typeSyntax.as(OptionalTypeSyntax.self) {
                rawTypeName = optionalType.wrappedType.trimmedDescription; isOptional = true
            } else {
                rawTypeName = typeSyntax.trimmedDescription; isOptional = false
            }
            let finalSwiftTypeString = isOptional ? "\(rawTypeName)?" : rawTypeName
            // Standard log kept for now
             print("  Processing Property: \(currentStructName ?? "").\(variableName) (Type: \(finalSwiftTypeString), Optional: \(isOptional), Doc: \(varDoc != nil))")
            let paramInfo = ParameterInfo(name: variableName, swiftType: finalSwiftTypeString, description: varDoc, isOptional: isOptional)
            currentParameters.append(paramInfo)
        }
        return .skipChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
         guard parsingError == nil else { return .skipChildren }
         let enumName = node.name.text
         // print("Visiting enum: \(enumName)") // Keep for now
         var inheritsFromString = false
         if let inheritance = node.inheritanceClause {
             inheritsFromString = inheritance.inheritedTypes.contains { $0.type.as(IdentifierTypeSyntax.self)?.name.text == "String" }
         }
         guard inheritsFromString else { return .skipChildren }

         print("  Found String enum: \(enumName). Caching definition.")
         let enumDoc = extractLeadingDocumentation(from: Syntax(node))
         var cases: [EnumCaseInfo] = []
         for member in node.memberBlock.members {
             guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
             for element in caseDecl.elements {
                 let caseName = element.name.text
                 let caseElementDoc = extractLeadingDocumentation(from: Syntax(element))
                 // print("    Found case: \(caseName)") // DEBUG
                 cases.append(EnumCaseInfo(name: caseName, description: caseElementDoc))
             }
         }
         if !cases.isEmpty { enumCache[enumName] = EnumSchemaInfo(name: enumName, description: enumDoc, cases: cases) }
          else { print("  Warning: String enum '\(enumName)' has no cases.")}
         return .skipChildren
    }

    // MARK: Helper Methods
    /// Extracts documentation comments.
    private func extractLeadingDocumentation(from node: Syntax) -> String? {
        // Multi-line version for readability
        var commentLines: [String] = []
        for triviaPiece in node.leadingTrivia.reversed() {
            switch triviaPiece {
            case .docLineComment(let text):
                commentLines.append(text.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")))
            case .docBlockComment(let text):
                let cleanedText = text.split(separator: "\n").map { line -> String in
                    var trimmedLine = line.trimmingCharacters(in: .whitespaces)
                    if trimmedLine.hasSuffix("*/") { trimmedLine.removeLast(trimmedLine.hasPrefix("/**") && trimmedLine.count <= 5 ? 0 : 2) }
                    if trimmedLine.hasPrefix("/**") { trimmedLine.removeFirst(3) }
                    if trimmedLine.hasPrefix("* ") { trimmedLine.removeFirst(2) }
                    else if trimmedLine.hasPrefix("*") { trimmedLine.removeFirst(1) }
                    return trimmedLine.trimmingCharacters(in: .whitespaces)
                }.filter { !$0.isEmpty }.joined(separator: "\n")
                if !cleanedText.isEmpty { commentLines.append(cleanedText) }
            case .newlines, .spaces, .tabs, .carriageReturns, .carriageReturnLineFeeds:
                continue
            default:
                guard !commentLines.isEmpty else { return nil }
                 return commentLines.reversed().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return commentLines.isEmpty ? nil : commentLines.reversed().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Syntax Extension (Keep as is)
extension TypeSyntax {
    var trimmedDescription: String { return self.trimmed.description }
}
