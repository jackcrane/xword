//
//  CrosswordGame.swift
//  xword
//

import Combine
import Foundation

enum CrosswordSettings {
    static let maximumGridDimension = 20
}

extension CrosswordSettings {
    static func supports(_ puzzle: CrosswordPuzzle) -> Bool {
        puzzle.width <= maximumGridDimension && puzzle.height <= maximumGridDimension
    }
}

@MainActor
final class CrosswordGame: ObservableObject {
    @Published private(set) var puzzle: CrosswordPuzzle?
    @Published private(set) var entries: [CrosswordCoordinate: String] = [:]
    @Published private(set) var selectedCell: CrosswordCoordinate?
    @Published private(set) var selectedDirection: CrosswordDirection = .across
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    private static let puzzleURLs = discoverPuzzleURLs()

    init() {
        loadRandomPuzzle()
    }

    init(
        puzzle: CrosswordPuzzle,
        entries: [CrosswordCoordinate: String],
        selectedCell: CrosswordCoordinate? = nil,
        selectedDirection: CrosswordDirection = .across
    ) {
        self.puzzle = puzzle
        self.entries = Dictionary(uniqueKeysWithValues: puzzle.playableCells.map { cell in
            (cell.coordinate, entries[cell.coordinate, default: ""])
        })
        self.selectedCell = selectedCell ?? puzzle.acrossClues.first?.cells.first ?? puzzle.playableCells.first?.coordinate
        self.selectedDirection = selectedDirection
        self.errorMessage = nil
    }

    var currentClue: CrosswordClue? {
        guard let selectedCell else {
            return nil
        }

        return puzzle?.clue(at: selectedCell, direction: selectedDirection)
    }

    var completionText: String {
        guard let clue = currentClue else {
            return "Tap a square to start."
        }

        let filledCount = clue.cells.reduce(into: 0) { partialResult, coordinate in
            if !(entries[coordinate, default: ""].isEmpty) {
                partialResult += 1
            }
        }

        return "\(filledCount) of \(clue.cells.count) filled"
    }

    var currentClueCells: Set<CrosswordCoordinate> {
        Set(currentClue?.cells ?? [])
    }

    func entry(for coordinate: CrosswordCoordinate) -> String {
        entries[coordinate, default: ""]
    }

    func loadRandomPuzzle() {
        isLoading = true

        Task {
            do {
                guard !Self.puzzleURLs.isEmpty else {
                    throw NSError(domain: "xword", code: 1, userInfo: [NSLocalizedDescriptionKey: "No bundled puzzles were found."])
                }

                let parsedPuzzle = try await Task.detached(priority: .userInitiated) {
                    for url in Self.puzzleURLs.shuffled() {
                        let contents = try String(contentsOf: url, encoding: .utf8)
                        let puzzle = try CrosswordParser().parse(contents: contents)

                        guard CrosswordSettings.supports(puzzle) else {
                            continue
                        }

                        return puzzle
                    }

                    throw NSError(
                        domain: "xword",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "No puzzles were found at or under \(CrosswordSettings.maximumGridDimension)x\(CrosswordSettings.maximumGridDimension)."]
                    )
                }.value

                applyPuzzle(parsedPuzzle)
                errorMessage = nil
            } catch {
                puzzle = nil
                entries = [:]
                selectedCell = nil
                errorMessage = error.localizedDescription
            }

            isLoading = false
        }
    }

    func selectCell(_ coordinate: CrosswordCoordinate) {
        guard let puzzle, let cell = puzzle.cell(at: coordinate), !cell.isBlock else {
            return
        }

        let directions = puzzle.directions(at: coordinate)
        if selectedCell == coordinate, directions.count > 1 {
            selectedDirection = selectedDirection == .across ? .down : .across
        } else {
            selectedCell = coordinate
            if puzzle.clue(at: coordinate, direction: selectedDirection) == nil {
                selectedDirection = directions.first ?? .across
            }
        }
    }

    func selectClue(_ clue: CrosswordClue) {
        selectedDirection = clue.direction
        selectedCell = clue.cells.first
    }

    func insert(text: String) {
        guard let selectedCell else {
            return
        }

        guard let character = normalizedInput(from: text) else {
            return
        }

        entries[selectedCell] = character
        moveForward()
    }

    func deleteSelectedEntry() {
        guard let selectedCell else {
            return
        }

        if !(entries[selectedCell, default: ""].isEmpty) {
            entries[selectedCell] = ""
            return
        }

        moveBackward()
        if let selectedCell = self.selectedCell {
            entries[selectedCell] = ""
        }
    }

    func isSelected(_ coordinate: CrosswordCoordinate) -> Bool {
        selectedCell == coordinate
    }

    func isInCurrentClue(_ coordinate: CrosswordCoordinate) -> Bool {
        currentClue?.cells.contains(coordinate) == true
    }

    func toggleDirection() {
        guard let selectedCell, let puzzle else {
            return
        }

        let directions = puzzle.directions(at: selectedCell)
        guard directions.count > 1 else {
            return
        }

        selectedDirection = selectedDirection == .across ? .down : .across
    }

    func selectNextClue() {
        selectAdjacentClue(step: 1)
    }

    func selectPreviousClue() {
        selectAdjacentClue(step: -1)
    }

    private func moveForward() {
        guard let clue = currentClue, let selectedCell, let index = clue.cells.firstIndex(of: selectedCell) else {
            return
        }

        let nextIndex = clue.cells.index(after: index)
        guard clue.cells.indices.contains(nextIndex) else {
            return
        }

        self.selectedCell = clue.cells[nextIndex]
    }

    private func moveBackward() {
        guard let clue = currentClue, let selectedCell, let index = clue.cells.firstIndex(of: selectedCell), index > 0 else {
            return
        }

        self.selectedCell = clue.cells[index - 1]
    }

    private func selectAdjacentClue(step: Int) {
        guard
            let puzzle,
            let currentClue,
            let currentIndex = clues(for: currentClue.direction).firstIndex(of: currentClue)
        else {
            return
        }

        let clueSet = clues(for: currentClue.direction)
        guard !clueSet.isEmpty else {
            return
        }

        let nextIndex = (currentIndex + step + clueSet.count) % clueSet.count
        selectClue(clueSet[nextIndex])
    }

    private func clues(for direction: CrosswordDirection) -> [CrosswordClue] {
        guard let puzzle else {
            return []
        }

        switch direction {
        case .across:
            return puzzle.acrossClues
        case .down:
            return puzzle.downClues
        }
    }

    private func applyPuzzle(_ puzzle: CrosswordPuzzle) {
        self.puzzle = puzzle
        entries = Dictionary(uniqueKeysWithValues: puzzle.playableCells.map { ($0.coordinate, "") })
        selectedDirection = .across
        selectedCell = puzzle.acrossClues.first?.cells.first ?? puzzle.playableCells.first?.coordinate
    }

    private static func discoverPuzzleURLs() -> [URL] {
        let fileManager = FileManager.default
        let candidateDirectories = ["data", "Resources/data"].compactMap { path in
            Bundle.main.resourceURL?.appending(path: path, directoryHint: .isDirectory)
        }

        for directory in candidateDirectories where fileManager.fileExists(atPath: directory.path) {
            let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            let urls = (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "xd" }
            if !urls.isEmpty {
                return urls
            }
        }

        if let bundledURLs = Bundle.main.urls(forResourcesWithExtension: "xd", subdirectory: "data"), !bundledURLs.isEmpty {
            return bundledURLs
        }

        guard let resourceURL = Bundle.main.resourceURL else {
            return []
        }

        let enumerator = fileManager.enumerator(
            at: resourceURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let urls = (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "xd" }
        return urls
    }

    private func normalizedInput(from value: String) -> String? {
        let trimmedCharacters = value.filter { !$0.isWhitespace && !$0.isNewline }
        guard let lastCharacter = trimmedCharacters.last else {
            return nil
        }

        return String(lastCharacter).uppercased()
    }
}
