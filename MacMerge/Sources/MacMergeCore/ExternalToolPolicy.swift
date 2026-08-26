import CryptoKit
import Darwin
import Foundation

/// Portable outcomes formerly supplied by WinMerge plugins and scripts.
public enum ExternalToolCapability: String, CaseIterable, Equatable, Hashable, Sendable {
    case unpacker
    case prediffer
    case editorScript
    case copyingScript
    case pluginReload
    case inProcessExtensions
}

public enum ExternalToolCapabilityStatus: String, Equatable, Hashable, Sendable {
    case supported
    case disabled
    case unsupported
}

public enum ExternalToolCapabilityReason: Equatable, Hashable, Sendable {
    case explicitExternalExecutableRuleConfigured
    case explicitExternalExecutableRuleRequired
    case pluginReloadUnsupported
    case inProcessExtensionsUnsupported
}

public struct ExternalToolCapabilityDecision: Equatable, Hashable, Sendable {
    public let capability: ExternalToolCapability
    public let status: ExternalToolCapabilityStatus
    public let reason: ExternalToolCapabilityReason

    public init(
        capability: ExternalToolCapability,
        status: ExternalToolCapabilityStatus,
        reason: ExternalToolCapabilityReason
    ) {
        self.capability = capability
        self.status = status
        self.reason = reason
    }

    public var isSupported: Bool { status == .supported }
}

/// One filesystem item or an existing directory and all of its descendants.
public struct ExternalToolPathScope: Equatable, Hashable, Sendable {
    public enum Kind: String, Equatable, Hashable, Sendable {
        case exactItem
        case directoryTree
    }

    public let url: URL
    public let kind: Kind

    public init(url: URL, kind: Kind) {
        self.url = url
        self.kind = kind
    }
}

/// Filesystem and content identity fixed when a rule enters a policy.
public struct ExternalToolExecutableIdentity: Equatable, Hashable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let generation: UInt32
    public let size: Int64
    public let modificationTimeSeconds: Int64
    public let modificationTimeNanoseconds: Int64
    public let changeTimeSeconds: Int64
    public let changeTimeNanoseconds: Int64
    public let sha256: [UInt8]

    public init(
        device: UInt64,
        inode: UInt64,
        generation: UInt32,
        size: Int64,
        modificationTimeSeconds: Int64,
        modificationTimeNanoseconds: Int64,
        changeTimeSeconds: Int64,
        changeTimeNanoseconds: Int64,
        sha256: [UInt8]
    ) {
        self.device = device
        self.inode = inode
        self.generation = generation
        self.size = size
        self.modificationTimeSeconds = modificationTimeSeconds
        self.modificationTimeNanoseconds = modificationTimeNanoseconds
        self.changeTimeSeconds = changeTimeSeconds
        self.changeTimeNanoseconds = changeTimeNanoseconds
        self.sha256 = sha256
    }
}

/// Open descriptor pin for bytes accepted by policy validation.
///
/// Executors must copy bytes from a duplicated descriptor into a private, non-writable executable,
/// verify `identity.sha256`, and launch that copy. Launching `sourceURL` is forbidden because path
/// revalidation does not close replacement or in-place mutation races.
public final class ExternalToolExecutablePin: @unchecked Sendable, Equatable {
    public let sourceURL: URL
    public let identity: ExternalToolExecutableIdentity

    private let fileDescriptor: Int32

    fileprivate init(
        sourceURL: URL,
        identity: ExternalToolExecutableIdentity,
        fileDescriptor: Int32
    ) {
        self.sourceURL = sourceURL
        self.identity = identity
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        Darwin.close(fileDescriptor)
    }

    public static func == (lhs: ExternalToolExecutablePin, rhs: ExternalToolExecutablePin) -> Bool {
        lhs.sourceURL == rhs.sourceURL && lhs.identity == rhs.identity
    }

    /// Returns a close-on-exec descriptor owned by the caller.
    public func duplicateReadOnlyFileDescriptor() throws -> Int32 {
        let duplicate = Darwin.fcntl(fileDescriptor, F_DUPFD_CLOEXEC, 3)
        guard duplicate >= 0 else {
            throw ExternalToolPolicyError.executablePinCannotBeDuplicated(errno: errno)
        }
        return duplicate
    }
}

/// Fixed-position argv grammar. An empty list permits no arguments.
public enum ExternalToolArgumentConstraint: Equatable, Hashable, Sendable {
    /// One policy-authored argv value.
    case exact(String)
    /// One value selected from a finite policy-authored set.
    case oneOf([String])
    /// Opaque data that cannot begin with an option or response-file sigil.
    case value
    /// Absolute path covered by a request read scope.
    case readPath
    /// Absolute path covered by a request write scope.
    case writePath
}

public enum ExternalToolAmbientAccess: String, Equatable, Hashable, Sendable {
    case denied
    case allowed
}

/// Sandbox requirements. Ambient capabilities are denied unless a rule opts in.
public struct ExternalToolIsolationPolicy: Equatable, Hashable, Sendable {
    public static let `default` = ExternalToolIsolationPolicy()

    public let network: ExternalToolAmbientAccess
    public let childProcesses: ExternalToolAmbientAccess
    public let interprocessCommunication: ExternalToolAmbientAccess

    public init(
        network: ExternalToolAmbientAccess = .denied,
        childProcesses: ExternalToolAmbientAccess = .denied,
        interprocessCommunication: ExternalToolAmbientAccess = .denied
    ) {
        self.network = network
        self.childProcesses = childProcesses
        self.interprocessCommunication = interprocessCommunication
    }
}

public enum ExternalToolStandardInputPolicy: String, Equatable, Hashable, Sendable {
    case nullDevice
}

public enum ExternalToolInheritedDescriptorPolicy: String, Equatable, Hashable, Sendable {
    case closeAllExceptStandardStreams
}

public enum ExternalToolExecutableLaunchPolicy: String, Equatable, Hashable, Sendable {
    case privateImmutableCopyFromPinnedDescriptor
}

public enum ExternalToolLibraryValidationPolicy: String, Equatable, Hashable, Sendable {
    case required
}

public enum ExternalToolDynamicLoadPolicy: String, Equatable, Hashable, Sendable {
    /// Deny every dynamic image unless the executor explicitly validates it under library validation.
    case defaultDeny
}

public enum ExternalToolProcessGroupPolicy: String, Equatable, Hashable, Sendable {
    case dedicatedProcessGroup
}

public enum ExternalToolTerminationPolicy: String, Equatable, Hashable, Sendable {
    case terminateThenKillProcessGroup
}

public enum ExternalToolOutputDrainPolicy: String, Equatable, Hashable, Sendable {
    case concurrentlyUntilEndOfFile
}

/// Hard resource bounds for one direct executable invocation.
public struct ExternalToolInvocationLimits: Equatable, Hashable, Sendable {
    public static let hardMaximumArgumentCount = 4_096
    public static let hardMaximumArgumentUTF8Bytes = 256 * 1_024
    public static let hardMaximumTotalArgumentUTF8Bytes = 4 * 1_024 * 1_024
    public static let hardMaximumEnvironmentEntryCount = 1_024
    public static let hardMaximumEnvironmentValueUTF8Bytes = 1 * 1_024 * 1_024
    public static let hardMaximumTotalEnvironmentUTF8Bytes = 4 * 1_024 * 1_024
    public static let hardMaximumScopeCount = 1_024
    public static let hardMaximumPathUTF8Bytes = 16 * 1_024
    public static let hardMaximumTotalPathUTF8Bytes = 16 * 1_024 * 1_024
    public static let hardMaximumTimeoutSeconds: TimeInterval = 3_600
    public static let hardMaximumOutputBytes = 256 * 1_024 * 1_024

    public static let `default`: ExternalToolInvocationLimits = {
        try! ExternalToolInvocationLimits()
    }()

    public let maximumArgumentCount: Int
    public let maximumArgumentUTF8Bytes: Int
    public let maximumTotalArgumentUTF8Bytes: Int
    public let maximumEnvironmentEntryCount: Int
    public let maximumEnvironmentKeyUTF8Bytes: Int
    public let maximumEnvironmentValueUTF8Bytes: Int
    public let maximumTotalEnvironmentUTF8Bytes: Int
    public let maximumScopeCount: Int
    public let maximumPathUTF8Bytes: Int
    public let maximumTotalPathUTF8Bytes: Int
    public let timeoutSeconds: TimeInterval
    public let standardOutputLimitBytes: Int
    public let standardErrorLimitBytes: Int
    public let combinedOutputLimitBytes: Int

    public init(
        maximumArgumentCount: Int = 256,
        maximumArgumentUTF8Bytes: Int = 64 * 1_024,
        maximumTotalArgumentUTF8Bytes: Int = 1 * 1_024 * 1_024,
        maximumEnvironmentEntryCount: Int = 128,
        maximumEnvironmentKeyUTF8Bytes: Int = 256,
        maximumEnvironmentValueUTF8Bytes: Int = 64 * 1_024,
        maximumTotalEnvironmentUTF8Bytes: Int = 1 * 1_024 * 1_024,
        maximumScopeCount: Int = 128,
        maximumPathUTF8Bytes: Int = 4_096,
        maximumTotalPathUTF8Bytes: Int = 1 * 1_024 * 1_024,
        timeoutSeconds: TimeInterval = 60,
        standardOutputLimitBytes: Int = 8 * 1_024 * 1_024,
        standardErrorLimitBytes: Int = 8 * 1_024 * 1_024,
        combinedOutputLimitBytes: Int = 16 * 1_024 * 1_024
    ) throws {
        try Self.requireLimit(
            maximumArgumentCount,
            named: "maximumArgumentCount",
            range: 0...Self.hardMaximumArgumentCount
        )
        try Self.requireLimit(
            maximumArgumentUTF8Bytes,
            named: "maximumArgumentUTF8Bytes",
            range: 1...Self.hardMaximumArgumentUTF8Bytes
        )
        try Self.requireLimit(
            maximumTotalArgumentUTF8Bytes,
            named: "maximumTotalArgumentUTF8Bytes",
            range: maximumArgumentUTF8Bytes...Self.hardMaximumTotalArgumentUTF8Bytes
        )
        try Self.requireLimit(
            maximumEnvironmentEntryCount,
            named: "maximumEnvironmentEntryCount",
            range: 0...Self.hardMaximumEnvironmentEntryCount
        )
        try Self.requireLimit(
            maximumEnvironmentKeyUTF8Bytes,
            named: "maximumEnvironmentKeyUTF8Bytes",
            range: 1...256
        )
        try Self.requireLimit(
            maximumEnvironmentValueUTF8Bytes,
            named: "maximumEnvironmentValueUTF8Bytes",
            range: 0...Self.hardMaximumEnvironmentValueUTF8Bytes
        )
        try Self.requireLimit(
            maximumTotalEnvironmentUTF8Bytes,
            named: "maximumTotalEnvironmentUTF8Bytes",
            range: 0...Self.hardMaximumTotalEnvironmentUTF8Bytes
        )
        try Self.requireLimit(
            maximumScopeCount,
            named: "maximumScopeCount",
            range: 1...Self.hardMaximumScopeCount
        )
        try Self.requireLimit(
            maximumPathUTF8Bytes,
            named: "maximumPathUTF8Bytes",
            range: 1...Self.hardMaximumPathUTF8Bytes
        )
        try Self.requireLimit(
            maximumTotalPathUTF8Bytes,
            named: "maximumTotalPathUTF8Bytes",
            range: maximumPathUTF8Bytes...Self.hardMaximumTotalPathUTF8Bytes
        )
        guard timeoutSeconds.isFinite,
            timeoutSeconds > 0,
            timeoutSeconds <= Self.hardMaximumTimeoutSeconds
        else {
            throw ExternalToolPolicyError.invalidLimit(
                name: "timeoutSeconds",
                value: String(describing: timeoutSeconds)
            )
        }
        try Self.requireLimit(
            standardOutputLimitBytes,
            named: "standardOutputLimitBytes",
            range: 0...Self.hardMaximumOutputBytes
        )
        try Self.requireLimit(
            standardErrorLimitBytes,
            named: "standardErrorLimitBytes",
            range: 0...Self.hardMaximumOutputBytes
        )
        try Self.requireLimit(
            combinedOutputLimitBytes,
            named: "combinedOutputLimitBytes",
            range: max(standardOutputLimitBytes, standardErrorLimitBytes)...Self.hardMaximumOutputBytes
        )

        self.maximumArgumentCount = maximumArgumentCount
        self.maximumArgumentUTF8Bytes = maximumArgumentUTF8Bytes
        self.maximumTotalArgumentUTF8Bytes = maximumTotalArgumentUTF8Bytes
        self.maximumEnvironmentEntryCount = maximumEnvironmentEntryCount
        self.maximumEnvironmentKeyUTF8Bytes = maximumEnvironmentKeyUTF8Bytes
        self.maximumEnvironmentValueUTF8Bytes = maximumEnvironmentValueUTF8Bytes
        self.maximumTotalEnvironmentUTF8Bytes = maximumTotalEnvironmentUTF8Bytes
        self.maximumScopeCount = maximumScopeCount
        self.maximumPathUTF8Bytes = maximumPathUTF8Bytes
        self.maximumTotalPathUTF8Bytes = maximumTotalPathUTF8Bytes
        self.timeoutSeconds = timeoutSeconds
        self.standardOutputLimitBytes = standardOutputLimitBytes
        self.standardErrorLimitBytes = standardErrorLimitBytes
        self.combinedOutputLimitBytes = combinedOutputLimitBytes
    }

    private static func requireLimit(
        _ value: Int,
        named name: String,
        range: ClosedRange<Int>
    ) throws {
        guard range.contains(value) else {
            throw ExternalToolPolicyError.invalidLimit(name: name, value: String(value))
        }
    }
}

/// Explicit opt-in for one named, directly launched executable.
///
/// Rules never search `PATH`, inherit the caller's environment, or accept a shell command string.
public struct ExternalToolExecutableRule: Equatable, Hashable, Sendable {
    public static let maximumRuleCount = 64

    public let identifier: String
    public let capability: ExternalToolCapability
    public let executableURL: URL
    /// SHA-256 of reviewed executable bytes, supplied by trusted policy configuration.
    /// Deriving this value from a request-selected file does not constitute approval.
    public let approvedExecutableSHA256: [UInt8]
    public let permittedWorkingDirectories: [ExternalToolPathScope]
    public let permittedReadScopes: [ExternalToolPathScope]
    public let permittedWriteScopes: [ExternalToolPathScope]
    public let allowedEnvironmentKeys: [String]
    public let argumentConstraints: [ExternalToolArgumentConstraint]
    public let isolationPolicy: ExternalToolIsolationPolicy
    public let limits: ExternalToolInvocationLimits

    public init(
        identifier: String,
        capability: ExternalToolCapability,
        executableURL: URL,
        approvedExecutableSHA256: [UInt8],
        permittedWorkingDirectories: [ExternalToolPathScope],
        permittedReadScopes: [ExternalToolPathScope],
        permittedWriteScopes: [ExternalToolPathScope] = [],
        allowedEnvironmentKeys: [String] = [],
        argumentConstraints: [ExternalToolArgumentConstraint] = [],
        isolationPolicy: ExternalToolIsolationPolicy = .default,
        limits: ExternalToolInvocationLimits = .default
    ) {
        self.identifier = identifier
        self.capability = capability
        self.executableURL = executableURL
        self.approvedExecutableSHA256 = approvedExecutableSHA256
        self.permittedWorkingDirectories = permittedWorkingDirectories
        self.permittedReadScopes = permittedReadScopes
        self.permittedWriteScopes = permittedWriteScopes
        self.allowedEnvironmentKeys = allowedEnvironmentKeys
        self.argumentConstraints = argumentConstraints
        self.isolationPolicy = isolationPolicy
        self.limits = limits
    }
}

/// Per-invocation data. Arguments are already separated and remain opaque strings.
public struct ExternalToolRequest: Equatable, Sendable {
    public let ruleIdentifier: String
    public let capability: ExternalToolCapability
    public let workingDirectoryURL: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let readScopes: [ExternalToolPathScope]
    public let writeScopes: [ExternalToolPathScope]

    public init(
        ruleIdentifier: String,
        capability: ExternalToolCapability,
        workingDirectoryURL: URL,
        arguments: [String] = [],
        environment: [String: String] = [:],
        readScopes: [ExternalToolPathScope],
        writeScopes: [ExternalToolPathScope] = []
    ) {
        self.ruleIdentifier = ruleIdentifier
        self.capability = capability
        self.workingDirectoryURL = workingDirectoryURL
        self.arguments = arguments
        self.environment = environment
        self.readScopes = readScopes
        self.writeScopes = writeScopes
    }
}

public struct ExternalToolEnvironmentEntry: Equatable, Hashable, Sendable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public enum ExternalToolInvocationMethod: String, Equatable, Hashable, Sendable {
    case directExecutable
}

/// Validated inputs for an executor; this type does not launch a process.
///
/// An executor must pass `arguments` as distinct argv entries, set an explicit environment from
/// `environment`, materialize the pinned executable as required by `executableLaunchPolicy`, and
/// enforce every isolation, library-validation, dynamic-load, descriptor, process-group, timeout,
/// termination, and drain property. Path scopes are mandatory sandbox inputs, not filesystem access
/// controls by themselves.
public struct ExternalToolExecutionPlan: Equatable, Sendable {
    public let ruleIdentifier: String
    public let capability: ExternalToolCapability
    public let invocationMethod: ExternalToolInvocationMethod
    public let executableURL: URL
    public let executablePin: ExternalToolExecutablePin
    public let executableLaunchPolicy: ExternalToolExecutableLaunchPolicy
    public let libraryValidationPolicy: ExternalToolLibraryValidationPolicy
    public let dynamicLoadPolicy: ExternalToolDynamicLoadPolicy
    public let workingDirectoryURL: URL
    public let arguments: [String]
    public let environment: [ExternalToolEnvironmentEntry]
    public let readScopes: [ExternalToolPathScope]
    public let writeScopes: [ExternalToolPathScope]
    public let timeoutSeconds: TimeInterval
    public let standardOutputLimitBytes: Int
    public let standardErrorLimitBytes: Int
    public let combinedOutputLimitBytes: Int
    public let isolationPolicy: ExternalToolIsolationPolicy
    public let standardInputPolicy: ExternalToolStandardInputPolicy
    public let inheritedDescriptorPolicy: ExternalToolInheritedDescriptorPolicy
    public let processGroupPolicy: ExternalToolProcessGroupPolicy
    public let terminationPolicy: ExternalToolTerminationPolicy
    public let outputDrainPolicy: ExternalToolOutputDrainPolicy

    public var environmentDictionary: [String: String] {
        Dictionary(uniqueKeysWithValues: environment.map { ($0.key, $0.value) })
    }

    fileprivate init(
        ruleIdentifier: String,
        capability: ExternalToolCapability,
        invocationMethod: ExternalToolInvocationMethod = .directExecutable,
        executableURL: URL,
        executablePin: ExternalToolExecutablePin,
        workingDirectoryURL: URL,
        arguments: [String],
        environment: [ExternalToolEnvironmentEntry],
        readScopes: [ExternalToolPathScope],
        writeScopes: [ExternalToolPathScope],
        timeoutSeconds: TimeInterval,
        standardOutputLimitBytes: Int,
        standardErrorLimitBytes: Int,
        combinedOutputLimitBytes: Int,
        isolationPolicy: ExternalToolIsolationPolicy
    ) {
        self.ruleIdentifier = ruleIdentifier
        self.capability = capability
        self.invocationMethod = invocationMethod
        self.executableURL = executableURL
        self.executablePin = executablePin
        executableLaunchPolicy = .privateImmutableCopyFromPinnedDescriptor
        libraryValidationPolicy = .required
        dynamicLoadPolicy = .defaultDeny
        self.workingDirectoryURL = workingDirectoryURL
        self.arguments = arguments
        self.environment = environment
        self.readScopes = readScopes
        self.writeScopes = writeScopes
        self.timeoutSeconds = timeoutSeconds
        self.standardOutputLimitBytes = standardOutputLimitBytes
        self.standardErrorLimitBytes = standardErrorLimitBytes
        self.combinedOutputLimitBytes = combinedOutputLimitBytes
        self.isolationPolicy = isolationPolicy
        standardInputPolicy = .nullDevice
        inheritedDescriptorPolicy = .closeAllExceptStandardStreams
        processGroupPolicy = .dedicatedProcessGroup
        terminationPolicy = .terminateThenKillProcessGroup
        outputDrainPolicy = .concurrentlyUntilEndOfFile
    }
}

public enum ExternalToolPathPurpose: String, Equatable, Hashable, Sendable {
    case executable
    case workingDirectory
    case permittedWorkingDirectory
    case readScope
    case writeScope
}

public enum ExternalToolPolicyError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimit(name: String, value: String)
    case invalidRuleIdentifier(String)
    case tooManyRules(maximum: Int)
    case duplicateRuleIdentifier(String)
    case capabilityCannotUseExternalExecutable(ExternalToolCapability)
    case unsupportedCapability(ExternalToolCapability, reason: ExternalToolCapabilityReason)
    case externalExecutableRuleRequired(ExternalToolCapability)
    case ruleNotFound(String)
    case ruleCapabilityMismatch(rule: String, requested: ExternalToolCapability, configured: ExternalToolCapability)
    case invalidAbsoluteFileURL(purpose: ExternalToolPathPurpose, value: String)
    case pathTooLarge(purpose: ExternalToolPathPurpose, maximumUTF8Bytes: Int)
    case totalPathsTooLarge(maximumUTF8Bytes: Int)
    case pathCannotBeResolved(purpose: ExternalToolPathPurpose, path: String)
    case executableNotRegularFile(String)
    case executableNotExecutable(String)
    case executableScriptNotAllowed(String)
    case executableHasMultipleLinks(String)
    case invalidApprovedExecutableDigest(String)
    case executableDoesNotMatchApprovedIdentity(String)
    case executableUntrustedOwner(path: String, owner: UInt32)
    case executableUnsafeMode(String)
    case executableUnsafeACL(String)
    case executableUntrustedAncestor(String)
    case executableIdentityChanged(String)
    case insufficientFileDescriptorCapacity(required: Int)
    case executablePinCannotBeDuplicated(errno: Int32)
    case workingDirectoryNotDirectory(String)
    case workingDirectoryNotSearchable(String)
    case scopeNotFileOrDirectory(String)
    case directoryTreeScopeNotDirectory(String)
    case rootDirectoryTreeNotAllowed
    case noPermittedWorkingDirectory(String)
    case tooManyScopes(maximum: Int)
    case workingDirectoryScopeNotReadable(String)
    case executableCoveredByWriteScope(String)
    case workingDirectoryNotPermitted(String)
    case workingDirectoryNotDeclaredReadable(String)
    case readScopeNotPermitted(String)
    case writeScopeNotPermitted(String)
    case tooManyArguments(maximum: Int)
    case argumentContainsNull(index: Int)
    case argumentTooLarge(index: Int, maximumUTF8Bytes: Int)
    case totalArgumentsTooLarge(maximumUTF8Bytes: Int)
    case argumentConstraintCountMismatch(expected: Int, actual: Int)
    case argumentConstraintViolation(index: Int)
    case invalidArgumentConstraint(index: Int)
    case tooManyEnvironmentEntries(maximum: Int)
    case invalidEnvironmentKey(String)
    case environmentKeyNotAllowed(String)
    case environmentKeyPermanentlyDenied(String)
    case environmentKeyTooLarge(String, maximumUTF8Bytes: Int)
    case environmentValueContainsNull(key: String)
    case environmentValueTooLarge(key: String, maximumUTF8Bytes: Int)
    case totalEnvironmentTooLarge(maximumUTF8Bytes: Int)
    case processInputTooLarge(maximumBytes: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidLimit(let name, let value):
            "Invalid external-tool limit \(name): \(value)."
        case .invalidRuleIdentifier(let identifier):
            "Invalid external-tool rule identifier: \(identifier)."
        case .tooManyRules(let maximum):
            "External-tool policy exceeds the \(maximum)-rule limit."
        case .duplicateRuleIdentifier(let identifier):
            "External-tool rule identifier is duplicated: \(identifier)."
        case .capabilityCannotUseExternalExecutable(let capability):
            "External executable rules cannot enable \(capability.rawValue)."
        case .unsupportedCapability(let capability, _):
            "External-tool capability is unsupported: \(capability.rawValue)."
        case .externalExecutableRuleRequired(let capability):
            "External-tool capability requires an explicit executable rule: \(capability.rawValue)."
        case .ruleNotFound(let identifier):
            "External-tool rule was not found: \(identifier)."
        case .ruleCapabilityMismatch(let rule, let requested, let configured):
            "External-tool rule \(rule) is configured for \(configured.rawValue), not \(requested.rawValue)."
        case .invalidAbsoluteFileURL(let purpose, let value):
            "External-tool \(purpose.rawValue) must be an absolute local file URL: \(value)."
        case .pathTooLarge(let purpose, let maximumUTF8Bytes):
            "External-tool \(purpose.rawValue) path exceeds the \(maximumUTF8Bytes)-byte limit."
        case .totalPathsTooLarge(let maximumUTF8Bytes):
            "External-tool paths exceed the \(maximumUTF8Bytes)-byte aggregate limit."
        case .pathCannotBeResolved(let purpose, let path):
            "External-tool \(purpose.rawValue) path cannot be resolved: \(path)."
        case .executableNotRegularFile(let path):
            "External-tool executable is not a regular file: \(path)."
        case .executableNotExecutable(let path):
            "External-tool file is not executable: \(path)."
        case .executableScriptNotAllowed(let path):
            "External-tool executable cannot be a shebang script: \(path)."
        case .executableHasMultipleLinks(let path):
            "External-tool executable has multiple filesystem links and cannot be combined with write scopes: \(path)."
        case .invalidApprovedExecutableDigest(let path):
            "External-tool rule must approve exactly one SHA-256 executable digest: \(path)."
        case .executableDoesNotMatchApprovedIdentity(let path):
            "External-tool executable does not match the path and digest approved by its rule: \(path)."
        case .executableUntrustedOwner(let path, let owner):
            "External-tool executable has untrusted owner \(owner): \(path)."
        case .executableUnsafeMode(let path):
            "External-tool executable has unsafe ownership or mode bits: \(path)."
        case .executableUnsafeACL(let path):
            "External-tool executable or ancestor has a mutating allow ACL: \(path)."
        case .executableUntrustedAncestor(let path):
            "External-tool executable has an untrusted writable or unowned ancestor: \(path)."
        case .executableIdentityChanged(let path):
            "External-tool executable no longer matches its pinned identity: \(path)."
        case .insufficientFileDescriptorCapacity(let required):
            "External-tool policy cannot reserve \(required) executable descriptors."
        case .executablePinCannotBeDuplicated(let errorNumber):
            "External-tool executable pin cannot be duplicated (errno \(errorNumber))."
        case .workingDirectoryNotDirectory(let path):
            "External-tool working directory is not a directory: \(path)."
        case .workingDirectoryNotSearchable(let path):
            "External-tool working directory is not searchable: \(path)."
        case .scopeNotFileOrDirectory(let path):
            "External-tool scope is not a regular file or directory: \(path)."
        case .directoryTreeScopeNotDirectory(let path):
            "External-tool directory-tree scope is not a directory: \(path)."
        case .rootDirectoryTreeNotAllowed:
            "An external-tool directory-tree scope cannot cover the filesystem root."
        case .noPermittedWorkingDirectory(let rule):
            "External-tool rule has no permitted working directory: \(rule)."
        case .tooManyScopes(let maximum):
            "External-tool request or rule exceeds the \(maximum)-scope limit."
        case .workingDirectoryScopeNotReadable(let path):
            "Permitted external-tool working directory is outside declared read scopes: \(path)."
        case .executableCoveredByWriteScope(let path):
            "External-tool executable is covered by a permitted write scope: \(path)."
        case .workingDirectoryNotPermitted(let path):
            "External-tool working directory is not permitted: \(path)."
        case .workingDirectoryNotDeclaredReadable(let path):
            "External-tool working directory is not covered by the request's read scopes: \(path)."
        case .readScopeNotPermitted(let path):
            "External-tool read scope is not permitted: \(path)."
        case .writeScopeNotPermitted(let path):
            "External-tool write scope is not permitted: \(path)."
        case .tooManyArguments(let maximum):
            "External-tool request exceeds the \(maximum)-argument limit."
        case .argumentContainsNull(let index):
            "External-tool argument \(index) contains a null byte."
        case .argumentTooLarge(let index, let maximumUTF8Bytes):
            "External-tool argument \(index) exceeds the \(maximumUTF8Bytes)-byte limit."
        case .totalArgumentsTooLarge(let maximumUTF8Bytes):
            "External-tool arguments exceed the \(maximumUTF8Bytes)-byte total limit."
        case .argumentConstraintCountMismatch(let expected, let actual):
            "External-tool request has \(actual) arguments; rule requires exactly \(expected)."
        case .argumentConstraintViolation(let index):
            "External-tool argument \(index) violates its rule constraint."
        case .invalidArgumentConstraint(let index):
            "External-tool rule has an invalid argument constraint at index \(index)."
        case .tooManyEnvironmentEntries(let maximum):
            "External-tool request exceeds the \(maximum)-environment-entry limit."
        case .invalidEnvironmentKey(let key):
            "Invalid external-tool environment key: \(key)."
        case .environmentKeyNotAllowed(let key):
            "External-tool environment key is not allowed by the rule: \(key)."
        case .environmentKeyPermanentlyDenied(let key):
            "External-tool loader environment key is permanently denied: \(key)."
        case .environmentKeyTooLarge(let key, let maximumUTF8Bytes):
            "External-tool environment key \(key) exceeds the \(maximumUTF8Bytes)-byte limit."
        case .environmentValueContainsNull(let key):
            "External-tool environment value contains a null byte: \(key)."
        case .environmentValueTooLarge(let key, let maximumUTF8Bytes):
            "External-tool environment value \(key) exceeds the \(maximumUTF8Bytes)-byte limit."
        case .totalEnvironmentTooLarge(let maximumUTF8Bytes):
            "External-tool environment exceeds the \(maximumUTF8Bytes)-byte total limit."
        case .processInputTooLarge(let maximumBytes):
            "External-tool arguments and environment exceed the \(maximumBytes)-byte process-input limit."
        }
    }
}

/// UI-independent policy. Default policy enables no executable and explicitly rejects plugin
/// reload and in-process extension hosting.
public struct ExternalToolPolicy: Equatable, Sendable {
    public static let `default` = ExternalToolPolicy()

    public let externalExecutableRules: [ExternalToolExecutableRule]
    fileprivate let executablePins: [String: ExternalToolExecutablePin]

    public init() {
        externalExecutableRules = []
        executablePins = [:]
    }

    public init(externalExecutableRules: [ExternalToolExecutableRule]) throws {
        let validated = try ExternalToolRequestPlanner.validateRules(externalExecutableRules)
        self.externalExecutableRules = validated.rules
        executablePins = validated.pins
    }

    public func decision(for capability: ExternalToolCapability) -> ExternalToolCapabilityDecision {
        switch capability {
        case .pluginReload:
            return ExternalToolCapabilityDecision(
                capability: capability,
                status: .unsupported,
                reason: .pluginReloadUnsupported
            )
        case .inProcessExtensions:
            return ExternalToolCapabilityDecision(
                capability: capability,
                status: .unsupported,
                reason: .inProcessExtensionsUnsupported
            )
        case .unpacker, .prediffer, .editorScript, .copyingScript:
            if externalExecutableRules.contains(where: { $0.capability == capability }) {
                return ExternalToolCapabilityDecision(
                    capability: capability,
                    status: .supported,
                    reason: .explicitExternalExecutableRuleConfigured
                )
            }
            return ExternalToolCapabilityDecision(
                capability: capability,
                status: .disabled,
                reason: .explicitExternalExecutableRuleRequired
            )
        }
    }

    public var decisions: [ExternalToolCapabilityDecision] {
        ExternalToolCapability.allCases.map(decision(for:))
    }

    fileprivate func rule(identifier: String) -> ExternalToolExecutableRule? {
        externalExecutableRules.first { $0.identifier == identifier }
    }

    fileprivate func executablePin(identifier: String) -> ExternalToolExecutablePin? {
        executablePins[identifier]
    }

    public static func == (lhs: ExternalToolPolicy, rhs: ExternalToolPolicy) -> Bool {
        lhs.externalExecutableRules == rhs.externalExecutableRules && lhs.executablePins == rhs.executablePins
    }
}

/// Validates requests and produces direct-execution plans without launching an executable.
public struct ExternalToolRequestPlanner: Sendable {
    public let policy: ExternalToolPolicy

    public init(policy: ExternalToolPolicy = .default) {
        self.policy = policy
    }

    public func plan(_ request: ExternalToolRequest) throws -> ExternalToolExecutionPlan {
        let decision = policy.decision(for: request.capability)
        switch decision.status {
        case .unsupported:
            throw ExternalToolPolicyError.unsupportedCapability(
                request.capability,
                reason: decision.reason
            )
        case .disabled:
            throw ExternalToolPolicyError.externalExecutableRuleRequired(request.capability)
        case .supported:
            break
        }

        guard let configuredRule = policy.rule(identifier: request.ruleIdentifier) else {
            throw ExternalToolPolicyError.ruleNotFound(request.ruleIdentifier)
        }
        guard configuredRule.capability == request.capability else {
            throw ExternalToolPolicyError.ruleCapabilityMismatch(
                rule: configuredRule.identifier,
                requested: request.capability,
                configured: configuredRule.capability
            )
        }

        guard let executablePin = policy.executablePin(identifier: configuredRule.identifier) else {
            throw ExternalToolPolicyError.executableIdentityChanged(configuredRule.executableURL.path)
        }
        try Self.validatePinnedExecutable(executablePin)
        let rule = configuredRule
        let limits = rule.limits
        try Self.prefilterPath(
            request.workingDirectoryURL,
            purpose: .workingDirectory,
            maximumPathUTF8Bytes: limits.maximumPathUTF8Bytes
        )
        let lexicalWorkingScope = ExternalToolPathScope(
            url: request.workingDirectoryURL.standardizedFileURL,
            kind: .exactItem
        )
        guard rule.permittedWorkingDirectories.contains(where: { Self.isSubset(lexicalWorkingScope, of: $0) }) else {
            throw ExternalToolPolicyError.workingDirectoryNotPermitted(request.workingDirectoryURL.path)
        }
        guard request.readScopes.count <= limits.maximumScopeCount,
            request.writeScopes.count <= limits.maximumScopeCount - request.readScopes.count
        else {
            throw ExternalToolPolicyError.tooManyScopes(maximum: limits.maximumScopeCount)
        }
        try Self.prefilterScopes(
            request.readScopes,
            against: rule.permittedReadScopes,
            purpose: .readScope,
            limits: limits
        )
        try Self.prefilterScopes(
            request.writeScopes,
            against: rule.permittedWriteScopes,
            purpose: .writeScope,
            limits: limits
        )
        try Self.validateAggregatePathBytes(
            urls: [rule.executableURL, request.workingDirectoryURL]
                + request.readScopes.map(\.url)
                + request.writeScopes.map(\.url),
            limits: limits
        )
        let workingDirectory = try Self.canonicalItem(
            request.workingDirectoryURL,
            purpose: .workingDirectory,
            maximumPathUTF8Bytes: limits.maximumPathUTF8Bytes
        )
        guard workingDirectory.kind == .directory else {
            throw ExternalToolPolicyError.workingDirectoryNotDirectory(workingDirectory.url.path)
        }
        guard Self.canSearch(workingDirectory.url.path) else {
            throw ExternalToolPolicyError.workingDirectoryNotSearchable(workingDirectory.url.path)
        }
        let workingScope = ExternalToolPathScope(url: workingDirectory.url, kind: .exactItem)
        guard rule.permittedWorkingDirectories.contains(where: { Self.isSubset(workingScope, of: $0) }) else {
            throw ExternalToolPolicyError.workingDirectoryNotPermitted(workingDirectory.url.path)
        }

        try Self.validateArguments(
            request.arguments,
            constraints: rule.argumentConstraints,
            readScopes: request.readScopes,
            writeScopes: request.writeScopes,
            limits: limits
        )
        let environment = try Self.validateEnvironment(
            request.environment,
            allowedKeys: rule.allowedEnvironmentKeys,
            limits: limits
        )
        try Self.validateProcessInput(
            executablePath: rule.executableURL.path,
            arguments: request.arguments,
            environment: environment
        )
        let readScopes = try Self.canonicalScopes(
            request.readScopes,
            purpose: .readScope,
            limits: limits
        )
        let writeScopes = try Self.canonicalScopes(
            request.writeScopes,
            purpose: .writeScope,
            limits: limits
        )
        try Self.validateAggregatePathBytes(
            urls: [rule.executableURL, workingDirectory.url]
                + readScopes.map(\.url)
                + writeScopes.map(\.url),
            limits: limits
        )

        for scope in readScopes where !rule.permittedReadScopes.contains(where: { Self.isSubset(scope, of: $0) }) {
            throw ExternalToolPolicyError.readScopeNotPermitted(scope.url.path)
        }
        for scope in writeScopes where !rule.permittedWriteScopes.contains(where: { Self.isSubset(scope, of: $0) }) {
            throw ExternalToolPolicyError.writeScopeNotPermitted(scope.url.path)
        }
        guard readScopes.contains(where: { Self.isSubset(workingScope, of: $0) }) else {
            throw ExternalToolPolicyError.workingDirectoryNotDeclaredReadable(workingDirectory.url.path)
        }

        return ExternalToolExecutionPlan(
            ruleIdentifier: rule.identifier,
            capability: rule.capability,
            executableURL: rule.executableURL,
            executablePin: executablePin,
            workingDirectoryURL: workingDirectory.url,
            arguments: request.arguments,
            environment: environment,
            readScopes: readScopes,
            writeScopes: writeScopes,
            timeoutSeconds: limits.timeoutSeconds,
            standardOutputLimitBytes: limits.standardOutputLimitBytes,
            standardErrorLimitBytes: limits.standardErrorLimitBytes,
            combinedOutputLimitBytes: limits.combinedOutputLimitBytes,
            isolationPolicy: rule.isolationPolicy
        )
    }
}

extension ExternalToolRequestPlanner {
    fileprivate enum ItemKind {
        case regularFile
        case directory
    }

    fileprivate struct CanonicalItem {
        let url: URL
        let kind: ItemKind
        let linkCount: nlink_t
        let information: stat
    }

    fileprivate struct ValidatedRules {
        let rules: [ExternalToolExecutableRule]
        let pins: [String: ExternalToolExecutablePin]
    }

    fileprivate static func validateRules(
        _ rules: [ExternalToolExecutableRule]
    ) throws -> ValidatedRules {
        guard rules.count <= ExternalToolExecutableRule.maximumRuleCount else {
            throw ExternalToolPolicyError.tooManyRules(
                maximum: ExternalToolExecutableRule.maximumRuleCount
            )
        }
        try preflightRuleDescriptors(count: rules.count)
        for rule in rules {
            try validateRuleIdentifier(rule.identifier)
        }
        let sortedRules = rules.sorted {
            if $0.identifier != $1.identifier { return $0.identifier < $1.identifier }
            return $0.capability.rawValue < $1.capability.rawValue
        }
        for index in sortedRules.indices {
            if index > sortedRules.startIndex,
                sortedRules[index - 1].identifier == sortedRules[index].identifier
            {
                throw ExternalToolPolicyError.duplicateRuleIdentifier(sortedRules[index].identifier)
            }
        }
        var validatedRules: [ExternalToolExecutableRule] = []
        var pins: [String: ExternalToolExecutablePin] = [:]
        validatedRules.reserveCapacity(sortedRules.count)
        pins.reserveCapacity(sortedRules.count)
        for rule in sortedRules {
            let validated = try validateRule(rule)
            validatedRules.append(validated.rule)
            pins[validated.rule.identifier] = validated.pin
        }
        return ValidatedRules(rules: validatedRules, pins: pins)
    }

    fileprivate static func validateRule(
        _ rule: ExternalToolExecutableRule
    ) throws -> (rule: ExternalToolExecutableRule, pin: ExternalToolExecutablePin) {
        try validateRuleIdentifier(rule.identifier)
        switch rule.capability {
        case .unpacker, .prediffer, .editorScript, .copyingScript:
            break
        case .pluginReload, .inProcessExtensions:
            throw ExternalToolPolicyError.capabilityCannotUseExternalExecutable(rule.capability)
        }

        let limits = rule.limits
        guard rule.approvedExecutableSHA256.count == SHA256.Digest.byteCount else {
            throw ExternalToolPolicyError.invalidApprovedExecutableDigest(rule.executableURL.path)
        }
        let executable = try canonicalItem(
            rule.executableURL,
            purpose: .executable,
            maximumPathUTF8Bytes: limits.maximumPathUTF8Bytes
        )
        guard executable.kind == .regularFile else {
            throw ExternalToolPolicyError.executableNotRegularFile(executable.url.path)
        }
        guard canExecute(executable.url.path) else {
            throw ExternalToolPolicyError.executableNotExecutable(executable.url.path)
        }
        try validateExecutableTrust(executable)
        let executablePin = try pinExecutable(executable)
        guard executablePin.identity.sha256 == rule.approvedExecutableSHA256 else {
            throw ExternalToolPolicyError.executableDoesNotMatchApprovedIdentity(executable.url.path)
        }
        guard !rule.permittedWorkingDirectories.isEmpty else {
            throw ExternalToolPolicyError.noPermittedWorkingDirectory(rule.identifier)
        }
        guard rule.permittedWorkingDirectories.count <= limits.maximumScopeCount,
            rule.permittedReadScopes.count
                <= limits.maximumScopeCount - rule.permittedWorkingDirectories.count,
            rule.permittedWriteScopes.count
                <= limits.maximumScopeCount
                - rule.permittedWorkingDirectories.count
                - rule.permittedReadScopes.count
        else {
            throw ExternalToolPolicyError.tooManyScopes(maximum: limits.maximumScopeCount)
        }
        try validateAggregatePathBytes(
            urls: [executable.url]
                + rule.permittedWorkingDirectories.map(\.url)
                + rule.permittedReadScopes.map(\.url)
                + rule.permittedWriteScopes.map(\.url),
            limits: limits
        )

        let workingDirectories = try canonicalScopes(
            rule.permittedWorkingDirectories,
            purpose: .permittedWorkingDirectory,
            limits: limits,
            requireDirectory: true
        )
        let readScopes = try canonicalScopes(
            rule.permittedReadScopes,
            purpose: .readScope,
            limits: limits
        )
        let writeScopes = try canonicalScopes(
            rule.permittedWriteScopes,
            purpose: .writeScope,
            limits: limits
        )
        if !writeScopes.isEmpty, executable.linkCount != 1 {
            throw ExternalToolPolicyError.executableHasMultipleLinks(executable.url.path)
        }
        for scope in workingDirectories where !readScopes.contains(where: { isSubset(scope, of: $0) }) {
            throw ExternalToolPolicyError.workingDirectoryScopeNotReadable(scope.url.path)
        }
        let executableScope = ExternalToolPathScope(url: executable.url, kind: .exactItem)
        guard !writeScopes.contains(where: { isSubset(executableScope, of: $0) }) else {
            throw ExternalToolPolicyError.executableCoveredByWriteScope(executable.url.path)
        }
        let environmentKeys = try validateAllowedEnvironmentKeys(rule.allowedEnvironmentKeys, limits: limits)
        let argumentConstraints = try validateArgumentConstraints(rule.argumentConstraints, limits: limits)
        try validateAggregatePathBytes(
            urls: [executable.url]
                + workingDirectories.map(\.url)
                + readScopes.map(\.url)
                + writeScopes.map(\.url),
            limits: limits
        )

        return (
            ExternalToolExecutableRule(
                identifier: rule.identifier,
                capability: rule.capability,
                executableURL: executable.url,
                approvedExecutableSHA256: rule.approvedExecutableSHA256,
                permittedWorkingDirectories: workingDirectories,
                permittedReadScopes: readScopes,
                permittedWriteScopes: writeScopes,
                allowedEnvironmentKeys: environmentKeys,
                argumentConstraints: argumentConstraints,
                isolationPolicy: rule.isolationPolicy,
                limits: limits
            ),
            executablePin
        )
    }

    fileprivate static func preflightRuleDescriptors(count: Int) throws {
        guard count > 0 else { return }
        var descriptors: [Int32] = []
        descriptors.reserveCapacity(count)
        defer {
            for descriptor in descriptors {
                Darwin.close(descriptor)
            }
        }
        for _ in 0..<count {
            let descriptor = Darwin.open("/dev/null", O_RDONLY | O_CLOEXEC)
            guard descriptor >= 0 else {
                throw ExternalToolPolicyError.insufficientFileDescriptorCapacity(required: count)
            }
            descriptors.append(descriptor)
        }
    }

    fileprivate static func validateRuleIdentifier(_ identifier: String) throws {
        guard !identifier.isEmpty, identifier.utf8.count <= 128 else {
            throw ExternalToolPolicyError.invalidRuleIdentifier(identifier)
        }
        let bytes = Array(identifier.utf8)
        guard isASCIIAlphaNumeric(bytes[0]),
            bytes.allSatisfy({ isASCIIAlphaNumeric($0) || $0 == 0x2D || $0 == 0x2E || $0 == 0x5F })
        else {
            throw ExternalToolPolicyError.invalidRuleIdentifier(identifier)
        }
    }

    fileprivate static func validateArguments(
        _ arguments: [String],
        constraints: [ExternalToolArgumentConstraint],
        readScopes: [ExternalToolPathScope],
        writeScopes: [ExternalToolPathScope],
        limits: ExternalToolInvocationLimits
    ) throws {
        guard arguments.count <= limits.maximumArgumentCount else {
            throw ExternalToolPolicyError.tooManyArguments(maximum: limits.maximumArgumentCount)
        }
        guard arguments.count == constraints.count else {
            throw ExternalToolPolicyError.argumentConstraintCountMismatch(
                expected: constraints.count,
                actual: arguments.count
            )
        }
        var total = 0
        for (index, pair) in zip(arguments, constraints).enumerated() {
            let (argument, constraint) = pair
            guard !argument.utf8.contains(0) else {
                throw ExternalToolPolicyError.argumentContainsNull(index: index)
            }
            let count = argument.utf8.count
            guard count <= limits.maximumArgumentUTF8Bytes else {
                throw ExternalToolPolicyError.argumentTooLarge(
                    index: index,
                    maximumUTF8Bytes: limits.maximumArgumentUTF8Bytes
                )
            }
            guard count <= limits.maximumTotalArgumentUTF8Bytes - total else {
                throw ExternalToolPolicyError.totalArgumentsTooLarge(
                    maximumUTF8Bytes: limits.maximumTotalArgumentUTF8Bytes
                )
            }
            total += count
            guard
                argumentSatisfies(
                    argument,
                    constraint: constraint,
                    readScopes: readScopes,
                    writeScopes: writeScopes
                )
            else {
                throw ExternalToolPolicyError.argumentConstraintViolation(index: index)
            }
        }
    }

    fileprivate static func validateArgumentConstraints(
        _ constraints: [ExternalToolArgumentConstraint],
        limits: ExternalToolInvocationLimits
    ) throws -> [ExternalToolArgumentConstraint] {
        guard constraints.count <= limits.maximumArgumentCount else {
            throw ExternalToolPolicyError.tooManyArguments(maximum: limits.maximumArgumentCount)
        }
        for (index, constraint) in constraints.enumerated() {
            switch constraint {
            case .exact(let value):
                guard validConstraintValue(value, limits: limits) else {
                    throw ExternalToolPolicyError.invalidArgumentConstraint(index: index)
                }
            case .oneOf(let values):
                guard !values.isEmpty,
                    values.count <= 256,
                    Set(values).count == values.count,
                    values.allSatisfy({ validConstraintValue($0, limits: limits) })
                else {
                    throw ExternalToolPolicyError.invalidArgumentConstraint(index: index)
                }
            case .value, .readPath, .writePath:
                break
            }
        }
        return constraints
    }

    fileprivate static func validConstraintValue(
        _ value: String,
        limits: ExternalToolInvocationLimits
    ) -> Bool {
        !value.utf8.contains(0) && value.utf8.count <= limits.maximumArgumentUTF8Bytes
    }

    fileprivate static func argumentSatisfies(
        _ argument: String,
        constraint: ExternalToolArgumentConstraint,
        readScopes: [ExternalToolPathScope],
        writeScopes: [ExternalToolPathScope]
    ) -> Bool {
        switch constraint {
        case .exact(let value):
            return argument == value
        case .oneOf(let values):
            return values.contains(argument)
        case .value:
            return !argument.isEmpty
                && argument != "-"
                && !argument.hasPrefix("-")
                && !argument.hasPrefix("@")
        case .readPath:
            return lexicalArgumentPath(argument, isCoveredBy: readScopes)
        case .writePath:
            return lexicalArgumentPath(argument, isCoveredBy: writeScopes)
        }
    }

    fileprivate static func lexicalArgumentPath(
        _ argument: String,
        isCoveredBy scopes: [ExternalToolPathScope]
    ) -> Bool {
        guard argument.hasPrefix("/"),
            !argument.hasPrefix("//"),
            !argument.utf8.contains(0),
            !argument.contains("/../"),
            !argument.hasSuffix("/..")
        else {
            return false
        }
        let scope = ExternalToolPathScope(
            url: URL(fileURLWithPath: argument).standardizedFileURL,
            kind: .exactItem
        )
        return scopes.contains { isSubset(scope, of: $0) }
    }

    fileprivate static func validateAllowedEnvironmentKeys(
        _ keys: [String],
        limits: ExternalToolInvocationLimits
    ) throws -> [String] {
        guard keys.count <= limits.maximumEnvironmentEntryCount else {
            throw ExternalToolPolicyError.tooManyEnvironmentEntries(
                maximum: limits.maximumEnvironmentEntryCount
            )
        }
        let keys = Array(Set(keys)).sorted()
        for key in keys {
            try validateEnvironmentKey(key, limits: limits)
            guard !isPermanentlyDeniedEnvironmentKey(key) else {
                throw ExternalToolPolicyError.environmentKeyPermanentlyDenied(key)
            }
        }
        return keys
    }

    fileprivate static func validateEnvironment(
        _ environment: [String: String],
        allowedKeys: [String],
        limits: ExternalToolInvocationLimits
    ) throws -> [ExternalToolEnvironmentEntry] {
        guard environment.count <= limits.maximumEnvironmentEntryCount else {
            throw ExternalToolPolicyError.tooManyEnvironmentEntries(
                maximum: limits.maximumEnvironmentEntryCount
            )
        }
        let allowed = Set(allowedKeys)
        var total = 0
        var result: [ExternalToolEnvironmentEntry] = []
        result.reserveCapacity(environment.count)
        for key in environment.keys.sorted() {
            try validateEnvironmentKey(key, limits: limits)
            guard !isPermanentlyDeniedEnvironmentKey(key) else {
                throw ExternalToolPolicyError.environmentKeyPermanentlyDenied(key)
            }
            guard allowed.contains(key) else {
                throw ExternalToolPolicyError.environmentKeyNotAllowed(key)
            }
            let value = environment[key]!
            guard !value.utf8.contains(0) else {
                throw ExternalToolPolicyError.environmentValueContainsNull(key: key)
            }
            let valueCount = value.utf8.count
            guard valueCount <= limits.maximumEnvironmentValueUTF8Bytes else {
                throw ExternalToolPolicyError.environmentValueTooLarge(
                    key: key,
                    maximumUTF8Bytes: limits.maximumEnvironmentValueUTF8Bytes
                )
            }
            let entryCount = key.utf8.count + valueCount + 2
            guard entryCount <= limits.maximumTotalEnvironmentUTF8Bytes - total else {
                throw ExternalToolPolicyError.totalEnvironmentTooLarge(
                    maximumUTF8Bytes: limits.maximumTotalEnvironmentUTF8Bytes
                )
            }
            total += entryCount
            result.append(ExternalToolEnvironmentEntry(key: key, value: value))
        }
        return result
    }

    fileprivate static func validateEnvironmentKey(
        _ key: String,
        limits: ExternalToolInvocationLimits
    ) throws {
        guard !key.isEmpty else {
            throw ExternalToolPolicyError.invalidEnvironmentKey(key)
        }
        guard key.utf8.count <= limits.maximumEnvironmentKeyUTF8Bytes else {
            throw ExternalToolPolicyError.environmentKeyTooLarge(
                key,
                maximumUTF8Bytes: limits.maximumEnvironmentKeyUTF8Bytes
            )
        }
        let bytes = Array(key.utf8)
        guard isASCIIAlpha(bytes[0]) || bytes[0] == 0x5F,
            bytes.dropFirst().allSatisfy({ isASCIIAlphaNumeric($0) || $0 == 0x5F })
        else {
            throw ExternalToolPolicyError.invalidEnvironmentKey(key)
        }
    }

    fileprivate static func isPermanentlyDeniedEnvironmentKey(_ key: String) -> Bool {
        key.uppercased().hasPrefix("DYLD_")
    }

    fileprivate static func validateProcessInput(
        executablePath: String,
        arguments: [String],
        environment: [ExternalToolEnvironmentEntry]
    ) throws {
        let configuredLimit = Darwin.sysconf(_SC_ARG_MAX)
        let argumentMaximum = configuredLimit > 0 ? Int(configuredLimit) : 256 * 1_024
        let safetyReserve = min(4_096, argumentMaximum)
        let maximum = argumentMaximum - safetyReserve
        let pointerCount = arguments.count + environment.count + 3
        var required = executablePath.utf8.count + 1 + pointerCount * MemoryLayout<UnsafeRawPointer?>.stride
        for argument in arguments {
            required += argument.utf8.count + 1
        }
        for entry in environment {
            required += entry.key.utf8.count + entry.value.utf8.count + 2
        }
        guard required <= maximum else {
            throw ExternalToolPolicyError.processInputTooLarge(maximumBytes: maximum)
        }
    }

    fileprivate static func canonicalScopes(
        _ scopes: [ExternalToolPathScope],
        purpose: ExternalToolPathPurpose,
        limits: ExternalToolInvocationLimits,
        requireDirectory: Bool = false
    ) throws -> [ExternalToolPathScope] {
        let sortedScopes = scopes.sorted(by: scopePrecedes)
        var unique: Set<ExternalToolPathScope> = []
        var result: [ExternalToolPathScope] = []
        result.reserveCapacity(sortedScopes.count)
        for scope in sortedScopes {
            let item = try canonicalItem(
                scope.url,
                purpose: purpose,
                maximumPathUTF8Bytes: limits.maximumPathUTF8Bytes
            )
            guard item.kind == .regularFile || item.kind == .directory else {
                throw ExternalToolPolicyError.scopeNotFileOrDirectory(item.url.path)
            }
            if requireDirectory, item.kind != .directory {
                throw ExternalToolPolicyError.workingDirectoryNotDirectory(item.url.path)
            }
            if scope.kind == .directoryTree {
                guard item.kind == .directory else {
                    throw ExternalToolPolicyError.directoryTreeScopeNotDirectory(item.url.path)
                }
                guard item.url.path != "/" else {
                    throw ExternalToolPolicyError.rootDirectoryTreeNotAllowed
                }
            }
            let canonical = ExternalToolPathScope(url: item.url, kind: scope.kind)
            if unique.insert(canonical).inserted {
                result.append(canonical)
            }
        }
        return result.sorted(by: scopePrecedes)
    }

    fileprivate static func prefilterScopes(
        _ scopes: [ExternalToolPathScope],
        against permittedScopes: [ExternalToolPathScope],
        purpose: ExternalToolPathPurpose,
        limits: ExternalToolInvocationLimits
    ) throws {
        var total = 0
        for scope in scopes {
            try prefilterPath(
                scope.url,
                purpose: purpose,
                maximumPathUTF8Bytes: limits.maximumPathUTF8Bytes
            )
            let count = scope.url.path.utf8.count
            guard count <= limits.maximumTotalPathUTF8Bytes - total else {
                throw ExternalToolPolicyError.totalPathsTooLarge(
                    maximumUTF8Bytes: limits.maximumTotalPathUTF8Bytes
                )
            }
            total += count
            let lexical = ExternalToolPathScope(
                url: scope.url.standardizedFileURL,
                kind: scope.kind
            )
            guard permittedScopes.contains(where: { isSubset(lexical, of: $0) }) else {
                switch purpose {
                case .readScope:
                    throw ExternalToolPolicyError.readScopeNotPermitted(scope.url.path)
                case .writeScope:
                    throw ExternalToolPolicyError.writeScopeNotPermitted(scope.url.path)
                case .executable, .workingDirectory, .permittedWorkingDirectory:
                    throw ExternalToolPolicyError.invalidAbsoluteFileURL(
                        purpose: purpose,
                        value: scope.url.absoluteString
                    )
                }
            }
        }
    }

    fileprivate static func prefilterPath(
        _ url: URL,
        purpose: ExternalToolPathPurpose,
        maximumPathUTF8Bytes: Int
    ) throws {
        guard isAbsoluteLocalFileURL(url) else {
            throw ExternalToolPolicyError.invalidAbsoluteFileURL(
                purpose: purpose,
                value: url.absoluteString
            )
        }
        guard url.path.utf8.count <= maximumPathUTF8Bytes else {
            throw ExternalToolPolicyError.pathTooLarge(
                purpose: purpose,
                maximumUTF8Bytes: maximumPathUTF8Bytes
            )
        }
    }

    fileprivate static func validateAggregatePathBytes(
        urls: [URL],
        limits: ExternalToolInvocationLimits
    ) throws {
        var total = 0
        for url in urls {
            let count = url.path.utf8.count
            guard count <= limits.maximumTotalPathUTF8Bytes - total else {
                throw ExternalToolPolicyError.totalPathsTooLarge(
                    maximumUTF8Bytes: limits.maximumTotalPathUTF8Bytes
                )
            }
            total += count
        }
    }

    fileprivate static func canonicalItem(
        _ url: URL,
        purpose: ExternalToolPathPurpose,
        maximumPathUTF8Bytes: Int
    ) throws -> CanonicalItem {
        try prefilterPath(
            url,
            purpose: purpose,
            maximumPathUTF8Bytes: maximumPathUTF8Bytes
        )
        let suppliedPath = url.path
        guard let pointer = suppliedPath.withCString({ Darwin.realpath($0, nil) }) else {
            throw ExternalToolPolicyError.pathCannotBeResolved(purpose: purpose, path: suppliedPath)
        }
        defer { Darwin.free(pointer) }
        let resolvedPath = String(cString: pointer)
        guard resolvedPath.utf8.count <= maximumPathUTF8Bytes else {
            throw ExternalToolPolicyError.pathTooLarge(
                purpose: purpose,
                maximumUTF8Bytes: maximumPathUTF8Bytes
            )
        }

        var information = stat()
        guard resolvedPath.withCString({ Darwin.lstat($0, &information) }) == 0 else {
            throw ExternalToolPolicyError.pathCannotBeResolved(purpose: purpose, path: resolvedPath)
        }
        let kind: ItemKind
        switch information.st_mode & S_IFMT {
        case S_IFREG:
            kind = .regularFile
        case S_IFDIR:
            kind = .directory
        default:
            throw ExternalToolPolicyError.scopeNotFileOrDirectory(resolvedPath)
        }
        return CanonicalItem(
            url: URL(
                fileURLWithPath: resolvedPath,
                isDirectory: kind == .directory
            ).standardizedFileURL,
            kind: kind,
            linkCount: information.st_nlink,
            information: information
        )
    }

    fileprivate static func validateExecutableTrust(_ executable: CanonicalItem) throws {
        let owner = executable.information.st_uid
        let currentUser = Darwin.geteuid()
        guard owner == 0 || owner == currentUser else {
            throw ExternalToolPolicyError.executableUntrustedOwner(
                path: executable.url.path,
                owner: owner
            )
        }
        guard executable.information.st_mode & (S_IWGRP | S_IWOTH) == 0 else {
            throw ExternalToolPolicyError.executableUnsafeMode(executable.url.path)
        }
        try rejectMutatingAllowACL(executable.url.path)

        var ancestor = executable.url.deletingLastPathComponent().standardizedFileURL
        while true {
            var information = stat()
            guard ancestor.path.withCString({ Darwin.lstat($0, &information) }) == 0 else {
                throw ExternalToolPolicyError.pathCannotBeResolved(
                    purpose: .executable,
                    path: ancestor.path
                )
            }
            guard information.st_uid == 0 || information.st_uid == currentUser,
                information.st_mode & S_IWGRP == 0,
                information.st_mode & S_IWOTH == 0
            else {
                throw ExternalToolPolicyError.executableUntrustedAncestor(ancestor.path)
            }
            try rejectMutatingAllowACL(ancestor.path)
            if ancestor.path == "/" { break }
            ancestor.deleteLastPathComponent()
        }
    }

    fileprivate static func rejectMutatingAllowACL(_ path: String) throws {
        errno = 0
        guard let acl = path.withCString({ Darwin.acl_get_file($0, ACL_TYPE_EXTENDED) }) else {
            if errno == ENOENT { return }
            throw ExternalToolPolicyError.executableUnsafeACL(path)
        }
        defer { Darwin.acl_free(UnsafeMutableRawPointer(acl)) }

        var entry: acl_entry_t?
        var entryID = ACL_FIRST_ENTRY.rawValue
        while Darwin.acl_get_entry(acl, entryID, &entry) == 0 {
            entryID = ACL_NEXT_ENTRY.rawValue
            guard let entry else { continue }
            var tag = ACL_UNDEFINED_TAG
            guard Darwin.acl_get_tag_type(entry, &tag) == 0 else {
                throw ExternalToolPolicyError.executableUnsafeACL(path)
            }
            guard tag == ACL_EXTENDED_ALLOW else { continue }
            var permissions: acl_permset_t?
            guard Darwin.acl_get_permset(entry, &permissions) == 0,
                let permissions
            else {
                throw ExternalToolPolicyError.executableUnsafeACL(path)
            }
            let mutatingPermissions = [
                ACL_WRITE_DATA,
                ACL_DELETE,
                ACL_APPEND_DATA,
                ACL_DELETE_CHILD,
                ACL_WRITE_ATTRIBUTES,
                ACL_WRITE_EXTATTRIBUTES,
                ACL_WRITE_SECURITY,
                ACL_CHANGE_OWNER
            ]
            if mutatingPermissions.contains(where: { Darwin.acl_get_perm_np(permissions, $0) == 1 }) {
                throw ExternalToolPolicyError.executableUnsafeACL(path)
            }
        }
        guard errno == 0 || errno == EINVAL else {
            throw ExternalToolPolicyError.executableUnsafeACL(path)
        }
    }

    fileprivate static func pinExecutable(_ executable: CanonicalItem) throws -> ExternalToolExecutablePin {
        let descriptor = executable.url.path.withCString {
            Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw ExternalToolPolicyError.pathCannotBeResolved(
                purpose: .executable,
                path: executable.url.path
            )
        }
        do {
            var information = stat()
            guard Darwin.fstat(descriptor, &information) == 0 else {
                throw ExternalToolPolicyError.pathCannotBeResolved(
                    purpose: .executable,
                    path: executable.url.path
                )
            }
            guard sameIdentity(information, executable.information) else {
                throw ExternalToolPolicyError.executableIdentityChanged(executable.url.path)
            }
            let identity = try executableIdentity(
                descriptor: descriptor,
                information: information,
                path: executable.url.path
            )
            return ExternalToolExecutablePin(
                sourceURL: executable.url,
                identity: identity,
                fileDescriptor: descriptor
            )
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    fileprivate static func validatePinnedExecutable(_ pin: ExternalToolExecutablePin) throws {
        let descriptor = try pin.duplicateReadOnlyFileDescriptor()
        defer { Darwin.close(descriptor) }
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else {
            throw ExternalToolPolicyError.executableIdentityChanged(pin.sourceURL.path)
        }
        guard sameIdentity(information, pin.identity) else {
            throw ExternalToolPolicyError.executableIdentityChanged(pin.sourceURL.path)
        }
        let identity = try executableIdentity(
            descriptor: descriptor,
            information: information,
            path: pin.sourceURL.path
        )
        var finalInformation = stat()
        guard Darwin.fstat(descriptor, &finalInformation) == 0,
            sameIdentity(information, finalInformation),
            identity == pin.identity
        else {
            throw ExternalToolPolicyError.executableIdentityChanged(pin.sourceURL.path)
        }
    }

    fileprivate static func executableIdentity(
        descriptor: Int32,
        information: stat,
        path: String
    ) throws -> ExternalToolExecutableIdentity {
        guard information.st_size >= 0 else {
            throw ExternalToolPolicyError.executableIdentityChanged(path)
        }
        try rejectShebang(descriptor: descriptor, size: information.st_size, path: path)
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        var offset: off_t = 0
        while offset < information.st_size {
            let requestedCount = min(buffer.count, Int(information.st_size - offset))
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.pread(descriptor, rawBuffer.baseAddress, requestedCount, offset)
            }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw ExternalToolPolicyError.executableIdentityChanged(path)
            }
            hasher.update(data: Data(buffer[0..<count]))
            offset += off_t(count)
        }
        var finalInformation = stat()
        guard Darwin.fstat(descriptor, &finalInformation) == 0,
            sameIdentity(information, finalInformation)
        else {
            throw ExternalToolPolicyError.executableIdentityChanged(path)
        }
        return ExternalToolExecutableIdentity(
            device: UInt64(information.st_dev),
            inode: UInt64(information.st_ino),
            generation: information.st_gen,
            size: information.st_size,
            modificationTimeSeconds: Int64(information.st_mtimespec.tv_sec),
            modificationTimeNanoseconds: Int64(information.st_mtimespec.tv_nsec),
            changeTimeSeconds: Int64(information.st_ctimespec.tv_sec),
            changeTimeNanoseconds: Int64(information.st_ctimespec.tv_nsec),
            sha256: Array(hasher.finalize())
        )
    }

    fileprivate static func rejectShebang(descriptor: Int32, size: off_t, path: String) throws {
        guard size >= 2 else { return }
        var prefix = [UInt8](repeating: 0, count: 2)
        var offset: off_t = 0
        while offset < prefix.count {
            let remainingCount = prefix.count - Int(offset)
            let count = prefix.withUnsafeMutableBytes { rawBuffer in
                Darwin.pread(
                    descriptor,
                    rawBuffer.baseAddress?.advanced(by: Int(offset)),
                    remainingCount,
                    offset
                )
            }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw ExternalToolPolicyError.executableIdentityChanged(path)
            }
            offset += off_t(count)
        }
        guard prefix != [0x23, 0x21] else {
            throw ExternalToolPolicyError.executableScriptNotAllowed(path)
        }
    }

    fileprivate static func sameIdentity(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev
            && lhs.st_ino == rhs.st_ino
            && lhs.st_gen == rhs.st_gen
            && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }

    fileprivate static func sameIdentity(
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

    fileprivate static func isAbsoluteLocalFileURL(_ url: URL) -> Bool {
        guard url.isFileURL,
            url.baseURL == nil,
            url.query == nil,
            url.fragment == nil,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "file",
            components.user == nil,
            components.password == nil,
            components.port == nil,
            components.host?.isEmpty != false
                || components.host?.caseInsensitiveCompare("localhost") == .orderedSame,
            url.path.hasPrefix("/"),
            !url.path.hasPrefix("//"),
            !url.path.utf8.contains(0)
        else {
            return false
        }
        return true
    }

    fileprivate static func isSubset(_ candidate: ExternalToolPathScope, of permitted: ExternalToolPathScope) -> Bool {
        switch permitted.kind {
        case .exactItem:
            return candidate.kind == .exactItem && candidate.url.path == permitted.url.path
        case .directoryTree:
            return path(candidate.url, isWithin: permitted.url)
        }
    }

    fileprivate static func path(_ candidate: URL, isWithin root: URL) -> Bool {
        let candidateComponents = candidate.pathComponents
        let rootComponents = root.pathComponents
        guard candidateComponents.count >= rootComponents.count else { return false }
        return candidateComponents.prefix(rootComponents.count).elementsEqual(rootComponents)
    }

    fileprivate static func scopePrecedes(_ lhs: ExternalToolPathScope, _ rhs: ExternalToolPathScope) -> Bool {
        if lhs.url.path != rhs.url.path { return lhs.url.path < rhs.url.path }
        return lhs.kind.rawValue < rhs.kind.rawValue
    }

    fileprivate static func canExecute(_ path: String) -> Bool {
        path.withCString { Darwin.access($0, X_OK) == 0 }
    }

    fileprivate static func canSearch(_ path: String) -> Bool {
        path.withCString { Darwin.access($0, X_OK) == 0 }
    }

    fileprivate static func isASCIIAlpha(_ byte: UInt8) -> Bool {
        (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
    }

    fileprivate static func isASCIIAlphaNumeric(_ byte: UInt8) -> Bool {
        isASCIIAlpha(byte) || (0x30...0x39).contains(byte)
    }
}
