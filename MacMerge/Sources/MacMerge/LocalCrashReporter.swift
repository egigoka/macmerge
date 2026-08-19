import Foundation
import MetricKit

final class CrashDiagnosticStore: @unchecked Sendable {
    private let directoryURL: URL
    private let maximumReports: Int
    private let lock = NSLock()

    init(directoryURL: URL, maximumReports: Int = 20) {
        precondition(maximumReports > 0)
        self.directoryURL = directoryURL
        self.maximumReports = maximumReports
    }

    func save(_ payloads: [Data], recordedAt: Date = Date()) throws {
        guard !payloads.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        defer { try? removeExcessReports() }
        let timestamp = Int64(recordedAt.timeIntervalSince1970 * 1_000)
        for payload in payloads
        where JSONSerialization.isValidJSONObject(
            (try? JSONSerialization.jsonObject(with: payload)) ?? NSNull()
        ) {
            let filename = String(format: "%020lld-%@.json", timestamp, UUID().uuidString)
            try payload.write(to: directoryURL.appending(path: filename), options: .atomic)
        }
        try removeExcessReports()
    }

    private func removeExcessReports() throws {
        let reports = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for report in reports.dropLast(maximumReports) {
            try FileManager.default.removeItem(at: report)
        }
    }
}

final class LocalCrashReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    private let store: CrashDiagnosticStore

    override convenience init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.init(
            store: CrashDiagnosticStore(
                directoryURL:
                    applicationSupport
                    .appending(path: "MacMerge", directoryHint: .isDirectory)
                    .appending(path: "Diagnostics", directoryHint: .isDirectory)
            ))
    }

    init(store: CrashDiagnosticStore) {
        self.store = store
        super.init()
    }

    func start() {
        MXMetricManager.shared.add(self)
    }

    func stop() {
        MXMetricManager.shared.remove(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        try? store.save(payloads.map { $0.jsonRepresentation() })
    }
}
