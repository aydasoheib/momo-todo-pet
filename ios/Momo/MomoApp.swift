import SwiftUI
import UserNotifications

@main
struct MomoApp: App {
    init() {
        // lets reminders show as banners even while the app is open
        UNUserNotificationCenter.current().delegate = Bridge.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        ZStack {
            Color(red: 0.976, green: 0.839, blue: 0.953).ignoresSafeArea()
            WebView()
        }
    }
}
