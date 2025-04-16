import Foundation

// MARK: - Struct Intermediate Representation

/// Intermediate Representation (IR) for the information extracted from a target
/// Swift struct, intended for generating a function/tool schema.
///
/// Conforms to Equatable and Hashable primarily for testing purposes or if needed
/// for storage in Sets or as Dictionary keys later.
struct FunctionSchemaInfo: Hashable, Equatable {
    /// The original name of the Swift struct (e.g., "UserProfile").
    let structName: String

    /// The documentation comment (`///` or `/** ... */`) attached to the struct.
    /// Used as the primary description for the generated function/tool.
    /// Combined and cleaned multi-line comments.
    let description: String?

    /// An array holding information about each relevant property (parameter)
    /// within the struct. Mutable (`var`) to allow modification during generation passes
    /// if necessary (e.g., by SchemaGenerator - though currently populated by parser).
    /// Marked `var` based on previous iteration needs, could potentially be `let`
    /// if parser guarantees full population. Keep as `var` for flexibility from Step 40 refactor.
    var parameters: [ParameterInfo]
}

/// Intermediate Representation (IR) for a single property within a target Swift struct.
/// Corresponds to a single parameter in the generated JSON schema's "properties".
///
/// Conforms to Equatable and Hashable primarily for testing purposes.
struct ParameterInfo: Hashable, Equatable {
    /// The name of the Swift property (e.g., "userId").
    let name: String

    /// The raw Swift type declaration string as it appeared in the source code
    /// (e.g., "String", "Int?", "[Date]", "[String: UserData]").
    /// This string representation is parsed further during schema generation (`mapSwiftType`).
    let swiftType: String

    /// The documentation comment (`///` or `/** ... */`) attached to the property.
    /// Used for the parameter's description field in the schema.
    /// Combined and cleaned multi-line comments.
    let description: String?

    /// A boolean indicating whether the property's type is optional
    /// (e.g., declared with `?` like `String?` or `[Item]?`).
    /// Determines inclusion in the JSON schema's 'required' array.
    let isOptional: Bool
}


// MARK: - Enum Intermediate Representation

/// Intermediate Representation (IR) for a parsed Swift enum that conforms to `String` raw values.
/// Used when generating schema for properties that have an enum type.
///
/// Conforms to Equatable and Hashable primarily for testing purposes.
struct EnumSchemaInfo: Hashable, Equatable {
    /// The name of the Swift enum (e.g., "TaskStatus").
    let name: String

    /// The documentation comment (`///` or `/** ... */`) attached to the enum definition.
    /// Used as the base description for the parameter's schema description.
    /// Combined and cleaned multi-line comments.
    let description: String?

    /// An array holding information about each case within the enum.
    let cases: [EnumCaseInfo]
}

/// Intermediate Representation (IR) for a single case element within a `String`-based Swift enum.
///
/// Conforms to Equatable and Hashable primarily for testing purposes.
struct EnumCaseInfo: Hashable, Equatable {
    /// The name of the enum case (e.g., "active"). This is the value used in the
    /// generated schema's "enum" array. Note that this parser does *not* currently
    /// respect explicit raw values (like `case active = "in_progress"`), it only uses
    /// the case name itself. Future enhancement could parse the raw value.
    let name: String

    /// The documentation comment (`///` or `/** ... */`) attached directly to the enum case element.
    /// Used to enrich the description in the parameter's schema.
    /// Combined and cleaned multi-line comments.
    let description: String?
}
