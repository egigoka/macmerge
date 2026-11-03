import CryptoKit
import Darwin
import Foundation

/// UI-independent plan-only external-tool executor.
///
/// Consumes a validated `ExternalToolExecutionPlan` and returns either a launch-ready
/// receipt or a fail-closed non-launch outcome. This stub never spawns a process, never
/// touches the filesystem outside bounded pinned-descriptor verification reads, and never
/// presents UI. Full typed-argument, scope, and trust validation happens in
/// `ExternalToolRequestPlanner`; the executor re-asserts cheap structural invariants,
/// re-verifies the pinned executable identity (canonical device/inode/generation,
/// size, timestamps, trusted SHA-256) from a duplicated descriptor only, enforces
/// host sandbox authority and default-deny ambient capabilities, honors cancellation,
/// and reports staleness through caller-supplied revalidation probes.
///
/// Explicitly unsupported and fail-closed: plugin reload and in-process extensions can
/// never produce a launch receipt. Trust UI, persistence, and workflow integration
/// remain missing; no UI is claimed.
public struct ExternalToolExecutorLimits: Equatable, Hashable, Sendable {
    public static let hardMaximumVerificationBytes = 512 * 1_024 * 1_024
    public static let hardMaximumCancellationCheckInterval = 4_096

    public static let `default` = Self(
        maximumVerificationBytes: 64 * 1_024 * 1_024,
        cancellationCheckInterval: 64,
        validated: ()
    )

    /// Upper bound on executable bytes hashed during one pinned verification.
    public let maximumVerificationBytes: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumVerificationBytes: Int = 64 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 64
    ) throws(ExternalToolExecutorError) {
        guard
            (1...Self.hardMaximumVerificationBytes).contains(maximumVerificationBytes),
            (1...Self.hardMaximumCancellationCheckInterval).contains(cancellationCheckInterval)
        else {
            throw ExternalToolExecutorError.invalidLimits
        }
        self.init(
            maximumVerificationBytes: maximumVerificationBytes,
            cancellationCheckInterval: cancellationCheckInterval,
            validated: ()
        )
    }

    private init(
        maximumVerificationBytes: Int,
        cancellationCheckInterval: Int,
        validated: Void
    ) {
        self.maximumVerificationBytes = maximumVerificationBytes
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum ExternalToolExecutorError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimits
    case cancelled
    case workLimitExceeded(maximum: Int)
    case staleExecutable(String)
    case verificationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "External-tool executor limits are invalid."
        case .cancelled:
            "External-tool executor operation was cancelled."
        case .workLimitExceeded(let maximum):
            "External-tool executable exceeds the \(maximum)-byte verification bound."
        case .staleExecutable(let path):
            "External-tool executable no longer matches its pinned identity: \(path)."
        case .verificationFailed(let path):
            "External-tool executable could not be verified from its pinned descriptor: \(path)."
        }
    }
}

public enum ExternalToolExecutorAmbientContract: String, Hashable, Sendable {
    case defaultDeny
}

public enum ExternalToolExecutorSpawningContract: String, Hashable, Sendable {
    case stubValidatesOnlyNeverSpawns
}

/// Fixed enforcement surface echoed on every receipt. Ambient capabilities stay denied
/// unless the plan's rule opted in; this stub itself never grants anything and never spawns.
public struct ExternalToolExecutorContract: Hashable, Sendable {
    public static let required = Self()

    public let launchPolicy =
        ExternalToolExecutableLaunchPolicy.privateImmutableCopyFromPinnedDescriptor
    public let libraryValidation = ExternalToolLibraryValidationPolicy.required
    public let dynamicLoad = ExternalToolDynamicLoadPolicy.defaultDeny
    public let standardInput = ExternalToolStandardInputPolicy.nullDevice
    public let inheritedDescriptors =
        ExternalToolInheritedDescriptorPolicy.closeAllExceptStandardStreams
    public let processGroup = ExternalToolProcessGroupPolicy.dedicatedProcessGroup
    public let termination = ExternalToolTerminationPolicy.terminateThenKillProcessGroup
    public let outputDrain = ExternalToolOutputDrainPolicy.concurrentlyUntilEndOfFile
    public let invocationMethod = ExternalToolInvocationMethod.directExecutable
    public let ambientCapabilities = ExternalToolExecutorAmbientContract.defaultDeny
    public let processSpawning = ExternalToolExecutorSpawningContract.stubValidatesOnlyNeverSpawns

    public init() {}
}

/// Launch-ready description. Construction performs no mutation; it echoes the exact
/// validated plan the executor checked. A receipt is not proof of launch.
public struct ExternalToolStubExecutorReceipt: Equatable, Sendable {
    public let ruleIdentifier: String
    public let capability: ExternalToolCapability
    public let invocationMethod: ExternalToolInvocationMethod
    public let executablePath: String
    public let executableSHA256: [UInt8]
    public let workingDirectoryPath: String
    public let argumentCount: Int
    public let environmentEntryCount: Int
    public let readScopeCount: Int
    public let writeScopeCount: Int
    public let timeoutSeconds: TimeInterval
    public let standardOutputLimitBytes: Int
    public let standardErrorLimitBytes: Int
    public let combinedOutputLimitBytes: Int
    public let isolationPolicy: ExternalToolIsolationPolicy
    public let executorContract = ExternalToolExecutorContract.required

    fileprivate init(plan: ExternalToolExecutionPlan) {
        ruleIdentifier = plan.ruleIdentifier
        capability = plan.capability
        invocationMethod = plan.invocationMethod
        executablePath = plan.executableURL.path
        executableSHA256 = plan.executablePin.identity.sha256
        workingDirectoryPath = plan.workingDirectoryURL.path
        argumentCount = plan.arguments.count
        environmentEntryCount = plan.environment.count
        readScopeCount = plan.readScopes.count
        writeScopeCount = plan.writeScopes.count
        timeoutSeconds = plan.timeoutSeconds
        standardOutputLimitBytes = plan.standardOutputLimitBytes
        standardErrorLimitBytes = plan.standardErrorLimitBytes
        combinedOutputLimitBytes = plan.combinedOutputLimitBytes
        isolationPolicy = plan.isolationPolicy
    }
}

/// Host-granted filesystem boundary. Every plan scope must sit inside these roots;
/// the default denies everything. Plan scopes remain mandatory sandbox inputs, not
/// access grants by themselves.
public struct ExternalToolExecutorSandboxAuthority: Equatable, Hashable, Sendable {
    public let readableRootPaths: Set<String>
    public let writableRootPaths: Set<String>

    public init(
        readableRootPaths: Set<String> = [],
        writableRootPaths: Set<String> = []
    ) {
        self.readableRootPaths = readableRootPaths
        self.writableRootPaths = writableRootPaths
    }

    public func authorizes(_ plan: ExternalToolExecutionPlan) -> Bool {
        for scope in plan.readScopes {
            guard readableRootPaths.contains(where: { externalToolPathIsWithin(scope.url.path, root: $0) }) else {
                return false
            }
        }
        for scope in plan.writeScopes {
            guard writableRootPaths.contains(where: { externalToolPathIsWithin(scope.url.path, root: $0) }) else {
                return false
            }
        }
        return readableRootPaths.contains(where: {
            externalToolPathIsWithin(plan.workingDirectoryURL.path, root: $0)
        })
    }
}

/// Caller-supplied liveness probes. The stub performs no scope I/O itself; owners with
/// revision leases or pinned descriptors answer whether plan inputs are current.
public struct ExternalToolExecutorRevalidation: Sendable {
    public let executableCurrent: @Sendable (ExternalToolExecutionPlan) async -> Bool
    public let scopesCurrent: @Sendable (ExternalToolExecutionPlan) async -> Bool

    public init(
        executableCurrent: @escaping @Sendable (ExternalToolExecutionPlan) async -> Bool,
        scopesCurrent: @escaping @Sendable (ExternalToolExecutionPlan) async -> Bool
    ) {
        self.executableCurrent = executableCurrent
        self.scopesCurrent = scopesCurrent
    }

    public static var assumeCurrent: ExternalToolExecutorRevalidation {
        ExternalToolExecutorRevalidation(
            executableCurrent: { _ in true },
            scopesCurrent: { _ in true }
        )
    }

    public static var stale: ExternalToolExecutorRevalidation {
        ExternalToolExecutorRevalidation(
            executableCurrent: { _ in false },
            scopesCurrent: { _ in false }
        )
    }
}

public enum ExternalToolExecutorNonLaunchReason: String, CaseIterable, Hashable, Sendable {
    case cancelled
    case rejected
    case staleExecutable
    case staleScopes
    case authorityDenied
    case verificationFailed
    case workLimitExceeded
    case unsupportedCapability
}

public enum ExternalToolExecutorOutcome: Equatable, Sendable {
    case ready(ExternalToolStubExecutorReceipt)
    case notLaunched(reason: ExternalToolExecutorNonLaunchReason, detail: String)
}

/// Plan-only stub executor: validates binding, authority, pinned identity, staleness,
/// and cancellation, then returns a pre-launch receipt without spawning a process.
public struct ExternalToolStubExecutor: Sendable {
    public let authority: ExternalToolExecutorSandboxAuthority
    public let revalidation: ExternalToolExecutorRevalidation
    public let limits: ExternalToolExecutorLimits

    public init(
        authority: ExternalToolExecutorSandboxAuthority = ExternalToolExecutorSandboxAuthority(),
        revalidation: ExternalToolExecutorRevalidation = .assumeCurrent,
        limits: ExternalToolExecutorLimits = .default
    ) {
        self.authority = authority
        self.revalidation = revalidation
        self.limits = limits
    }

    public func describe(_ plan: ExternalToolExecutionPlan) -> ExternalToolStubExecutorReceipt {
        ExternalToolStubExecutorReceipt(plan: plan)
    }

    /// Explicit fail-closed rejection for capabilities that can never launch.
    /// Plugin reload and in-process extensions are unsupported; executable capabilities
    /// require a validated direct-executable plan instead of this shortcut.
    public func unsupportedRejection(for capability: ExternalToolCapability) -> ExternalToolExecutorOutcome {
        switch capability {
        case .pluginReload:
            return .notLaunched(
                reason: .unsupportedCapability,
                detail: "Plugin reload is explicitly unsupported and can never produce a launch receipt."
            )
        case .inProcessExtensions:
            return .notLaunched(
                reason: .unsupportedCapability,
                detail: "In-process extensions are explicitly unsupported and can never produce a launch receipt."
            )
        case .unpacker, .prediffer, .editorScript, .copyingScript:
            return .notLaunched(
                reason: .rejected,
                detail: "Capability \(capability.rawValue) requires a validated direct-executable plan; "
                    + "plan with ExternalToolRequestPlanner, then execute the resulting plan."
            )
        }
    }

    public func execute(_ plan: ExternalToolExecutionPlan) async -> ExternalToolExecutorOutcome {
        if Task.isCancelled {
            return .notLaunched(reason: .cancelled, detail: "Cancelled before external-tool validation.")
        }
        switch plan.capability {
        case .pluginReload, .inProcessExtensions:
            return .notLaunched(
                reason: .unsupportedCapability,
                detail: "Capability \(plan.capability.rawValue) cannot use direct execution."
            )
        case .unpacker, .prediffer, .editorScript, .copyingScript:
            break
        }
        if let rejection = structuralRejection(plan) {
            return .notLaunched(reason: .rejected, detail: rejection)
        }
        guard authority.authorizes(plan) else {
            return .notLaunched(
                reason: .authorityDenied,
                detail: "Plan scopes exceed the host sandbox authority."
            )
        }
        do {
            try verifyPinnedExecutable(plan.executablePin, limits: limits)
        } catch {
            switch error {
            case .cancelled:
                return .notLaunched(reason: .cancelled, detail: "Cancelled during pinned verification.")
            case .staleExecutable(let path):
                return .notLaunched(
                    reason: .staleExecutable,
                    detail: "Executable no longer matches its pinned identity: \(path)."
                )
            case .verificationFailed(let path):
                return .notLaunched(
                    reason: .verificationFailed,
                    detail: "Executable could not be verified from its pinned descriptor: \(path)."
                )
            case .workLimitExceeded(let maximum):
                return .notLaunched(
                    reason: .workLimitExceeded,
                    detail: "Executable exceeds the \(maximum)-byte verification bound."
                )
            case .invalidLimits:
                return .notLaunched(
                    reason: .rejected,
                    detail: "Executor was constructed with invalid limits."
                )
            }
        }
        if Task.isCancelled {
            return .notLaunched(reason: .cancelled, detail: "Cancelled after pinned verification.")
        }
        guard await revalidation.executableCurrent(plan) else {
            return .notLaunched(
                reason: .staleExecutable,
                detail: "Executable inputs changed after pinned verification."
            )
        }
        if Task.isCancelled {
            return .notLaunched(reason: .cancelled, detail: "Cancelled after executable revalidation.")
        }
        guard await revalidation.scopesCurrent(plan) else {
            return .notLaunched(
                reason: .staleScopes,
                detail: "Filesystem scopes changed after pinned verification."
            )
        }
        if Task.isCancelled {
            return .notLaunched(reason: .cancelled, detail: "Cancelled after scope revalidation.")
        }
        // Never spawns: no process, filesystem, pasteboard, UI, or publication mutation.
        return .ready(describe(plan))
    }

    /// Cheap structural re-assertion only. Typed-argument grammar, scope subset proofs,
    /// and trust validation already happened in the planner; this rejects malformed or
    /// ambient-unsafe plans that must never reach verification.
    private func structuralRejection(_ plan: ExternalToolExecutionPlan) -> String? {
        for (index, argument) in plan.arguments.enumerated() {
            guard !argument.utf8.contains(0) else {
                return "Argument \(index) contains a null byte."
            }
        }
        for entry in plan.environment {
            guard !entry.key.utf8.contains(0), !entry.value.utf8.contains(0) else {
                return "Environment entry \(entry.key) contains a null byte."
            }
            guard !entry.key.uppercased().hasPrefix("DYLD_") else {
                return "Loader environment key \(entry.key) is permanently denied."
            }
        }
        let workingPath = plan.workingDirectoryURL.path
        guard plan.readScopes.contains(where: { externalToolScopeCovers(path: workingPath, scope: $0) }) else {
            return "Working directory is not covered by the plan read scopes."
        }
        let executablePath = plan.executableURL.path
        for scope in plan.writeScopes where externalToolScopeCovers(path: executablePath, scope: scope) {
            return "Executable is covered by a plan write scope."
        }
        return nil
    }

    /// Bounded re-verification from a duplicated pinned descriptor only. The path is
    /// never opened, so replacement or in-place mutation races fail closed as stale.
    private func verifyPinnedExecutable(
        _ pin: ExternalToolExecutablePin,
        limits: ExternalToolExecutorLimits
    ) throws(ExternalToolExecutorError) {
        let duplicate: Int32
        do {
            duplicate = try pin.duplicateReadOnlyFileDescriptor()
        } catch {
            throw ExternalToolExecutorError.verificationFailed(pin.sourceURL.path)
        }
        defer { Darwin.close(duplicate) }
        var opened = stat()
        guard Darwin.fstat(duplicate, &opened) == 0 else {
            throw ExternalToolExecutorError.verificationFailed(pin.sourceURL.path)
        }
        guard externalToolSameIdentity(opened, pin.identity) else {
            throw ExternalToolExecutorError.staleExecutable(pin.sourceURL.path)
        }
        guard opened.st_size >= 0 else {
            throw ExternalToolExecutorError.staleExecutable(pin.sourceURL.path)
        }
        guard opened.st_size <= off_t(limits.maximumVerificationBytes) else {
            throw ExternalToolExecutorError.workLimitExceeded(maximum: limits.maximumVerificationBytes)
        }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        var offset: off_t = 0
        var chunks = 0
        while offset < opened.st_size {
            let remaining = Int(opened.st_size - offset)
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.pread(duplicate, rawBuffer.baseAddress, min(remaining, rawBuffer.count), offset)
            }
            guard count != 0 else {
                throw ExternalToolExecutorError.staleExecutable(pin.sourceURL.path)
            }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw ExternalToolExecutorError.staleExecutable(pin.sourceURL.path)
            }
            hasher.update(data: Data(buffer[0..<count]))
            offset += off_t(count)
            chunks += 1
            if chunks.isMultiple(of: limits.cancellationCheckInterval), Task.isCancelled {
                throw ExternalToolExecutorError.cancelled
            }
        }
        var closing = stat()
        guard Darwin.fstat(duplicate, &closing) == 0,
            externalToolSameIdentity(closing, pin.identity),
            externalToolSameIdentity(opened, closing),
            Array(hasher.finalize()) == pin.identity.sha256
        else {
            throw ExternalToolExecutorError.staleExecutable(pin.sourceURL.path)
        }
    }
}

private func externalToolSameIdentity(
    _ information: stat,
    _ identity: ExternalToolExecutableIdentity
) -> Bool {
    UInt64(information.st_dev) == identity.device
        && UInt64(information.st_ino) == identity.inode
        && information.st_gen == identity.generation
        && information.st_size == identity.size
        && Int64(information.st_mtimespec.tv_sec) == identity.modificationTimeSeconds
        && Int64(information.st_mtimespec.tv_nsec) == identity.modificationTimeNanoseconds
        && Int64(information.st_ctimespec.tv_sec) == identity.changeTimeSeconds
        && Int64(information.st_ctimespec.tv_nsec) == identity.changeTimeNanoseconds
}

private func externalToolSameIdentity(_ lhs: stat, _ rhs: stat) -> Bool {
    lhs.st_dev == rhs.st_dev
        && lhs.st_ino == rhs.st_ino
        && lhs.st_gen == rhs.st_gen
        && lhs.st_size == rhs.st_size
        && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
        && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
        && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
        && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
}

private func externalToolScopeCovers(path: String, scope: ExternalToolPathScope) -> Bool {
    switch scope.kind {
    case .exactItem:
        return path == scope.url.path
    case .directoryTree:
        return externalToolPathIsWithin(path, root: scope.url.path)
    }
}

private func externalToolPathIsWithin(_ candidate: String, root: String) -> Bool {
    candidate == root || candidate.hasPrefix(root == "/" ? "/" : root + "/")
}
