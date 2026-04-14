import Foundation

// MARK: - AuthError

enum AuthError: LocalizedError {
    case invalidCredentials
    case accountLocked(until: Date)
    case accountDeactivated
    case biometricNotAvailable
    case biometricNotEnrolled
    case biometricFailed
    case passwordTooShort
    case passwordMissingNumber
    case usernameTaken
    case usernameInvalid
    case sessionExpired
    case notAuthorized
    case keychainStoreFailed

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid username or password."
        case .accountLocked(let until):
            return "Account locked until \(DateFormatters.display.string(from: until))."
        case .accountDeactivated:
            return "This account has been deactivated. Contact an administrator."
        case .biometricNotAvailable:
            return "Biometric authentication is not available on this device."
        case .biometricNotEnrolled:
            return "No biometric data enrolled. Please set up Face ID or Touch ID in Settings."
        case .biometricFailed:
            return "Biometric authentication failed."
        case .passwordTooShort:
            return "Password must be at least 10 characters."
        case .passwordMissingNumber:
            return "Password must contain at least one number."
        case .usernameTaken:
            return "This username is already taken."
        case .usernameInvalid:
            return "Username must be 3–100 characters: letters, numbers, dots, hyphens, or underscores."
        case .sessionExpired:
            return "Your session has expired. Please log in again."
        case .notAuthorized:
            return "You are not authorized to perform this action."
        case .keychainStoreFailed:
            return "Account could not be created. Please try again."
        }
    }
}

// MARK: - PostingError

enum PostingError: LocalizedError {
    case titleRequired
    case siteAddressRequired
    case dueDateMustBeFuture
    case budgetMustBePositive
    case invalidStatusTransition(from: PostingStatus, to: PostingStatus)
    case notAuthorized
    case postingNotFound

    var errorDescription: String? {
        switch self {
        case .titleRequired:
            return "Posting title is required."
        case .siteAddressRequired:
            return "Site address is required."
        case .dueDateMustBeFuture:
            return "Due date must be in the future."
        case .budgetMustBePositive:
            return "Budget must be greater than zero."
        case .invalidStatusTransition(let from, let to):
            return "Cannot transition posting from \(from.rawValue) to \(to.rawValue)."
        case .notAuthorized:
            return "You are not authorized to perform this action."
        case .postingNotFound:
            return "Service posting not found."
        }
    }
}

// MARK: - TaskError

enum TaskError: LocalizedError {
    case titleRequired
    case invalidStatusTransition(from: TaskStatus, to: TaskStatus)
    case blockedCommentRequired
    case blockedCommentTooShort
    case unmetDependencies
    case subtasksNotComplete
    case taskNotFound
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .titleRequired:
            return "Task title is required."
        case .invalidStatusTransition(let from, let to):
            return "Cannot transition task from \(from.rawValue) to \(to.rawValue)."
        case .blockedCommentRequired:
            return "A comment is required when blocking a task."
        case .blockedCommentTooShort:
            return "Blocked comment must be at least 10 characters."
        case .unmetDependencies:
            return "This task has unmet dependencies that must be completed first."
        case .subtasksNotComplete:
            return "All subtasks must be completed before completing the parent task."
        case .taskNotFound:
            return "Task not found."
        case .notAuthorized:
            return "You are not authorized to perform this action."
        }
    }
}

// MARK: - AttachmentError

enum AttachmentError: LocalizedError {
    case unsupportedFileType
    case fileTooLarge(maxMB: Int)
    case quotaExceeded
    case checksumMismatch
    case duplicateFile
    case fileNotFound
    case compressionFailed
    case invalidMagicBytes
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "Unsupported file type. Allowed: PDF, JPG, PNG, HEIC, MOV."
        case .fileTooLarge(let maxMB):
            return "File exceeds the maximum size of \(maxMB) MB."
        case .quotaExceeded:
            return "Storage quota exceeded. Delete old files or contact your administrator."
        case .checksumMismatch:
            return "File integrity check failed. The file may be corrupted."
        case .duplicateFile:
            return "A file with the same content already exists for this posting."
        case .fileNotFound:
            return "The requested file could not be found."
        case .compressionFailed:
            return "Failed to compress the image."
        case .invalidMagicBytes:
            return "File content does not match the expected format."
        case .notAuthorized:
            return "You are not authorized to access this attachment."
        }
    }
}

// MARK: - AssignmentError

enum AssignmentError: LocalizedError {
    case alreadyAssigned(name: String, at: Date)
    case notInvited
    case invalidStatusTransition(from: AssignmentStatus, to: AssignmentStatus)
    case assignmentNotFound
    case notAuthorized
    case postingNotOpen

    var errorDescription: String? {
        switch self {
        case .alreadyAssigned(let name, let at):
            return "Already assigned to \(name) at \(DateFormatters.display.string(from: at))."
        case .notInvited:
            return "You have not been invited to this posting."
        case .invalidStatusTransition(let from, let to):
            return "Cannot transition assignment from \(from.rawValue) to \(to.rawValue)."
        case .assignmentNotFound:
            return "Assignment not found."
        case .notAuthorized:
            return "You are not authorized to perform this action."
        case .postingNotOpen:
            return "This posting is not accepting assignments."
        }
    }
}

// MARK: - SyncError

enum SyncError: LocalizedError {
    case exportFailed(reason: String)
    case importFailed(reason: String)
    case checksumValidationFailed
    case conflictsDetected(count: Int)
    case invalidSyncFile
    case incompatibleVersion
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .importFailed(let reason):
            return "Import failed: \(reason)"
        case .checksumValidationFailed:
            return "File integrity validation failed. The sync file may be corrupted."
        case .conflictsDetected(let count):
            return "\(count) conflict(s) detected. Please resolve before applying."
        case .invalidSyncFile:
            return "The selected file is not a valid ForgeFlow sync file."
        case .incompatibleVersion:
            return "This sync file was created with an incompatible version."
        case .notAuthorized:
            return "You are not authorized to perform this action."
        }
    }
}

// MARK: - PluginError

enum PluginError: LocalizedError {
    case nameRequired
    case invalidStatusTransition(from: PluginStatus, to: PluginStatus)
    case sameApproverNotAllowed
    case sameApproverBothSteps
    case pluginNotFound
    case postingNotFound
    case testingRequired
    case notAuthorized
    case noFieldsDefined
    case noTestResults
    case testsFailed
    case invalidApprovalStep
    case step1NotCompleted
    case stepAlreadyCompleted(step: Int)

    var errorDescription: String? {
        switch self {
        case .nameRequired:
            return "Plugin name is required."
        case .invalidStatusTransition(let from, let to):
            return "Cannot transition plugin from \(from.rawValue) to \(to.rawValue)."
        case .sameApproverNotAllowed, .sameApproverBothSteps:
            return "The same administrator cannot approve both steps."
        case .pluginNotFound:
            return "Plugin not found."
        case .postingNotFound:
            return "Posting not found."
        case .testingRequired:
            return "Plugin must be tested before submitting for approval."
        case .notAuthorized:
            return "You are not authorized to manage plugins."
        case .noFieldsDefined:
            return "Plugin must have at least one field defined."
        case .noTestResults:
            return "Plugin must be tested before submitting."
        case .testsFailed:
            return "All tests must pass before submitting for approval."
        case .invalidApprovalStep:
            return "Approval step must be 1 or 2."
        case .step1NotCompleted:
            return "Step 1 approval must be completed first."
        case .stepAlreadyCompleted(let step):
            return "Approval step \(step) has already been completed."
        }
    }
}

// MARK: - NotificationError

enum NotificationError: LocalizedError {
    case notificationNotFound
    case invalidStatusTransition(from: NotificationStatus, to: NotificationStatus)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .notificationNotFound:
            return "Notification not found."
        case .invalidStatusTransition(let from, let to):
            return "Cannot transition notification from \(from.rawValue) to \(to.rawValue)."
        case .unauthorized:
            return "Access denied."
        }
    }
}

// MARK: - StaleRecordError

struct StaleRecordError: LocalizedError {
    let entityType: String
    let entityId: UUID

    var errorDescription: String? {
        return "This \(entityType) was modified by another session. Please refresh and try again."
    }
}
