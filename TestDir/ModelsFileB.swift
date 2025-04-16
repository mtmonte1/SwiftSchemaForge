// TestDir/ModelsFileB.swift
import Foundation

struct IgnoreThisOne: Codable {
    let ignoredId: Int
}

/// A very simple extra structure.
struct ExtraSimpleData: Codable {
    /// A boolean flag.
    let isActive: Bool
    /// An optional score value.
    var score: Float?
}
