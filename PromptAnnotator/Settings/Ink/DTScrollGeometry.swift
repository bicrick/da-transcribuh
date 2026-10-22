import CoreGraphics
import Foundation

/// Named scroll / thumb geometry for `DTScrollView`.
///
/// - `contentHeight`: document height after layout (do not inflate with viewport)
/// - `viewportHeight`: clip bounds height
/// - `offset`: distance scrolled from the top (flipped clip: `bounds.origin.y`)
/// - `thumbHeight` / `thumbY`: derived for a track of height `trackH`
struct DTScrollGeometry: Equatable {
    var contentHeight: CGFloat
    var viewportHeight: CGFloat
    var offset: CGFloat

    var scrollable: CGFloat {
        max(contentHeight - viewportHeight, 0)
    }

    var needsScroller: Bool {
        contentHeight > viewportHeight + 1
    }

    func thumbHeight(trackH: CGFloat, minH: CGFloat) -> CGFloat {
        guard contentHeight > 0, trackH > 0 else { return minH }
        let ratio = min(1, viewportHeight / contentHeight)
        return max(minH, trackH * ratio)
    }

    func thumbY(trackH: CGFloat, minH: CGFloat) -> CGFloat {
        let thumbH = thumbHeight(trackH: trackH, minH: minH)
        let travel = max(trackH - thumbH, 0)
        guard scrollable > 0, travel > 0 else { return 0 }
        let fraction = min(max(offset / scrollable, 0), 1)
        return fraction * travel
    }

    /// Flipped document: offset is clip `bounds.origin.y`.
    static func fromFlippedClip(contentHeight: CGFloat, viewportHeight: CGFloat, originY: CGFloat) -> DTScrollGeometry {
        DTScrollGeometry(
            contentHeight: contentHeight,
            viewportHeight: viewportHeight,
            offset: max(0, originY)
        )
    }
}
