import Foundation

/// UI-independent patch execution stub.
///
/// Binds an already-planned `PatchGenerationMutationPlan` (ordered sources, style,
/// context lines, direction, create/replace/append or clipboard/file output) to
/// exact filesystem revision checks, sandbox authority, stale validation, and
/// cancellation. Plan-only: performs no filesystem, pasteboard, UI, or process
/// mutation and never calls `PatchGenerationExecutionSession.beginPublication`,
/// so every outcome is a pre-publication non-commit. A future native layer owns
/// real descriptor-relative compare-and-swap publication under
/// `PatchGenerationExecutorContract.required` and seals commit evidence through
/// `PatchGenerationExecutionOutcomeFactory`.
public struct PatchGenerationStubSandboxAuthority: Equatable, Hashable, Sendable {
    /// Exact percent-decoded absolute parent directory paths the executor may target.
    public let writableParentPaths: Set<String>
    public let allowsClipboard: Bool

    public init(writableParentPaths: Set<String> = [], allowsClipboard: Bool = false) {
        self.writableParentPaths = writableParentPaths
        self.allowsClipboard = allowsClipboard
    }

    public func authorizes(_ plan: PatchGenerationMutationPlan) -> Bool {
        switch plan.destination {
        case .clipboard:
            return allowsClipboard
        case .file(let destination):
            return writableParentPaths.contains(
                destination.url.deletingLastPathComponent().path(percentEncoded: false)
            )
        }
    }
}

/// Caller-supplied liveness probes. The stub performs no I/O itself; owners with
/// revision leases or pinned descriptors answer whether plan inputs are current.
public struct PatchGenerationStubRevalidation: Sendable {
    public let sourcesCurrent: @Sendable (PatchGenerationMutationPlan) async -> Bool
    public let destinationCurrent: @Sendable (PatchGenerationMutationPlan) async -> Bool

    public init(
        sourcesCurrent: @escaping @Sendable (PatchGenerationMutationPlan) async -> Bool,
        destinationCurrent: @escaping @Sendable (PatchGenerationMutationPlan) async -> Bool
    ) {
        self.sourcesCurrent = sourcesCurrent
        self.destinationCurrent = destinationCurrent
    }

    public static var assumeCurrent: PatchGenerationStubRevalidation {
        PatchGenerationStubRevalidation(
            sourcesCurrent: { _ in true },
            destinationCurrent: { _ in true }
        )
    }

    public static var stale: PatchGenerationStubRevalidation {
        PatchGenerationStubRevalidation(
            sourcesCurrent: { _ in false },
            destinationCurrent: { _ in false }
        )
    }
}

public enum PatchGenerationStubDestinationSummary: Equatable, Hashable, Sendable {
    case clipboard
    case createNew
    case overwrite
    case append
}

/// Execution receipt. Construction performs no mutation; it echoes the exact
/// ordered plan the executor validated.
public struct PatchGenerationStubExecutorReceipt: Equatable, Sendable {
    public let sourceIDs: [PatchGenerationSourceID]
    public let style: PatchGenerationStyle
    public let contextLines: Int
    public let direction: PatchGenerationDirection
    public let destination: PatchGenerationStubDestinationSummary
    public let payloadByteCount: Int
    public let planSHA256: [UInt8]
    public let executorContract = PatchGenerationExecutorContract.required

    fileprivate init(
        sourceIDs: [PatchGenerationSourceID],
        style: PatchGenerationStyle,
        contextLines: Int,
        direction: PatchGenerationDirection,
        destination: PatchGenerationStubDestinationSummary,
        payloadByteCount: Int,
        planSHA256: [UInt8]
    ) {
        self.sourceIDs = sourceIDs
        self.style = style
        self.contextLines = contextLines
        self.direction = direction
        self.destination = destination
        self.payloadByteCount = payloadByteCount
        self.planSHA256 = planSHA256
    }
}

/// Plan-only stub executor: validates binding, authority, staleness, and
/// cancellation, then returns a pre-publication non-commit without mutating.
public struct PatchGenerationStubExecutor: PatchGenerationPlanExecutor {
    public let authority: PatchGenerationStubSandboxAuthority
    public let revalidation: PatchGenerationStubRevalidation

    public init(
        authority: PatchGenerationStubSandboxAuthority = PatchGenerationStubSandboxAuthority(),
        revalidation: PatchGenerationStubRevalidation = .assumeCurrent
    ) {
        self.authority = authority
        self.revalidation = revalidation
    }

    public func describe(_ plan: PatchGenerationMutationPlan) -> PatchGenerationStubExecutorReceipt {
        PatchGenerationStubExecutorReceipt(
            sourceIDs: plan.sources.map(\.id),
            style: plan.style,
            contextLines: plan.contextLines,
            direction: plan.direction,
            destination: summary(plan.destination),
            payloadByteCount: payloadBytes(plan.destination),
            planSHA256: plan.planSHA256
        )
    }

    public func execute(
        _ plan: PatchGenerationMutationPlan,
        session: PatchGenerationExecutionSession
    ) async -> PatchGenerationExecutionOutcome {
        if Task.isCancelled {
            return PatchGenerationExecutionOutcomeFactory.notCommittedBeforePublication(
                session: session,
                reason: .cancelled
            )
        }
        if let reason = structuralRejection(plan) {
            return PatchGenerationExecutionOutcomeFactory.notCommittedBeforePublication(
                session: session,
                reason: .rejected(reason)
            )
        }
        if let reason = bindingRejection(plan) {
            return PatchGenerationExecutionOutcomeFactory.notCommittedBeforePublication(
                session: session,
                reason: .rejected(reason)
            )
        }
        guard authority.authorizes(plan) else {
            return PatchGenerationExecutionOutcomeFactory.notCommittedBeforePublication(
                session: session,
                reason: .securityContractUnavailable
            )
        }
        guard await revalidation.sourcesCurrent(plan) else {
            return PatchGenerationExecutionOutcomeFactory.notCommittedBeforePublication(
                session: session,
                reason: .sourceChanged
            )
        }
        if Task.isCancelled {
            return PatchGenerationExecutionOutcomeFactory.notCommittedBeforePublication(
                session: session,
                reason: .cancelled
            )
        }
        guard await revalidation.destinationCurrent(plan) else {
            return PatchGenerationExecutionOutcomeFactory.notCommittedBeforePublication(
                session: session,
                reason: .destinationChanged
            )
        }
        if Task.isCancelled {
            return PatchGenerationExecutionOutcomeFactory.notCommittedBeforePublication(
                session: session,
                reason: .cancelled
            )
        }
        // Never begins publication: no filesystem, pasteboard, UI, or process mutation.
        return PatchGenerationExecutionOutcomeFactory.notCommittedBeforePublication(
            session: session,
            reason: .rejected("Stub executor performs no filesystem, pasteboard, or UI mutation.")
        )
    }

    private func summary(
        _ destination: PatchGenerationPlannedDestination
    ) -> PatchGenerationStubDestinationSummary {
        switch destination {
        case .clipboard:
            return .clipboard
        case .file(let file):
            switch file.operation {
            case .createNew:
                return .createNew
            case .overwrite:
                return .overwrite
            case .append:
                return .append
            }
        }
    }

    private func payloadBytes(_ destination: PatchGenerationPlannedDestination) -> Int {
        switch destination {
        case .clipboard(_, let text):
            return text.utf8.count
        case .file(let file):
            return file.payload.count
        }
    }

    private func structuralRejection(_ plan: PatchGenerationMutationPlan) -> String? {
        guard !plan.sources.isEmpty else {
            return "Stub executor requires at least one planned source."
        }
        guard plan.style == .unified else {
            return "Stub executor supports only unified style."
        }
        guard plan.contextLines >= 0 else {
            return "Stub executor requires non-negative context lines."
        }
        guard plan.generatedPatch.utf8.count == plan.generatedPatchUTF8ByteCount else {
            return "Stub executor found generated-patch bytes inconsistent with plan."
        }
        return nil
    }

    /// Exact string binding only: no URL resolution and no filesystem access.
    /// Sandbox scope is checked separately through `authority`.
    private func bindingRejection(_ plan: PatchGenerationMutationPlan) -> String? {
        guard case .file(let destination) = plan.destination else {
            return nil
        }
        guard !destination.url.hasDirectoryPath,
            !destination.url.lastPathComponent.isEmpty,
            !destination.url.lastPathComponent.contains("/")
        else {
            return "Stub executor requires a leaf file destination URL."
        }
        let parentPath = destination.url.deletingLastPathComponent().path(percentEncoded: false)
        switch destination.operation {
        case .createNew(let parent):
            guard parent.kind == .directory,
                parent.canonicalURL.path(percentEncoded: false) == parentPath
            else {
                return "Stub executor found create destination outside its bound parent identity."
            }
        case .overwrite(let parent, let expected), .append(let parent, let expected):
            guard parent.kind == .directory,
                parent.canonicalURL.path(percentEncoded: false) == parentPath,
                expected.identity.kind == .regularFile,
                expected.identity.canonicalURL.path(percentEncoded: false)
                    == destination.url.path(percentEncoded: false)
            else {
                return "Stub executor found replace destination outside its bound revision identity."
            }
        }
        return nil
    }
}
