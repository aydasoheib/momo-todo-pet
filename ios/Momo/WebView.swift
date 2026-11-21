import SwiftUI
import WebKit

/// Shows the bundled Momo web app (the same index.html as the website) inside the iPhone app.
struct WebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(Bridge.shared, name: "momo")

        let pink = UIColor(red: 0.976, green: 0.839, blue: 0.953, alpha: 1)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = pink
        webView.scrollView.backgroundColor = pink
        webView.scrollView.bounces = false
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        Bridge.shared.webView = webView

        if let dir = Bundle.main.url(forResource: "web", withExtension: nil) {
            webView.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: dir)
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
