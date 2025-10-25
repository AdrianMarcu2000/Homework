//
//  AgenticAnalysisModels.swift
//  Homework
//
//  Created for Agentic Cloud Analysis
//  Data models for multi-agent homework analysis system
//

import Foundation

// MARK: - Agentic Analysis Request

/// Request model for agentic homework analysis
struct AgenticAnalysisRequest: Codable, Sendable {
    let imageBase64: String
    let ocrBlocks: [OCRBlockData]
    let userPreferences: UserPreferences?

    struct OCRBlockData: Codable, Sendable {
        let text: String
        let startY: Double
        let endY: Double
    }

    struct UserPreferences: Codable, Sendable {
        let detailLevel: String? // "summary", "detailed", "comprehensive"
        let includeExtraPractice: Bool?
        let preferredLanguage: String? // "en", "es", "de", etc.
    }
}

// MARK: - Agentic Analysis Response

/// Response model from agentic homework analysis
struct AgenticAnalysisResponse: @unchecked Sendable, Decodable {
    let routing: RoutingInfo
    let analysis: AnalysisData
    let metadata: ResponseMetadata

    // Explicitly nonisolated Decodable conformance
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.routing = try container.decode(RoutingInfo.self, forKey: .routing)
        self.analysis = try container.decode(AnalysisData.self, forKey: .analysis)
        self.metadata = try container.decode(ResponseMetadata.self, forKey: .metadata)
    }

    enum CodingKeys: String, CodingKey {
        case routing, analysis, metadata
    }

    /// Information about how the homework was classified and routed
    struct RoutingInfo: Codable, Sendable {
        let subject: String // "Math", "Science-Physics", "Language-English", etc.
        let contentType: String // "study_material", "exercises", "hybrid"
        let gradeLevel: String // "Elementary", "MiddleSchool", "HighSchool", "University"
        let confidence: Double // 0.0 to 1.0
        let agentUsed: String // e.g., "math_exercise_agent"
    }

    /// Analysis data from specialized agents
    struct AnalysisData: Codable, Sendable {
        let type: String // "exercises", "study_material"
        let subject: String
        let exercises: [AgenticExercise]?
        let summary: StudyMaterialSummary?
        let context: LearningContext?
        let practiceExercises: [PracticeExercise]?
        let overallMetadata: OverallMetadata?

        // For language exercises
        let language: String?
        let branch: String? // For science: "physics", "chemistry", "biology"
    }

    /// Study material summary (for lessons/theory)
    struct StudyMaterialSummary: Codable, Sendable {
        let title: String
        let mainTopics: [String]
        let keyPoints: [KeyPoint]
        let highlightedElements: [HighlightedElement]

        struct KeyPoint: Codable, Sendable {
            let point: String
            let importance: String // "high", "medium", "low"
            let position: Position?
        }

        struct HighlightedElement: Codable, Sendable {
            let type: String // "definition", "theorem", "formula", "example"
            let content: String
            let latexContent: String?
            let position: Position?
        }
    }

    /// Learning context for study material
    struct LearningContext: Codable, Sendable {
        let prerequisiteTopics: [String]
        let relatedConcepts: [String]
        let realWorldApplications: [String]
        let difficultyLevel: String // "beginner", "intermediate", "advanced"
    }

    /// Practice exercise from study material
    struct PracticeExercise: Codable, Sendable {
        let exerciseNumber: Int
        let questionText: String
        let questionLatex: String?
        let difficulty: String // "easy", "medium", "hard"
        let inputType: String
        let inputConfig: InputConfig
        let hints: [String]
    }

    /// Detailed exercise structure from agentic analysis
    struct AgenticExercise: Codable, Sendable {
        let exerciseNumber: String // Can be "2a", "1", "3b", etc. (changed from Int to support alphanumeric)
        let questionText: String
        let questionLatex: String?
        let topic: String
        let difficulty: String? // "easy", "medium", "hard" (optional for extraction-only)
        let estimatedTimeMinutes: Int?

        let inputType: String // Specialized input types
        let inputConfig: InputConfig? // Configuration for the input type (optional)

        let position: Position
        let relatedConcepts: [String]?
        let solutionSteps: [String]?

        // For language exercises
        let exerciseType: String? // "grammar", "vocabulary", "reading", etc.
        let grammarPattern: String? // "present_simple", "past_continuous", etc.

        // For science exercises
        let scientificData: ScientificData?
    }

    /// Scientific data for science exercises
    struct ScientificData: Codable, Sendable {
        let formulasNeeded: [String]
        let constants: [String]
        let safetyNotes: [String]
    }

    /// Configuration for different input types
    struct InputConfig: Codable, Sendable {
        // For inline fill-in-blanks
        let placeholders: [String]?
        let placeholderPositions: [PlaceholderPosition]?

        // For multiple choice
        let options: [String]?

        // For canvas types
        let canvasType: String? // "math", "freeform", "circuit", "molecule"
        let requiresGrid: Bool?

        // For text areas
        let minWords: Int?
        let maxWords: Int?

        // For science problems
        let expectedUnits: [String]?

        struct PlaceholderPosition: Codable, Sendable {
            let start: Int // Character index
            let end: Int
            let index: Int // Placeholder index (0, 1, 2...)
            let expectedType: String? // e.g., "verb_past_tense", "number", "equation"
        }
    }

    /// Position information for cropping
    struct Position: Codable, Sendable {
        let startY: Double // 0.0 to 1.0
        let endY: Double
    }

    /// Overall metadata for exercise sets
    struct OverallMetadata: Codable, Sendable {
        let totalExercises: Int
        let topics: [String]
        let estimatedTotalTime: Int // minutes
        let difficultyDistribution: [String: Int] // e.g., {"easy": 3, "medium": 5}
        let requiresLabEquipment: Bool?
        let exerciseTypes: [String]? // For language exercises
    }

    /// Metadata about the analysis process
    struct ResponseMetadata: Codable, Sendable {
        let processingTimeMs: Int
        let agentsInvoked: [String]
        let modelVersions: [String: String]
        let timestamp: String
    }
}

// MARK: - Input Type Enum

/// Enum for all supported input types
enum ExerciseInputType: String, Codable {
    case mathCanvas = "math_canvas"
    case drawingCanvas = "drawing_canvas"
    case textArea = "text_area"
    case textInput = "text_input"
    case inline = "inline"
    case multipleChoice = "multiple_choice"

    var displayName: String {
        switch self {
        case .mathCanvas: return "Math Canvas"
        case .drawingCanvas: return "Drawing Canvas"
        case .textArea: return "Text Area"
        case .textInput: return "Text Input"
        case .inline: return "Fill in Blanks"
        case .multipleChoice: return "Multiple Choice"
        }
    }

    var icon: String {
        switch self {
        case .mathCanvas: return "function"
        case .drawingCanvas: return "pencil.and.outline"
        case .textArea: return "text.alignleft"
        case .textInput: return "text.cursor"
        case .inline: return "text.insert"
        case .multipleChoice: return "list.bullet.circle"
        }
    }
}

// MARK: - Conversion Extensions

extension AgenticAnalysisResponse {

    /// Converts agentic response to the existing AnalysisResult format
    /// This maintains compatibility with existing UI components
    nonisolated func toAnalysisResult() -> AnalysisResult {
        var allExercises: [Exercise] = []

        // Convert exercises from the analysis
        if let exercises = analysis.exercises {
            for agenticEx in exercises {
                let exercise = Exercise(
                    exerciseNumber: agenticEx.exerciseNumber, // Already a String
                    type: inferExerciseType(from: agenticEx),
                    fullContent: formatExerciseContent(agenticEx),
                    startY: agenticEx.position.startY,
                    endY: agenticEx.position.endY,
                    subject: routing.subject,
                    inputType: agenticEx.inputType
                )
                allExercises.append(exercise)
            }
        }

        // Convert practice exercises from study material if present
        if let practiceExercises = analysis.practiceExercises {
            for practiceEx in practiceExercises {
                let exercise = Exercise(
                    exerciseNumber: "\(practiceEx.exerciseNumber)",
                    type: inferExerciseType(from: practiceEx.inputType),
                    fullContent: practiceEx.questionLatex ?? practiceEx.questionText,
                    startY: 0.0, // Practice exercises don't have positions
                    endY: 0.0,
                    subject: routing.subject,
                    inputType: practiceEx.inputType
                )
                allExercises.append(exercise)
            }
        }

        return AnalysisResult(exercises: allExercises)
    }

    nonisolated private func formatExerciseContent(_ exercise: AgenticExercise) -> String {
        if let latex = exercise.questionLatex, !latex.isEmpty {
            return latex
        }
        return exercise.questionText
    }

    nonisolated private func inferExerciseType(from agenticExercise: AgenticExercise) -> String {
        // Use the exercise type if available
        if let exerciseType = agenticExercise.exerciseType {
            return exerciseType
        }

        // Otherwise infer from input type
        return inferExerciseType(from: agenticExercise.inputType)
    }

    nonisolated private func inferExerciseType(from inputType: String) -> String {
        switch inputType {
        case "math_canvas": return "mathematical"
        case "drawing_canvas": return "diagram"
        case "text_area": return "essay"
        case "text_input": return "short_answer"
        case "inline": return "fill_in_blanks"
        case "multiple_choice": return "multiple_choice"
        default: return "other"
        }
    }
}

// MARK: - Extended Exercise Properties

/// Extension to add agentic-specific computed properties to existing Exercise struct
extension Exercise {

    /// Returns the recommended UI component for this exercise (based on inputType)
    var recommendedInputComponent: ExerciseInputType {
        guard let inputType = self.inputType else {
            return .mathCanvas // Default fallback
        }
        return ExerciseInputType(rawValue: inputType) ?? .mathCanvas
    }

    /// Returns true if this exercise is inline fill-in-blanks
    var isInlineType: Bool {
        return inputType == "inline"
    }

    /// Returns true if this exercise is multiple choice
    var isMultipleChoice: Bool {
        return inputType == "multiple_choice"
    }

    /// Returns true if this exercise requires a canvas
    var requiresCanvas: Bool {
        return inputType == "math_canvas" || inputType == "drawing_canvas" || inputType == "canvas"
    }

    /// Returns true if this exercise requires text input
    var requiresTextInput: Bool {
        return inputType == "text_area" || inputType == "text_input" || inputType == "text"
    }
}
