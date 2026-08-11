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
            // Ép toàn app dùng giao diện tối (nền đen) thay vì trắng — vừa đúng yêu cầu
            // vừa giúp các mã màu chat (đặc biệt màu tối như đen/đỏ đậm/xanh đậm) hiện rõ,
            // đúng như trong Minecraft thật (chat luôn có nền tối).
            .preferredColorScheme(.dark)
            .tint(.green)
        }
    }
}
