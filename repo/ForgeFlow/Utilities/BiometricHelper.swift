import Foundation
import LocalAuthentication

enum BiometricHelper {
    enum BiometricType: Sendable {
        case faceID
        case touchID
        case none

        var systemImageName: String {
            switch self {
            case .faceID: return "faceid"
            case .touchID: return "touchid"
            case .none: return "lock.fill"
            }
        }

        var displayName: String {
            switch self {
            case .faceID: return "Face ID"
            case .touchID: return "Touch ID"
            case .none: return "Biometric"
            }
        }
    }

    static func availableBiometricType() -> BiometricType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .none
        }
    }

    static func isBiometricAvailable() -> Bool {
        availableBiometricType() != .none
    }

    static func authenticate(reason: String) async throws {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            if let laError = error as? LAError {
                switch laError.code {
                case .biometryNotEnrolled:
                    throw AuthError.biometricNotEnrolled
                default:
                    throw AuthError.biometricNotAvailable
                }
            }
            throw AuthError.biometricNotAvailable
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            guard success else {
                throw AuthError.biometricFailed
            }
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.biometricFailed
        }
    }
}
