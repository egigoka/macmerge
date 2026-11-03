import Foundation

/// UI-independent binding plan from a resolved syntax scheme to renderer-ready token spans.
///
/// This is planning groundwork only: it maps built-in/custom scheme metadata plus the
/// selection/fallback outcome in `SyntaxSchemeResolution` to strict token-color roles,
/// resolves each role through an existing `EditorColorPalette`, validates contrast, and
/// attaches a non-color fallback cue wherever color alone is insufficient. It performs no
/// AppKit/SwiftUI rendering and claims no menu or settings adoption.
public struct SyntaxRendererBindingLimits: Hashable, Sendable {
    public static let hardMaximumSpanCount = 1_000_000
    public static let hardMaximumWorkUnits = 64 * 1_024 * 1_024
    public static let hardMaximumCancellationCheckInterval = 4_096

    public static let `default` = SyntaxRendererBindingLimits(
        maximumSpanCount: 1_000_000,
        maximumWorkUnits: 64 * 1_024 * 1_024,
        cancellationCheckInterval: 64,
        validated: ()
    )

    public let maximumSpanCount: Int
    public let maximumWorkUnits: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumSpanCount: Int = 1_000_000,
        maximumWorkUnits: Int = 64 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 64
    ) throws {
        self.init(
            maximumSpanCount: maximumSpanCount,
            maximumWorkUnits: maximumWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval,
            validated: ()
        )
        try validate()
    }

    fileprivate func validate() throws {
        guard (1...Self.hardMaximumSpanCount).contains(maximumSpanCount),
            (1...Self.hardMaximumWorkUnits).contains(maximumWorkUnits),
            (1...Self.hardMaximumCancellationCheckInterval).contains(cancellationCheckInterval)
        else {
            throw SyntaxRendererBindingError.invalidLimits
        }
    }

    private init(
        maximumSpanCount: Int,
        maximumWorkUnits: Int,
        cancellationCheckInterval: Int,
        validated: Void
    ) {
        self.maximumSpanCount = maximumSpanCount
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum SyntaxRendererBindingError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimits
    case tooManySpans(maximum: Int)
    case unorderedOrOverlappingTokens
    case incompletePalette
    case workLimitExceeded(maximumWorkUnits: Int)
    case staleCatalog(
        expected: SyntaxSchemeCatalogRevision,
        actual: SyntaxSchemeCatalogRevision
    )
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Syntax renderer binding limits are invalid."
        case .tooManySpans(let maximum):
            "Syntax renderer binding exceeds the \(maximum)-span limit."
        case .unorderedOrOverlappingTokens:
            "Syntax tokens are not in strictly increasing, non-overlapping order."
        case .incompletePalette:
            "Editor palette is missing a color required for syntax binding."
        case .workLimitExceeded(let maximumWorkUnits):
            "Syntax renderer binding exceeds the \(maximumWorkUnits)-unit work limit."
        case .staleCatalog:
            "Syntax renderer binding belongs to a stale catalog snapshot."
        case .cancelled:
            "Syntax renderer binding was cancelled."
        }
    }
}

/// Abstract non-color geometry a renderer draws when a token's color contrast is insufficient.
///
/// Each token kind maps to a distinct cue, so failed spans remain distinguishable without
/// relying on color perception. Renderers draw the cue only when `SyntaxRendererSpan.cue`
/// is not `none`; the concrete stroke style remains renderer-owned.
public enum SyntaxTokenNonColorCue: String, CaseIterable, Hashable, Sendable {
    case none
    case underline
    case doubleUnderline
    case dashedUnderline
    case outline
    case dashedOutline
    case doubleOutline
    case strikethrough
    case overline
    case boxed
}

extension SyntaxTokenKind {
    /// Distinct fallback cue used only when this kind's color contrast fails.
    public var insufficientContrastCue: SyntaxTokenNonColorCue {
        switch self {
        case .keyword: .underline
        case .string: .doubleUnderline
        case .comment: .dashedUnderline
        case .number: .outline
        case .literal: .dashedOutline
        case .heading: .doubleOutline
        case .emphasis: .strikethrough
        case .code: .overline
        case .link: .boxed
        }
    }
}

/// One highlight token bound to its strict color role, resolved color, and fallback cue.
public struct SyntaxRendererSpan: Hashable, Sendable {
    public let tokenKind: SyntaxTokenKind
    public let range: NSRange
    public let colorRole: EditorColorRole
    public let color: EditorColorComponents
    /// `true` when the kind's role had no palette entry and plain-text foreground was used.
    public let didFallBackToPlainTextColor: Bool
    public let contrastRatio: Double
    public let meetsContrast: Bool
    /// `.none` when contrast passes; otherwise the kind's distinct fallback geometry.
    public let cue: SyntaxTokenNonColorCue

    public init(
        tokenKind: SyntaxTokenKind,
        range: NSRange,
        colorRole: EditorColorRole,
        color: EditorColorComponents,
        didFallBackToPlainTextColor: Bool,
        contrastRatio: Double,
        meetsContrast: Bool,
        cue: SyntaxTokenNonColorCue
    ) {
        self.tokenKind = tokenKind
        self.range = range
        self.colorRole = colorRole
        self.color = color
        self.didFallBackToPlainTextColor = didFallBackToPlainTextColor
        self.contrastRatio = contrastRatio
        self.meetsContrast = meetsContrast
        self.cue = cue
    }
}

/// Renderer-ready binding of one `SyntaxSchemeResolution` plus highlight tokens.
///
/// Scheme metadata stays redacted in reflection, matching `SyntaxSchemeResolution`.
public struct SyntaxRendererBindingPlan:
    Hashable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let resolution: SyntaxSchemeResolution
    public let variant: EditorColorSchemeVariant
    public let background: EditorColorComponents
    public let spans: [SyntaxRendererSpan]
    /// Palette contrast failures restricted to syntax roles on the bound background.
    public let contrastIssues: [EditorContrastIssue]

    public var schemeIdentifier: SyntaxSchemeIdentifier { resolution.scheme.id }

    public var schemeOrigin: SyntaxSchemeOrigin { resolution.scheme.origin }

    public var source: SyntaxSchemeResolutionSource { resolution.source }

    /// `true` when any span needed a non-color cue or a plain-text color fallback.
    public var requiresNonColorFallback: Bool {
        spans.contains { $0.cue != .none || $0.didFallBackToPlainTextColor }
    }

    public var description: String {
        "SyntaxRendererBindingPlan(source: \(source.rawValue), spans: \(spans.count), bindings: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "source": source.rawValue,
                "spanCount": spans.count,
                "contrastIssueCount": contrastIssues.count,
                "bindings": "<redacted>"
            ],
            displayStyle: .struct
        )
    }

    public func isCurrent(in catalog: SyntaxSchemeCatalog) throws -> Bool {
        try resolution.isCurrent(in: catalog)
    }

    public func validate(against catalog: SyntaxSchemeCatalog) throws {
        do {
            try resolution.validate(against: catalog)
        } catch let error as SyntaxSchemeCatalogError {
            switch error {
            case .staleCatalog(let expected, let actual):
                throw SyntaxRendererBindingError.staleCatalog(
                    expected: expected,
                    actual: actual
                )
            case .cancelled:
                throw SyntaxRendererBindingError.cancelled
            default:
                throw error
            }
        }
    }
}

/// Plans renderer bindings without touching UI, menus, or settings storage.
public enum SyntaxRendererBindingPlanner: Sendable {
    /// Binds highlight tokens to palette colors through the resolved scheme's token-color roles.
    ///
    /// Validates the resolution against `catalog` first, so stale snapshots fail before any
    /// per-token work. Contrast is measured per span against the opaque `textBackground`;
    /// failing spans keep their color and gain their kind's distinct non-color cue.
    public static func bind(
        _ resolution: SyntaxSchemeResolution,
        tokens: [SyntaxToken],
        palette: EditorColorPalette,
        in catalog: SyntaxSchemeCatalog,
        standards: EditorContrastStandards = .default,
        limits: SyntaxRendererBindingLimits = .default
    ) throws -> SyntaxRendererBindingPlan {
        try limits.validate()
        try SyntaxRendererBindingValidation.checkCancellation()
        do {
            try resolution.validate(against: catalog)
        } catch let error as SyntaxSchemeCatalogError {
            switch error {
            case .staleCatalog(let expected, let actual):
                throw SyntaxRendererBindingError.staleCatalog(
                    expected: expected,
                    actual: actual
                )
            case .cancelled:
                throw SyntaxRendererBindingError.cancelled
            default:
                throw error
            }
        }
        guard tokens.count <= limits.maximumSpanCount else {
            throw SyntaxRendererBindingError.tooManySpans(maximum: limits.maximumSpanCount)
        }
        guard let background = palette.color(for: .textBackground), background.alpha == 1 else {
            throw SyntaxRendererBindingError.incompletePalette
        }
        guard let plainTextColor = palette.color(for: .textForeground) else {
            throw SyntaxRendererBindingError.incompletePalette
        }
        let minimumRatio =
            palette.variant.isHighContrast ? standards.enhancedText : standards.normalText
        var budget = SyntaxRendererBindingWorkBudget(limits: limits)
        var spans: [SyntaxRendererSpan] = []
        spans.reserveCapacity(min(tokens.count, 4_096))
        var contrastIssues: [EditorContrastIssue] = []
        var reportedContrastRoles = Set<EditorColorRole>()
        var previousEnd = 0
        for token in tokens {
            try budget.consume()
            guard token.range.location != NSNotFound,
                token.range.length >= 0,
                token.range.location >= previousEnd
            else {
                throw SyntaxRendererBindingError.unorderedOrOverlappingTokens
            }
            let end = token.range.location.addingReportingOverflow(token.range.length)
            guard !end.overflow else {
                throw SyntaxRendererBindingError.unorderedOrOverlappingTokens
            }
            previousEnd = end.partialValue
            let role = token.kind.editorColorRole
            let resolved = palette.color(for: role)
            let color = resolved ?? plainTextColor
            let effective = color.composited(over: background)
            let ratio = effective.contrastRatio(with: background)
            let meets = ratio >= minimumRatio
            if !meets, reportedContrastRoles.insert(role).inserted {
                contrastIssues.append(
                    EditorContrastIssue(
                        variant: palette.variant,
                        // Reports token role, not plain-text fallback role.
                        foregroundRole: role,
                        backgroundRole: .textBackground,
                        actualRatio: ratio,
                        minimumRatio: minimumRatio
                    )
                )
            }
            spans.append(
                SyntaxRendererSpan(
                    tokenKind: token.kind,
                    range: token.range,
                    colorRole: role,
                    color: color,
                    didFallBackToPlainTextColor: resolved == nil,
                    contrastRatio: ratio,
                    meetsContrast: meets,
                    cue: meets ? .none : token.kind.insufficientContrastCue
                )
            )
        }
        try SyntaxRendererBindingValidation.checkCancellation()
        return SyntaxRendererBindingPlan(
            resolution: resolution,
            variant: palette.variant,
            background: background,
            spans: spans,
            contrastIssues: contrastIssues
        )
    }
}

private enum SyntaxRendererBindingValidation {
    static func checkCancellation() throws {
        if Task.isCancelled { throw SyntaxRendererBindingError.cancelled }
    }
}

private struct SyntaxRendererBindingWorkBudget {
    let limits: SyntaxRendererBindingLimits
    private(set) var consumed = 0

    init(limits: SyntaxRendererBindingLimits) {
        self.limits = limits
    }

    mutating func consume(_ amount: Int = 1) throws {
        guard amount >= 0 else {
            throw SyntaxRendererBindingError.workLimitExceeded(
                maximumWorkUnits: limits.maximumWorkUnits
            )
        }
        let addition = consumed.addingReportingOverflow(amount)
        guard !addition.overflow, addition.partialValue <= limits.maximumWorkUnits else {
            throw SyntaxRendererBindingError.workLimitExceeded(
                maximumWorkUnits: limits.maximumWorkUnits
            )
        }
        let previous = consumed
        consumed = addition.partialValue
        if previous / limits.cancellationCheckInterval
            != consumed / limits.cancellationCheckInterval
        {
            try SyntaxRendererBindingValidation.checkCancellation()
        }
    }
}
