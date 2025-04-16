import Foundation

// --- NEW Enums ---
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


/// Represents user profile information.
struct UserProfile: Codable {
    // ... (Existing properties) ...
    let userId: Int
    var fullName: String?
    let isVerified: Bool
    let signupDate: Date
    var points: Double = 0.0
    let tags: [String]
    let profilePictureURL: URL?
    let preferences: [String: String]?
    let configData: Data
    let primaryAddress: Address

    // --- NEW Enum Properties ---
    /// Current user status.
    var status: TaskStatus // Required Enum
    /// User's notification preference.
    var alertPriority: Priority? // Optional Enum
    // --- End Enum Properties ---
}

/// Defines shipping address details.
struct Address: Codable {
    // ... (Existing properties) ...
    let street: String
    var streetOptional: String?
    let city: String
    let postalCode: String
    var phoneNumbers: [String]?
    let nestedCoordinates: [[Int]]?
    var deliveryNotes: [String: Int]
}

// ... (InternalConfig, MinimalData remain) ...
