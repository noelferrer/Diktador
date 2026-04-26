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
}

extension HotkeyRegistryTests {
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
}

extension HotkeyRegistryTests {
    func test_registeringTwice_yieldsDistinctTokens() {
        let registry = HotkeyRegistry()
        let combo = KeyCombo(key: .c, modifiers: [.command])
        let t1 = registry.register(combo: combo, onPress: {}, onRelease: {})
        let t2 = registry.register(combo: combo, onPress: {}, onRelease: {})
        XCTAssertNotEqual(t1, t2)
        XCTAssertEqual(registry.activeRegistrationCount, 2)
    }
}
