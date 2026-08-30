import CoreGraphics
import Foundation

enum LastCaptureRegionStore {
    private static let defaultsKey = "lastCaptureRegion.normalized"

    static func save(
        selection: CGRect,
        in screenFrame: CGRect,
        defaults: UserDefaults = .standard
    ) {
        guard screenFrame.width > 0, screenFrame.height > 0 else { return }
        let normalized = [
            (selection.minX - screenFrame.minX) / screenFrame.width,
            (selection.minY - screenFrame.minY) / screenFrame.height,
            selection.width / screenFrame.width,
            selection.height / screenFrame.height
        ]
        defaults.set(normalized.map(Double.init), forKey: defaultsKey)
    }

    static func selection(
        in screenFrame: CGRect,
        defaults: UserDefaults = .standard
    ) -> CGRect? {
        guard let values = defaults.array(forKey: defaultsKey) as? [Double], values.count == 4 else {
            return nil
        }
        let normalized = values.map { CGFloat($0) }
        guard normalized.allSatisfy({ $0.isFinite }),
              normalized[2] > 0,
              normalized[3] > 0 else { return nil }
        let selection = CGRect(
            x: screenFrame.minX + normalized[0] * screenFrame.width,
            y: screenFrame.minY + normalized[1] * screenFrame.height,
            width: normalized[2] * screenFrame.width,
            height: normalized[3] * screenFrame.height
        ).integral
        let clipped = selection.intersection(screenFrame)
        return clipped.width >= 2 && clipped.height >= 2 ? clipped : nil
    }
}
