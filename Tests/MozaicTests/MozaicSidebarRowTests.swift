import SwiftUI
import Testing
@testable import Mozaic

@MainActor
@Suite(.tags(.model))
struct MozaicSidebarRowTests {
    @Test("MozaicSidebarRow constructs selected and unselected rows")
    func constructsSelectedAndUnselectedRows() {
        let selected = MozaicSidebarRow(
            title: "Home",
            systemImage: "house",
            isSelected: true,
            action: {}
        )
        let unselected = MozaicSidebarRow(
            title: "Search",
            systemImage: "magnifyingglass",
            isSelected: false,
            action: {}
        )

        #expect(String(describing: selected).isEmpty == false)
        #expect(String(describing: unselected).isEmpty == false)
    }
}
