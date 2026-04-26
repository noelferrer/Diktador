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
