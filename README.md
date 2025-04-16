# SwiftSchemaForge

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)]() <!-- Placeholder -->
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT) <!-- Placeholder -->
[![Swift Version](https://img.shields.io/badge/Swift-5.10+-orange.svg)]() <!-- Placeholder -->

A command-line tool for macOS to automatically generate JSON Schema definitions suitable for LLM function/tool calling (OpenAI, Grok, Gemini formats) directly from Swift `Codable` struct definitions in your source code.

## Overview

Large Language Models (LLMs) often support "Function Calling" or "Tool Use" features, allowing them to request structured data or actions from external APIs. Defining the expected parameters for these functions requires specific JSON Schema objects. Manually creating and maintaining these schemas alongside Swift `Codable` models is tedious, error-prone, and doesn't scale well.

`SwiftSchemaForge` solves this by parsing your Swift source code containing `Codable` struct definitions and automatically generating the necessary JSON schema in the formats required by popular LLMs.

## Key Features

*   **Parses Swift Source:** Reads `.swift` files containing your `Codable` struct definitions.
*   **Targeted Generation:** Generates schemas only for structs explicitly specified via command-line arguments.
*   **Documentation Extraction:** Uses standard Swift documentation comments (`///` or `/** ... */`) for generating `description` fields in the schema for both functions (structs) and parameters (properties).
*   **Type Mapping:** Maps common Swift types (including `Int`, `String`, `Bool`, `Double`, `Float`, `Date`, `URL`, `UUID`, `Data`, `Optional<T>`, `Array<T>`, `[String: T]`) to appropriate JSON Schema types and formats (`integer`, `string`, `boolean`, `number`, `array`, `object`, `date-time`, `uri`, `uuid`, `byte`).
*   **Optional Handling:** Correctly identifies optional properties (`T?`) and populates the JSON Schema `required` array.
*   **Enum Support (Basic):** Generates `{"type": "string", "enum": ["case1", ...]}` for simple `enum EnumName: String, Codable { ... }` types used as properties, including case descriptions in the overall parameter description. (Does not respect custom raw values).
*   **Nested Struct Support:** Generates inline nested object schemas for properties whose type is another struct *if* that nested struct was also specified as a target via `--type-name`.
*   **Multiple LLM Formats:** Supports output formats for:
    *   OpenAI (`tools` array format)
    *   Grok (Currently identical to OpenAI format)
    *   Gemini (`FunctionDeclaration` array format)
*   **CLI Integration:** Easy to invoke from terminal or integrate into Xcode build scripts.
*   **Valid JSON Output:** Produces well-formatted and escaped JSON. Optional pretty-printing.

## Requirements

*   **macOS:** macOS 13.0 (Ventura) or later (due to dependencies like SwiftSyntax and modern Swift features).
*   **Swift:** Swift 5.10 or later toolchain (required for the specific SwiftSyntax version used).

## Installation

1.  **Clone the Repository:**
    ```bash
    git clone https://github.com/mtmonte1/SwiftSchemaForge.git
    ```

2.  **Build:**
    *   For debugging:
        ```bash
        swift build
        ```
        The executable will be located at `.build/debug/SwiftSchemaForge`.
    *   For a release build (optimized):
        ```bash
        swift build -c release
        ```
        The executable will be located at `.build/release/SwiftSchemaForge`.

3.  **(Optional) Install Globally:** For easier access from anywhere, copy the executable to a location in your `PATH`:
    ```bash
    # Example using release build:
    cp .build/release/SwiftSchemaForge /usr/local/bin/swiftschemaforge
    # You can then run it just by typing 'swiftschemaforge'
    ```

## Usage

```bash
swiftschemaforge --input-file <path/to/YourModels.swift> \
                 --type-name <StructName1> [--type-name <StructName2> ...] \
                 --output-file <path/to/output.json> \
                 [--format <openai|grok|gemini>] \
                 [--pretty-print] \
                 [--help] \
                 [--version]
Use code with caution.
Markdown
Options:

Option    Short    Required    Description
--input-file    -i    Yes    Path to the input .swift source file containing the target struct definitions.
--type-name    -t    Yes    Name of the Codable Swift struct(s) to generate schema for. Can be repeated for multiple structs.
--output-file    -o    Yes    Path where the output JSON schema file should be written.
--format        No    Output format (openai, grok, gemini). Defaults to openai.
--pretty-print        No    Output JSON in a human-readable, indented format with sorted keys.
--version        No    Display the version of the tool.
--help    -h    No    Show usage instructions and available options.
Examples
Input Swift (ExampleModels.swift):

import Foundation

/// Describes a user query for finding hotels.
struct HotelSearch: Codable {
    /// The destination city or area.
    let destination: String
    /// Check-in date (ISO 8601).
    let checkInDate: Date
    /// Optional check-out date (ISO 8601).
    var checkOutDate: Date?
    /// Number of adults staying. Defaults to 1 if not specified by user.
    let adults: Int
    /// Specific preferences for the stay.
    let preferences: SearchPreferences? // Nested Struct (Optional)
    /// Priority level for this search request.
    let priority: SearchPriority // Enum
}

/// Nested preferences structure.
struct SearchPreferences: Codable {
    /// Maximum allowed price per night.
    var maxPrice: Double?
    /// List of required amenities (e.g., "pool", "gym").
    let requiredAmenities: [String]
}

/// Priority levels for search requests.
enum SearchPriority: String, Codable {
    /// Standard priority
    case standard = "STD"
    /// High priority
    case high = "HIGH"
}
Use code with caution.
Swift
Command:

swiftschemaforge -i ExampleModels.swift \
                 -t HotelSearch \
                 -t SearchPreferences \
                 -o schema_output.json \
                 --format <FORMAT> \
                 --pretty-print
Use code with caution.
Bash
Output JSON (--format openai or --format grok):

[
  {
    "function": {
      "description": "Nested preferences structure.",
      "name": "SearchPreferences",
      "parameters": {
        "properties": {
          "maxPrice": {
            "description": "Maximum allowed price per night.",
            "type": "number"
          },
          "requiredAmenities": {
            "description": "List of required amenities (e.g., \"pool\", \"gym\").",
            "items": {
              "type": "string"
            },
            "type": "array"
          }
        },
        "required": [
          "requiredAmenities"
        ],
        "type": "object"
      }
    },
    "type": "function"
  },
  {
    "function": {
      "description": "Describes a user query for finding hotels.",
      "name": "HotelSearch",
      "parameters": {
        "properties": {
          "adults": {
            "description": "Number of adults staying. Defaults to 1 if not specified by user.",
            "type": "integer"
          },
          "checkInDate": {
            "description": "Check-in date (ISO 8601).",
            "format": "date-time",
            "type": "string"
          },
          "checkOutDate": {
            "description": "Optional check-out date (ISO 8601).",
            "format": "date-time",
            "type": "string"
          },
          "destination": {
            "description": "The destination city or area.",
            "type": "string"
          },
          "preferences": {
            "description": "Specific preferences for the stay.",
            "properties": {
              "maxPrice": {
                "description": "Maximum allowed price per night.",
                "type": "number"
              },
              "requiredAmenities": {
                "description": "List of required amenities (e.g., \"pool\", \"gym\").",
                "items": {
                  "type": "string"
                },
                "type": "array"
              }
            },
            "required": [
              "requiredAmenities"
            ],
            "type": "object"
          },
          "priority": {
            "description": "Priority level for this search request.\n\nPossible values:\n  - `standard`: Standard priority\n  - `high`: High priority",
            "enum": [
              "standard",
              "high"
            ],
            "type": "string"
          }
        },
        "required": [
          "destination",
          "checkInDate",
          "adults",
          "priority"
        ],
        "type": "object"
      }
    },
    "type": "function"
  }
]
Use code with caution.
Json
Output JSON (--format gemini):

[
  {
    "description": "Nested preferences structure.",
    "name": "SearchPreferences",
    "parameters": {
      "properties": {
        "maxPrice": {
          "description": "Maximum allowed price per night.",
          "type": "NUMBER"
        },
        "requiredAmenities": {
          "description": "List of required amenities (e.g., \"pool\", \"gym\").",
          "items": {
            "type": "STRING"
          },
          "type": "ARRAY"
        }
      },
      "required": [
        "requiredAmenities"
      ],
      "type": "OBJECT"
    }
  },
  {
    "description": "Describes a user query for finding hotels.",
    "name": "HotelSearch",
    "parameters": {
      "properties": {
        "adults": {
          "description": "Number of adults staying. Defaults to 1 if not specified by user.",
          "type": "INTEGER"
        },
        "checkInDate": {
          "description": "Check-in date (ISO 8601).",
          "type": "STRING"
        },
        "checkOutDate": {
          "description": "Optional check-out date (ISO 8601).",
          "type": "STRING"
        },
        "destination": {
          "description": "The destination city or area.",
          "type": "STRING"
        },
        "preferences": {
          "description": "Specific preferences for the stay.",
          "properties": {
            "maxPrice": {
              "description": "Maximum allowed price per night.",
              "type": "NUMBER"
            },
            "requiredAmenities": {
              "description": "List of required amenities (e.g., \"pool\", \"gym\").",
              "items": {
                "type": "STRING"
              },
              "type": "ARRAY"
            }
          },
          "required": [
            "requiredAmenities"
          ],
          "type": "OBJECT"
        },
        "priority": {
          "description": "Priority level for this search request.\n\nPossible values:\n  - `standard`: Standard priority\n  - `high`: High priority",
          "enum": [
            "standard",
            "high"
          ],
          "type": "STRING"
        }
      },
      "required": [
        "destination",
        "checkInDate",
        "adults",
        "priority"
      ],
      "type": "OBJECT"
    }
  }
]
Use code with caution.
Json
Supported Swift Features
struct Declarations: Only generates schemas for struct types.
Codable Conformance: Assumes structs intended for generation conform to Codable (syntactic check not performed).
Basic Types: String, Int (and variants like Int64), Bool, Double, Float.
Common Foundation Types: Date, URL, UUID, Data, CGFloat.
Optionals: Correctly identifies Type? and adjusts required array.
Arrays: Handles [Type], including nested arrays like [[Int]], where Type is any supported type.
Dictionaries: Handles simple dictionaries [String: Type], where Type is any supported type. Keys must be String.
Enums (String-based): Handles enum Name: String, Codable { case ... }. Maps to JSON Schema enum constraint using case names (not raw values). Doc comments on enum and cases are used.
Nested Structs: Handles properties whose type is another struct only if the nested struct's name is also provided via --type-name. Generates the nested schema inline. Handles simple cycles by detection.
Doc Comments: Parses /// and /** ... */ comments immediately preceding struct and property (let/var) declarations for descriptions.
Limitations & Unsupported Features
Non-Struct Types: Does not process class, protocol, or complex (non-String) enum types.
Computed Properties: Ignores computed properties (requires initialization block analysis).
Complex Generics: Does not support parsing or generating schemas for structs with complex generic type parameters or constraints.
Property Wrappers: Does not interpret the logic within property wrappers. It will see the property wrapper's underlying wrappedValue type syntax if declared explicitly, or may fail if the type is heavily obscured.
Complex Codable: Does not analyze custom CodingKeys, init(from:), or encode(to:) implementations. Relies on synthesized Codable behavior or simple key mapping.
Type Aliases: Does not resolve complex type aliases across files. Simple, same-file aliases might appear as their aliased name in the type string.
Cross-File Resolution: Cannot resolve type definitions located in other files (unless SwiftSyntax provides this easily in future). --input-file handles one file at a time.
Semantic Analysis: Performs syntactic parsing only. It doesn't guarantee the Swift code compiles or that types actually conform to Codable semantically.
RawRepresentable Enum Values: Currently uses the case name for String enums, not the raw value.
Non-String Dictionary Keys: Only [String: T] is supported.
GUI: This is a command-line tool only.
Roadmap / Future Work
Improve Enum support (respect raw values, potentially non-String enums if feasible).
Handle nested struct properties automatically without requiring --type-name (more complex parsing).
Add --input-directory and --output-directory options.
Support marking structs via a specific protocol conformance instead of only names.
Investigate handling simple type aliases.
Explore configuration files (e.g., .swift-schema-forge.yml).
More robust error reporting with source locations.
Generate schemas for other languages (e.g., Kotlin, TypeScript) from Swift (ambitious).
Contributing
Contributions are welcome! Please feel free to submit issues or pull requests on the GitHub repository. https://github.com/mtmonte1/SwiftSchemaForge.git

License
This project is licensed under the MIT License - see the LICENSE file for details. (You should create a LICENSE file containing the MIT license text).



