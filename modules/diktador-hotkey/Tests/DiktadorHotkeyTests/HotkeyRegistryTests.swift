import XCTest
@testable import DiktadorHotkey

final class HotkeyRegistryTests: XCTestCase {
    func test_register_returnsToken_andTracksRegistration() {
        let registry = HotkeyRegistry()
        let token = registry.register(
            combo: KeyCombo(key: .a, modifiers: [.command]),
            onPress: {},
            onRelease: {}
        )
        XCTAssertEqual(registry.activeRegistrationCount, 1)
        XCTAssertNotNil(token)
    }

    func test_unregister_removesEntry() {
        let registry = HotkeyRegistry()
        let token = registry.register(
            combo: KeyCombo(key: .b, modifiers: [.option]),
            onPress: {},
            onRelease: {}
        )
        XCTAssertEqual(registry.activeRegistrationCount, 1)

        registry.unregister(token)

        XCTAssertEqual(registry.activeRegistrationCount, 0)
    }

    func test_registeringTwice_yieldsDistinctTokens() {
        let registry = HotkeyRegistry()
        let combo = KeyCombo(key: .c, modifiers: [.command])
        let t1 = registry.register(combo: combo, onPress: {}, onRelease: {})
        let t2 = registry.register(combo: combo, onPress: {}, onRelease: {})
        XCTAssertNotEqual(t1, t2)
        XCTAssertEqual(registry.activeRegistrationCount, 2)
    }

    func test_modifierTrigger_isHashable() {
        let a: ModifierTrigger = .fn
        let b: ModifierTrigger = .fn
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set([a, b]).count, 1)
    }

    func test_inputMonitoringPermission_reflectsProviderStatus() {
        let stub = StubPermissionProvider()
        stub.statusToReturn = .granted
        let registry = HotkeyRegistry(permissionProvider: stub)
        XCTAssertEqual(registry.inputMonitoringPermission, .granted)

        stub.statusToReturn = .denied
        XCTAssertEqual(registry.inputMonitoringPermission, .denied)
    }

    func test_requestInputMonitoringPermission_callsProviderAndReturnsResult() {
        let stub = StubPermissionProvider()
        stub.requestResultToReturn = .granted
        let registry = HotkeyRegistry(permissionProvider: stub)

        let expectation = self.expectation(description: "completion called")
        var observed: InputMonitoringStatus?
        registry.requestInputMonitoringPermission { status in
            observed = status
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(observed, .granted)
        XCTAssertEqual(stub.requestCallCount, 1)
    }

    func test_registerModifierTrigger_returnsToken_andTracksRegistration() {
        let registry = HotkeyRegistry(permissionProvider: StubPermissionProvider())
        let token = registry.register(
            modifierTrigger: .fn,
            onPress: {},
            onRelease: {}
        )
        XCTAssertEqual(registry.activeRegistrationCount, 1)
        XCTAssertNotNil(token)

        registry.unregister(token)
        XCTAssertEqual(registry.activeRegistrationCount, 0)
    }

    func test_registerModifierTrigger_andCombo_trackIndependently() {
        let registry = HotkeyRegistry(permissionProvider: StubPermissionProvider())
        let comboToken = registry.register(
            combo: KeyCombo(key: .a, modifiers: [.command]),
            onPress: {},
            onRelease: {}
        )
        let modifierToken = registry.register(
            modifierTrigger: .fn,
            onPress: {},
            onRelease: {}
        )
        XCTAssertEqual(registry.activeRegistrationCount, 2)
        XCTAssertNotEqual(comboToken, modifierToken)

        registry.unregister(comboToken)
        XCTAssertEqual(registry.activeRegistrationCount, 1)

        registry.unregister(modifierToken)
        XCTAssertEqual(registry.activeRegistrationCount, 0)
    }
}

private final class StubPermissionProvider: PermissionProvider, @unchecked Sendable {
    var statusToReturn: InputMonitoringStatus = .undetermined
    var requestResultToReturn: InputMonitoringStatus = .granted
    private(set) var requestCallCount = 0

    func currentStatus() -> InputMonitoringStatus { statusToReturn }

    func requestAccess(completion: @escaping (InputMonitoringStatus) -> Void) {
        requestCallCount += 1
        let result = requestResultToReturn
        DispatchQueue.main.async { completion(result) }
    }
}
