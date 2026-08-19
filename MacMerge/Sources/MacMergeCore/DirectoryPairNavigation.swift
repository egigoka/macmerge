public enum DirectoryPairNavigationCommand: CaseIterable, Hashable, Sendable {
    case first
    case previous
    case next
    case last
}

public struct DirectoryPairNavigationCommandStates: Equatable, Sendable {
    public let first: Bool
    public let previous: Bool
    public let next: Bool
    public let last: Bool

    public init(first: Bool, previous: Bool, next: Bool, last: Bool) {
        self.first = first
        self.previous = previous
        self.next = next
        self.last = last
    }

    public subscript(command: DirectoryPairNavigationCommand) -> Bool {
        switch command {
        case .first:
            first
        case .previous:
            previous
        case .next:
            next
        case .last:
            last
        }
    }
}

public struct DirectoryPairNavigationOutcome: Equatable, Sendable {
    public let command: DirectoryPairNavigationCommand
    public let previousID: DirectoryResult.ID?
    public let selectedID: DirectoryResult.ID
    public let didWrap: Bool

    public init(
        command: DirectoryPairNavigationCommand,
        previousID: DirectoryResult.ID?,
        selectedID: DirectoryResult.ID,
        didWrap: Bool
    ) {
        self.command = command
        self.previousID = previousID
        self.selectedID = selectedID
        self.didWrap = didWrap
    }
}

/// Navigates file pairs in the exact order presented by `DirectoryResults.visibleResults`.
public struct DirectoryPairNavigator: Equatable, Sendable {
    public private(set) var visiblePairIDs: [DirectoryResult.ID]
    public private(set) var selectedID: DirectoryResult.ID?
    public var wrapsAtBoundaries: Bool

    public var currentID: DirectoryResult.ID? { selectedID }

    public var commandStates: DirectoryPairNavigationCommandStates {
        DirectoryPairNavigationCommandStates(
            first: destination(for: .first) != nil,
            previous: destination(for: .previous) != nil,
            next: destination(for: .next) != nil,
            last: destination(for: .last) != nil
        )
    }

    public var canMoveToFirst: Bool { commandStates.first }
    public var canMoveToPrevious: Bool { commandStates.previous }
    public var canMoveToNext: Bool { commandStates.next }
    public var canMoveToLast: Bool { commandStates.last }

    public init(
        results: DirectoryResults,
        selectedID: DirectoryResult.ID? = nil,
        wrap: Bool = false
    ) {
        let visiblePairIDs = Self.orderedOpenableIDs(in: results)
        self.visiblePairIDs = visiblePairIDs
        wrapsAtBoundaries = wrap

        let requestedID =
            selectedID.flatMap { requestedID in
                visiblePairIDs.contains(requestedID) ? requestedID : nil
            }
            ?? visiblePairIDs.first {
                results.selectedIDs.contains($0)
            }
        self.selectedID = requestedID
    }

    public func isEnabled(_ command: DirectoryPairNavigationCommand) -> Bool {
        commandStates[command]
    }

    /// Updates visible order while retaining the selected ID when possible.
    /// If that ID disappears, the result at its prior visible ordinal is selected,
    /// falling back to the new last result when the list shrinks.
    @discardableResult
    public mutating func update(with results: DirectoryResults) -> Bool {
        let previousSelection = selectedID
        let previousIndex = previousSelection.flatMap { visiblePairIDs.firstIndex(of: $0) }
        let updatedIDs = Self.orderedOpenableIDs(in: results)
        visiblePairIDs = updatedIDs

        if let previousSelection, updatedIDs.contains(previousSelection) {
            selectedID = previousSelection
        } else if let previousIndex, !updatedIDs.isEmpty {
            selectedID = updatedIDs[min(previousIndex, updatedIDs.count - 1)]
        } else {
            selectedID = updatedIDs.first { results.selectedIDs.contains($0) }
        }
        return selectedID != previousSelection
    }

    /// Selects only IDs that are currently visible and represent two regular files.
    @discardableResult
    public mutating func select(_ id: DirectoryResult.ID?) -> Bool {
        guard let id else {
            let changed = selectedID != nil
            selectedID = nil
            return changed
        }
        guard visiblePairIDs.contains(id) else { return false }
        let changed = selectedID != id
        selectedID = id
        return changed
    }

    @discardableResult
    public mutating func move(
        _ command: DirectoryPairNavigationCommand
    ) -> DirectoryPairNavigationOutcome? {
        guard let destination = destination(for: command) else { return nil }
        let previousID = selectedID
        selectedID = destination.id
        return DirectoryPairNavigationOutcome(
            command: command,
            previousID: previousID,
            selectedID: destination.id,
            didWrap: destination.didWrap
        )
    }

    @discardableResult
    public mutating func moveToFirst() -> DirectoryPairNavigationOutcome? {
        move(.first)
    }

    @discardableResult
    public mutating func moveToPrevious() -> DirectoryPairNavigationOutcome? {
        move(.previous)
    }

    @discardableResult
    public mutating func moveToNext() -> DirectoryPairNavigationOutcome? {
        move(.next)
    }

    @discardableResult
    public mutating func moveToLast() -> DirectoryPairNavigationOutcome? {
        move(.last)
    }

    public func selectedResult(in results: DirectoryResults) -> DirectoryResult? {
        guard let selectedID, visiblePairIDs.contains(selectedID) else { return nil }
        return results.visibleResults.first {
            $0.id == selectedID && $0.isOpenableFilePair
        }
    }

    private struct Destination {
        let id: DirectoryResult.ID
        let didWrap: Bool
    }

    private func destination(for command: DirectoryPairNavigationCommand) -> Destination? {
        switch command {
        case .first:
            guard let first = visiblePairIDs.first, first != selectedID else { return nil }
            return Destination(id: first, didWrap: false)
        case .last:
            guard let last = visiblePairIDs.last, last != selectedID else { return nil }
            return Destination(id: last, didWrap: false)
        case .previous:
            guard let selectedIndex else {
                return visiblePairIDs.last.map { Destination(id: $0, didWrap: false) }
            }
            if selectedIndex > 0 {
                return Destination(id: visiblePairIDs[selectedIndex - 1], didWrap: false)
            }
            guard wrapsAtBoundaries, visiblePairIDs.count > 1,
                let last = visiblePairIDs.last
            else {
                return nil
            }
            return Destination(id: last, didWrap: true)
        case .next:
            guard let selectedIndex else {
                return visiblePairIDs.first.map { Destination(id: $0, didWrap: false) }
            }
            if selectedIndex < visiblePairIDs.count - 1 {
                return Destination(id: visiblePairIDs[selectedIndex + 1], didWrap: false)
            }
            guard wrapsAtBoundaries, visiblePairIDs.count > 1,
                let first = visiblePairIDs.first
            else {
                return nil
            }
            return Destination(id: first, didWrap: true)
        }
    }

    private var selectedIndex: Int? {
        selectedID.flatMap { visiblePairIDs.firstIndex(of: $0) }
    }

    private static func orderedOpenableIDs(in results: DirectoryResults) -> [DirectoryResult.ID] {
        results.visibleResults.compactMap { result in
            result.isOpenableFilePair ? result.id : nil
        }
    }
}

public typealias DirectoryPairNavigation = DirectoryPairNavigator
