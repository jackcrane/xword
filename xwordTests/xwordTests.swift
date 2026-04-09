//
//  xwordTests.swift
//  xwordTests
//

import Foundation
import Testing
@testable import xword

struct xwordTests {
    private let parser = CrosswordParser()

    @Test func parsesStandardPuzzle() throws {
        let contents = try String(contentsOf: sampleURL("xword/Resources/data/wsj/2018/wsj2018-03-02.xd"), encoding: .utf8)
        let puzzle = try parser.parse(contents: contents)

        #expect(puzzle.title == "Mess Kit")
        #expect(puzzle.width == 15)
        #expect(puzzle.height == 15)
        #expect(puzzle.acrossClues.count == 38)
        #expect(puzzle.downClues.count == 39)
        #expect(puzzle.clue(at: CrosswordCoordinate(row: 0, column: 0), direction: .across)?.prompt == "Ball brand since 1970")
    }

    @Test func preservesCircledCellsAndSymbols() throws {
        let contents = try String(contentsOf: sampleURL("xword/Resources/data/nytimes/2005/nyt2005-04-10.xd"), encoding: .utf8)
        let puzzle = try parser.parse(contents: contents)
        let symbolCell = try #require(puzzle.cell(at: CrosswordCoordinate(row: 11, column: 10)))

        #expect(symbolCell.solution == "=")

        let circledContents = try String(contentsOf: sampleURL("xword/Resources/data/latimes/2024/lat2024-01-01.xd"), encoding: .utf8)
        let circledPuzzle = try parser.parse(contents: circledContents)
        let circledCell = try #require(circledPuzzle.cell(at: CrosswordCoordinate(row: 3, column: 1)))

        #expect(circledCell.isCircled)
        #expect(circledPuzzle.clue(at: CrosswordCoordinate(row: 3, column: 0), direction: .across)?.answer == "PAYRESPECTTO")
    }

    @Test func allowsPuzzlesSmallerThanMaximumGridDimension() throws {
        let puzzle = try parser.parse(contents: """
        Title: Tiny Puzzle
        Author: Tests
        Date: 2026-04-08


        SUN
        ERA
        NET


        A1. Bright day source ~ SUN
        A4. Historical period ~ ERA
        A5. Mesh material ~ NET
        D1. Preview down clue ~ SEN
        D2. Uncertain sound ~ URE
        D3. Park service shorthand ~ NAT
        """)

        #expect(puzzle.width == 3)
        #expect(puzzle.height == 3)
        #expect(CrosswordSettings.supports(puzzle))
    }

    @Test func rejectsPuzzlesLargerThanMaximumGridDimension() throws {
        let oversizedWidth = CrosswordSettings.maximumGridDimension + 1
        let oversizedRow = "A" + String(repeating: "#", count: oversizedWidth - 1)
        let oversized = try parser.parse(contents: """
        Title: Oversized
        Author: Tests
        Date: 2026-04-08


        \(oversizedRow)


        A1. Oversized row start ~ A
        D1. First oversized column ~ A
        """)

        #expect(!CrosswordSettings.supports(oversized))
    }

    @MainActor
    @Test func nextClueMovesFromFinalAcrossToFirstDown() throws {
        let puzzle = try parser.parse(contents: """
        Title: Tiny Puzzle
        Author: Tests
        Date: 2026-04-08


        SUN
        ERA
        NET


        A1. Bright day source ~ SUN
        A4. Historical period ~ ERA
        A5. Mesh material ~ NET
        D1. Preview down clue ~ SEN
        D2. Uncertain sound ~ URE
        D3. Park service shorthand ~ NAT
        """)

        let game = CrosswordGame(
            puzzle: puzzle,
            entries: [:],
            selectedCell: CrosswordCoordinate(row: 2, column: 0),
            selectedDirection: .across
        )

        game.selectNextClue()

        #expect(game.currentClue?.id == "down-1")
        #expect(game.selectedCell == CrosswordCoordinate(row: 0, column: 0))
    }

    @MainActor
    @Test func nextClueMovesFromFinalDownToFirstAcross() throws {
        let puzzle = try parser.parse(contents: """
        Title: Tiny Puzzle
        Author: Tests
        Date: 2026-04-08


        SUN
        ERA
        NET


        A1. Bright day source ~ SUN
        A4. Historical period ~ ERA
        A5. Mesh material ~ NET
        D1. Preview down clue ~ SEN
        D2. Uncertain sound ~ URE
        D3. Park service shorthand ~ NAT
        """)

        let game = CrosswordGame(
            puzzle: puzzle,
            entries: [:],
            selectedCell: CrosswordCoordinate(row: 0, column: 2),
            selectedDirection: .down
        )

        game.selectNextClue()

        #expect(game.currentClue?.id == "across-1")
        #expect(game.selectedCell == CrosswordCoordinate(row: 0, column: 0))
    }

    @MainActor
    @Test func previousClueMovesFromFirstDownToFinalAcross() throws {
        let puzzle = try parser.parse(contents: """
        Title: Tiny Puzzle
        Author: Tests
        Date: 2026-04-08


        SUN
        ERA
        NET


        A1. Bright day source ~ SUN
        A4. Historical period ~ ERA
        A5. Mesh material ~ NET
        D1. Preview down clue ~ SEN
        D2. Uncertain sound ~ URE
        D3. Park service shorthand ~ NAT
        """)

        let game = CrosswordGame(
            puzzle: puzzle,
            entries: [:],
            selectedCell: CrosswordCoordinate(row: 0, column: 0),
            selectedDirection: .down
        )

        game.selectPreviousClue()

        #expect(game.currentClue?.id == "across-5")
        #expect(game.selectedCell == CrosswordCoordinate(row: 2, column: 0))
    }

    @MainActor
    @Test func solvePuzzleFillsAllEntriesWithSolutions() throws {
        let puzzle = try parser.parse(contents: """
        Title: Tiny Puzzle
        Author: Tests
        Date: 2026-04-08


        SUN
        ERA
        NET


        A1. Bright day source ~ SUN
        A4. Historical period ~ ERA
        A5. Mesh material ~ NET
        D1. Preview down clue ~ SEN
        D2. Uncertain sound ~ URE
        D3. Park service shorthand ~ NAT
        """)

        let game = CrosswordGame(puzzle: puzzle, entries: [:])

        game.solvePuzzle()

        for cell in puzzle.playableCells {
            #expect(game.entry(for: cell.coordinate) == cell.solution)
        }
    }

    @MainActor
    @Test func remoteFinalEntryShowsCompletionSheet() throws {
        let puzzle = try parser.parse(contents: """
        Title: Tiny Puzzle
        Author: Tests
        Date: 2026-04-08


        SUN
        ERA
        NET


        A1. Bright day source ~ SUN
        A4. Historical period ~ ERA
        A5. Mesh material ~ NET
        D1. Preview down clue ~ SEN
        D2. Uncertain sound ~ URE
        D3. Park service shorthand ~ NAT
        """)

        let almostSolvedEntries = Dictionary(uniqueKeysWithValues: puzzle.playableCells.map { cell in
            let value = cell.coordinate == CrosswordCoordinate(row: 2, column: 2) ? "" : (cell.solution ?? "")
            return (cell.coordinate, value)
        })
        let game = CrosswordGame(puzzle: puzzle, entries: almostSolvedEntries)

        game.relayClient(
            MultiplayerRelayClient(),
            didReceive: .relayed(
                fromPlayerID: "remote-player",
                event: .entryUpdated(MultiplayerEntrySnapshot(coordinate: CrosswordCoordinate(row: 2, column: 2), value: "T"))
            )
        )

        #expect(game.isShowingCompletionSheet)
    }

    @MainActor
    @Test func solvedRemoteSnapshotShowsCompletionSheet() throws {
        let puzzle = try parser.parse(contents: """
        Title: Tiny Puzzle
        Author: Tests
        Date: 2026-04-08


        SUN
        ERA
        NET


        A1. Bright day source ~ SUN
        A4. Historical period ~ ERA
        A5. Mesh material ~ NET
        D1. Preview down clue ~ SEN
        D2. Uncertain sound ~ URE
        D3. Park service shorthand ~ NAT
        """)

        let game = CrosswordGame(puzzle: puzzle, entries: [:])
        let snapshot = MultiplayerStateSnapshot(
            puzzleID: puzzle.sourceID,
            entries: puzzle.playableCells.map { cell in
                MultiplayerEntrySnapshot(coordinate: cell.coordinate, value: cell.solution ?? "")
            },
            selection: MultiplayerSelection(coordinate: CrosswordCoordinate(row: 0, column: 0), direction: .across)
        )

        game.relayClient(
            MultiplayerRelayClient(),
            didReceive: .relayed(
                fromPlayerID: "remote-player",
                event: .stateSnapshot(snapshot)
            )
        )

        #expect(game.isShowingCompletionSheet)
    }

    private func sampleURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: relativePath)
    }
}
