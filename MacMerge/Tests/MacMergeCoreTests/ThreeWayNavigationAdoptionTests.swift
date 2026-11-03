import MacMergeCore
import XCTest

final class ThreeWayNavigationAdoptionTests: XCTestCase {
    typealias Adoption = ThreeWayNavigationAdoption
    typealias Difference = ThreeWayDifferenceNavigationDifference
    typealias DifferenceType = ThreeWayDifferenceType
    typealias NavigationError = ThreeWayDifferenceNavigationError

    func testMakeIndexPreservesGenerationAndIdentity() throws {
        let differences = [
            difference(2, .panePair(.leftAndRight), 0..<3),
            difference(1, .panePair(.leftAndMiddle), 0..<4),
            difference(3, .oneSided(.rightOnly), 10..<11)
        ]
        let index = try Adoption.makeIndex(generation: 41, differences: differences)
        XCTAssertEqual(index.generation, 41)
        XCTAssertEqual(index.count, 3)
        XCTAssertEqual(index.targets.map(\.sourceID.rawValue), [2, 1, 3])
        for target in index.targets {
            XCTAssertEqual(target.generation, 41)
            XCTAssertEqual(target.id.generation, 41)
            XCTAssertEqual(target.id.sourceID, target.sourceID)
            XCTAssertEqual(target.id.type, target.type)
            XCTAssertEqual(target.id.rowRange, target.rowRange)
        }
        XCTAssertEqual(try Adoption.targets(in: index), index.targets)
    }

    func testFilterPerPanePair() throws {
        let index = try Adoption.makeIndex(generation: 1, differences: mixedDifferences())
        for pair in ThreeWayDifferencePanePair.allCases {
            let filter = Adoption.filter(for: pair)
            XCTAssertEqual(filter, .panePair(pair))
            let targets = try Adoption.targets(in: index, matching: filter)
            XCTAssertFalse(targets.isEmpty)
            XCTAssertTrue(targets.allSatisfy { $0.type == .panePair(pair) })
            XCTAssertEqual(
                targets.map(\.sourceID),
                index.targets.filter { $0.type == .panePair(pair) }.map(\.sourceID)
            )
        }
    }

    func testFilterPerOneSidedType() throws {
        let index = try Adoption.makeIndex(generation: 1, differences: mixedDifferences())
        for oneSided in ThreeWayOneSidedDifferenceType.allCases {
            let filter = Adoption.filter(for: oneSided)
            XCTAssertEqual(filter, .oneSided(oneSided))
            let targets = try Adoption.targets(in: index, matching: filter)
            XCTAssertEqual(targets.map(\.type), [.oneSided(oneSided)])
        }
    }

    func testFilterForTypesSetAndEmptySetThrows() throws {
        let index = try Adoption.makeIndex(generation: 1, differences: mixedDifferences())
        let wanted: Set<DifferenceType> = [.panePair(.leftAndRight), .oneSided(.rightOnly)]
        let filter = try Adoption.filter(forTypes: wanted)
        XCTAssertEqual(filter.types, wanted)
        XCTAssertEqual(
            try Adoption.targets(in: index, matching: filter).map(\.type),
            [.panePair(.leftAndRight), .oneSided(.rightOnly)]
        )
        assertNavigationError(.emptyFilter) {
            _ = try Adoption.filter(forTypes: [])
        }
    }

    func testResolveNeverWraps() throws {
        let index = try Adoption.makeIndex(
            generation: 7,
            differences: [
                difference(1, .panePair(.leftAndMiddle), 10..<12),
                difference(2, .panePair(.leftAndMiddle), 20..<22),
                difference(3, .panePair(.leftAndMiddle), 30..<32)
            ]
        )
        let firstContext = Adoption.Context(generation: 7, selectedTarget: index.targets[0])
        let lastContext = Adoption.Context(generation: 7, selectedTarget: index.targets[2])

        XCTAssertNil(try Adoption.previous(in: index, context: firstContext)?.id)
        XCTAssertNil(try Adoption.resolve(.previous, in: index, context: firstContext).target)
        XCTAssertFalse(try Adoption.isEnabled(.previous, in: index, context: firstContext))

        XCTAssertNil(try Adoption.next(in: index, context: lastContext)?.id)
        XCTAssertNil(try Adoption.resolve(.next, in: index, context: lastContext).target)
        XCTAssertFalse(try Adoption.isEnabled(.next, in: index, context: lastContext))

        XCTAssertEqual(try Adoption.first(in: index, context: lastContext), index.targets[0])
        XCTAssertEqual(try Adoption.last(in: index, context: firstContext), index.targets[2])
    }

    func testConvenienceAccessorsMatchResolve() throws {
        let index = try Adoption.makeIndex(generation: 7, differences: mixedDifferences())
        let context = Adoption.Context(
            generation: 7,
            selectedTarget: index.targets[2],
            currentTarget: index.targets[0],
            cursorRow: 0
        )
        for command in Adoption.Command.allCases {
            let resolution = try Adoption.resolve(command, in: index, context: context)
            XCTAssertEqual(resolution.command, command)
            XCTAssertEqual(resolution.expectedGeneration, 7)
            XCTAssertEqual(resolution.canExecute, resolution.target != nil)
            XCTAssertEqual(resolution.isEnabled, resolution.canExecute)
        }
        XCTAssertEqual(
            try Adoption.first(in: index, context: context),
            try Adoption.resolve(.first, in: index, context: context).target
        )
        XCTAssertEqual(
            try Adoption.current(in: index, context: context),
            try Adoption.resolve(.current, in: index, context: context).target
        )
        XCTAssertEqual(
            try Adoption.previous(in: index, context: context),
            try Adoption.resolve(.previous, in: index, context: context).target
        )
        XCTAssertEqual(
            try Adoption.next(in: index, context: context),
            try Adoption.resolve(.next, in: index, context: context).target
        )
        XCTAssertEqual(
            try Adoption.last(in: index, context: context),
            try Adoption.resolve(.last, in: index, context: context).target
        )
    }

    func testCommandStatesAndIsEnabledAgree() throws {
        let index = try Adoption.makeIndex(generation: 3, differences: mixedDifferences())
        let midContext = Adoption.Context(generation: 3, selectedTarget: index.targets[2])
        let states = try Adoption.commandStates(in: index, context: midContext)
        for command in Adoption.Command.allCases {
            XCTAssertEqual(
                states[command],
                try Adoption.isEnabled(command, in: index, context: midContext),
                "\(command)"
            )
        }
        XCTAssertEqual(
            states,
            Adoption.States(first: true, current: true, previous: true, next: true, last: true)
        )

        let empty = try Adoption.makeIndex(generation: 3, differences: [])
        let emptyContext = Adoption.Context(generation: 3)
        let emptyStates = try Adoption.commandStates(in: empty, context: emptyContext)
        XCTAssertEqual(
            emptyStates,
            Adoption.States(
                first: false, current: false, previous: false, next: false, last: false
            )
        )
        for command in Adoption.Command.allCases {
            XCTAssertFalse(try Adoption.isEnabled(command, in: empty, context: emptyContext))
        }
    }

    func testErrorPropagation() throws {
        assertNavigationError(.invalidLimits) {
            _ = try Adoption.makeIndex(
                generation: 1,
                differences: [],
                limits: Adoption.Limits(maximumRows: -1)
            )
        }
        assertNavigationError(.tooManyDifferences(maximum: 1)) {
            _ = try Adoption.makeIndex(
                generation: 1,
                differences: [
                    difference(1, .panePair(.leftAndMiddle), 0..<1),
                    difference(2, .panePair(.leftAndMiddle), 2..<3)
                ],
                limits: Adoption.Limits(maximumDifferences: 1)
            )
        }
        assertNavigationError(
            .invalidRowRange(id: .init(rawValue: 9), range: 5..<5, maximumRows: Adoption.Limits.default.maximumRows)
        ) {
            _ = try Adoption.makeIndex(
                generation: 1,
                differences: [difference(9, .panePair(.leftAndMiddle), 5..<5)]
            )
        }
        assertNavigationError(.duplicateDifferenceID(.init(rawValue: 42))) {
            _ = try Adoption.makeIndex(
                generation: 1,
                differences: [
                    difference(42, .panePair(.leftAndMiddle), 0..<1),
                    difference(42, .panePair(.leftAndMiddle), 2..<3)
                ]
            )
        }
        assertNavigationError(
            .overlappingDifferences(
                type: .panePair(.leftAndMiddle),
                first: .init(rawValue: 1),
                second: .init(rawValue: 2)
            )
        ) {
            _ = try Adoption.makeIndex(
                generation: 1,
                differences: [
                    difference(1, .panePair(.leftAndMiddle), 0..<4),
                    difference(2, .panePair(.leftAndMiddle), 2..<3)
                ]
            )
        }
        assertNavigationError(.workLimitExceeded(maximumWork: 0)) {
            _ = try Adoption.makeIndex(
                generation: 1,
                differences: [difference(1, .panePair(.leftAndMiddle), 0..<1)],
                limits: Adoption.Limits(maximumWork: 0)
            )
        }

        let index = try Adoption.makeIndex(generation: 12, differences: mixedDifferences())
        assertNavigationError(.staleGeneration(expected: 12, actual: 11)) {
            _ = try Adoption.resolve(.first, in: index, context: Adoption.Context(generation: 11))
        }
        assertNavigationError(.staleGeneration(expected: 12, actual: 11)) {
            _ = try Adoption.commandStates(in: index, context: Adoption.Context(generation: 11))
        }
        assertNavigationError(.staleGeneration(expected: 12, actual: 11)) {
            _ = try Adoption.first(in: index, context: Adoption.Context(generation: 11))
        }

        let other = try Adoption.makeIndex(
            generation: 12,
            differences: [difference(99, .panePair(.leftAndMiddle), 0..<1)]
        )
        let missing = try XCTUnwrap(other.first)
        XCTAssertNil(index.target(withID: missing.id))
        let staleContext = Adoption.Context(generation: 12, selectedTarget: missing)
        assertNavigationError(.staleIdentity(role: .selected, id: missing.id)) {
            _ = try Adoption.resolve(.next, in: index, context: staleContext)
        }
        assertNavigationError(.staleIdentity(role: .selected, id: missing.id)) {
            _ = try Adoption.commandStates(in: index, context: staleContext)
        }
    }

    func testCancellationStopsEveryEntryPoint() async {
        let differences = [difference(1, .oneSided(.leftOnly), 0..<1)]
        let limits = Adoption.Limits(
            maximumRows: 1,
            maximumDifferences: 1,
            maximumWork: 10,
            cancellationCheckInterval: 1
        )
        let index = try? Adoption.makeIndex(generation: 14, differences: differences, limits: limits)
        guard let index else {
            XCTFail("fixture index failed")
            return
        }
        let context = Adoption.Context(generation: 14)

        let errors = await Task { () -> [NavigationError?] in
            withUnsafeCurrentTask { $0?.cancel() }
            var errors: [NavigationError?] = []
            do {
                _ = try Adoption.makeIndex(
                    generation: 14, differences: differences, limits: limits
                )
                errors.append(nil)
            } catch {
                errors.append(error as? NavigationError)
            }
            do {
                _ = try Adoption.targets(in: index)
                errors.append(nil)
            } catch {
                errors.append(error as? NavigationError)
            }
            do {
                _ = try Adoption.resolve(.first, in: index, context: context)
                errors.append(nil)
            } catch {
                errors.append(error as? NavigationError)
            }
            do {
                _ = try Adoption.commandStates(in: index, context: context)
                errors.append(nil)
            } catch {
                errors.append(error as? NavigationError)
            }
            return errors
        }.value

        XCTAssertEqual(errors, [.cancelled, .cancelled, .cancelled, .cancelled])
    }

    private func mixedDifferences() -> [Difference] {
        [
            difference(1, .panePair(.leftAndMiddle), 0..<1),
            difference(2, .panePair(.leftAndRight), 2..<3),
            difference(3, .panePair(.middleAndRight), 4..<5),
            difference(4, .oneSided(.leftOnly), 6..<7),
            difference(5, .oneSided(.middleOnly), 8..<9),
            difference(6, .oneSided(.rightOnly), 10..<11)
        ]
    }

    private func difference(
        _ id: UInt64,
        _ type: DifferenceType,
        _ rowRange: Range<Int>
    ) -> Difference {
        Difference(id: id, type: type, rowRange: rowRange)
    }

    private func assertNavigationError(
        _ expected: NavigationError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? NavigationError, expected, file: file, line: line)
        }
    }
}
