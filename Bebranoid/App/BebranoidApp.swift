import SwiftUI

@main
public struct BebranoidApp: App {
    @StateObject private var appState = BebranoidAppState()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            if TelegramClientService.isRunningUnderXCTest {
                Text("Testing...")
            } else {
                RootTabView(appState: appState)
                    .preferredColorScheme(.dark)
            }
        }
    }
}
