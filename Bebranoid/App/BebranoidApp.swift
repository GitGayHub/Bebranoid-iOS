import SwiftUI

@main
public struct BebranoidApp: App {
    @StateObject private var appState = BebranoidAppState()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            RootTabView(appState: appState)
                .preferredColorScheme(.dark)
        }
    }
}
