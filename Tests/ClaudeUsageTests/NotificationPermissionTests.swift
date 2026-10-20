import XCTest
import UserNotifications
@testable import ClaudeUsage

@MainActor
final class FakeNotificationClient: UsageNotificationClient {
    var permission = NotificationPermission(authorization: .notDetermined, alertsEnabled: false)
    var requestError: Error?
    var deliveryError: Error?
    var grantsPermission = true
    var requestCount = 0
    var requests: [UNNotificationRequest] = []
    var suspendedRequest: CheckedContinuation<Bool, Error>?
    var onRequest: (() -> Void)?
    var suspendRequest = false

    func setDelegate(_ delegate: UNUserNotificationCenterDelegate) {}
    func settings() async -> NotificationPermission { permission }
    func requestAuthorization() async throws -> Bool {
        requestCount += 1
        if let requestError { throw requestError }
        if suspendRequest {
            return try await withCheckedThrowingContinuation {
                suspendedRequest = $0
                onRequest?()
            }
        }
        permission = NotificationPermission(authorization: grantsPermission ? .authorized : .denied,
                                            alertsEnabled: grantsPermission)
        return grantsPermission
    }
    func add(_ request: UNNotificationRequest) async throws {
        if let deliveryError { throw deliveryError }
        requests.append(request)
    }
}

final class NotificationPermissionTests: XCTestCase {
    @MainActor
    private func controller(_ client: FakeNotificationClient) -> UsageNotifications {
        UsageNotifications(client: client, defaults: UserDefaults(suiteName: "notification-tests-\(UUID().uuidString)")!)
    }

    @MainActor
    func testTestButtonRequestsPermissionBeforeSubmitting() async {
        let client = FakeNotificationClient()
        let notifications = controller(client)
        await notifications.sendTest()
        XCTAssertEqual(client.requestCount, 1)
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(notifications.authorization, .authorized)
        XCTAssertNotNil(notifications.testMessage)
        XCTAssertNil(notifications.errorMessage)
        XCTAssertFalse(notifications.isSendingTest)
        await notifications.sendTest()
        XCTAssertEqual(client.requestCount, 1, "Already-authorized users must not get repeated requests")
        XCTAssertEqual(client.requests.count, 2)
        XCTAssertNotEqual(client.requests[0].identifier, client.requests[1].identifier)
    }

    @MainActor
    func testDeniedPermissionDoesNotRetryOrSubmit() async {
        let client = FakeNotificationClient()
        client.permission.authorization = .denied
        let notifications = controller(client)
        await notifications.sendTest()
        XCTAssertEqual(client.requestCount, 0)
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertEqual(notifications.authorization, .denied)
        XCTAssertNil(notifications.testMessage)
    }

    @MainActor
    func testUserDenialUpdatesStateWithoutClaimingDelivery() async {
        let client = FakeNotificationClient()
        client.grantsPermission = false
        let notifications = controller(client)
        await notifications.sendTest()
        XCTAssertEqual(client.requestCount, 1)
        XCTAssertEqual(notifications.authorization, .denied)
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertNil(notifications.testMessage)
    }

    @MainActor
    func testAuthorizationErrorRemainsRetryableAndIncludesDiagnosticCode() async {
        let client = FakeNotificationClient()
        client.requestError = NSError(domain: "PermissionTest", code: 42)
        let notifications = controller(client)
        await notifications.sendTest()
        XCTAssertTrue(notifications.errorMessage?.contains("PermissionTest 42") == true)
        XCTAssertFalse(notifications.isRequestingAuthorization)
        XCTAssertTrue(client.requests.isEmpty)
        client.requestError = nil
        await notifications.sendTest()
        XCTAssertEqual(client.requestCount, 2)
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertNil(notifications.errorMessage)
    }

    @MainActor
    func testDeliveryFailureIsNotReportedAsSuccess() async {
        let client = FakeNotificationClient()
        client.permission = NotificationPermission(authorization: .authorized, alertsEnabled: true)
        client.deliveryError = NSError(domain: "DeliveryTest", code: 7)
        let notifications = controller(client)
        await notifications.sendTest()
        XCTAssertTrue(notifications.errorMessage?.contains("DeliveryTest 7") == true)
        XCTAssertNil(notifications.testMessage)
    }

    @MainActor
    func testRefreshReflectsPermissionAndBannersChangedInSystemSettings() async {
        let client = FakeNotificationClient()
        let notifications = controller(client)
        await notifications.refreshAuthorization()
        XCTAssertTrue(notifications.authorizationChecked)
        client.permission = NotificationPermission(authorization: .authorized, alertsEnabled: false)
        await notifications.refreshAuthorization()
        XCTAssertEqual(notifications.authorization, .authorized)
        XCTAssertFalse(notifications.alertsEnabled)
        XCTAssertEqual(client.requestCount, 0, "Refreshing status must not show a permission prompt")
    }

    @MainActor
    func testConcurrentClicksDoNotCreateDuplicatePermissionRequests() async {
        let client = FakeNotificationClient()
        client.suspendRequest = true
        let started = expectation(description: "Permission request pending")
        client.onRequest = { started.fulfill() }
        let notifications = controller(client)
        let first = Task { await notifications.sendTest() }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(notifications.isSendingTest)
        XCTAssertTrue(notifications.isRequestingAuthorization)
        await notifications.sendTest()
        let duplicate = await notifications.requestAuthorization()
        XCTAssertFalse(duplicate)
        XCTAssertEqual(client.requestCount, 1)
        client.permission = NotificationPermission(authorization: .authorized, alertsEnabled: true)
        client.suspendedRequest?.resume(returning: true)
        await first.value
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertFalse(notifications.isRequestingAuthorization)
    }
}
