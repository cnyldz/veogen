//
//  FalService.swift
//  veogen
//
//  Created by Heavyshark on 6.06.2025.
//

import Combine
import Foundation

/// Service for interacting with fal.ai's Veo 3 model
class FalService: ObservableObject {

    // MARK: - Configuration

    private let baseURL = "https://queue.fal.run"
    private let modelEndpoint = "fal-ai/veo3"
    private var apiKey: String

    // MARK: - Publishers

    @Published var isGenerating = false
    @Published var generationProgress: Double = 0.0
    @Published var generationLogs: [String] = []

    // MARK: - Private Properties

    private var currentTask: Task<Void, Never>?
    private let session: URLSession

    // MARK: - Initialization

    init(apiKey: String) {
        self.apiKey = apiKey
        self.session = URLSession.shared
    }

    // MARK: - Public Methods

    /// Generate a video from a text prompt
    /// - Parameters:
    ///   - prompt: The text description for the video
    ///   - aspectRatio: Video aspect ratio (16:9 or 9:16)
    ///   - duration: Video duration in seconds (5-8s)
    ///   - resolution: Video resolution (currently 720p)
    ///   - progressCallback: Optional callback for progress updates
    /// - Returns: FalVideoResponse containing the generated video URL
    func generateVideo(
        prompt: String,
        aspectRatio: AspectRatio = .landscape,
        duration: Double = 5.0,
        resolution: VideoResolution = .hd720,
        progressCallback: ((Double, String?) -> Void)? = nil
    ) async throws -> FalVideoResponse {

        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FalError.invalidPrompt
        }

        // Validate parameters
        try validateParameters(duration: duration, resolution: resolution)

        // Update UI state
        await MainActor.run {
            isGenerating = true
            generationProgress = 0.0
            generationLogs = []
        }

        do {
            let request = FalVideoRequest(
                prompt: prompt,
                aspectRatio: aspectRatio.rawValue,
                duration: duration,
                resolution: resolution.rawValue
            )

            // Subscribe to the generation queue
            let response = try await subscribeToGeneration(
                request: request,
                progressCallback: progressCallback
            )

            await MainActor.run {
                isGenerating = false
                generationProgress = 1.0
            }

            return response

        } catch {
            await MainActor.run {
                isGenerating = false
                generationProgress = 0.0
            }
            throw error
        }
    }

    /// Cancel the current video generation
    func cancelGeneration() {
        currentTask?.cancel()
        currentTask = nil

        Task { @MainActor in
            isGenerating = false
            generationProgress = 0.0
            generationLogs = []
        }
    }

    // MARK: - Private Methods

    private func validateParameters(duration: Double, resolution: VideoResolution) throws {
        // Validate duration (5-8 seconds for Veo 3)
        guard duration >= 5.0 && duration <= 8.0 else {
            throw FalError.invalidDuration
        }

        // Validate resolution (currently only 720p supported)
        guard resolution == .hd720 else {
            throw FalError.unsupportedResolution
        }
    }

    private func subscribeToGeneration(
        request: FalVideoRequest,
        progressCallback: ((Double, String?) -> Void)?
    ) async throws -> FalVideoResponse {

        // Step 1: Submit the generation request
        let requestId = try await submitGenerationRequest(request)

        // Step 2: Poll for results with progress updates
        return try await pollForResults(
            requestId: requestId,
            progressCallback: progressCallback
        )
    }

    private func submitGenerationRequest(_ request: FalVideoRequest) async throws -> String {
        let url = URL(string: "\(baseURL)/\(modelEndpoint)")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FalError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw FalError.apiError(httpResponse.statusCode, errorMessage)
        }

        let submitResponse = try JSONDecoder().decode(FalSubmitResponse.self, from: data)
        return submitResponse.requestId
    }

    private func pollForResults(
        requestId: String,
        progressCallback: ((Double, String?) -> Void)?
    ) async throws -> FalVideoResponse {

        let statusURL = URL(string: "\(baseURL)/requests/\(requestId)/status")!
        var statusRequest = URLRequest(url: statusURL)
        statusRequest.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")

        let maxAttempts = 120  // 10 minutes with 5-second intervals
        var attempts = 0

        while attempts < maxAttempts {
            // Check if task was cancelled
            try Task.checkCancellation()

            let (data, response) = try await session.data(for: statusRequest)

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                throw FalError.networkError("Failed to check status")
            }

            let statusResponse = try JSONDecoder().decode(FalStatusResponse.self, from: data)

            // Update progress
            let progress = Double(attempts) / Double(maxAttempts)
            await updateProgress(progress, statusResponse.status)
            progressCallback?(progress, statusResponse.status)

            switch statusResponse.status {
            case "completed":
                guard let result = statusResponse.output else {
                    throw FalError.noOutput
                }
                return result

            case "failed":
                let errorMessage = statusResponse.error ?? "Generation failed"
                throw FalError.generationFailed(errorMessage)

            case "in_progress", "in_queue":
                // Continue polling
                break

            default:
                throw FalError.unknownStatus(statusResponse.status)
            }

            // Wait before next poll
            try await Task.sleep(nanoseconds: 5_000_000_000)  // 5 seconds
            attempts += 1
        }

        throw FalError.timeout
    }

    @MainActor
    private func updateProgress(_ progress: Double, _ status: String) {
        generationProgress = progress

        let logMessage = "Status: \(status) (\(Int(progress * 100))%)"
        if generationLogs.last != logMessage {
            generationLogs.append(logMessage)
        }
    }
}

// MARK: - Request/Response Models

struct FalVideoRequest: Codable {
    let prompt: String
    let aspectRatio: String
    let duration: Double
    let resolution: String

    enum CodingKeys: String, CodingKey {
        case prompt
        case aspectRatio = "aspect_ratio"
        case duration
        case resolution
    }
}

struct FalSubmitResponse: Codable {
    let requestId: String

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
    }
}

struct FalStatusResponse: Codable {
    let status: String
    let output: FalVideoResponse?
    let error: String?
}

struct FalVideoResponse: Codable {
    let video: FalVideoFile
    let seed: Int?
    let timings: FalTimings?

    struct FalVideoFile: Codable {
        let url: String
        let contentType: String?
        let filename: String?
        let fileSize: Int?

        enum CodingKeys: String, CodingKey {
            case url
            case contentType = "content_type"
            case filename
            case fileSize = "file_size"
        }
    }

    struct FalTimings: Codable {
        let inference: Double?
        let total: Double?
    }
}

// MARK: - Error Types

enum FalError: LocalizedError {
    case invalidPrompt
    case invalidDuration
    case unsupportedResolution
    case networkError(String)
    case apiError(Int, String)
    case generationFailed(String)
    case noOutput
    case unknownStatus(String)
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidPrompt:
            return "Please provide a valid prompt"
        case .invalidDuration:
            return "Duration must be between 5 and 8 seconds"
        case .unsupportedResolution:
            return "Only 720p resolution is currently supported"
        case .networkError(let message):
            return "Network error: \(message)"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .generationFailed(let message):
            return "Generation failed: \(message)"
        case .noOutput:
            return "No video output received"
        case .unknownStatus(let status):
            return "Unknown generation status: \(status)"
        case .timeout:
            return "Generation timed out. Please try again."
        case .cancelled:
            return "Generation was cancelled"
        }
    }
}

// MARK: - Extensions

extension FalService {
    /// Convenience method to generate video with default settings
    func generateVideo(prompt: String) async throws -> FalVideoResponse {
        return try await generateVideo(
            prompt: prompt,
            aspectRatio: .landscape,
            duration: 5.0,
            resolution: .hd720
        )
    }

    /// Check if the service is properly configured
    var isConfigured: Bool {
        return !apiKey.isEmpty
    }

    /// Estimate generation cost based on duration
    func estimatedCost(for duration: Double) -> Double {
        // Base cost for 5 seconds, additional cost per extra second
        let baseCost = 0.10  // $0.10 for 5 seconds
        let extraSeconds = max(0, duration - 5.0)
        let extraCost = extraSeconds * 0.02  // $0.02 per extra second

        return baseCost + extraCost
    }
}

// MARK: - Sample/Test Methods

extension FalService {
    /// Create a mock service for testing/previews
    static func mock() -> FalService {
        return FalService(apiKey: "mock-api-key")
    }

    /// Simulate generation for testing
    func simulateGeneration(
        prompt: String,
        duration: TimeInterval = 10.0
    ) async throws -> FalVideoResponse {

        await MainActor.run {
            isGenerating = true
            generationProgress = 0.0
            generationLogs = ["Starting simulation..."]
        }

        // Simulate progress updates
        for i in 1...10 {
            try await Task.sleep(nanoseconds: UInt64(duration * 100_000_000))  // duration/10 seconds

            let progress = Double(i) / 10.0
            await MainActor.run {
                generationProgress = progress
                generationLogs.append("Progress: \(Int(progress * 100))%")
            }
        }

        await MainActor.run {
            isGenerating = false
            generationProgress = 1.0
            generationLogs.append("Simulation complete!")
        }

        // Return mock response
        return FalVideoResponse(
            video: FalVideoResponse.FalVideoFile(
                url: "https://example.com/mock-video.mp4",
                contentType: "video/mp4",
                filename: "generated_video.mp4",
                fileSize: 1_024_000
            ),
            seed: 12345,
            timings: FalVideoResponse.FalTimings(
                inference: 8.5,
                total: 10.2
            )
        )
    }
}
