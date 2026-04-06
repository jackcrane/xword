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

    private func sampleURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: relativePath)
    }
}
