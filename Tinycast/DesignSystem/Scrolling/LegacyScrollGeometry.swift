import AppKit
import SwiftUI

/// The slice of macOS 15's `ScrollGeometry` that this design system reads.
///
/// Sonoma port: `ScrollGeometry`, `onScrollGeometryChange` and `onScrollPhaseChange` are all macOS
/// 15+, and SwiftUI 14 offers no way to read a scroll view's offset from outside its content. This
/// reaches the `NSScrollView` backing the enclosing `ScrollView` — the same introspection
/// `NativeScrollerHider` already depends on — and republishes its geometry in the shape the rest of
/// the design system talks to. Field names match `ScrollGeometry`, so call sites keep their
/// transform closures untouched and only rename the modifier.
struct LegacyScrollGeometry: Equatable {
    var contentOffset: CGPoint = .zero
    var contentSize: CGSize = .zero
    var containerSize: CGSize = .zero
    var contentInsets = EdgeInsets()

    init() {}

    /// AppKit's scroll-view geometry is main-actor isolated, and every caller of this is on it.
    @MainActor
    init(_ scrollView: NSScrollView) {
        let clip = scrollView.contentView
        contentOffset = clip.bounds.origin
        containerSize = clip.bounds.size
        // The document view is the scrolled content; its frame carries the full content height.
        contentSize = scrollView.documentView?.frame.size ?? .zero
        let insets = scrollView.contentInsets
        contentInsets = EdgeInsets(
            top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
    }
}

extension View {
    /// Back-deployed `onScrollGeometryChange(for:of:action:)`.
    func onLegacyScrollGeometryChange<T: Equatable>(
        for type: T.Type,
        of transform: @escaping (LegacyScrollGeometry) -> T,
        action: @escaping (T, T) -> Void
    ) -> some View {
        // Fills the scroll view's frame, which is what lets the observer pick out the right
        // `NSScrollView` when a screen holds more than one; it never takes hits (see `hitTest`).
        background(ScrollGeometryObserver(transform: transform, action: action))
    }

    /// Back-deployed `onScrollPhaseChange`, collapsed to the one bit callers use here: whether a
    /// live scroll is in progress.
    func onLegacyScrollPhaseChange(_ action: @escaping (Bool) -> Void) -> some View {
        background(ScrollPhaseObserver(action: action))
    }
}

// MARK: - Observation

private struct ScrollGeometryObserver<T: Equatable>: NSViewRepresentable {
    let transform: (LegacyScrollGeometry) -> T
    let action: (T, T) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ScrollObservingView()
        view.onScrollView = { [weak coordinator = context.coordinator] scrollView in
            guard let coordinator else { return }
            let value = transform(LegacyScrollGeometry(scrollView))
            let previous = coordinator.last
            coordinator.last = value
            if let previous, previous != value { action(previous, value) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ScrollObservingView)?.refresh()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var last: T?
    }
}

private struct ScrollPhaseObserver: NSViewRepresentable {
    let action: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ScrollObservingView()
        view.onScrollView = { _ in }
        view.onPhase = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ScrollObservingView)?.refresh()
    }
}

/// Reports the enclosing scroll view's geometry. It is installed as the `ScrollView`'s background,
/// so the backing `NSScrollView` is nearby in the AppKit tree rather than above this view — the
/// search therefore goes up to the nearest ancestor that owns one, then walks that subtree.
@MainActor
private final class ScrollObservingView: NSView {
    var onScrollView: ((NSScrollView) -> Void)?
    var onPhase: ((Bool) -> Void)?

    private weak var scrollView: NSScrollView?
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attach()
    }

    func refresh() {
        attach()
        report()
    }

    private func attach() {
        guard let found = Self.enclosingScrollView(from: self), found !== scrollView else { return }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        scrollView = found
        found.contentView.postsBoundsChangedNotifications = true
        found.postsFrameChangedNotifications = true
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSView.boundsDidChangeNotification, object: found.contentView,
                queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.report() } })
        observers.append(
            center.addObserver(
                forName: NSView.frameDidChangeNotification, object: found, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.report() } })
        observers.append(
            center.addObserver(
                forName: NSScrollView.willStartLiveScrollNotification, object: found, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.onPhase?(true) } })
        observers.append(
            center.addObserver(
                forName: NSScrollView.didEndLiveScrollNotification, object: found, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.onPhase?(false) } })
    }

    private func report() {
        guard let scrollView else { return }
        onScrollView?(scrollView)
    }

    /// Never intercepts clicks: this view only exists to watch the scroll view behind it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Nearest `NSScrollView`. The observer fills the `ScrollView`'s frame, so the right one is the
    /// candidate whose window-space frame overlaps this view; the shallowest match is the tiebreak.
    private static func enclosingScrollView(from view: NSView) -> NSScrollView? {
        let mine = view.convert(view.bounds, to: nil)
        var ancestor = view.superview
        while let current = ancestor {
            let candidates = scrollViews(in: current)
            if let overlapping = candidates.first(where: {
                $0.convert($0.bounds, to: nil).intersects(mine)
            }) {
                return overlapping
            }
            if let nearest = candidates.first { return nearest }
            ancestor = current.superview
        }
        return nil
    }

    private static func scrollViews(in root: NSView) -> [NSScrollView] {
        var found: [NSScrollView] = []
        var level: [NSView] = [root]
        while !level.isEmpty {
            var next: [NSView] = []
            for view in level {
                if let scrollView = view as? NSScrollView {
                    found.append(scrollView)
                } else {
                    next.append(contentsOf: view.subviews)
                }
            }
            level = next
        }
        return found
    }

    deinit {
        // `observers` is main-actor state, and these views are released on the main actor.
        MainActor.assumeIsolated {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
