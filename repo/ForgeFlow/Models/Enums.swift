import Foundation

// MARK: - Role

enum Role: String, Codable, CaseIterable, Sendable {
    case admin = "ADMIN"
    case coordinator = "COORDINATOR"
    case technician = "TECHNICIAN"
}

// MARK: - UserStatus

enum UserStatus: String, Codable, CaseIterable, Sendable {
    case active = "ACTIVE"
    case locked = "LOCKED"
    case deactivated = "DEACTIVATED"
}

// MARK: - PostingStatus

enum PostingStatus: String, Codable, CaseIterable, Sendable {
    case draft = "DRAFT"
    case open = "OPEN"
    case inProgress = "IN_PROGRESS"
    case completed = "COMPLETED"
    case cancelled = "CANCELLED"
}

// MARK: - AssignmentStatus

enum AssignmentStatus: String, Codable, CaseIterable, Sendable {
    case invited = "INVITED"
    case accepted = "ACCEPTED"
    case declined = "DECLINED"
    case completed = "COMPLETED"
}

// MARK: - TaskStatus

enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case notStarted = "NOT_STARTED"
    case inProgress = "IN_PROGRESS"
    case blocked = "BLOCKED"
    case done = "DONE"
}

// MARK: - Priority

enum Priority: String, Codable, CaseIterable, Sendable {
    case p0 = "P0"
    case p1 = "P1"
    case p2 = "P2"
    case p3 = "P3"

    var label: String {
        switch self {
        case .p0: return "Critical"
        case .p1: return "High"
        case .p2: return "Medium"
        case .p3: return "Low"
        }
    }
}

// MARK: - NotificationStatus

enum NotificationStatus: String, Codable, CaseIterable, Sendable {
    case pending = "PENDING"
    case delivered = "DELIVERED"
    case seen = "SEEN"
}

// MARK: - NotificationEventType

enum NotificationEventType: String, Codable, CaseIterable, Sendable {
    case assignmentInvited = "ASSIGNMENT_INVITED"
    case assignmentAccepted = "ASSIGNMENT_ACCEPTED"
    case taskStatusChanged = "TASK_STATUS_CHANGED"
    case taskBlocked = "TASK_BLOCKED"
    case commentAdded = "COMMENT_ADDED"
    case postingCompleted = "POSTING_COMPLETED"
    case postingCancelled = "POSTING_CANCELLED"
    case pluginApprovalNeeded = "PLUGIN_APPROVAL_NEEDED"
    case pluginApproved = "PLUGIN_APPROVED"
    case pluginRejected = "PLUGIN_REJECTED"

    var displayName: String {
        switch self {
        case .assignmentInvited: return "Invitation"
        case .assignmentAccepted: return "Accepted"
        case .taskStatusChanged: return "Task Update"
        case .taskBlocked: return "Task Blocked"
        case .commentAdded: return "Comment"
        case .postingCompleted: return "Completed"
        case .postingCancelled: return "Cancelled"
        case .pluginApprovalNeeded: return "Approval Needed"
        case .pluginApproved: return "Plugin Approved"
        case .pluginRejected: return "Plugin Rejected"
        }
    }
}

// MARK: - PluginStatus

enum PluginStatus: String, Codable, CaseIterable, Sendable {
    case draft = "DRAFT"
    case testing = "TESTING"
    case pendingApproval = "PENDING_APPROVAL"
    case approved = "APPROVED"
    case rejected = "REJECTED"
    case active = "ACTIVE"
}

// MARK: - AttachmentMimeType

enum AttachmentMimeType: String, Codable, CaseIterable, Sendable {
    case pdf = "application/pdf"
    case jpg = "image/jpeg"
    case png = "image/png"
    case heic = "image/heic"
    case mov = "video/quicktime"
}

// MARK: - AcceptanceMode

enum AcceptanceMode: String, Codable, CaseIterable, Sendable {
    case inviteOnly = "INVITE_ONLY"
    case open = "OPEN"
}

// MARK: - DependencyType

enum DependencyType: String, Codable, CaseIterable, Sendable {
    case finishToStart = "FINISH_TO_START"
}

// MARK: - PluginFieldType

enum PluginFieldType: String, Codable, CaseIterable, Sendable {
    case text = "TEXT"
    case number = "NUMBER"
    case boolean = "BOOLEAN"
    case select = "SELECT"
}

// MARK: - SyncImportStatus

enum SyncImportStatus: String, Codable, CaseIterable, Sendable {
    case pending = "PENDING"
    case validated = "VALIDATED"
    case applied = "APPLIED"
    case failed = "FAILED"
    case partialFailure = "PARTIAL_FAILURE"
}

// MARK: - PluginApprovalDecision

enum PluginApprovalDecision: String, Codable, CaseIterable, Sendable {
    case approved = "APPROVED"
    case rejected = "REJECTED"
}

// MARK: - PluginTestResultStatus

enum PluginTestResultStatus: String, Codable, CaseIterable, Sendable {
    case pass = "PASS"
    case fail = "FAIL"
}
