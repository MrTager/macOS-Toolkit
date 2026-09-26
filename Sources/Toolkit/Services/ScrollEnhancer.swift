import AppKit
import Combine
import CoreGraphics

struct ScrollSettings: Codable, Equatable {
    var reverse = true
    var smooth = true
    var stepRatio = 0.8
    var duration = 0.25
    var disableWhenExternalMouse = false
}

final class ScrollEnhancer: ObservableObject {
    @Published var settings: ScrollSettings {
        didSet {
            persist()
            applyMode()
        }
    }
    @Published private(set) var active = false
    @Published private(set) var permissionGranted = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var animations: [ScrollAnimation] = []
    private var displayLink: CVDisplayLink?
    private var lastEventTime: CFTimeInterval = 0
    private static let maxConcurrent = 10

    private static var configURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("macOS Toolkit/scroll.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.configURL),
           let loaded = try? JSONDecoder().decode(ScrollSettings.self, from: data) {
            settings = loaded
        } else {
            settings = ScrollSettings()
        }
        refreshPermission()
    }

    deinit {
        stopTap()
    }

    func refreshPermission() {
        permissionGranted = AXIsProcessTrusted()
    }

    func openPermissionSettings() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func toggle() {
        if active {
            stopTap()
        } else {
            startTap()
        }
    }

    private func applyMode() {
        guard active else { return }
        stopTap()
        startTap()
    }

    private func startTap() {
        guard permissionGranted else { return }
        guard eventTap == nil else { return }

        let mask = (1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { proxy, type, event, userInfo in
                let enhancer = Unmanaged<ScrollEnhancer>.fromOpaque(userInfo!).takeUnretainedValue()
                return enhancer.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            active = false
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        active = true
        setupDisplayLinkIfNeeded()
    }

    private func stopTap() {
        animations.removeAll()
        if let tap = eventTap {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            runLoopSource = nil
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        active = false
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }
        guard type == .scrollWheel, active else {
            return Unmanaged.passRetained(event)
        }

        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        guard !isContinuous else {
            return Unmanaged.passRetained(event)
        }
        if settings.disableWhenExternalMouse && hasExternalMouse() {
            return Unmanaged.passRetained(event)
        }

        var deltaY = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        var deltaX = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        if settings.reverse {
            deltaY = -deltaY
            deltaX = -deltaX
        }
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: deltaY)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: deltaX)
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: deltaY * 65536 / 8)
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2, value: deltaX * 65536 / 8)

        if settings.smooth {
            enqueueAnimation(deltaY: deltaY, deltaX: deltaX, event: event)
            return nil
        }
        return Unmanaged.passRetained(event)
    }

    private func enqueueAnimation(deltaY: Int64, deltaX: Int64, event: CGEvent) {
        let now = CACurrentMediaTime()
        if now - lastEventTime < 0.15 {
            if let last = animations.last, last.settled {
                last.extend(deltaY: deltaY, deltaX: deltaX)
                lastEventTime = now
                return
            }
        }
        if animations.count >= Self.maxConcurrent {
            animations.removeFirst(animations.count - Self.maxConcurrent + 1)
        }
        animations.append(ScrollAnimation(
            deltaY: deltaY,
            deltaX: deltaX,
            stepRatio: settings.stepRatio,
            duration: settings.duration,
            template: event.copy() ?? event
        ))
        lastEventTime = now
    }

    private func hasExternalMouse() -> Bool {
        false
    }

    private func setupDisplayLinkIfNeeded() {
        guard displayLink == nil else { return }
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }
        displayLink = link
        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, userInfo in
            let enhancer = Unmanaged<ScrollEnhancer>.fromOpaque(userInfo!).takeUnretainedValue()
            enhancer.tick()
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(link)
    }

    private func tick() {
        let alive = animations.compactMap { animation -> ScrollAnimation? in
            animation.advance()
            if animation.isFinished {
                animation.flushRemainder()
                return nil
            }
            return animation
        }
        animations = alive
        if animations.isEmpty {
            if let link = displayLink, CVDisplayLinkIsRunning(link) {
                CVDisplayLinkStop(link)
            }
        } else {
            if let link = displayLink, !CVDisplayLinkIsRunning(link) {
                CVDisplayLinkStart(link)
            }
        }
    }

    private func persist() {
        let url = Self.configURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

extension ScrollEnhancer {
    final class ScrollAnimation {
        let stepRatio: Double
        let duration: CFTimeInterval
        let template: CGEvent

        var settled = false
        private(set) var isFinished = false
        private var remainingY: Double
        private var remainingX: Double
        private var elapsed: CFTimeInterval = 0
        private var frames = 0

        init(deltaY: Int64, deltaX: Int64, stepRatio: Double, duration: CFTimeInterval, template: CGEvent) {
            self.stepRatio = stepRatio
            self.duration = duration
            self.template = template
            self.remainingY = Double(deltaY)
            self.remainingX = Double(deltaX)
        }

        func extend(deltaY: Int64, deltaX: Int64) {
            remainingY += Double(deltaY)
            remainingX += Double(deltaX)
            elapsed = 0
            frames = 0
            settled = true
        }

        func advance() {
            let step = 1.0 / 60.0
            elapsed += step
            frames += 1
            let progress = min(elapsed / duration, 1)
            let factor = stepRatio * (1 - pow(1 - progress, 2)) / max(1, Double(frames) * stepRatio * 0.6)
            let deltaY = Int64((remainingY * max(factor, 0.12)).rounded())
            let deltaX = Int64((remainingX * max(factor, 0.12)).rounded())
            if abs(deltaY) > 0 || abs(deltaX) > 0 {
                emit(deltaY: deltaY, deltaX: deltaX)
                remainingY -= Double(deltaY)
                remainingX -= Double(deltaX)
            }
            if progress >= 1, abs(remainingY) < 1, abs(remainingX) < 1 {
                isFinished = true
            }
        }

        func flushRemainder() {
            let deltaY = Int64(remainingY.rounded())
            let deltaX = Int64(remainingX.rounded())
            if deltaY != 0 || deltaX != 0 {
                emit(deltaY: deltaY, deltaX: deltaX)
            }
        }

        private func emit(deltaY: Int64, deltaX: Int64) {
            let event = template.copy() ?? template
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: deltaY)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: deltaX)
            event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: deltaY * 65536 / 8)
            event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2, value: deltaX * 65536 / 8)
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
