// Sources/TestModels.swift

import Foundation

// --- Enums ---
/// Represents the status of a task.
enum TaskStatus: String, Codable {
    /// Task is pending assignment.
    case pending
    /// Task is actively being worked on.
    case active = "in_progress" // Test raw value - schema should use 'active'
    /// Task is completed successfully.
    case completed
    /// Task failed or was cancelled.
    case failed
}

/// Represents different priority levels.
enum Priority: String, Codable {
    // No overall doc comment
    /// Low priority task.
    case low
    /// Medium priority task.
    case medium // No case doc comment
    /// High priority task.
    case high = "urgent" // Test raw value
}

// --- Structs ---

/// Represents user profile information.
struct UserProfile: Codable {
    /// The unique identifier for the user.
    let userId: Int
    /// The user's full name. Can be nil if not provided during signup.
    var fullName: String?
    /// Indicates if the user's email has been verified.
    let isVerified: Bool
    /**
     A multi-line block comment describing the signup date.
     Stored as an ISO 8601 formatted string in JSON.
     */
    let signupDate: Date
    // No doc comment for this property
    var points: Double = 0.0
    /// List of tags associated with the user. Can be empty.
    let tags: [String]
    /// Optional URL to the user's profile picture.
    let profilePictureURL: URL?
    /// User preferences stored as string key-value pairs. E.g., "theme": "dark"
    let preferences: [String: String]?
    /// Some miscellaneous config data.
    let configData: Data
    /// The primary address associated with the user profile.
    let primaryAddress: Address // Nested struct
    /// Current user status.
    var status: TaskStatus // Required Enum
    /// User's notification preference.
    var alertPriority: Priority? // Optional Enum
    /// Unique session identifier, if available.
    var sessionID: UUID? // Added UUID type
}

/// Defines shipping address details.
struct Address: Codable {
    /// Street address line 1.
    let street: String
    /// Optional street address line 2.
    var streetOptional: String?
    /// City name.
    let city: String
    /** Postal code (ZIP code). */
    let postalCode: String
    /// Optional array of phone numbers associated with this address.
    var phoneNumbers: [String]?
    /// Nested array example for testing basic array handling.
    let nestedCoordinates: [[Int]]?
    /// Additional details, where values are simple numeric counters.
    var deliveryNotes: [String: Int]
}

/// Internal struct not intended for direct schema generation usually.
struct InternalConfig: Codable {
    let apiKey: String
    let timeoutSeconds: Int
}

/// A simple struct to test with no documentation at all.
struct MinimalData: Codable {
    let id: String
    var value: Int?
}
