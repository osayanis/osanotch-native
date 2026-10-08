import SwiftUI
import AppKit

struct ScrollDetector: NSViewRepresentable {
    var onSwipe: (Int) -> Void
    
    func makeNSView(context: Context) -> ScrollTrackingView {
        let view = ScrollTrackingView()
        view.onSwipe = onSwipe
        return view
    }
    
    func updateNSView(_ nsView: ScrollTrackingView, context: Context) {
        nsView.onSwipe = onSwipe
    }
}

class ScrollTrackingView: NSView {
    var onSwipe: ((Int) -> Void)?
    var accumX: CGFloat = 0
    
    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began || event.phase == .mayBegin { accumX = 0 }
        
        // scrollingDeltaX is positive when scrolling left (swiping right)
        accumX += event.scrollingDeltaX
        
        if accumX > 60 {
            onSwipe?(-1)
            accumX = 0
        } else if accumX < -60 {
            onSwipe?(1)
            accumX = 0
        }
    }
}
