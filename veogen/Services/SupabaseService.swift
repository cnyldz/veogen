//
//  SupabaseService.swift
//  veogen
//
//  Created by Heavyshark on 6.06.2025.
//

import AuthenticationServices
import Combine
import Foundation
import Supabase

/// Service for handling Supabase authentication and storage operations
class SupabaseService: ObservableObject {

    // MARK: - Configuration

    private let supabaseURL: URL
    private let supabaseAnonKey: String
    private let supabase: SupabaseClient

    // MARK: - Publishers

    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var error: SupabaseError?

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private let videoBucketName = "user-videos"

    // MARK: - Initialization

    init(url: String, anonKey: String) {
        guard let supabaseURL = URL(string: url) else {
            fatalError("Invalid Supabase URL")
        }

        self.supabaseURL = supabaseURL
        self.supabaseAnonKey = anonKey
        self.supabase = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: anonKey)

        setupAuthListener()
    }

    // MARK: - Authentication

    /// Sign in with Apple using Supabase OAuth
    func signInWithApple() async throws {
        await setLoading(true)

        do {
            let session = try await supabase.auth.signInWithOAuth(
                provider: .apple,
                scopes: "name email"
            )

            // Create or update user profile
            if let supabaseUser = session.user {
                try await createOrUpdateUserProfile(from: supabaseUser)
            }

            await setLoading(false)

        } catch {
            await setLoading(false)
            throw SupabaseError.authenticationFailed(error.localizedDescription)
        }
    }

    /// Sign out the current user
    func signOut() async throws {
        await setLoading(true)

        do {
            try await supabase.auth.signOut()

            await MainActor.run {
                currentUser = nil
                isAuthenticated = false
                isLoading = false
            }

        } catch {
            await setLoading(false)
            throw SupabaseError.signOutFailed(error.localizedDescription)
        }
    }

    /// Check if user is currently authenticated
    func checkAuthStatus() async {
        do {
            if let session = try await supabase.auth.session {
                try await loadUserProfile(for: session.user.id.uuidString)
            } else {
                await MainActor.run {
                    isAuthenticated = false
                    currentUser = nil
                }
            }
        } catch {
            await setError(.authCheckFailed(error.localizedDescription))
        }
    }

    // MARK: - User Profile Management

    /// Create or update user profile in database
    private func createOrUpdateUserProfile(from supabaseUser: AuthUser) async throws {
        let userProfile = User(
            supabaseId: supabaseUser.id.uuidString,
            email: supabaseUser.email,
            displayName: supabaseUser.userMetadata?["name"] as? String,
            fullName: supabaseUser.userMetadata?["full_name"] as? String,
            lastSignInAt: Date(),
            emailVerified: supabaseUser.emailConfirmedAt != nil
        )

        try await saveUserProfile(userProfile)
    }

    /// Save user profile to database
    func saveUserProfile(_ user: User) async throws {
        do {
            try await supabase
                .from("users")
                .upsert(user, onConflict: "supabase_id")
                .execute()

            await MainActor.run {
                currentUser = user
                isAuthenticated = true
            }

        } catch {
            throw SupabaseError.profileSaveFailed(error.localizedDescription)
        }
    }

    /// Load user profile from database
    private func loadUserProfile(for supabaseId: String) async throws {
        do {
            let response: [User] =
                try await supabase
                .from("users")
                .select()
                .eq("supabase_id", value: supabaseId)
                .execute()
                .value

            if let user = response.first {
                await MainActor.run {
                    currentUser = user
                    isAuthenticated = true
                }
            } else {
                throw SupabaseError.userNotFound
            }

        } catch {
            throw SupabaseError.profileLoadFailed(error.localizedDescription)
        }
    }

    /// Update user preferences
    func updateUserPreferences(_ updates: [String: Any]) async throws {
        guard let user = currentUser else {
            throw SupabaseError.userNotAuthenticated
        }

        do {
            try await supabase
                .from("users")
                .update(updates)
                .eq("supabase_id", value: user.supabaseId)
                .execute()

            // Reload user profile to get updated data
            try await loadUserProfile(for: user.supabaseId)

        } catch {
            throw SupabaseError.profileUpdateFailed(error.localizedDescription)
        }
    }

    // MARK: - Video Storage

    /// Upload video file to Supabase storage
    func uploadVideo(
        _ videoData: Data,
        for video: Video,
        progressCallback: ((Double) -> Void)? = nil
    ) async throws -> URL {

        guard isAuthenticated else {
            throw SupabaseError.userNotAuthenticated
        }

        do {
            // Upload video file
            let videoPath = video.storageKey

            try await supabase.storage
                .from(videoBucketName)
                .upload(
                    path: videoPath,
                    file: videoData,
                    options: FileOptions(
                        contentType: "video/mp4",
                        upsert: true
                    )
                )

            // Get public URL
            let publicURL = try supabase.storage
                .from(videoBucketName)
                .getPublicURL(path: videoPath)

            // Update video record in database
            try await saveVideoMetadata(video.copy(videoURL: publicURL))

            // Update user storage usage
            if let user = currentUser {
                var updatedUser = user
                updatedUser.addStorageUsage(Int64(videoData.count))
                try await saveUserProfile(updatedUser)
            }

            return publicURL

        } catch {
            throw SupabaseError.uploadFailed(error.localizedDescription)
        }
    }

    /// Download video from storage
    func downloadVideo(from storageKey: String) async throws -> Data {
        do {
            let data = try await supabase.storage
                .from(videoBucketName)
                .download(path: storageKey)

            return data

        } catch {
            throw SupabaseError.downloadFailed(error.localizedDescription)
        }
    }

    /// Delete video from storage
    func deleteVideo(storageKey: String) async throws {
        guard isAuthenticated else {
            throw SupabaseError.userNotAuthenticated
        }

        do {
            // Delete file from storage
            try await supabase.storage
                .from(videoBucketName)
                .remove(paths: [storageKey])

            // Delete metadata from database
            try await supabase
                .from("videos")
                .delete()
                .eq("storage_key", value: storageKey)
                .execute()

        } catch {
            throw SupabaseError.deleteFailed(error.localizedDescription)
        }
    }

    /// Get signed URL for temporary access
    func getSignedURL(for storageKey: String, expiresIn: Int = 3600) async throws -> URL {
        do {
            let signedURL = try await supabase.storage
                .from(videoBucketName)
                .createSignedURL(path: storageKey, expiresIn: expiresIn)

            return signedURL

        } catch {
            throw SupabaseError.signedURLFailed(error.localizedDescription)
        }
    }

    // MARK: - Video Metadata Management

    /// Save video metadata to database
    func saveVideoMetadata(_ video: Video) async throws {
        guard isAuthenticated else {
            throw SupabaseError.userNotAuthenticated
        }

        do {
            try await supabase
                .from("videos")
                .upsert(video, onConflict: "id")
                .execute()

        } catch {
            throw SupabaseError.metadataSaveFailed(error.localizedDescription)
        }
    }

    /// Load user's videos from database
    func loadUserVideos() async throws -> [Video] {
        guard let user = currentUser else {
            throw SupabaseError.userNotAuthenticated
        }

        do {
            let response: [Video] =
                try await supabase
                .from("videos")
                .select()
                .eq("user_id", value: user.supabaseId)
                .order("created_at", ascending: false)
                .execute()
                .value

            return response

        } catch {
            throw SupabaseError.videosLoadFailed(error.localizedDescription)
        }
    }

    /// Update video status
    func updateVideoStatus(_ videoId: UUID, status: VideoStatus, errorMessage: String? = nil)
        async throws
    {
        var updates: [String: Any] = [
            "status": status.rawValue,
            "updated_at": ISO8601DateFormatter().string(from: Date()),
        ]

        if let errorMessage = errorMessage {
            updates["error_message"] = errorMessage
        }

        do {
            try await supabase
                .from("videos")
                .update(updates)
                .eq("id", value: videoId.uuidString)
                .execute()

        } catch {
            throw SupabaseError.statusUpdateFailed(error.localizedDescription)
        }
    }

    /// Delete video metadata
    func deleteVideoMetadata(_ videoId: UUID) async throws {
        do {
            try await supabase
                .from("videos")
                .delete()
                .eq("id", value: videoId.uuidString)
                .execute()

        } catch {
            throw SupabaseError.metadataDeleteFailed(error.localizedDescription)
        }
    }

    // MARK: - Storage Management

    /// Get user's storage usage statistics
    func getStorageUsage() async throws -> StorageUsage {
        guard let user = currentUser else {
            throw SupabaseError.userNotAuthenticated
        }

        do {
            let videos = try await loadUserVideos()
            let totalFiles = videos.count
            let totalSize = videos.compactMap { $0.videoURL }.count  // Approximate

            return StorageUsage(
                totalFiles: totalFiles,
                totalSizeBytes: Int64(totalSize * 5_000_000),  // Estimate 5MB per video
                availableBytes: user.subscriptionStatus.maxStorageBytes - user.totalStorageUsed,
                usagePercentage: user.storageUsagePercentage
            )

        } catch {
            throw SupabaseError.storageUsageFailed(error.localizedDescription)
        }
    }

    // MARK: - Private Helpers

    private func setupAuthListener() {
        // Listen for auth state changes
        supabase.auth.onAuthStateChange { [weak self] event, session in
            Task { @MainActor in
                switch event {
                case .signedIn:
                    if let session = session {
                        try? await self?.loadUserProfile(for: session.user.id.uuidString)
                    }
                case .signedOut:
                    self?.currentUser = nil
                    self?.isAuthenticated = false
                default:
                    break
                }
            }
        }
        .store(in: &cancellables)
    }

    @MainActor
    private func setLoading(_ loading: Bool) {
        isLoading = loading
    }

    @MainActor
    private func setError(_ error: SupabaseError) {
        self.error = error
        isLoading = false
    }

    @MainActor
    private func clearError() {
        error = nil
    }
}

// MARK: - Supporting Types

struct StorageUsage {
    let totalFiles: Int
    let totalSizeBytes: Int64
    let availableBytes: Int64
    let usagePercentage: Double

    var formattedTotalSize: String {
        ByteCountFormatter().string(fromByteCount: totalSizeBytes)
    }

    var formattedAvailableSize: String {
        ByteCountFormatter().string(fromByteCount: availableBytes)
    }
}

// MARK: - Error Types

enum SupabaseError: LocalizedError {
    case authenticationFailed(String)
    case signOutFailed(String)
    case authCheckFailed(String)
    case userNotAuthenticated
    case userNotFound
    case profileSaveFailed(String)
    case profileLoadFailed(String)
    case profileUpdateFailed(String)
    case uploadFailed(String)
    case downloadFailed(String)
    case deleteFailed(String)
    case signedURLFailed(String)
    case metadataSaveFailed(String)
    case videosLoadFailed(String)
    case statusUpdateFailed(String)
    case metadataDeleteFailed(String)
    case storageUsageFailed(String)
    case configurationError(String)

    var errorDescription: String? {
        switch self {
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .signOutFailed(let message):
            return "Sign out failed: \(message)"
        case .authCheckFailed(let message):
            return "Auth check failed: \(message)"
        case .userNotAuthenticated:
            return "User is not authenticated"
        case .userNotFound:
            return "User profile not found"
        case .profileSaveFailed(let message):
            return "Failed to save profile: \(message)"
        case .profileLoadFailed(let message):
            return "Failed to load profile: \(message)"
        case .profileUpdateFailed(let message):
            return "Failed to update profile: \(message)"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .deleteFailed(let message):
            return "Delete failed: \(message)"
        case .signedURLFailed(let message):
            return "Failed to create signed URL: \(message)"
        case .metadataSaveFailed(let message):
            return "Failed to save video metadata: \(message)"
        case .videosLoadFailed(let message):
            return "Failed to load videos: \(message)"
        case .statusUpdateFailed(let message):
            return "Failed to update video status: \(message)"
        case .metadataDeleteFailed(let message):
            return "Failed to delete video metadata: \(message)"
        case .storageUsageFailed(let message):
            return "Failed to get storage usage: \(message)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
}

// MARK: - Extensions

extension SupabaseService {
    /// Create a mock service for testing/previews
    static func mock() -> SupabaseService {
        let service = SupabaseService(
            url: "https://mock.supabase.co",
            anonKey: "mock-anon-key"
        )
        service.currentUser = User.sampleUser
        service.isAuthenticated = true
        return service
    }

    /// Check if service is properly configured
    var isConfigured: Bool {
        return !supabaseAnonKey.isEmpty && supabaseURL.absoluteString.contains("supabase")
    }
}

extension Video {
    func copy(videoURL: URL) -> Video {
        return Video(
            id: self.id,
            userId: self.userId,
            prompt: self.prompt,
            aspectRatio: self.aspectRatio,
            duration: self.duration,
            resolution: self.resolution,
            frameRate: self.frameRate,
            createdAt: self.createdAt,
            updatedAt: Date(),
            storageKey: self.storageKey,
            thumbnailStorageKey: self.thumbnailStorageKey,
            videoURL: videoURL,
            thumbnailURL: self.thumbnailURL,
            generationId: self.generationId,
            status: .completed,
            generationTime: self.generationTime,
            errorMessage: nil,
            title: self.title,
            tags: self.tags,
            favorited: self.favorited,
            shareCount: self.shareCount,
            viewCount: self.viewCount
        )
    }
}
