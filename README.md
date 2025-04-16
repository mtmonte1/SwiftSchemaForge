# SwiftSchemaForge

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)]() <!-- Placeholder -->
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT) <!-- Placeholder -->
[![Swift Version](https://img.shields.io/badge/Swift-5.10+-orange.svg)]() <!-- Placeholder -->

A command-line tool for macOS to automatically generate JSON Schema definitions suitable for LLM function/tool calling (OpenAI, Grok, Gemini formats) directly from Swift `Codable` struct definitions in your source code.

## Overview

Large Language Models (LLMs) often support "Function Calling" or "Tool Use" features, allowing them to request structured data or actions from external APIs. Defining the expected parameters for these functions requires specific JSON Schema objects. Manually creating and maintaining these schemas alongside Swift `Codable` models is tedious, error-prone, and doesn't scale well.

`SwiftSchemaForge` solves this by parsing your Swift source code file(s) containing `Codable` struct definitions and automatically generating the necessary JSON schema in the formats required by popular LLMs.

## Key Features

*   **Parses Swift Source:** Reads individual `.swift` files or recursively scans directories for `.swift` files. <!-- MODIFIED -->
*   **Targeted Generation:** Generates schemas only for structs explicitly specified via `--type-name`.
*   **Documentation Extraction:** Uses standard Swift documentation comments (`///` or `/** ... */`) for generating `description` fields in the schema for both functions (structs) and parameters (properties).
*   **Type Mapping:** Maps common Swift types (including `Int`, `String`, `Bool`, `Double`, `Float`, `Date`, `URL`, `UUID`, `Data`, `Optional<T>`, `Array<T>`, `[String: T]`) to appropriate JSON Schema types and formats (`integer`, `string`, `boolean`, `number`, `array`, `object`, `date-time`, `uri`, `uuid`, `byte`).
*   **Optional Handling:** Correctly identifies optional properties (`T?`) and populates the JSON Schema `required` array.
*   **Enum Support (Basic):** Generates `{"type": "string", "enum": ["case1", ...]}` for simple `enum EnumName: String, Codable { ... }` types used as properties, including case descriptions in the overall parameter description. (Does not respect custom raw values). <!-- NEW -->
*   **Nested Struct Support (Conditional):** Generates inline nested object schemas for properties whose type is another struct *only if* that nested struct's name was *also* specified via `--type-name`. <!-- MODIFIED -->
*   **Multiple LLM Formats:** Supports output formats for:
    *   OpenAI (`tools` array format)
    *   Grok (Currently identical to OpenAI format)
    *   Gemini (`FunctionDeclaration` array format)
*   **CLI Integration:** Easy to invoke from terminal or integrate into Xcode build scripts.
*   **Valid JSON Output:** Produces well-formatted and escaped JSON. Optional pretty-printing. Outputs a single aggregated JSON file. <!-- MODIFIED -->

## Requirements

*   **macOS:** macOS 13.0 (Ventura) or later.
*   **Swift:** Swift 5.10 or later toolchain.

## Installation

1.  **Clone the Repository:**
    ```bash
    git clone https://github.com/mtmonte1/SwiftSchemaForge.git # Using your updated URL
    cd SwiftSchemaForge
    ```

2.  **Build:**
    ```bash
    swift build -c release
    ```
    The executable will be located at `.build/release/SwiftSchemaForge`.

3.  **(Optional) Install Globally:**
    ```bash
    cp .build/release/SwiftSchemaForge /usr/local/bin/swiftschemaforge
    ```

## Usage

Specify *either* `--input-file` OR `--input-dir`. Provide one or more `--type-name` arguments.

**Using a single input file:**

```bash
swiftschemaforge --input-file <path/to/YourModels.swift> \
                 --type-name <StructName1> [--type-name <StructName2> ...] \
                 --output-file <path/to/output.json> \
                 [--format <openai|grok|gemini>] \
                 [--pretty-print]
Use code with caution.
Markdown
Using an input directory:

# Will recursively scan ./MyProject/Sources for .swift files
swiftschemaforge --input-dir <path/to/MyProject/Sources> \
                 --type-name <StructName1> [--type-name <StructName2> ...] \
                 --output-file <path/to/aggregated_output.json> \
                 [--format <openai|grok|gemini>] \
                 [--pretty-print]
Use code with caution.
Bash
Options: <!-- MODIFIED Table -->

Option    Short    Required    Description
--input-file    -i    Yes (or input-dir)    Path to a single input .swift source file containing target struct definitions.
--input-dir    -d    Yes (or input-file)    Path to a directory containing .swift files to process recursively.
--type-name    -t    Yes    Name of the Codable Swift struct(s) to generate schema for. Can be repeated for multiple structs.
--output-file    -o    Yes    Path where the single aggregated output JSON schema file should be written.
--format        No    Output format (openai, grok, gemini). Defaults to openai.
--pretty-print        No    Output JSON in a human-readable, indented format with sorted keys.
--version        No    Display the version of the tool.
--help    -h    No    Show usage instructions and available options.
Note: You must provide exactly one of --input-file or --input-dir.

Examples
Input Swift Files:

Assume you have:

Models/User.swift (defines UserProfile, Address, TaskStatus, Priority)
Models/Orders.swift (defines Order, LineItem)
Example 1: Generate Schema for UserProfile and its nested Address:

swiftschemaforge -i Models/User.swift \
                 -t UserProfile \
                 -t Address \
                 -o user_profile_schema.json \
                 --pretty-print
Use code with caution.
Bash
(Generates UserProfile schema, which includes the inline schema for Address because Address was also specified with -t)

Example 2: Generate Schemas for structs across multiple files:

# Assume Order uses UserProfile as a property type
swiftschemaforge -d Models \
                 -t Order \
                 -t UserProfile \
                 -t Address \
                 -t LineItem \
                 -o all_schemas.json \
                 --format gemini
Use code with caution.
Bash
(Scans the Models directory, finds all four structs, generates schemas including nested ones (UserProfile in Order, Address in UserProfile), and outputs a single aggregated JSON in Gemini format)

Example 3: Generate only Order, fails if Order needs other non-basic types:

# This will likely FAIL if Order uses UserProfile, Address, or LineItem types
swiftschemaforge -i Models/Orders.swift \
                 -t Order \
                 -o order_schema.json
Use code with caution.
Bash
(Fails with an error because the generation for Order would require processing UserProfile, Address, or LineItem, but they weren't requested via -t)

<!-- Removed verbose JSON examples for brevity, refer to actual output files -->
Supported Swift Features
Input: Single .swift files (--input-file) or recursive directory scanning (--input-dir). <!-- MODIFIED -->
struct Declarations: Only generates schemas for struct types specified via --type-name.
Codable Conformance: Assumed, not enforced syntactically.
Basic Types: String, Int variants, Bool, Double, Float, CGFloat.
Foundation Types: Date, URL, UUID, Data.
Optionals: Type? (adjusts required array).
Arrays: [Type] including nested [[Type]] (where Type is supported).
Dictionaries: [String: Type] (where Type is supported, key must be String).
Enums: Simple enum Name: String, Codable are parsed when used as property types. Generates JSON Schema enum constraint using case names. Doc comments supported. <!-- MODIFIED -->
Nested Structs: Requires the nested struct type to also be specified via --type-name. Cycle detection included. <!-- MODIFIED -->
Doc Comments: /// and /** ... */ for struct and property descriptions.
Limitations & Unsupported Features
Output: Only generates a single aggregated JSON file, even with directory input. <!-- NEW -->
Non-Struct/Enum Types: Does not process class, protocol, complex enums.
Generics/Property Wrappers/Computed Properties: Not supported.
Complex Codable Logic: Ignores CodingKeys, custom encode/decode.
Type Resolution: Limited to syntactic names within processed files. No complex alias or cross-file resolution (beyond finding types in files scanned via --input-dir).
Enum Raw Values: Uses case names, not specified raw values.
Semantic Analysis: Purely syntactic parsing.
Roadmap / Future Work
Option for separate output files per input file when using --input-dir.
Improve Enum support (respect raw values).
Automatic nested struct handling without requiring --type-name (more complex).
Support marking structs via a protocol instead of only name matching.
Configuration files.
More robust error reporting.
Formal unit and snapshot testing.
Contributing
Contributions are welcome! Please feel free to submit issues or pull requests on the GitHub repository. <!-- Your URL -->

License
This project is licensed under the MIT License. (It's recommended to add a LICENSE file containing the MIT license text to your repository).
