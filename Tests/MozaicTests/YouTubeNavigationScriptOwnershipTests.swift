import Foundation
import Testing
@testable import Mozaic

@Suite("YouTube navigation script ownership", .tags(.service))
struct YouTubeNavigationScriptOwnershipTests {
    @Test("Redirect script reinstall preserves the pending seek attempt id")
    func redirectReinstallPreservesPendingSeekAttempt() throws {
        let source = try String(
            contentsOfFile: #filePath.replacingOccurrences(
                of: "Tests/MozaicTests/YouTubeNavigationScriptOwnershipTests.swift",
                with: "Sources/Mozaic/Views/YouTube/YouTubeWatchWebView.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains(
            "pendingSeekAttemptID: self.pendingSeekAttemptIDsByGeneration[trackedNavigation.generation]"
        ))
    }
}
