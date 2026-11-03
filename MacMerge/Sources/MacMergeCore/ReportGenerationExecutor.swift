import Foundation

/// UI-independent comparison-report workflow executor stub.
///
/// Binds an already-planned `ComparisonReportWorkflowPlan` (file/folder source, all/selected
/// scope, plain-text/CSV/HTML format, clipboard/file output, linked reports, overwrite policy,
/// sandbox authority, open-after-generation intent) to exact snapshot revalidation, sandbox
/// authority, and cancellation. Plan-only: performs no filesystem, pasteboard, process, or UI
/// work and never publishes bytes, so every outcome proves zero publication through an empty
/// completed prefix. A future native layer owns descriptor-relative no-follow path resolution,
/// canonical aliasing/collision/overlap rejection, overwrite-policy atomic compare-and-swap
/// publication in plan order, balanced security-scope access, clipboard replacement, and
/// primary-only open after every output publishes, all under
/// `ComparisonReportExecutorContract.required`, and seals commit evidence through
/// `ComparisonReportExecutionOutcomeFactory`. This file claims no UI.
public struct ReportGenerationSandboxAuthority: Equatable, Hashable, Sendable {
    /// Exact percent-decoded absolute parent directory paths the executor may target.
    public let writableParentPaths: Set<String>
    public let allowsClipboard: Bool

    public init(writableParentPaths: Set<String> = [], allowsClipboard: Bool = false) {
        self.writableParentPaths = writableParentPaths
        self.allowsClipboard = allowsClipboard
    }

    public func authorizes(_ plan: ComparisonReportWorkflowPlan) -> Bool {
        uncoveredOutputIdentity(plan) == nil
    }

    /// First planned output lacking authority, in plan order, or nil when covered.
    public func uncoveredOutputIdentity(
        _ plan: ComparisonReportWorkflowPlan
    ) -> ComparisonReportOutputIdentity? {
        for output in plan.outputs {
            switch output.destination {
            case .clipboard:
                guard allowsClipboard else { return .clipboard }
            case .file(let requestedURL, let identity, _, let access):
                guard access == .ambient else {
                    return .file(identity)
                }
                let parent = identity.fileURL.deletingLastPathComponent().path
                guard writableParentPaths.contains(parent) else {
                    return .file(identity)
                }
                let requestedParent = requestedURL.standardizedFileURL.deletingLastPathComponent().path
                guard requestedParent == parent,
                    writableParentPaths.contains(requestedParent),
                    requestedURL.standardizedFileURL.lastPathComponent == identity.fileURL.lastPathComponent
                else {
                    return .file(identity)
                }
            }
        }
        return nil
    }
}

/// Caller-supplied liveness probes. The stub performs no I/O itself; owners with revision
/// leases or pinned descriptors answer whether plan inputs and destinations are current.
public struct ReportGenerationRevalidation: Sendable {
    public let sourcesCurrent: @Sendable (ComparisonReportWorkflowPlan) async -> Bool
    public let destinationsCurrent: @Sendable (ComparisonReportWorkflowPlan) async -> Bool

    public init(
        sourcesCurrent: @escaping @Sendable (ComparisonReportWorkflowPlan) async -> Bool,
        destinationsCurrent: @escaping @Sendable (ComparisonReportWorkflowPlan) async -> Bool
    ) {
        self.sourcesCurrent = sourcesCurrent
        self.destinationsCurrent = destinationsCurrent
    }

    public static var assumeCurrent: ReportGenerationRevalidation {
        ReportGenerationRevalidation(
            sourcesCurrent: { _ in true },
            destinationsCurrent: { _ in true }
        )
    }

    public static var stale: ReportGenerationRevalidation {
        ReportGenerationRevalidation(
            sourcesCurrent: { _ in false },
            destinationsCurrent: { _ in false }
        )
    }
}

/// Mutation-free echo of one planned output: exact bytes stay in the plan.
public struct ReportGenerationOutputBinding: Equatable, Sendable {
    public let role: ComparisonReportPlannedOutputRole
    public let identity: ComparisonReportOutputIdentity
    public let overwritePolicy: ComparisonReportOverwritePolicy?
    public let sandboxAccess: ComparisonReportSandboxAccess?
    public let byteCount: Int

    fileprivate init(_ planned: ComparisonReportPlannedOutput) {
        role = planned.role
        identity = planned.destination.outputIdentity
        switch planned.destination {
        case .clipboard:
            overwritePolicy = nil
            sandboxAccess = nil
        case .file(_, _, let policy, let access):
            overwritePolicy = policy
            sandboxAccess = access
        }
        byteCount = planned.outputByteCount
    }
}

/// Execution receipt. Construction performs no mutation; it echoes the exact plan.
public struct ReportGenerationExecutorReceipt: Equatable, Sendable {
    public let snapshot: ComparisonReportWorkflowSnapshotReference
    public let scope: ComparisonReportScope
    public let format: ComparisonReportFormat
    public let outputs: [ReportGenerationOutputBinding]
    public let openAfterGeneration: Bool
    public let executorContract = ComparisonReportExecutorContract.required

    fileprivate init(_ plan: ComparisonReportWorkflowPlan) {
        snapshot = plan.snapshotFingerprint.reference
        scope = plan.scope
        format = plan.format
        outputs = plan.outputs.map(ReportGenerationOutputBinding.init)
        openAfterGeneration = plan.openAfterGeneration
    }
}

/// Plan-only stub executor: validates binding, authority, staleness, and cancellation,
/// then reports no-commit without mutating. Conforms to `ComparisonReportPlanExecutor`
/// so `ToolsCommandWorkflow.executeReportEffects` accepts it.
public struct ReportGenerationExecutor: ComparisonReportPlanExecutor, Sendable {
    public let authority: ReportGenerationSandboxAuthority
    public let revalidation: ReportGenerationRevalidation

    public init(
        authority: ReportGenerationSandboxAuthority = ReportGenerationSandboxAuthority(),
        revalidation: ReportGenerationRevalidation = .assumeCurrent
    ) {
        self.authority = authority
        self.revalidation = revalidation
    }

    public func describe(_ plan: ComparisonReportWorkflowPlan) -> ReportGenerationExecutorReceipt {
        ReportGenerationExecutorReceipt(plan)
    }

    public func execute(
        _ plan: ComparisonReportWorkflowPlan,
        validating currentSnapshot: ComparisonReportWorkflowSnapshot,
        linkedReports: [ComparisonReportLinkedReport]
    ) async -> ComparisonReportExecutionOutcome {
        if Task.isCancelled {
            return ComparisonReportExecutionOutcomeFactory.cancelled(plan: plan)
        }
        if structuralRejection(plan) != nil {
            return ComparisonReportExecutionOutcomeFactory.failed(plan: plan, code: .invalidPlan)
        }
        do {
            try plan.validateCurrentSnapshot(currentSnapshot, linkedReports: linkedReports)
        } catch is CancellationError {
            return ComparisonReportExecutionOutcomeFactory.cancelled(plan: plan)
        } catch let error as ComparisonReportWorkflowError {
            switch error {
            case .cancelled:
                return ComparisonReportExecutionOutcomeFactory.cancelled(plan: plan)
            case .snapshotIdentityChanged, .snapshotGenerationChanged, .snapshotContentsChanged:
                return ComparisonReportExecutionOutcomeFactory.failed(
                    plan: plan,
                    code: .staleSnapshot
                )
            default:
                return ComparisonReportExecutionOutcomeFactory.failed(
                    plan: plan,
                    code: .invalidPlan
                )
            }
        } catch {
            return ComparisonReportExecutionOutcomeFactory.failed(plan: plan, code: .invalidPlan)
        }
        if Task.isCancelled {
            return ComparisonReportExecutionOutcomeFactory.cancelled(plan: plan)
        }
        if let uncovered = authority.uncoveredOutputIdentity(plan) {
            return authorityFailure(plan: plan, identity: uncovered)
        }
        guard await revalidation.sourcesCurrent(plan) else {
            return ComparisonReportExecutionOutcomeFactory.failed(
                plan: plan,
                code: .staleSnapshot
            )
        }
        if Task.isCancelled {
            return ComparisonReportExecutionOutcomeFactory.cancelled(plan: plan)
        }
        guard await revalidation.destinationsCurrent(plan) else {
            return destinationFailure(plan: plan)
        }
        if Task.isCancelled {
            return ComparisonReportExecutionOutcomeFactory.cancelled(plan: plan)
        }
        // Never publishes: no filesystem, pasteboard, process, or UI mutation, and no open.
        // A native layer owns exact-byte atomic publication in plan order plus primary-only open.
        return ComparisonReportExecutionOutcomeFactory.failed(
            plan: plan,
            code: .contractUnsupported
        )
    }

    private func authorityFailure(
        plan: ComparisonReportWorkflowPlan,
        identity: ComparisonReportOutputIdentity
    ) -> ComparisonReportExecutionOutcome {
        switch identity {
        case .clipboard:
            return ComparisonReportExecutionOutcomeFactory.failed(
                plan: plan,
                code: .clipboardUnavailable,
                outputIdentity: identity
            )
        case .file(let canonical):
            let isScoped = plan.outputs.contains {
                guard
                    case .file(_, let identity, _, .securityScoped) = $0.destination
                else { return false }
                return identity == canonical
            }
            if isScoped {
                return ComparisonReportExecutionOutcomeFactory.failed(
                    plan: plan,
                    code: .securityScopeUnavailable,
                    outputIdentity: identity
                )
            }
            return ComparisonReportExecutionOutcomeFactory.failed(
                plan: plan,
                code: .contractUnsupported
            )
        }
    }

    private func destinationFailure(
        plan: ComparisonReportWorkflowPlan
    ) -> ComparisonReportExecutionOutcome {
        // Probe carries no identity: never attribute staleness to one output.
        return ComparisonReportExecutionOutcomeFactory.failed(
            plan: plan,
            code: .contractUnsupported
        )
    }

    /// Exact string binding only: no URL resolution and no filesystem access. Sandbox scope
    /// is checked separately through `authority`; descriptor pinning stays native.
    private func structuralRejection(_ plan: ComparisonReportWorkflowPlan) -> String? {
        guard !plan.outputs.isEmpty, plan.outputs[0].role == .primary else {
            return "Stub executor requires a non-empty plan with a primary first output."
        }
        switch plan.primaryOutput.destination {
        case .clipboard:
            guard plan.outputs.count == 1, !plan.openAfterGeneration else {
                return "Stub executor requires clipboard plans to hold one output and no open."
            }
        case .file(let requestedURL, let identity, _, _):
            guard
                isBoundCanonicalFileURL(
                    requestedURL,
                    identity: identity,
                    format: plan.format
                )
            else {
                return "Stub executor found a primary destination outside its bound identity."
            }
        }
        guard case .file(_, let primaryIdentity, _, _) = plan.primaryOutput.destination else {
            return nil
        }
        let primaryParent = primaryIdentity.fileURL.deletingLastPathComponent().path
        var seenIdentities: [ComparisonReportCanonicalOutputIdentity] = [primaryIdentity]
        for output in plan.linkedOutputs {
            guard
                case .linked = output.role,
                case .file(let requestedURL, let identity, _, _) = output.destination,
                isBoundCanonicalFileURL(
                    requestedURL,
                    identity: identity,
                    format: plan.format
                ),
                isContainedUnderParent(identity: identity, parentPath: primaryParent)
            else {
                return "Stub executor requires linked outputs to bind leaf file destinations."
            }
            for existing in seenIdentities {
                if existing == identity
                    || isAncestorPath(existing.canonicalPath, identity.canonicalPath)
                    || isAncestorPath(identity.canonicalPath, existing.canonicalPath)
                {
                    return "Stub executor requires linked outputs to bind leaf file destinations."
                }
            }
            seenIdentities.append(identity)
        }
        return nil
    }

    private func isLeafFileURL(_ url: URL) -> Bool {
        url.isFileURL && !url.hasDirectoryPath && !url.lastPathComponent.isEmpty
    }

    private func isBoundCanonicalFileURL(
        _ url: URL,
        identity: ComparisonReportCanonicalOutputIdentity,
        format: ComparisonReportFormat
    ) -> Bool {
        guard isLeafFileURL(url),
            url.baseURL == nil,
            url.path.hasPrefix("/"),
            isLocalFileHost(url.host),
            url.user == nil,
            url.password == nil,
            url.port == nil,
            url.query == nil,
            url.fragment == nil,
            !url.path.contains("\0"),
            url.standardizedFileURL.path == identity.fileURL.path,
            identity.fileURL.path == identity.canonicalPath,
            url.standardizedFileURL.pathExtension == format.fileExtension,
            identity.fileURL.pathExtension == format.fileExtension
        else {
            return false
        }
        return true
    }

    private func isLocalFileHost(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else { return true }
        let expectedHost = Array("localhost".utf8)
        guard host.utf8.count == expectedHost.count else { return false }
        for (actual, expected) in zip(host.utf8, expectedHost) {
            let folded =
                actual >= UInt8(ascii: "A") && actual <= UInt8(ascii: "Z")
                ? actual + (UInt8(ascii: "a") - UInt8(ascii: "A"))
                : actual
            guard folded == expected else { return false }
        }
        return true
    }

    private func isContainedUnderParent(
        identity: ComparisonReportCanonicalOutputIdentity,
        parentPath: String
    ) -> Bool {
        if parentPath == "/" {
            return identity.canonicalPath.hasPrefix("/") && identity.canonicalPath != "/"
        }
        return identity.canonicalPath.hasPrefix(parentPath + "/")
    }

    private func isAncestorPath(_ ancestor: String, _ descendant: String) -> Bool {
        let ancestorBytes = Array(ancestor.utf8)
        let descendantBytes = Array(descendant.utf8)
        guard descendantBytes.count > ancestorBytes.count else { return false }
        if ancestorBytes.count == 1, ancestorBytes[0] == UInt8(ascii: "/") { return true }
        for index in 0..<ancestorBytes.count {
            guard ancestorBytes[index] == descendantBytes[index] else { return false }
        }
        return descendantBytes[ancestorBytes.count] == UInt8(ascii: "/")
    }
}
