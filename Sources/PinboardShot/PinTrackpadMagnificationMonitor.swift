import AppKit
import CoreGraphics

final class PinTrackpadMagnificationMonitor: @unchecked Sendable {
    typealias Handler = @MainActor @Sendable (CGFloat) -> Void

    private let handler: Handler
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    @MainActor
    init?(handler: @escaping Handler) {
        self.handler = handler

        let gestureMask = CGEventMask(1) << CGEventMask(NSEvent.EventType.gesture.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: gestureMask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return nil }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.eventTap = eventTap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<PinTrackpadMagnificationMonitor>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = monitor.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let appKitEvent = NSEvent(cgEvent: event),
              appKitEvent.type == .magnify,
              appKitEvent.magnification != 0 else {
            return Unmanaged.passUnretained(event)
        }

        let magnification = appKitEvent.magnification
        Task { @MainActor in
            monitor.handler(magnification)
        }
        return Unmanaged.passUnretained(event)
    }
}
