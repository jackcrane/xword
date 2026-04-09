//
//  CrosswordGame.swift
//  xword
//

import Combine
import Foundation
import SwiftUI

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
    @Published private(set) var multiplayerPlayers: [MultiplayerLobbyPlayer] = []
    @Published private(set) var multiplayerRole: MultiplayerRelayRole?
    @Published private(set) var multiplayerLocalPlayerID: String?
    @Published private(set) var multiplayerToast: MultiplayerToast?
    @Published private(set) var multiplayerDismissSequence = 0
    @Published private var multiplayerRemoteSelections: [String: MultiplayerSelection] = [:]

    private struct PuzzleRecord: Sendable {
        let id: String
        let url: URL
    }

    nonisolated private static let puzzleRecords = discoverPuzzleRecords()
    nonisolated private static let puzzleRecordsByID = Dictionary(uniqueKeysWithValues: puzzleRecords.map { ($0.id, $0) })
    nonisolated private static let multiplayerPinAlphabet = Array("23456789ABCDEFGHJKMNPQRSTVWXYZ")

    private let multiplayerRelayClient = MultiplayerRelayClient()

    init() {
        multiplayerLobbyPin = Self.generateMultiplayerLobbyPin()
        multiplayerRelayClient.delegate = self
        loadRandomPuzzle()
    }

    init(
        puzzle: CrosswordPuzzle,
        entries: [CrosswordCoordinate: String],
        selectedCell: CrosswordCoordinate? = nil,
        selectedDirection: CrosswordDirection = .across
    ) {
        multiplayerLobbyPin = Self.generateMultiplayerLobbyPin()
        multiplayerRelayClient.delegate = self
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

    var isHostingLobby: Bool {
        multiplayerRole == .host && multiplayerLocalPlayerID != nil
    }

    var isJoinedLobby: Bool {
        multiplayerRole == .join && multiplayerLocalPlayerID != nil
    }

    var isInLobby: Bool {
        multiplayerRole != nil && multiplayerLocalPlayerID != nil
    }

    var canLoadNewPuzzle: Bool {
        !isJoinedLobby
    }

    var hasConnectedGuests: Bool {
        isHostingLobby && multiplayerPlayers.count > 1
    }

    var orderedLobbyPlayers: [MultiplayerLobbyPlayer] {
        multiplayerPlayers.sorted { $0.joinedAt < $1.joinedAt }
    }

    func entry(for coordinate: CrosswordCoordinate) -> String {
        entries[coordinate, default: ""]
    }

    func loadRandomPuzzle() {
        guard !isJoinedLobby else {
            return
        }

        loadRandomPuzzleInternal(notifyPeers: isHostingLobby)
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

        broadcastSelectionIfNeeded()
    }

    func selectClue(_ clue: CrosswordClue) {
        selectedDirection = clue.direction
        selectedCell = clue.cells.first
        broadcastSelectionIfNeeded()
    }

    func insert(text: String) {
        guard let selectedCell else {
            return
        }

        guard let character = normalizedInput(from: text) else {
            return
        }

        setEntry(character, at: selectedCell)
        checkedCells.remove(selectedCell)
        broadcastEntryUpdate(for: selectedCell)
        moveForward()
        broadcastSelectionIfNeeded()
    }

    func deleteSelectedEntry() {
        guard let selectedCell else {
            return
        }

        if !(entries[selectedCell, default: ""].isEmpty) {
            setEntry("", at: selectedCell)
            checkedCells.remove(selectedCell)
            broadcastEntryUpdate(for: selectedCell)
            return
        }

        moveBackward()
        if let selectedCell = self.selectedCell {
            setEntry("", at: selectedCell)
            checkedCells.remove(selectedCell)
            broadcastEntryUpdate(for: selectedCell)
            broadcastSelectionIfNeeded()
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

    func connectAsHost() {
        print("[MultiplayerRelay] Host connect requested for lobby \(multiplayerLobbyPin)")
        multiplayerRelayClient.connect(pin: multiplayerLobbyPin, role: .host)
    }

    func joinLobby(pin: String) {
        print("[MultiplayerRelay] Join connect requested for lobby \(pin)")
        multiplayerRelayClient.connect(pin: pin, role: .join)
    }

    func leaveLobby() {
        multiplayerRelayClient.disconnect()
        resetLocalLobbyStateAndReloadPuzzle()
    }

    func endLobby() {
        if isHostingLobby {
            multiplayerRelayClient.endLobby()
        }

        multiplayerRelayClient.disconnect()
        resetLocalLobbyStateAndReloadPuzzle()
    }

    func kick(playerID: String) {
        multiplayerRelayClient.kick(playerID: playerID)
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
        broadcastSelectionIfNeeded()
    }

    func selectNextClue() {
        selectAdjacentClue(step: 1)
    }

    func selectPreviousClue() {
        selectAdjacentClue(step: -1)
    }

    func displayColor(for player: MultiplayerLobbyPlayer) -> MultiplayerPlayerColor? {
        player.id == multiplayerLocalPlayerID ? nil : player.color
    }

    func lobbyRowColor(for player: MultiplayerLobbyPlayer) -> Color {
        player.id == multiplayerLocalPlayerID ? MultiplayerPlayerColor.localPlayer : player.color.swiftUIColor
    }

    func remoteSelectedColor(at coordinate: CrosswordCoordinate) -> MultiplayerPlayerColor? {
        guard let player = orderedLobbyPlayers.first(where: { player in
            player.id != multiplayerLocalPlayerID &&
            multiplayerRemoteSelections[player.id]?.coordinate == coordinate
        }) else {
            return nil
        }

        return player.color
    }

    func remoteHighlightedColor(at coordinate: CrosswordCoordinate) -> MultiplayerPlayerColor? {
        guard let puzzle else {
            return nil
        }

        guard let player = orderedLobbyPlayers.first(where: { player in
            guard player.id != multiplayerLocalPlayerID,
                  let selection = multiplayerRemoteSelections[player.id],
                  let clue = puzzle.clue(at: selection.coordinate, direction: selection.direction) else {
                return false
            }

            return clue.cells.contains(coordinate)
        }) else {
            return nil
        }

        return player.color
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

    private func loadRandomPuzzleInternal(notifyPeers: Bool) {
        isLoading = true

        Task {
            do {
                guard !Self.puzzleRecords.isEmpty else {
                    throw NSError(domain: "xword", code: 1, userInfo: [NSLocalizedDescriptionKey: "No bundled puzzles were found."])
                }

                let puzzle = try await Task.detached(priority: .userInitiated) {
                    for record in Self.puzzleRecords.shuffled() {
                        guard let parsed = try? Self.parsePuzzleRecord(record) else {
                            continue
                        }

                        return parsed
                    }

                    throw NSError(
                        domain: "xword",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "No puzzles were found at or under \(CrosswordSettings.currentMaximumGridDimension)x\(CrosswordSettings.currentMaximumGridDimension)."]
                    )
                }.value

                applyPuzzle(puzzle)
                errorMessage = nil
                if notifyPeers {
                    sendStateSnapshot()
                }
            } catch {
                puzzle = nil
                entries = [:]
                selectedCell = nil
                errorMessage = error.localizedDescription
            }

            isLoading = false
        }
    }

    private func loadPuzzle(
        withID puzzleID: String,
        entries snapshotEntries: [MultiplayerEntrySnapshot],
        selection: MultiplayerSelection?,
        preserveRemoteSelections: Bool = false
    ) {
        isLoading = true

        Task {
            do {
                guard let record = Self.puzzleRecordsByID[puzzleID] else {
                    throw NSError(domain: "xword", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing puzzle \(puzzleID)."])
                }

                let parsedPuzzle = try await Task.detached(priority: .userInitiated) {
                    try Self.parsePuzzleRecord(record)
                }.value

                let entryMap = Dictionary(uniqueKeysWithValues: snapshotEntries.map { ($0.coordinate, $0.value) })
                applyPuzzle(parsedPuzzle, entries: entryMap, selection: selection, clearRemoteSelections: !preserveRemoteSelections)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }

            isLoading = false
        }
    }

    private func applyPuzzle(
        _ puzzle: CrosswordPuzzle,
        entries providedEntries: [CrosswordCoordinate: String]? = nil,
        selection: MultiplayerSelection? = nil,
        clearRemoteSelections: Bool = true
    ) {
        self.puzzle = puzzle
        self.entries = Dictionary(uniqueKeysWithValues: puzzle.playableCells.map { cell in
            (cell.coordinate, providedEntries?[cell.coordinate, default: ""] ?? "")
        })
        self.selectedDirection = selection?.direction ?? .across

        if let selectionCoordinate = selection?.coordinate,
           let cell = puzzle.cell(at: selectionCoordinate),
           !cell.isBlock {
            self.selectedCell = selectionCoordinate
        } else {
            self.selectedCell = puzzle.acrossClues.first?.cells.first ?? puzzle.playableCells.first?.coordinate
        }

        checkedCells = []
        if clearRemoteSelections {
            multiplayerRemoteSelections = [:]
        }
    }

    private func sendStateSnapshot(targetPlayerID: String? = nil) {
        guard isHostingLobby, let puzzle else {
            print("[MultiplayerRelay] Skipped state snapshot send because host state was unavailable")
            return
        }

        let snapshot = MultiplayerStateSnapshot(
            puzzleID: puzzle.sourceID,
            entries: puzzle.playableCells.map { cell in
                MultiplayerEntrySnapshot(coordinate: cell.coordinate, value: entries[cell.coordinate, default: ""])
            },
            selection: selectedCell.map { MultiplayerSelection(coordinate: $0, direction: selectedDirection) }
        )

        let targetDescription = targetPlayerID ?? "all players"
        print(
            "[MultiplayerRelay] Sending state snapshot to \(targetDescription) puzzle=\(snapshot.puzzleID) entries=\(snapshot.entries.count) selection=\(snapshot.selection != nil)"
        )
        multiplayerRelayClient.sendRelayEvent(.stateSnapshot(snapshot), targetPlayerID: targetPlayerID)
    }

    private func broadcastSelectionIfNeeded() {
        guard isInLobby else {
            return
        }

        let selection = selectedCell.map { MultiplayerSelection(coordinate: $0, direction: selectedDirection) }
        multiplayerRelayClient.sendRelayEvent(.selectionUpdated(selection))
    }

    private func broadcastEntryUpdate(for coordinate: CrosswordCoordinate) {
        guard isInLobby else {
            return
        }

        multiplayerRelayClient.sendRelayEvent(
            .entryUpdated(MultiplayerEntrySnapshot(coordinate: coordinate, value: entries[coordinate, default: ""]))
        )
    }

    private func updateRoster(_ players: [MultiplayerLobbyPlayer]) {
        let previousPlayerIDs = Set(multiplayerPlayers.map(\.id))
        multiplayerPlayers = players.sorted { $0.joinedAt < $1.joinedAt }

        let activeIDs = Set(multiplayerPlayers.map(\.id))
        multiplayerRemoteSelections = multiplayerRemoteSelections.filter { activeIDs.contains($0.key) }
        broadcastSelectionIfNeeded()

        if isHostingLobby {
            let newRemotePlayerIDs = multiplayerPlayers
                .map(\.id)
                .filter { !previousPlayerIDs.contains($0) && $0 != multiplayerLocalPlayerID }

            for playerID in newRemotePlayerIDs {
                sendStateSnapshot(targetPlayerID: playerID)
            }
        }
    }

    private func applyRemoteEntry(_ entry: MultiplayerEntrySnapshot) {
        setEntry(entry.value, at: entry.coordinate)
        checkedCells.remove(entry.coordinate)
    }

    private func applyRemoteStateSnapshot(_ snapshot: MultiplayerStateSnapshot, fromPlayerID: String) {
        print(
            "[MultiplayerRelay] Applying state snapshot from \(fromPlayerID) puzzle=\(snapshot.puzzleID) entries=\(snapshot.entries.count) currentPuzzle=\(puzzle?.sourceID ?? "none")"
        )

        if puzzle?.sourceID == snapshot.puzzleID {
            let entryMap = Dictionary(uniqueKeysWithValues: snapshot.entries.map { ($0.coordinate, $0.value) })
            if let puzzle {
                entries = Dictionary(uniqueKeysWithValues: puzzle.playableCells.map { cell in
                    (cell.coordinate, entryMap[cell.coordinate, default: ""])
                })
            }
            checkedCells = []
            multiplayerRemoteSelections[fromPlayerID] = snapshot.selection
            print("[MultiplayerRelay] Applied state snapshot onto existing puzzle")
        } else {
            print("[MultiplayerRelay] Loading puzzle \(snapshot.puzzleID) from snapshot")
            loadPuzzle(withID: snapshot.puzzleID, entries: snapshot.entries, selection: snapshot.selection, preserveRemoteSelections: false)
            multiplayerRemoteSelections[fromPlayerID] = snapshot.selection
        }
    }

    private func resetLocalLobbyStateAndReloadPuzzle() {
        multiplayerPlayers = []
        multiplayerRole = nil
        multiplayerLocalPlayerID = nil
        multiplayerRemoteSelections = [:]
        requestDismissToKeyboard()
        loadRandomPuzzleInternal(notifyPeers: false)
    }

    private func showToast(_ message: String) {
        let toast = MultiplayerToast(message: message)
        multiplayerToast = toast

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard self?.multiplayerToast?.id == toast.id else {
                return
            }

            self?.multiplayerToast = nil
        }
    }

    private func requestDismissToKeyboard() {
        multiplayerDismissSequence += 1
    }

    private func setEntry(_ value: String, at coordinate: CrosswordCoordinate) {
        var updatedEntries = entries
        updatedEntries[coordinate] = value
        entries = updatedEntries
    }

    nonisolated private static func discoverPuzzleRecords() -> [PuzzleRecord] {
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
                return urls.map { PuzzleRecord(id: puzzleIdentifier(for: $0), url: $0) }
            }
        }

        if let bundledURLs = Bundle.main.urls(forResourcesWithExtension: "xd", subdirectory: "data"), !bundledURLs.isEmpty {
            return bundledURLs.map { PuzzleRecord(id: puzzleIdentifier(for: $0), url: $0) }
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
        return urls.map { PuzzleRecord(id: puzzleIdentifier(for: $0), url: $0) }
    }

    nonisolated private static func parsePuzzleRecord(_ record: PuzzleRecord) throws -> CrosswordPuzzle {
        let contents = try String(contentsOf: record.url, encoding: .utf8)
        let puzzle = try CrosswordParser().parse(contents: contents, sourceID: record.id)
        guard CrosswordSettings.supports(puzzle) else {
            throw NSError(
                domain: "xword",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Puzzle \(record.id) exceeds the current size limit."]
            )
        }

        return puzzle
    }

    nonisolated private static func puzzleIdentifier(for url: URL) -> String {
        let standardizedPath = url.standardizedFileURL.path

        if let range = standardizedPath.range(of: ".app/") {
            return String(standardizedPath[range.upperBound...])
        }

        if let range = standardizedPath.range(of: "/Resources/data/") {
            return String(standardizedPath[range.upperBound...])
        }

        if let range = standardizedPath.range(of: "/data/") {
            return String(standardizedPath[range.upperBound...])
        }

        return url.lastPathComponent
    }

    nonisolated private static func generateMultiplayerLobbyPin() -> String {
        let characters = (0..<6).map { _ in
            multiplayerPinAlphabet.randomElement() ?? "2"
        }

        return "\(String(characters.prefix(3)))-\(String(characters.suffix(3)))"
    }

    nonisolated private static func isValidMultiplayerLobbyPin(_ pin: String) -> Bool {
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

extension CrosswordGame: MultiplayerRelayClientDelegate {
    func relayClient(_ client: MultiplayerRelayClient, didReceive event: MultiplayerRelayClient.ServerEvent) {
        switch event {
        case .welcome(let selfID, _, let role, let players):
            multiplayerLocalPlayerID = selfID
            multiplayerRole = role
            updateRoster(players)
            if role == .join {
                print("[MultiplayerRelay] Requesting host snapshot after join welcome")
                multiplayerRelayClient.sendRelayEvent(.snapshotRequested)
                requestDismissToKeyboard()
                showToast("Successfully joined the room")
            }
            print("[MultiplayerRelay] Connected as \(role.rawValue)")

        case .roster(let players):
            updateRoster(players)

        case .playerJoined(let playerID):
            guard playerID != multiplayerLocalPlayerID else {
                return
            }

            if isHostingLobby {
                sendStateSnapshot(targetPlayerID: playerID)
            }

            showToast("Someone joined the room")

        case .relayed(let fromPlayerID, let relayEvent):
            guard fromPlayerID != multiplayerLocalPlayerID else {
                return
            }

            print("[MultiplayerRelay] Received relay event \(relayEvent.debugName) from \(fromPlayerID)")
            switch relayEvent {
            case .stateSnapshot(let snapshot):
                applyRemoteStateSnapshot(snapshot, fromPlayerID: fromPlayerID)
            case .snapshotRequested:
                if isHostingLobby {
                    print("[MultiplayerRelay] Received snapshot request from \(fromPlayerID)")
                    sendStateSnapshot(targetPlayerID: fromPlayerID)
                }
            case .selectionUpdated(let selection):
                multiplayerRemoteSelections[fromPlayerID] = selection
            case .entryUpdated(let entry):
                applyRemoteEntry(entry)
            }

        case .kicked:
            multiplayerRelayClient.disconnect()
            resetLocalLobbyStateAndReloadPuzzle()

        case .lobbyEnded:
            multiplayerRelayClient.disconnect()
            resetLocalLobbyStateAndReloadPuzzle()

        case .error(let message):
            print("[MultiplayerRelay] Error: \(message)")
        }
    }
}
