//
//  User.swift
//  veogen
//
//  Created by Heavyshark on 6.06.2025.
//

import Foundation

struct User: Identifiable, Codable, Equatable {
    let id: UUID
    let supabaseId: String  // Supabase auth user ID
    let appleId: String?  // Apple ID identifier

    // Profile Information
    var email: String?
    var displayName: String?
    var fullName: String?
    var avatarURL: URL?

    // Authentication
    let createdAt: Date
    var lastSignInAt: Date?
    var emailVerified: Bool

    // App Preferences
    var preferredAspectRatio: AspectRatio
    var defaultDuration: Double  // seconds
    var preferredResolution: VideoResolution
    var notificationsEnabled: Bool
    var autoSaveToPhotos: Bool

    // Usage & Limits
    var videosGenerated: Int
    var totalStorageUsed: Int64  // bytes
    var lastGenerationAt: Date?

    // Subscription (for future premium features)
    var subscriptionStatus: SubscriptionStatus
    var subscriptionExpiresAt: Date?
    var dailyGenerationCount: Int
    var lastDailyReset: Date

    // App Settings
    var appVersion: String?
    var onboardingCompleted: Bool
    var promptTipsShown: Bool

    init(
        id: UUID = UUID(),
        supabaseId: String,
        appleId: String? = nil,
        email: String? = nil,
        displayName: String? = nil,
        fullName: String? = nil,
        avatarURL: URL? = nil,
        createdAt: Date = Date(),
        lastSignInAt: Date? = nil,
        emailVerified: Bool = false,
        preferredAspectRatio: AspectRatio = .landscape,
        defaultDuration: Double = 5.0,
        preferredResolution: VideoResolution = .hd720,
        notificationsEnabled: Bool = true,
        autoSaveToPhotos: Bool = false,
        videosGenerated: Int = 0,
        totalStorageUsed: Int64 = 0,
        lastGenerationAt: Date? = nil,
        subscriptionStatus: SubscriptionStatus = .free,
        subscriptionExpiresAt: Date? = nil,
        dailyGenerationCount: Int = 0,
        lastDailyReset: Date = Calendar.current.startOfDay(for: Date()),
        appVersion: String? = nil,
        onboardingCompleted: Bool = false,
        promptTipsShown: Bool = false
    ) {
        self.id = id
        self.supabaseId = supabaseId
        self.appleId = appleId
        self.email = email
        self.displayName = displayName
        self.fullName = fullName
        self.avatarURL = avatarURL
        self.createdAt = createdAt
        self.lastSignInAt = lastSignInAt
        self.emailVerified = emailVerified
        self.preferredAspectRatio = preferredAspectRatio
        self.defaultDuration = defaultDuration
        self.preferredResolution = preferredResolution
        self.notificationsEnabled = notificationsEnabled
        self.autoSaveToPhotos = autoSaveToPhotos
        self.videosGenerated = videosGenerated
        self.totalStorageUsed = totalStorageUsed
        self.lastGenerationAt = lastGenerationAt
        self.subscriptionStatus = subscriptionStatus
        self.subscriptionExpiresAt = subscriptionExpiresAt
        self.dailyGenerationCount = dailyGenerationCount
        self.lastDailyReset = lastDailyReset
        self.appVersion = appVersion
        self.onboardingCompleted = onboardingCompleted
        self.promptTipsShown = promptTipsShown
    }
}

// MARK: - Supporting Enums

enum SubscriptionStatus: String, Codable, CaseIterable {
    case free = "free"
    case premium = "premium"
    case expired = "expired"
    case trial = "trial"

    var displayName: String {
        switch self {
        case .free:
            return "Free"
        case .premium:
            return "Premium"
        case .expired:
            return "Expired"
        case .trial:
            return "Trial"
        }
    }

    var isPremium: Bool {
        return self == .premium || self == .trial
    }

    var dailyGenerationLimit: Int {
        switch self {
        case .free:
            return 3
        case .premium, .trial:
            return 50
        case .expired:
            return 1
        }
    }

    var maxStorageBytes: Int64 {
        switch self {
        case .free:
            return 500_000_000  // 500 MB
        case .premium, .trial:
            return 5_000_000_000  // 5 GB
        case .expired:
            return 100_000_000  // 100 MB
        }
    }
}

// MARK: - Extensions

extension User {
    var initials: String {
        if let fullName = fullName {
            let components = fullName.components(separatedBy: " ")
            let initials = components.compactMap { $0.first }.map { String($0) }
            return initials.prefix(2).joined().uppercased()
        } else if let displayName = displayName {
            return String(displayName.prefix(2)).uppercased()
        } else if let email = email {
            return String(email.prefix(2)).uppercased()
        } else {
            return "U"
        }
    }

    var formattedStorageUsed: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalStorageUsed)
    }

    var formattedStorageLimit: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: subscriptionStatus.maxStorageBytes)
    }

    var storageUsagePercentage: Double {
        let limit = Double(subscriptionStatus.maxStorageBytes)
        let used = Double(totalStorageUsed)
        return min(used / limit, 1.0)
    }

    var canGenerateVideo: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let resetDate = Calendar.current.startOfDay(for: lastDailyReset)

        // Reset daily count if it's a new day
        if today > resetDate {
            return true  // Will be reset in the actual generation logic
        }

        return dailyGenerationCount < subscriptionStatus.dailyGenerationLimit
    }

    var remainingGenerationsToday: Int {
        let limit = subscriptionStatus.dailyGenerationLimit
        let used = dailyGenerationCount
        return max(0, limit - used)
    }

    var needsResetDailyCount: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let resetDate = Calendar.current.startOfDay(for: lastDailyReset)
        return today > resetDate
    }

    mutating func resetDailyCountIfNeeded() {
        if needsResetDailyCount {
            dailyGenerationCount = 0
            lastDailyReset = Date()
        }
    }

    mutating func incrementGenerationCount() {
        resetDailyCountIfNeeded()
        dailyGenerationCount += 1
        videosGenerated += 1
        lastGenerationAt = Date()
    }

    mutating func addStorageUsage(_ bytes: Int64) {
        totalStorageUsed += bytes
    }

    var isStorageNearLimit: Bool {
        return storageUsagePercentage > 0.8
    }

    var isStorageAtLimit: Bool {
        return storageUsagePercentage >= 1.0
    }

    var subscriptionIsExpiring: Bool {
        guard let expiresAt = subscriptionExpiresAt else { return false }
        let daysUntilExpiry =
            Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0
        return daysUntilExpiry <= 7 && daysUntilExpiry > 0
    }

    var subscriptionIsExpired: Bool {
        guard let expiresAt = subscriptionExpiresAt else { return false }
        return Date() > expiresAt
    }
}

// MARK: - Sample Data

extension User {
    static let sampleUser = User(
        supabaseId: "sample-user-123",
        appleId: "000123.abc456def789.1234",
        email: "user@example.com",
        displayName: "John Doe",
        fullName: "John Doe",
        lastSignInAt: Date().addingTimeInterval(-3600),
        emailVerified: true,
        videosGenerated: 15,
        totalStorageUsed: 250_000_000,
        lastGenerationAt: Date().addingTimeInterval(-1800),
        subscriptionStatus: .free,
        dailyGenerationCount: 2,
        onboardingCompleted: true,
        promptTipsShown: true
    )

    static let premiumUser = User(
        supabaseId: "premium-user-456",
        appleId: "000456.def789abc123.5678",
        email: "premium@example.com",
        displayName: "Jane Smith",
        fullName: "Jane Smith",
        lastSignInAt: Date().addingTimeInterval(-1800),
        emailVerified: true,
        videosGenerated: 42,
        totalStorageUsed: 1_500_000_000,
        lastGenerationAt: Date().addingTimeInterval(-600),
        subscriptionStatus: .premium,
        subscriptionExpiresAt: Date().addingTimeInterval(86400 * 30),
        dailyGenerationCount: 5,
        onboardingCompleted: true,
        promptTipsShown: true
    )
}
