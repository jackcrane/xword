//
//  CrosswordPuzzle.swift
//  xword
//

import Foundation

enum CrosswordDirection: String, CaseIterable, Hashable {
    case across
    case down

    var shortLabel: String {
        switch self {
        case .across:
            return "Across"
        case .down:
            return "Down"
        }
    }
}

struct CrosswordCoordinate: Hashable {
    let row: Int
    let column: Int
}

struct CrosswordCell: Hashable {
    let coordinate: CrosswordCoordinate
    let solution: String?
    let number: Int?
    let isCircled: Bool

    var isBlock: Bool {
        solution == nil
    }
}

struct CrosswordClue: Identifiable, Hashable {
    let direction: CrosswordDirection
    let number: Int
    let prompt: String
    let answer: String
    let cells: [CrosswordCoordinate]

    var id: String {
        "\(direction.rawValue)-\(number)"
    }

    var label: String {
        "\(number) \(direction.shortLabel)"
    }
}

struct CrosswordPuzzle {
    let title: String
    let width: Int
    let height: Int
    let grid: [[CrosswordCell]]
    let clues: [CrosswordClue]
    let cluesByID: [CrosswordClue.ID: CrosswordClue]
    let clueIDsByCoordinate: [CrosswordCoordinate: [CrosswordDirection: CrosswordClue.ID]]

    var acrossClues: [CrosswordClue] {
        clues.filter { $0.direction == .across }
    }

    var downClues: [CrosswordClue] {
        clues.filter { $0.direction == .down }
    }

    var playableCells: [CrosswordCell] {
        grid.flatMap { row in
            row.filter { !$0.isBlock }
        }
    }

    func cell(at coordinate: CrosswordCoordinate) -> CrosswordCell? {
        guard grid.indices.contains(coordinate.row) else {
            return nil
        }

        let row = grid[coordinate.row]
        guard row.indices.contains(coordinate.column) else {
            return nil
        }

        return row[coordinate.column]
    }

    func clue(at coordinate: CrosswordCoordinate, direction: CrosswordDirection) -> CrosswordClue? {
        guard let clueID = clueIDsByCoordinate[coordinate]?[direction] else {
            return nil
        }

        return cluesByID[clueID]
    }

    func directions(at coordinate: CrosswordCoordinate) -> [CrosswordDirection] {
        guard let mapping = clueIDsByCoordinate[coordinate] else {
            return []
        }

        let directions = Set(mapping.keys)
        return CrosswordDirection.allCases.filter { directions.contains($0) }
    }
}
