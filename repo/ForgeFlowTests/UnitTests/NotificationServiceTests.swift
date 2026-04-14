import Testing
import Foundation
@testable import ForgeFlow

// MARK: - Unit Tests: NotificationService (pure logic, no DB)

struct NotificationServiceTests {

    // MARK: - DND Logic

    @Test("DND: overnight range 22:00-07:00 — inside (23:00) → true")
    func dndOvernightInside() throws {
        let inDND = NotificationService.checkDND(
            startTime: "22:00", endTime: "07:00",
            at: makeTime(hour: 23, minute: 0)
        )
        #expect(inDND == true)
    }

    @Test("DND: overnight range 22:00-07:00 — early morning (03:00) → true")
    func dndOvernightEarlyMorning() throws {
        let inDND = NotificationService.checkDND(
            startTime: "22:00", endTime: "07:00",
            at: makeTime(hour: 3, minute: 0)
        )
        #expect(inDND == true)
    }

    @Test("DND: overnight range 22:00-07:00 — outside (10:00) → false")
    func dndOvernightOutside() throws {
        let inDND = NotificationService.checkDND(
            startTime: "22:00", endTime: "07:00",
            at: makeTime(hour: 10, minute: 0)
        )
        #expect(inDND == false)
    }

    @Test("DND: same-day range 09:00-17:00 — inside (12:00) → true")
    func dndSameDayInside() throws {
        let inDND = NotificationService.checkDND(
            startTime: "09:00", endTime: "17:00",
            at: makeTime(hour: 12, minute: 0)
        )
        #expect(inDND == true)
    }

    @Test("DND: same-day range 09:00-17:00 — outside (20:00) → false")
    func dndSameDayOutside() throws {
        let inDND = NotificationService.checkDND(
            startTime: "09:00", endTime: "17:00",
            at: makeTime(hour: 20, minute: 0)
        )
        #expect(inDND == false)
    }

    @Test("DND: nil start/end → false (DND disabled)")
    func dndNilSettings() throws {
        let inDND = NotificationService.checkDND(
            startTime: nil, endTime: nil,
            at: makeTime(hour: 23, minute: 0)
        )
        #expect(inDND == false)
    }

    @Test("DND: exactly at start time (22:00) → true")
    func dndAtStartBoundary() throws {
        let inDND = NotificationService.checkDND(
            startTime: "22:00", endTime: "07:00",
            at: makeTime(hour: 22, minute: 0)
        )
        #expect(inDND == true)
    }

    @Test("DND: exactly at end time (07:00) → false (exclusive)")
    func dndAtEndBoundary() throws {
        let inDND = NotificationService.checkDND(
            startTime: "22:00", endTime: "07:00",
            at: makeTime(hour: 7, minute: 0)
        )
        #expect(inDND == false)
    }

    // MARK: - Time parsing

    @Test("parseTimeToMinutes: valid '22:00' → 1320")
    func parseTimeValid() {
        #expect(NotificationService.parseTimeToMinutes("22:00") == 1320)
    }

    @Test("parseTimeToMinutes: '07:30' → 450")
    func parseTimeHalfHour() {
        #expect(NotificationService.parseTimeToMinutes("07:30") == 450)
    }

    @Test("parseTimeToMinutes: invalid string → nil")
    func parseTimeInvalid() {
        #expect(NotificationService.parseTimeToMinutes("bad") == nil)
    }

    // MARK: - Helpers

    private func makeTime(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }
}
