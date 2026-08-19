public struct ComparisonSnapshot: Equatable, Sendable {
    public let left: String
    public let right: String

    public init(left: String, right: String) {
        self.left = left
        self.right = right
    }

    public static func == (lhs: ComparisonSnapshot, rhs: ComparisonSnapshot) -> Bool {
        lhs.left.utf8.elementsEqual(rhs.left.utf8)
            && lhs.right.utf8.elementsEqual(rhs.right.utf8)
    }

    fileprivate var byteCount: Int {
        let (total, overflow) = left.utf8.count.addingReportingOverflow(right.utf8.count)
        return overflow ? .max : total
    }
}

public struct ComparisonHistory: Sendable {
    public private(set) var current: ComparisonSnapshot

    private let capacity: Int
    private let maximumBytes: Int
    private var undoStack: [ComparisonSnapshot] = []
    private var redoStack: [ComparisonSnapshot] = []

    public var canUndo: Bool { undoStack.last(where: { $0 != current }) != nil }
    public var canRedo: Bool { !redoStack.isEmpty }

    public init(
        current: ComparisonSnapshot,
        capacity: Int = 100,
        maximumBytes: Int = 128 * 1024 * 1024
    ) {
        precondition(capacity > 0, "History capacity must be positive")
        precondition(maximumBytes > 0, "History byte limit must be positive")
        self.current = current
        self.capacity = capacity
        self.maximumBytes = maximumBytes
    }

    @discardableResult
    public mutating func commit(_ snapshot: ComparisonSnapshot) -> Bool {
        guard snapshot != current else { return false }

        undoStack.append(current)
        current = snapshot
        redoStack.removeAll(keepingCapacity: true)
        trimHistory()
        return true
    }

    @discardableResult
    public mutating func replaceCurrent(_ snapshot: ComparisonSnapshot) -> Bool {
        guard snapshot != current else { return false }

        current = snapshot
        redoStack.removeAll(keepingCapacity: true)
        return true
    }

    public mutating func discardRedundantUndo() {
        while undoStack.last == current {
            undoStack.removeLast()
        }
    }

    public mutating func undo() -> ComparisonSnapshot? {
        discardRedundantUndo()
        guard let snapshot = undoStack.popLast() else { return nil }
        redoStack.append(current)
        current = snapshot
        trimHistory()
        return snapshot
    }

    public mutating func redo() -> ComparisonSnapshot? {
        guard let snapshot = redoStack.popLast() else { return nil }
        undoStack.append(current)
        current = snapshot
        trimHistory()
        return snapshot
    }

    public mutating func reset(to snapshot: ComparisonSnapshot) {
        current = snapshot
        undoStack.removeAll(keepingCapacity: true)
        redoStack.removeAll(keepingCapacity: true)
    }

    private mutating func trimHistory() {
        while undoStack.count > capacity {
            undoStack.removeFirst()
        }
        while redoStack.count > capacity {
            redoStack.removeFirst()
        }

        var retainedBytes = undoStack.reduce(0) { partial, snapshot in
            partial.addingClamped(snapshot.byteCount)
        }.addingClamped(redoStack.reduce(0) { partial, snapshot in
            partial.addingClamped(snapshot.byteCount)
        })
        while retainedBytes > maximumBytes {
            if !undoStack.isEmpty {
                retainedBytes -= undoStack.removeFirst().byteCount
            } else if !redoStack.isEmpty {
                retainedBytes -= redoStack.removeFirst().byteCount
            } else {
                break
            }
        }
    }
}

private extension Int {
    func addingClamped(_ other: Int) -> Int {
        let (result, overflow) = addingReportingOverflow(other)
        return overflow ? .max : result
    }
}
