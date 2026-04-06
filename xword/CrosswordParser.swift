//
//  CrosswordParser.swift
//  xword
//

import Foundation

enum CrosswordParserError: LocalizedError {
    case missingTitle
    case missingGrid
    case inconsistentGrid
    case malformedClue(String)
    case missingClueDefinition(CrosswordDirection, Int)

    var errorDescription: String? {
        switch self {
        case .missingTitle:
            return "The crossword is missing a title."
        case .missingGrid:
            return "The crossword grid could not be found."
        case .inconsistentGrid:
            return "The crossword grid rows are inconsistent."
        case let .malformedClue(line):
            return "Malformed clue line: \(line)"
        case let .missingClueDefinition(direction, number):
            return "Missing \(direction.shortLabel.lowercased()) clue \(number)."
        }
    }
}

struct CrosswordParser {
    func parse(contents: String) throws -> CrosswordPuzzle {
        let normalized = contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var index = 0
        var metadata: [String: String] = [:]

        while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            let line = lines[index]
            if let separator = line.firstIndex(of: ":") {
                let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                metadata[key] = value
            }
            index += 1
        }

        guard let title = metadata["Title"], !title.isEmpty else {
            throw CrosswordParserError.missingTitle
        }

        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            index += 1
        }

        var rawGrid: [[Character]] = []
        while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            rawGrid.append(Array(lines[index]))
            index += 1
        }

        guard let width = rawGrid.first?.count, width > 0 else {
            throw CrosswordParserError.missingGrid
        }

        guard rawGrid.allSatisfy({ $0.count == width }) else {
            throw CrosswordParserError.inconsistentGrid
        }

        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            index += 1
        }

        var clueDefinitions: [CrosswordDirection: [Int: (prompt: String, answer: String)]] = [:]

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            index += 1

            guard !line.isEmpty else {
                continue
            }

            let pattern = /^([AD])(\d+)\.\s*(.*)\s~\s(.+)$/
            guard let match = line.wholeMatch(of: pattern) else {
                throw CrosswordParserError.malformedClue(line)
            }

            let direction = match.1 == "A" ? CrosswordDirection.across : .down
            let number = Int(match.2) ?? 0
            let prompt = String(match.3).trimmingCharacters(in: .whitespaces)
            let answer = normalizeSolution(String(match.4))

            clueDefinitions[direction, default: [:]][number] = (prompt, answer)
        }

        let height = rawGrid.count
        var grid: [[CrosswordCell]] = Array(
            repeating: Array(
                repeating: CrosswordCell(
                    coordinate: CrosswordCoordinate(row: 0, column: 0),
                    solution: nil,
                    number: nil,
                    isCircled: false
                ),
                count: width
            ),
            count: height
        )
        var clues: [CrosswordClue] = []
        var cluesByID: [CrosswordClue.ID: CrosswordClue] = [:]
        var clueIDsByCoordinate: [CrosswordCoordinate: [CrosswordDirection: CrosswordClue.ID]] = [:]
        var nextNumber = 1

        for row in 0..<height {
            for column in 0..<width {
                let rawCharacter = rawGrid[row][column]
                let coordinate = CrosswordCoordinate(row: row, column: column)

                if rawCharacter == "#" {
                    grid[row][column] = CrosswordCell(
                        coordinate: coordinate,
                        solution: nil,
                        number: nil,
                        isCircled: false
                    )
                    continue
                }

                let solution = normalizeSolution(String(rawCharacter))
                let startsAcross = column == 0 || rawGrid[row][column - 1] == "#"
                let startsDown = row == 0 || rawGrid[row - 1][column] == "#"
                let clueNumber = (startsAcross || startsDown) ? nextNumber : nil

                grid[row][column] = CrosswordCell(
                    coordinate: coordinate,
                    solution: solution,
                    number: clueNumber,
                    isCircled: rawCharacter.isLetter && String(rawCharacter) != solution
                )

                if let clueNumber {
                    if startsAcross {
                        let cells = collectAcrossCells(from: coordinate, rawGrid: rawGrid)
                        let definition = try clueDefinition(
                            for: .across,
                            number: clueNumber,
                            clueDefinitions: clueDefinitions
                        )
                        let clue = CrosswordClue(
                            direction: .across,
                            number: clueNumber,
                            prompt: definition.prompt,
                            answer: cells.compactMap { cellCoordinate in
                                gridValue(at: cellCoordinate, rawGrid: rawGrid)
                            }.joined(),
                            cells: cells
                        )
                        clues.append(clue)
                        cluesByID[clue.id] = clue
                        for cell in cells {
                            clueIDsByCoordinate[cell, default: [:]][.across] = clue.id
                        }
                    }

                    if startsDown {
                        let cells = collectDownCells(from: coordinate, rawGrid: rawGrid)
                        let definition = try clueDefinition(
                            for: .down,
                            number: clueNumber,
                            clueDefinitions: clueDefinitions
                        )
                        let clue = CrosswordClue(
                            direction: .down,
                            number: clueNumber,
                            prompt: definition.prompt,
                            answer: cells.compactMap { cellCoordinate in
                                gridValue(at: cellCoordinate, rawGrid: rawGrid)
                            }.joined(),
                            cells: cells
                        )
                        clues.append(clue)
                        cluesByID[clue.id] = clue
                        for cell in cells {
                            clueIDsByCoordinate[cell, default: [:]][.down] = clue.id
                        }
                    }

                    nextNumber += 1
                }
            }
        }

        return CrosswordPuzzle(
            title: title,
            width: width,
            height: height,
            grid: grid,
            clues: clues,
            cluesByID: cluesByID,
            clueIDsByCoordinate: clueIDsByCoordinate
        )
    }

    private func clueDefinition(
        for direction: CrosswordDirection,
        number: Int,
        clueDefinitions: [CrosswordDirection: [Int: (prompt: String, answer: String)]]
    ) throws -> (prompt: String, answer: String) {
        guard let definition = clueDefinitions[direction]?[number] else {
            throw CrosswordParserError.missingClueDefinition(direction, number)
        }

        return definition
    }

    private func collectAcrossCells(
        from start: CrosswordCoordinate,
        rawGrid: [[Character]]
    ) -> [CrosswordCoordinate] {
        var cells: [CrosswordCoordinate] = []
        var column = start.column

        while column < rawGrid[start.row].count, rawGrid[start.row][column] != "#" {
            cells.append(CrosswordCoordinate(row: start.row, column: column))
            column += 1
        }

        return cells
    }

    private func collectDownCells(
        from start: CrosswordCoordinate,
        rawGrid: [[Character]]
    ) -> [CrosswordCoordinate] {
        var cells: [CrosswordCoordinate] = []
        var row = start.row

        while row < rawGrid.count, rawGrid[row][start.column] != "#" {
            cells.append(CrosswordCoordinate(row: row, column: start.column))
            row += 1
        }

        return cells
    }

    private func gridValue(at coordinate: CrosswordCoordinate, rawGrid: [[Character]]) -> String? {
        let value = rawGrid[coordinate.row][coordinate.column]
        guard value != "#" else {
            return nil
        }

        return normalizeSolution(String(value))
    }

    private func normalizeSolution(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

private extension Character {
    var isLetter: Bool {
        unicodeScalars.allSatisfy(CharacterSet.letters.contains(_:))
    }
}
