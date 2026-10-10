import SwiftUI

// Small back-deployments for macOS 15/26 API the main line uses but that this branch cannot call.
//
// Each one keeps the newer spelling when the OS has it and degrades to the closest older behaviour
// on 14, so the call sites stay one-liners and the difference is documented in one place.

extension View {
    /// Back-deployed `pointerStyle(.horizontalText)`: a cursor hint, so 14 keeps the default arrow.
    func horizontalTextPointer() -> some View {
        modifier(HorizontalTextPointer())
    }

    /// Back-deployed `.symbolEffect(.rotate, isActive:)`: the spin is decorative, so 14 shows the
    /// icon still.
    func rotatingSymbolWhenActive(_ isActive: Bool) -> some View {
        modifier(RotatingSymbol(isActive: isActive))
    }

    /// Back-deployed `defaultScrollAnchor(.bottom, for: .initialOffset)`. macOS 14 only has the
    /// single-role form, which pins every role to the bottom — the closest older behaviour.
    func initialScrollAnchorAtBottom() -> some View {
        modifier(InitialBottomScrollAnchor())
    }

    /// Back-deployed `onScrollVisibilityChange`. Lazy containers report a row leaving the viewport
    /// through `onDisappear` on 14, which is the same moment the callers here are watching for.
    func closeWhenScrolledAway(_ close: @escaping () -> Void) -> some View {
        modifier(CloseWhenScrolledAway(close: close))
    }
}

private struct HorizontalTextPointer: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(.horizontalText)
        } else {
            content
        }
    }
}

private struct RotatingSymbol: ViewModifier {
    let isActive: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.symbolEffect(.rotate, isActive: isActive)
        } else {
            content
        }
    }
}

private struct CloseWhenScrolledAway: ViewModifier {
    let close: () -> Void

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollVisibilityChange { visible in
                if !visible { close() }
            }
        } else {
            content.onDisappear { close() }
        }
    }
}

private struct InitialBottomScrollAnchor: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.defaultScrollAnchor(.bottom, for: .initialOffset)
        } else {
            content.defaultScrollAnchor(.bottom)
        }
    }
}
