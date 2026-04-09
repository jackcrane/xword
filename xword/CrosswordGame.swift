//
//  CrosswordGame.swift
//  xword
//

import Combine
import Foundation

enum CrosswordSettings {
    static let defaultMaximumGridDimension = 20
    static let minimumGridDimension = 15
    static let maximumGridDimension = 30
    static let maximumGridDimensionStorageKey = "maximumGridDimension"
    static let multiplayerLobbyPinStorageKey = "multiplayerLobbyPin"

    static var currentMaximumGridDimension: Int {
        let storedValue = UserDefaults.standard.integer(forKey: maximumGridDimensionStorageKey)
        if storedValue == 0 {
            return defaultMaximumGridDimension
        }

        return min(max(storedValue, minimumGridDimension), maximumGridDimension)
    }

    static func normalizeStoredMaximumGridDimension() {
        let storedValue = UserDefaults.standard.integer(forKey: maximumGridDimensionStorageKey)
        guard storedValue != 0, storedValue < minimumGridDimension else {
            return
        }

        UserDefaults.standard.set(minimumGridDimension, forKey: maximumGridDimensionStorageKey)
    }
}

extension CrosswordSettings {
    static func supports(_ puzzle: CrosswordPuzzle) -> Bool {
        let limit = currentMaximumGridDimension
        return puzzle.width <= limit && puzzle.height <= limit
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
    @Published var checkAsYouType = false
    @Published private(set) var checkedCells: Set<CrosswordCoordinate> = []
    @Published private(set) var multiplayerLobbyPin: String

    private static let puzzleURLs = discoverPuzzleURLs()
    private static let multiplayerPinAlphabet = Array("23456789ABCDEFGHJKMNPQRSTVWXYZ")

    init() {
        multiplayerLobbyPin = Self.loadOrCreateMultiplayerLobbyPin()
        loadRandomPuzzle()
    }

    init(
        puzzle: CrosswordPuzzle,
        entries: [CrosswordCoordinate: String],
        selectedCell: CrosswordCoordinate? = nil,
        selectedDirection: CrosswordDirection = .across
    ) {
        self.multiplayerLobbyPin = Self.loadOrCreateMultiplayerLobbyPin()
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
                        guard let contents = try? String(contentsOf: url, encoding: .utf8),
                              let puzzle = try? CrosswordParser().parse(contents: contents) else {
                            continue
                        }

                        guard CrosswordSettings.supports(puzzle) else {
                            continue
                        }

                        return puzzle
                    }

                    throw NSError(
                        domain: "xword",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "No puzzles were found at or under \(CrosswordSettings.currentMaximumGridDimension)x\(CrosswordSettings.currentMaximumGridDimension)."]
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
        checkedCells.remove(selectedCell)
        moveForward()
    }

    func deleteSelectedEntry() {
        guard let selectedCell else {
            return
        }

        if !(entries[selectedCell, default: ""].isEmpty) {
            entries[selectedCell] = ""
            checkedCells.remove(selectedCell)
            return
        }

        moveBackward()
        if let selectedCell = self.selectedCell {
            entries[selectedCell] = ""
            checkedCells.remove(selectedCell)
        }
    }

    func checkNow() {
        guard let puzzle else {
            checkedCells = []
            return
        }

        checkedCells = Set(
            puzzle.playableCells.compactMap { cell in
                guard
                    let solution = cell.solution,
                    let entry = entries[cell.coordinate],
                    !entry.isEmpty,
                    entry != solution
                else {
                    return nil
                }

                return cell.coordinate
            }
        )
    }

    func showsIncorrectEntry(at coordinate: CrosswordCoordinate) -> Bool {
        if checkAsYouType {
            guard
                let puzzle,
                let solution = puzzle.cell(at: coordinate)?.solution,
                let entry = entries[coordinate],
                !entry.isEmpty
            else {
                return false
            }

            return entry != solution
        }

        return checkedCells.contains(coordinate)
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
            let currentClue,
            step != 0
        else {
            return
        }

        let clueSet = clues(for: currentClue.direction)
        guard
            !clueSet.isEmpty,
            let currentIndex = clueSet.firstIndex(of: currentClue)
        else {
            return
        }

        let nextIndex = currentIndex + step
        if clueSet.indices.contains(nextIndex) {
            selectClue(clueSet[nextIndex])
            return
        }

        let alternateDirection: CrosswordDirection = currentClue.direction == .across ? .down : .across
        let alternateClues = clues(for: alternateDirection)
        guard !alternateClues.isEmpty else {
            let wrappedIndex = (currentIndex + step + clueSet.count) % clueSet.count
            selectClue(clueSet[wrappedIndex])
            return
        }

        let alternateIndex = step > 0 ? alternateClues.startIndex : alternateClues.index(before: alternateClues.endIndex)
        selectClue(alternateClues[alternateIndex])
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
        checkedCells = []
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

    private static func loadOrCreateMultiplayerLobbyPin() -> String {
        let defaults = UserDefaults.standard
        let storedPin = defaults.string(forKey: CrosswordSettings.multiplayerLobbyPinStorageKey) ?? ""
        if isValidMultiplayerLobbyPin(storedPin) {
            return storedPin
        }

        let newPin = generateMultiplayerLobbyPin()
        defaults.set(newPin, forKey: CrosswordSettings.multiplayerLobbyPinStorageKey)
        return newPin
    }

    private static func generateMultiplayerLobbyPin() -> String {
        let characters = (0..<6).map { _ in
            multiplayerPinAlphabet.randomElement() ?? "2"
        }

        return "\(String(characters.prefix(3)))-\(String(characters.suffix(3)))"
    }

    private static func isValidMultiplayerLobbyPin(_ pin: String) -> Bool {
        let components = pin.split(separator: "-")
        guard components.count == 2,
              components.allSatisfy({ $0.count == 3 }) else {
            return false
        }

        let allowedCharacters = Set(multiplayerPinAlphabet)
        return components.joined().allSatisfy { allowedCharacters.contains($0) }
    }

    private func normalizedInput(from value: String) -> String? {
        let trimmedCharacters = value.filter { !$0.isWhitespace && !$0.isNewline }
        guard let lastCharacter = trimmedCharacters.last else {
            return nil
        }

        return String(lastCharacter).uppercased()
    }
}
