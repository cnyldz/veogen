//
//  Video.swift
//  veogen
//
//  Created by Heavyshark on 6.06.2025.
//

import Foundation

struct Video: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: String
    let prompt: String
    let aspectRatio: AspectRatio
    let duration: Double  // in seconds
    let resolution: VideoResolution
    let frameRate: Int
    let createdAt: Date
    let updatedAt: Date

    // Storage and URLs
    let storageKey: String  // e.g., "user-videos/{userId}/{uuid}.mp4"
    let thumbnailStorageKey: String?  // e.g., "user-videos/{userId}/{uuid}_thumb.jpg"
    var videoURL: URL?
    var thumbnailURL: URL?

    // Generation metadata
    let generationId: String?  // fal.ai request ID for tracking
    var status: VideoStatus
    var generationTime: Double?  // seconds taken to generate
    var errorMessage: String?

    // Optional metadata
    var title: String?
    var tags: [String]
    var favorited: Bool
    var shareCount: Int
    var viewCount: Int

    init(
        id: UUID = UUID(),
        userId: String,
        prompt: String,
        aspectRatio: AspectRatio = .landscape,
        duration: Double = 5.0,
        resolution: VideoResolution = .hd720,
        frameRate: Int = 24,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        storageKey: String? = nil,
        thumbnailStorageKey: String? = nil,
        videoURL: URL? = nil,
        thumbnailURL: URL? = nil,
        generationId: String? = nil,
        status: VideoStatus = .pending,
        generationTime: Double? = nil,
        errorMessage: String? = nil,
        title: String? = nil,
        tags: [String] = [],
        favorited: Bool = false,
        shareCount: Int = 0,
        viewCount: Int = 0
    ) {
        self.id = id
        self.userId = userId
        self.prompt = prompt
        self.aspectRatio = aspectRatio
        self.duration = duration
        self.resolution = resolution
        self.frameRate = frameRate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.storageKey = storageKey ?? "user-videos/\(userId)/\(id.uuidString).mp4"
        self.thumbnailStorageKey =
            thumbnailStorageKey ?? "user-videos/\(userId)/\(id.uuidString)_thumb.jpg"
        self.videoURL = videoURL
        self.thumbnailURL = thumbnailURL
        self.generationId = generationId
        self.status = status
        self.generationTime = generationTime
        self.errorMessage = errorMessage
        self.title = title
        self.tags = tags
        self.favorited = favorited
        self.shareCount = shareCount
        self.viewCount = viewCount
    }
}

// MARK: - Supporting Enums

enum VideoStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"

    var displayName: String {
        switch self {
        case .pending:
            return "Pending"
        case .processing:
            return "Generating..."
        case .completed:
            return "Ready"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }

    var isInProgress: Bool {
        return self == .pending || self == .processing
    }

    var isCompleted: Bool {
        return self == .completed
    }

    var isFailed: Bool {
        return self == .failed || self == .cancelled
    }
}

enum VideoResolution: String, Codable, CaseIterable {
    case hd720 = "720p"
    case hd1080 = "1080p"  // Future support

    var displayName: String {
        return self.rawValue
    }

    var dimensions: (width: Int, height: Int) {
        switch self {
        case .hd720:
            return (width: 1280, height: 720)
        case .hd1080:
            return (width: 1920, height: 1080)
        }
    }
}

enum AspectRatio: String, CaseIterable, Codable {
    case landscape = "16:9"
    case portrait = "9:16"

    var displayName: String {
        return self.rawValue
    }

    var isLandscape: Bool {
        return self == .landscape
    }

    var ratio: Double {
        switch self {
        case .landscape:
            return 16.0 / 9.0
        case .portrait:
            return 9.0 / 16.0
        }
    }

    var dimensions: (width: Int, height: Int) {
        switch self {
        case .landscape:
            return (width: 1280, height: 720)
        case .portrait:
            return (width: 720, height: 1280)
        }
    }
}

// MARK: - Extensions

extension Video {
    var formattedDuration: String {
        return String(format: "%.1fs", duration)
    }

    var formattedCreatedAt: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    var isReady: Bool {
        return status == .completed && videoURL != nil
    }

    var canRegenerate: Bool {
        return status == .failed || status == .completed
    }

    // Generate a new variant with the same prompt
    func createVariant() -> Video {
        return Video(
            userId: self.userId,
            prompt: self.prompt,
            aspectRatio: self.aspectRatio,
            duration: self.duration,
            resolution: self.resolution,
            frameRate: self.frameRate,
            title: self.title.map { "\($0) (Variant)" },
            tags: self.tags
        )
    }

    // Create a copy for regeneration
    func regenerate() -> Video {
        return Video(
            userId: self.userId,
            prompt: self.prompt,
            aspectRatio: self.aspectRatio,
            duration: self.duration,
            resolution: self.resolution,
            frameRate: self.frameRate,
            title: self.title,
            tags: self.tags
        )
    }
}

// MARK: - Sample Data

extension Video {
    static let sampleVideos: [Video] = [
        Video(
            userId: "sample-user-1",
            prompt:
                "A vintage red convertible driving along Pacific Coast Highway at sunset, drifts into a hair-pin turn, 70mm IMAX, retro-noir palette",
            aspectRatio: .landscape,
            status: .completed,
            title: "Sunset Drive",
            tags: ["car", "sunset", "cinematic"],
            favorited: true
        ),
        Video(
            userId: "sample-user-1",
            prompt: "A majestic eagle soaring over snow-capped mountains with golden hour lighting",
            aspectRatio: .portrait,
            status: .processing,
            title: "Mountain Eagle",
            tags: ["nature", "wildlife", "mountains"]
        ),
        Video(
            userId: "sample-user-1",
            prompt: "Cyberpunk city street at night with neon reflections in the rain",
            aspectRatio: .landscape,
            status: .failed,
            errorMessage: "Content safety filter triggered",
            title: "Neon City",
            tags: ["cyberpunk", "city", "rain"]
        ),
    ]
}
