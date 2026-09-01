import AppKit
import QuartzCore

@MainActor
final class MainThreadPerformanceProbe: NSObject {
    private static let interval = 1.0 / 60.0
    private let outputURL = ProcessInfo.processInfo.environment["SIDEY_MAIN_THREAD_METRICS_PATH"]
        .map { URL(fileURLWithPath: $0) }
    private var timer: Timer?
    private var previousTick: CFTimeInterval?
    private var tickGapsMS = BoundedDoubleRingBuffer(capacity: 1_800)
    private var totalSampleCount = 0
    private let writer = MainThreadMetricsWriter()

    func start() {
        guard outputURL != nil, timer == nil else { return }
        previousTick = CACurrentMediaTime()
        let timer = Timer(
            timeInterval: Self.interval,
            target: self,
            selector: #selector(tick(_:)),
            userInfo: nil,
            repeats: true
        )
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        flush()
    }

    @objc private func tick(_ timer: Timer) {
        let now = CACurrentMediaTime()
        if let previousTick {
            tickGapsMS.append((now - previousTick) * 1_000)
            totalSampleCount += 1
        }
        previousTick = now
        if totalSampleCount > 0 && totalSampleCount.isMultiple(of: 300) {
            flush()
        }
    }

    private func flush() {
        guard let outputURL else { return }
        let sorted = tickGapsMS.values.sorted()
        let p95Index = sorted.isEmpty
            ? 0
            : min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        let maximumGap = sorted.last ?? 0
        let snapshot = MainThreadMetricsSnapshot(
            sampleCount: totalSampleCount,
            tickGapP95MS: sorted.isEmpty ? 0 : sorted[p95Index],
            tickGapMaxMS: maximumGap,
            maximumStallMS: max(0, maximumGap - Self.interval * 1_000)
        )
        Task(priority: .utility) { [writer] in
            await writer.write(snapshot, to: outputURL)
        }
    }
}

private struct BoundedDoubleRingBuffer {
    private var storage: [Double]
    private var nextIndex = 0
    private(set) var count = 0

    init(capacity: Int) {
        storage = Array(repeating: 0, count: max(1, capacity))
    }

    mutating func append(_ value: Double) {
        storage[nextIndex] = value
        nextIndex = (nextIndex + 1) % storage.count
        count = min(count + 1, storage.count)
    }

    var values: [Double] {
        guard count == storage.count else { return Array(storage.prefix(count)) }
        return Array(storage[nextIndex...]) + Array(storage[..<nextIndex])
    }
}

private actor MainThreadMetricsWriter {
    func write(_ snapshot: MainThreadMetricsSnapshot, to outputURL: URL) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: outputURL, options: .atomic)
    }
}

private struct MainThreadMetricsSnapshot: Codable, Sendable {
    let sampleCount: Int
    let tickGapP95MS: Double
    let tickGapMaxMS: Double
    let maximumStallMS: Double
}
