import CoreGraphics

/// Crops a full-display screenshot to a selection in display points.
/// Selection origin is the top-left of the display, y down, matching `CGImage` crops.
enum RegionCrop {
    static func pixelRect(selection: CGRect, pointSize: CGSize, pixelSize: CGSize) -> CGRect? {
        guard pointSize.width > 0, pointSize.height > 0, pixelSize.width > 0, pixelSize.height > 0 else {
            return nil
        }
        let box = selection.standardized
        guard box.width > 0, box.height > 0 else { return nil }

        let scaleX = pixelSize.width / pointSize.width
        let scaleY = pixelSize.height / pointSize.height
        let minX = Int(floor(box.minX * scaleX))
        let minY = Int(floor(box.minY * scaleY))
        let maxX = Int(ceil(box.maxX * scaleX))
        let maxY = Int(ceil(box.maxY * scaleY))

        let boundsWidth = Int(pixelSize.width)
        let boundsHeight = Int(pixelSize.height)
        let clampedMinX = min(max(minX, 0), boundsWidth)
        let clampedMinY = min(max(minY, 0), boundsHeight)
        let clampedMaxX = min(max(maxX, 0), boundsWidth)
        let clampedMaxY = min(max(maxY, 0), boundsHeight)
        let width = clampedMaxX - clampedMinX
        let height = clampedMaxY - clampedMinY
        guard width >= 1, height >= 1 else { return nil }

        return CGRect(x: clampedMinX, y: clampedMinY, width: width, height: height)
    }

    static func crop(_ image: CGImage, selection: CGRect, pointSize: CGSize) -> CGImage? {
        guard let pixel = pixelRect(
            selection: selection,
            pointSize: pointSize,
            pixelSize: CGSize(width: image.width, height: image.height)
        ) else {
            return nil
        }
        return image.cropping(to: pixel)
    }
}
