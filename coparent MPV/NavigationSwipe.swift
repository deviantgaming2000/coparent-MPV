import SwiftUI
import UIKit

/// Disables the system edge-swipe-back on a pushed screen. The app's tab-style
/// destinations (Timeline, Insights) are reached only via the bottom nav, so the
/// interactive pop gesture just causes accidental navigation while swiping through
/// content (e.g. insight cards). Apply `.disablesInteractivePop()` to those screens.
extension View {
    func disablesInteractivePop() -> some View {
        background(InteractivePopDisabler().frame(width: 0, height: 0))
    }
}

private struct InteractivePopDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { Controller() }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Controller: UIViewController {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            // Re-enable so ordinary pushed screens (entry detail, etc.) keep swipe-back.
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}
