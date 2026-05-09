import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowObservingView {
        let view = WindowObservingView()
        view.onWindowAttach = { window in
            // Restore saved frame if available
            if let savedFrame = AppearancePreference.shared.hostWindowFrame {
                if savedFrame.width > 0 && savedFrame.height > 0 {
                    window.setFrame(savedFrame, display: true)
                }
            }
            // Start observing changes
            context.coordinator.monitor(window: window)
        }
        return view
    }
    
    func updateNSView(_ nsView: WindowObservingView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    /// Custom NSView that reliably detects when it's added to a window.
    class WindowObservingView: NSView {
        var onWindowAttach: ((NSWindow) -> Void)?
        private var didAttach = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !didAttach, let window = self.window else { return }
            didAttach = true
            onWindowAttach?(window)
        }
    }
    
    class Coordinator: NSObject {
        var window: NSWindow?
        var observers: [NSObjectProtocol] = []
        
        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
        
        func monitor(window: NSWindow) {
            self.window = window
            
            // Clean up old observers
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
            
            let center = NotificationCenter.default
            
            observers.append(center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.saveFrame() }
            })

            observers.append(center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.saveFrame() }
            })
        }
        
        @MainActor
        private func saveFrame() {
            guard let window = window else { return }
            AppearancePreference.shared.hostWindowFrame = window.frame
        }
    }
}
