import AppKit
import CoreGraphics
import Darwin

struct ScrollFrameMatch: Equatable, Sendable {
    let verticalShift: Int
    let score: Double
}

enum ScrollFrameMatcher {
    static let maximumAcceptedScore = 18.0
    private static let duplicateFrameScore = 2.5
    private static let minimumMatchImprovement = 4.0
    private static let minimumDistinctCandidateImprovement = 1.5

    static func match(previous: CGImage, current: CGImage) -> ScrollFrameMatch? {
        guard previous.width == current.width,
              previous.height == current.height,
              let previousSample = ScrollFrameSample(image: previous),
              let currentSample = ScrollFrameSample(image: current) else { return nil }

        guard let sampledMatch = match(
            previous: previousSample.pixels,
            current: currentSample.pixels,
            width: previousSample.width,
            height: previousSample.height
        ) else { return nil }

        if sampledMatch.verticalShift == 0 {
            return ScrollFrameMatch(verticalShift: 0, score: sampledMatch.score)
        }

        let sourceShift = Int(
            (CGFloat(sampledMatch.verticalShift) * CGFloat(current.height) / CGFloat(currentSample.height)).rounded()
        )
        guard sourceShift != 0 else {
            return ScrollFrameMatch(verticalShift: 0, score: sampledMatch.score)
        }
        return ScrollFrameMatch(verticalShift: sourceShift, score: sampledMatch.score)
    }

    static func match(
        previous: [UInt8],
        current: [UInt8],
        width: Int,
        height: Int
    ) -> ScrollFrameMatch? {
        guard width >= 8, height >= 12,
              previous.count == width * height,
              current.count == width * height else { return nil }

        let noShiftScore = meanAbsoluteDifference(
            previous: previous,
            current: current,
            width: width,
            previousStartRow: 0,
            currentStartRow: 0,
            rowCount: height
        )
        if noShiftScore <= duplicateFrameScore {
            return ScrollFrameMatch(verticalShift: 0, score: 0)
        }

        let minimumShift = max(2, height / 120)
        let minimumTrackingShift = max(3, height / 120)
        let maximumShift = max(minimumShift, height * 3 / 4)
        var candidates: [ScrollFrameMatch] = []

        for shift in (-maximumShift)...maximumShift where abs(shift) >= minimumShift {
            let overlap = height - abs(shift)
            guard overlap >= max(8, height / 6) else { continue }
            let previousStartRow = shift > 0 ? shift : 0
            let currentStartRow = shift < 0 ? -shift : 0
            let score = robustDifference(
                previous: previous,
                current: current,
                width: width,
                previousStartRow: previousStartRow,
                currentStartRow: currentStartRow,
                rowCount: overlap
            )
            candidates.append(ScrollFrameMatch(verticalShift: shift, score: score))
        }

        candidates.sort { lhs, rhs in
            if lhs.score == rhs.score {
                return abs(lhs.verticalShift) < abs(rhs.verticalShift)
            }
            return lhs.score < rhs.score
        }
        guard let best = candidates.first,
              best.score <= maximumAcceptedScore,
              best.score + minimumMatchImprovement <= noShiftScore else { return nil }
        let ambiguityRadius = max(2, height / 100)
        if let distinctRunnerUp = candidates.first(where: {
            abs($0.verticalShift - best.verticalShift) > ambiguityRadius
        }), distinctRunnerUp.score < best.score + minimumDistinctCandidateImprovement {
            return nil
        }
        guard abs(best.verticalShift) >= minimumTrackingShift else {
            return ScrollFrameMatch(verticalShift: 0, score: best.score)
        }
        return best
    }

    fileprivate static func match(
        previous: ScrollFrameSample,
        current: ScrollFrameSample
    ) -> ScrollFrameMatch? {
        guard previous.sourceHeight == current.sourceHeight,
              let sampledMatch = match(
                previous: previous.pixels,
                current: current.pixels,
                width: previous.width,
                height: previous.height
              ) else { return nil }
        if sampledMatch.verticalShift == 0 {
            return sampledMatch
        }
        let sourceShift = Int(
            (CGFloat(sampledMatch.verticalShift) *
                CGFloat(current.sourceHeight) / CGFloat(current.height)).rounded()
        )
        return ScrollFrameMatch(verticalShift: sourceShift, score: sampledMatch.score)
    }

    fileprivate static func verificationScore(
        previous: ScrollFrameSample,
        current: ScrollFrameSample,
        sourceShift: Int
    ) -> Double? {
        guard previous.width == current.width,
              previous.height == current.height,
              previous.sourceHeight == current.sourceHeight,
              sourceShift != 0 else { return nil }
        let sampledShift = Int(
            (CGFloat(sourceShift) * CGFloat(current.height) /
                CGFloat(current.sourceHeight)).rounded()
        )
        guard sampledShift != 0, abs(sampledShift) < current.height else { return nil }
        let overlap = current.height - abs(sampledShift)
        guard overlap >= max(8, current.height / 6) else { return nil }
        let previousStartRow = sampledShift > 0 ? sampledShift : 0
        let currentStartRow = sampledShift < 0 ? -sampledShift : 0
        let score = robustDifference(
            previous: previous.pixels,
            current: current.pixels,
            width: current.width,
            previousStartRow: previousStartRow,
            currentStartRow: currentStartRow,
            rowCount: overlap
        )
        let noShiftScore = meanAbsoluteDifference(
            previous: previous.pixels,
            current: current.pixels,
            width: current.width,
            previousStartRow: 0,
            currentStartRow: 0,
            rowCount: current.height
        )
        guard score <= maximumAcceptedScore,
              score + minimumMatchImprovement / 2 <= noShiftScore else { return nil }
        return score
    }

    private static func meanAbsoluteDifference(
        previous: [UInt8],
        current: [UInt8],
        width: Int,
        previousStartRow: Int,
        currentStartRow: Int,
        rowCount: Int
    ) -> Double {
        let horizontalMargin = max(1, width / 12)
        let verticalMargin = rowCount >= 20 ? max(1, rowCount / 30) : 0
        let firstX = horizontalMargin
        let lastX = width - horizontalMargin
        let firstRow = verticalMargin
        let lastRow = rowCount - verticalMargin
        var total = 0
        var count = 0

        for row in stride(from: firstRow, to: lastRow, by: 2) {
            let previousOffset = (previousStartRow + row) * width
            let currentOffset = (currentStartRow + row) * width
            for x in stride(from: firstX, to: lastX, by: 3) {
                total += abs(Int(previous[previousOffset + x]) - Int(current[currentOffset + x]))
                count += 1
            }
        }
        guard count > 0 else { return .infinity }
        return Double(total) / Double(count)
    }

    private static func robustDifference(
        previous: [UInt8],
        current: [UInt8],
        width: Int,
        previousStartRow: Int,
        currentStartRow: Int,
        rowCount: Int
    ) -> Double {
        let horizontalMargin = max(1, width / 12)
        let availableWidth = width - horizontalMargin * 2
        guard availableWidth >= 4, rowCount >= 4 else { return .infinity }
        let rowBands = min(12, max(3, rowCount / 10))
        let columnBands = min(5, max(2, availableWidth / 24))
        var blockScores: [Double] = []

        for rowBand in 0..<rowBands {
            let rowStart = rowBand * rowCount / rowBands
            let rowEnd = (rowBand + 1) * rowCount / rowBands
            guard rowEnd > rowStart else { continue }
            for columnBand in 0..<columnBands {
                let xStart = horizontalMargin + columnBand * availableWidth / columnBands
                let xEnd = horizontalMargin + (columnBand + 1) * availableWidth / columnBands
                guard xEnd > xStart else { continue }
                var total = 0
                var count = 0
                for row in stride(from: rowStart, to: rowEnd, by: 2) {
                    let previousOffset = (previousStartRow + row) * width
                    let currentOffset = (currentStartRow + row) * width
                    for x in stride(from: xStart, to: xEnd, by: 2) {
                        total += abs(Int(previous[previousOffset + x]) - Int(current[currentOffset + x]))
                        count += 1
                    }
                }
                if count > 0 {
                    blockScores.append(Double(total) / Double(count))
                }
            }
        }

        guard !blockScores.isEmpty else { return .infinity }
        blockScores.sort()
        let retainedCount = max(1, Int((Double(blockScores.count) * 0.8).rounded(.up)))
        let retained = blockScores.prefix(retainedCount)
        let trimmedMean = retained.reduce(0, +) / Double(retained.count)
        let median = blockScores[blockScores.count / 2]
        return trimmedMean * 0.55 + median * 0.45
    }
}

enum ScrollCaptureAppendResult: Equatable, Sendable {
    case initial
    case appended(pixelHeight: Int, score: Double)
    case duplicate
    case revisited(pixelOffset: Int, score: Double)
    case unmatched
    case limitReached
}

private class ScrollCaptureByteSource {
    let byteCount: Int

    init(byteCount: Int) {
        self.byteCount = byteCount
    }

    func copyBytes(to buffer: UnsafeMutableRawPointer, position: Int, count: Int) -> Int {
        0
    }
}

private let scrollCaptureGetBytesAtPosition: CGDataProviderGetBytesAtPositionCallback = {
    info,
    buffer,
    position,
    count in
    guard let info, position >= 0 else { return 0 }
    let source = Unmanaged<ScrollCaptureByteSource>.fromOpaque(info).takeUnretainedValue()
    return source.copyBytes(
        to: buffer,
        position: Int(position),
        count: count
    )
}

private let scrollCaptureReleaseProviderInfo: CGDataProviderReleaseInfoCallback = { info in
    guard let info else { return }
    Unmanaged<ScrollCaptureByteSource>.fromOpaque(info).release()
}

private func scrollCaptureDataProvider(
    source: ScrollCaptureByteSource
) -> CGDataProvider? {
    let info = Unmanaged.passRetained(source).toOpaque()
    var callbacks = CGDataProviderDirectCallbacks(
        version: 0,
        getBytePointer: nil,
        releaseBytePointer: nil,
        getBytesAtPosition: scrollCaptureGetBytesAtPosition,
        releaseInfo: scrollCaptureReleaseProviderInfo
    )
    guard let provider = CGDataProvider(
        directInfo: info,
        size: off_t(source.byteCount),
        callbacks: &callbacks
    ) else {
        Unmanaged<ScrollCaptureByteSource>.fromOpaque(info).release()
        return nil
    }
    return provider
}

private struct ScrollCaptureStoredSlice {
    let fileOffset: off_t
    let width: Int
    let height: Int
    let bytesPerRow: Int

    var byteCount: Int { bytesPerRow * height }
}

private final class ScrollCaptureBackingStore {
    static let maximumByteCount = 1_000_000_000

    private let fileDescriptor: Int32
    private(set) var byteCount = 0

    init?() {
        var template = Array(
            (NSTemporaryDirectory() + "PinboardShot-scroll-capture.XXXXXX").utf8CString
        )
        let descriptor = template.withUnsafeMutableBufferPointer { buffer in
            mkstemp(buffer.baseAddress!)
        }
        guard descriptor >= 0 else { return nil }
        template.withUnsafeBufferPointer { buffer in
            _ = unlink(buffer.baseAddress!)
        }
        fileDescriptor = descriptor
    }

    deinit {
        close(fileDescriptor)
    }

    func append(_ image: CGImage) -> ScrollCaptureStoredSlice? {
        let (bytesPerRow, rowOverflow) = image.width.multipliedReportingOverflow(by: 4)
        let (sliceByteCount, overflow) = bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard !rowOverflow,
              !overflow,
              sliceByteCount > 0,
              sliceByteCount <= Self.maximumByteCount,
              byteCount <= Self.maximumByteCount - sliceByteCount,
              let data = NSMutableData(length: sliceByteCount),
              let context = CGContext(
                data: data.mutableBytes,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                    CGBitmapInfo.byteOrder32Big.rawValue
              ) else {
            return nil
        }
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )

        let fileOffset = off_t(byteCount)
        var writtenByteCount = 0
        while writtenByteCount < sliceByteCount {
            let result = pwrite(
                fileDescriptor,
                data.bytes.advanced(by: writtenByteCount),
                sliceByteCount - writtenByteCount,
                fileOffset + off_t(writtenByteCount)
            )
            if result < 0, errno == EINTR { continue }
            guard result > 0 else { return nil }
            writtenByteCount += result
        }
        byteCount += sliceByteCount
        return ScrollCaptureStoredSlice(
            fileOffset: fileOffset,
            width: image.width,
            height: image.height,
            bytesPerRow: bytesPerRow
        )
    }

    func image(for slice: ScrollCaptureStoredSlice) -> CGImage? {
        let source = ScrollCaptureFileRegionSource(store: self, slice: slice)
        guard let provider = scrollCaptureDataProvider(source: source) else { return nil }
        return CGImage(
            width: slice.width,
            height: slice.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: slice.bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue |
                    CGBitmapInfo.byteOrder32Big.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    func finalImage(
        slices: [ScrollCaptureStoredSlice],
        width: Int,
        height: Int
    ) -> CGImage? {
        let source = ScrollCaptureCompositeSource(store: self, slices: slices)
        guard source.byteCount == width * height * 4,
              let provider = scrollCaptureDataProvider(source: source) else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue |
                    CGBitmapInfo.byteOrder32Big.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    fileprivate func read(
        into buffer: UnsafeMutableRawPointer,
        fileOffset: off_t,
        count: Int
    ) -> Int {
        var readByteCount = 0
        while readByteCount < count {
            let result = pread(
                fileDescriptor,
                buffer.advanced(by: readByteCount),
                count - readByteCount,
                fileOffset + off_t(readByteCount)
            )
            if result < 0, errno == EINTR { continue }
            guard result > 0 else { break }
            readByteCount += result
        }
        return readByteCount
    }
}

private final class ScrollCaptureFileRegionSource: ScrollCaptureByteSource {
    private let store: ScrollCaptureBackingStore
    private let fileOffset: off_t

    init(store: ScrollCaptureBackingStore, slice: ScrollCaptureStoredSlice) {
        self.store = store
        fileOffset = slice.fileOffset
        super.init(byteCount: slice.byteCount)
    }

    override func copyBytes(
        to buffer: UnsafeMutableRawPointer,
        position: Int,
        count: Int
    ) -> Int {
        guard position >= 0, position < byteCount else { return 0 }
        return store.read(
            into: buffer,
            fileOffset: fileOffset + off_t(position),
            count: min(count, byteCount - position)
        )
    }
}

private final class ScrollCaptureCompositeSource: ScrollCaptureByteSource {
    private struct Segment {
        let logicalOffset: Int
        let fileOffset: off_t
        let byteCount: Int
    }

    private let store: ScrollCaptureBackingStore
    private let segments: [Segment]

    init(store: ScrollCaptureBackingStore, slices: [ScrollCaptureStoredSlice]) {
        self.store = store
        var logicalOffset = 0
        segments = slices.map { slice in
            defer { logicalOffset += slice.byteCount }
            return Segment(
                logicalOffset: logicalOffset,
                fileOffset: slice.fileOffset,
                byteCount: slice.byteCount
            )
        }
        super.init(byteCount: logicalOffset)
    }

    override func copyBytes(
        to buffer: UnsafeMutableRawPointer,
        position: Int,
        count: Int
    ) -> Int {
        guard position >= 0, position < byteCount, count > 0 else { return 0 }
        var segmentIndex = segmentIndex(containing: position)
        var logicalPosition = position
        var copiedByteCount = 0

        while segmentIndex < segments.count, copiedByteCount < count {
            let segment = segments[segmentIndex]
            let positionInSegment = logicalPosition - segment.logicalOffset
            let requestedByteCount = min(
                count - copiedByteCount,
                segment.byteCount - positionInSegment
            )
            let result = store.read(
                into: buffer.advanced(by: copiedByteCount),
                fileOffset: segment.fileOffset + off_t(positionInSegment),
                count: requestedByteCount
            )
            copiedByteCount += result
            logicalPosition += result
            guard result == requestedByteCount else { break }
            segmentIndex += 1
        }
        return copiedByteCount
    }

    private func segmentIndex(containing position: Int) -> Int {
        var lowerBound = 0
        var upperBound = segments.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            let segment = segments[middle]
            if position < segment.logicalOffset {
                upperBound = middle
            } else if position >= segment.logicalOffset + segment.byteCount {
                lowerBound = middle + 1
            } else {
                return middle
            }
        }
        return lowerBound
    }
}

final class ScrollCaptureAccumulator {
    static let maximumPixelCount = ScrollCaptureBackingStore.maximumByteCount / 4
    private static let maximumKeyframeCount = 160

    private let backingStore = ScrollCaptureBackingStore()
    private var slices: [ScrollCaptureStoredSlice] = []
    private(set) var pixelWidth = 0
    private(set) var pixelHeight = 0
    private var trackingSample: ScrollFrameSample?
    private var trackingVerificationSample: ScrollFrameSample?
    private var trackingPosition = 0
    private var capturedMinimumPosition = 0
    private var capturedMaximumPosition = 0
    private var keyframes: [ScrollCaptureKeyframe] = []

    var hasContent: Bool { !slices.isEmpty }

    func append(_ frame: CGImage) -> ScrollCaptureAppendResult {
        guard let sample = ScrollFrameSample(image: frame),
              let verificationSample = ScrollFrameSample(image: frame, targetWidthLimit: 480) else {
            return .unmatched
        }
        guard let trackingSample else {
            guard Self.canAppend(width: frame.width, currentHeight: 0, appendedHeight: frame.height),
                  let backingStore,
                  let storedSlice = backingStore.append(frame) else { return .limitReached }
            slices = [storedSlice]
            pixelWidth = frame.width
            pixelHeight = frame.height
            self.trackingSample = sample
            trackingVerificationSample = verificationSample
            trackingPosition = 0
            capturedMinimumPosition = 0
            capturedMaximumPosition = frame.height
            rememberKeyframe(sample, verificationSample: verificationSample, at: 0)
            return .initial
        }

        guard frame.width == pixelWidth,
              frame.height == trackingSample.sourceHeight else {
            return .unmatched
        }

        let localPlacement: ScrollCapturePlacement?
        let localMatch = ScrollFrameMatcher.match(previous: trackingSample, current: sample)
        if let match = localMatch, match.verticalShift == 0 {
            localPlacement = ScrollCapturePlacement(position: trackingPosition, score: match.score)
        } else if let match = localMatch,
                  let trackingVerificationSample,
                  let verificationScore = ScrollFrameMatcher.verificationScore(
                    previous: trackingVerificationSample,
                    current: verificationSample,
                    sourceShift: match.verticalShift
                  ) {
            localPlacement = ScrollCapturePlacement(
                position: trackingPosition + match.verticalShift,
                score: max(match.score, verificationScore)
            )
        } else {
            localPlacement = nil
        }
        var placement = localPlacement ?? relocalizedPlacement(
            for: sample,
            verificationSample: verificationSample
        )
        guard placement != nil else { return .unmatched }
        if let candidate = placement {
            let candidateMinimum = candidate.position
            let candidateMaximum = candidate.position + frame.height
            let extendsCapturedRange = candidateMinimum < capturedMinimumPosition ||
                candidateMaximum > capturedMaximumPosition
            let localDisplacement = abs(candidate.position - trackingPosition)
            let trustsStrongLocalMatch = localPlacement != nil &&
                candidate.score <= 6 &&
                localDisplacement <= frame.height / 3
            if extendsCapturedRange, keyframes.count > 1, !trustsStrongLocalMatch {
                let allowedPosition: ClosedRange<Int>
                if candidateMaximum > capturedMaximumPosition {
                    allowedPosition = ClosedRange(uncheckedBounds: (
                        capturedMaximumPosition - frame.height + 1,
                        capturedMaximumPosition - 1
                    ))
                } else {
                    allowedPosition = ClosedRange(uncheckedBounds: (
                        capturedMinimumPosition - frame.height + 1,
                        capturedMinimumPosition - 1
                    ))
                }
                guard let globallyVerified = relocalizedPlacement(
                    for: sample,
                    verificationSample: verificationSample,
                    allowedPosition: allowedPosition
                ) else {
                    return .unmatched
                }
                placement = globallyVerified
            }
        }
        guard let placement else { return .unmatched }
        if placement.position == trackingPosition {
            self.trackingSample = sample
            trackingVerificationSample = verificationSample
            return .duplicate
        }

        let frameMinimum = placement.position
        let frameMaximum = placement.position + frame.height
        guard frameMaximum > capturedMinimumPosition,
              frameMinimum < capturedMaximumPosition else {
            return .unmatched
        }

        if frameMinimum >= capturedMinimumPosition,
           frameMaximum <= capturedMaximumPosition {
            trackingPosition = placement.position
            self.trackingSample = sample
            trackingVerificationSample = verificationSample
            return .revisited(
                pixelOffset: placement.position - capturedMinimumPosition,
                score: placement.score
            )
        }

        let appendHeight: Int
        let stripRect: CGRect
        let shouldPrepend: Bool
        if frameMaximum > capturedMaximumPosition {
            appendHeight = frameMaximum - capturedMaximumPosition
            stripRect = CGRect(
                x: 0,
                y: frame.height - appendHeight,
                width: frame.width,
                height: appendHeight
            )
            shouldPrepend = false
        } else {
            appendHeight = capturedMinimumPosition - frameMinimum
            stripRect = CGRect(
                x: 0,
                y: 0,
                width: frame.width,
                height: appendHeight
            )
            shouldPrepend = true
        }

        guard appendHeight > 0,
              Self.canAppend(
                width: pixelWidth,
                currentHeight: pixelHeight,
                appendedHeight: appendHeight
              ) else { return .limitReached }
        guard let strip = frame.cropping(to: stripRect),
              let backingStore,
              let storedSlice = backingStore.append(strip) else { return .limitReached }
        if shouldPrepend {
            slices.insert(storedSlice, at: 0)
            capturedMinimumPosition = frameMinimum
        } else {
            slices.append(storedSlice)
            capturedMaximumPosition = frameMaximum
        }
        pixelHeight += storedSlice.height
        trackingPosition = placement.position
        self.trackingSample = sample
        trackingVerificationSample = verificationSample
        rememberKeyframe(
            sample,
            verificationSample: verificationSample,
            at: placement.position
        )
        return .appended(pixelHeight: storedSlice.height, score: placement.score)
    }

    func makeImage() -> CGImage? {
        guard pixelWidth > 0, pixelHeight > 0, let backingStore else { return nil }
        return backingStore.finalImage(
            slices: slices,
            width: pixelWidth,
            height: pixelHeight
        )
    }

    func makePreviewImage(maximumWidth: Int = 260, maximumHeight: Int = 4_096) -> CGImage? {
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        let scale = min(
            CGFloat(maximumWidth) / CGFloat(pixelWidth),
            CGFloat(maximumHeight) / CGFloat(pixelHeight),
            1
        )
        let previewWidth = max(1, Int((CGFloat(pixelWidth) * scale).rounded()))
        let previewHeight = max(1, Int((CGFloat(pixelHeight) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: previewWidth,
            height: previewHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium

        var top = CGFloat(previewHeight)
        for slice in slices {
            guard let backingStore,
                  let sliceImage = backingStore.image(for: slice) else { return nil }
            let sliceHeight = CGFloat(slice.height) * scale
            top -= sliceHeight
            context.draw(
                sliceImage,
                in: CGRect(x: 0, y: top, width: CGFloat(previewWidth), height: sliceHeight)
            )
        }
        return context.makeImage()
    }

    static func canAppend(width: Int, currentHeight: Int, appendedHeight: Int) -> Bool {
        guard width > 0, currentHeight >= 0, appendedHeight > 0 else { return false }
        let (height, heightOverflow) = currentHeight.addingReportingOverflow(appendedHeight)
        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        return !heightOverflow && !pixelOverflow && pixelCount <= maximumPixelCount
    }

    private func relocalizedPlacement(
        for sample: ScrollFrameSample,
        verificationSample: ScrollFrameSample,
        allowedPosition: ClosedRange<Int>? = nil
    ) -> ScrollCapturePlacement? {
        var candidates: [ScrollCapturePlacement] = []
        let maximumShift = sample.sourceHeight * 3 / 4
        let relevantKeyframes = keyframes.filter { keyframe in
            guard let allowedPosition else { return true }
            return keyframe.position >= allowedPosition.lowerBound - maximumShift &&
                keyframe.position <= allowedPosition.upperBound + maximumShift
        }
        let searchStride = max(1, relevantKeyframes.count / 48)
        for (index, keyframe) in relevantKeyframes.enumerated()
        where index.isMultiple(of: searchStride) || index == relevantKeyframes.count - 1 {
            guard let match = ScrollFrameMatcher.match(previous: keyframe.sample, current: sample) else {
                continue
            }
            let verificationScore: Double
            if match.verticalShift == 0 {
                verificationScore = match.score
            } else {
                guard let score = ScrollFrameMatcher.verificationScore(
                    previous: keyframe.verificationSample,
                    current: verificationSample,
                    sourceShift: match.verticalShift
                ) else { continue }
                verificationScore = score
            }
            let position = keyframe.position + match.verticalShift
            if let allowedPosition, !allowedPosition.contains(position) {
                continue
            }
            let maximum = position + sample.sourceHeight
            guard maximum > capturedMinimumPosition,
                  position < capturedMaximumPosition else { continue }
            candidates.append(ScrollCapturePlacement(
                position: position,
                score: max(match.score, verificationScore)
            ))
        }
        guard !candidates.isEmpty else { return nil }

        let tolerance = max(2, sample.sourceHeight / max(80, sample.height))
        var clusters: [[ScrollCapturePlacement]] = []
        for candidate in candidates.sorted(by: { $0.position < $1.position }) {
            if let index = clusters.indices.last,
               let last = clusters[index].last,
               abs(last.position - candidate.position) <= tolerance {
                clusters[index].append(candidate)
            } else {
                clusters.append([candidate])
            }
        }
        let ranked = clusters.map { cluster -> ScrollCapturePlacementCluster in
            let position = Int(
                (Double(cluster.map(\.position).reduce(0, +)) / Double(cluster.count)).rounded()
            )
            let score = cluster.map(\.score).reduce(0, +) / Double(cluster.count)
            return ScrollCapturePlacementCluster(position: position, score: score, votes: cluster.count)
        }.sorted {
            let lhsRank = $0.score - Double(min(3, $0.votes - 1)) * 1.5
            let rhsRank = $1.score - Double(min(3, $1.votes - 1)) * 1.5
            if lhsRank == rhsRank { return $0.votes > $1.votes }
            return lhsRank < rhsRank
        }
        guard let best = ranked.first else { return nil }
        if let runnerUp = ranked.dropFirst().first,
           runnerUp.score - Double(min(3, runnerUp.votes - 1)) * 1.5 <
            best.score - Double(min(3, best.votes - 1)) * 1.5 + 1.5 {
            return nil
        }
        guard best.votes >= 2 || best.score <= 6 else { return nil }
        return ScrollCapturePlacement(position: best.position, score: best.score)
    }

    private func rememberKeyframe(
        _ sample: ScrollFrameSample,
        verificationSample: ScrollFrameSample,
        at position: Int
    ) {
        let spacing = max(8, sample.sourceHeight / 10)
        if let existingIndex = keyframes.firstIndex(where: {
            abs($0.position - position) < spacing
        }) {
            if keyframes[existingIndex].position == position {
                keyframes[existingIndex] = ScrollCaptureKeyframe(
                    position: position,
                    sample: sample,
                    verificationSample: verificationSample
                )
            }
            return
        }
        keyframes.append(ScrollCaptureKeyframe(
            position: position,
            sample: sample,
            verificationSample: verificationSample
        ))
        keyframes.sort { $0.position < $1.position }
        if keyframes.count > Self.maximumKeyframeCount {
            let removableIndex = keyframes.count > 2 ? 1 : 0
            keyframes.remove(at: removableIndex)
        }
    }
}

private struct ScrollCapturePlacement {
    let position: Int
    let score: Double
}

private struct ScrollCapturePlacementCluster {
    let position: Int
    let score: Double
    let votes: Int
}

private struct ScrollCaptureKeyframe {
    let position: Int
    let sample: ScrollFrameSample
    let verificationSample: ScrollFrameSample
}

fileprivate struct ScrollFrameSample {
    let width: Int
    let height: Int
    let sourceHeight: Int
    let pixels: [UInt8]

    init?(image: CGImage, targetWidthLimit: Int = 180) {
        let targetWidth = min(targetWidthLimit, image.width)
        let scale = CGFloat(targetWidth) / CGFloat(image.width)
        let targetHeight = min(360, max(12, Int((CGFloat(image.height) * scale).rounded())))
        var pixels = [UInt8](repeating: 0, count: targetWidth * targetHeight)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: targetWidth,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
            return true
        }
        guard rendered else { return nil }
        self.width = targetWidth
        self.height = targetHeight
        sourceHeight = image.height
        self.pixels = pixels
    }
}
