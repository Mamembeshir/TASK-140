import Foundation
import Testing
@testable import ForgeFlow

@Suite("AuthService Unit Tests")
struct AuthServiceTests {

    // MARK: - Username Validation

    @Test("validateUsername rejects short usernames")
    func usernameRejectsShort() {
        #expect(throws: AuthError.self) {
            try AuthService.validateUsername("ab")
        }
    }

    @Test("validateUsername rejects empty username")
    func usernameRejectsEmpty() {
        #expect(throws: AuthError.self) {
            try AuthService.validateUsername("")
        }
    }

    @Test("validateUsername rejects invalid characters")
    func usernameRejectsInvalidChars() {
        #expect(throws: AuthError.self) {
            try AuthService.validateUsername("user name!")
        }
        #expect(throws: AuthError.self) {
            try AuthService.validateUsername("user@name")
        }
    }

    @Test("validateUsername accepts valid usernames")
    func usernameAcceptsValid() throws {
        try AuthService.validateUsername("admin")
        try AuthService.validateUsername("john.doe")
        try AuthService.validateUsername("user-name_123")
        try AuthService.validateUsername("abc")
    }

    @Test("validateUsername rejects over 100 chars")
    func usernameRejectsTooLong() {
        let longName = String(repeating: "a", count: 101)
        #expect(throws: AuthError.self) {
            try AuthService.validateUsername(longName)
        }
    }

    // MARK: - Password Validation

    @Test("validatePassword rejects short passwords")
    func passwordRejectsShort() {
        #expect(throws: AuthError.self) {
            try AuthService.validatePassword("short1")
        }
    }

    @Test("validatePassword rejects passwords without numbers")
    func passwordRejectsNoNumber() {
        #expect(throws: AuthError.self) {
            try AuthService.validatePassword("abcdefghijklm")
        }
    }

    @Test("validatePassword accepts valid passwords")
    func passwordAcceptsValid() throws {
        try AuthService.validatePassword("ForgeFlow1")
        try AuthService.validatePassword("abcdefgh12")
        try AuthService.validatePassword("1234567890")
    }

    @Test("validatePassword rejects over 128 chars")
    func passwordRejectsTooLong() {
        let longPass = String(repeating: "a", count: 128) + "1"
        #expect(throws: AuthError.self) {
            try AuthService.validatePassword(longPass)
        }
    }
}
