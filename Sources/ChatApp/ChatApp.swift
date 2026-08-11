import SwiftUI

@main
struct ChatApp: App {
    @StateObject private var accountStore = MCAccountStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                MCServerListView()
                    .environmentObject(accountStore)
                    .tabItem { Label("Servers", systemImage: "server.rack") }

                AccountListView()
                    .environmentObject(accountStore)
                    .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
            }
            .tint(.appAccent)
            .background(Color.appBackground.ignoresSafeArea())
            .preferredColorScheme(.dark)
        }
    }
}
