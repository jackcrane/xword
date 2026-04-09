//
//  MultiplayerModels.swift
//  xword
//

import Foundation
import SwiftUI

enum MultiplayerRelayRole: String, Codable {
    case host
    case join
}

enum MultiplayerPlayerColor: String, Codable, CaseIterable {
    case pink
    case orange
    case yellow
    case teal
    case lightGreen

    static let localPlayer = Color.blue

    var swiftUIColor: Color {
        switch self {
        case .pink:
            return Color(red: 0.94, green: 0.35, blue: 0.66)
        case .orange:
            return Color(red: 0.95, green: 0.58, blue: 0.18)
        case .yellow:
            return Color(red: 0.95, green: 0.79, blue: 0.23)
        case .teal:
            return Color(red: 0.14, green: 0.69, blue: 0.66)
        case .lightGreen:
            return Color(red: 0.56, green: 0.82, blue: 0.42)
        }
    }
}

struct MultiplayerSelection: Codable, Equatable {
    let row: Int
    let column: Int
    let direction: CrosswordDirection

    var coordinate: CrosswordCoordinate {
        CrosswordCoordinate(row: row, column: column)
    }

    init(coordinate: CrosswordCoordinate, direction: CrosswordDirection) {
        self.row = coordinate.row
        self.column = coordinate.column
        self.direction = direction
    }
}

struct MultiplayerLobbyPlayer: Identifiable, Codable, Equatable {
    let id: String
    let role: MultiplayerRelayRole
    let color: MultiplayerPlayerColor
    let joinedAt: Int
}

struct MultiplayerEntrySnapshot: Codable, Equatable {
    let row: Int
    let column: Int
    let value: String

    var coordinate: CrosswordCoordinate {
        CrosswordCoordinate(row: row, column: column)
    }

    init(coordinate: CrosswordCoordinate, value: String) {
        self.row = coordinate.row
        self.column = coordinate.column
        self.value = value
    }
}

struct MultiplayerStateSnapshot: Codable, Equatable {
    let puzzleID: String
    let entries: [MultiplayerEntrySnapshot]
    let selection: MultiplayerSelection?
}

struct MultiplayerToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

enum MultiplayerRelayEvent: Codable, Equatable {
    case stateSnapshot(MultiplayerStateSnapshot)
    case snapshotRequested
    case selectionUpdated(MultiplayerSelection?)
    case entryUpdated(MultiplayerEntrySnapshot)

    enum CodingKeys: String, CodingKey {
        case type
        case snapshot
        case snapshotRequest
        case selection
        case entry
    }

    enum Kind: String, Codable {
        case stateSnapshot
        case snapshotRequested
        case selectionUpdated
        case entryUpdated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)

        switch kind {
        case .stateSnapshot:
            self = .stateSnapshot(try container.decode(MultiplayerStateSnapshot.self, forKey: .snapshot))
        case .snapshotRequested:
            self = .snapshotRequested
        case .selectionUpdated:
            self = .selectionUpdated(try container.decodeIfPresent(MultiplayerSelection.self, forKey: .selection))
        case .entryUpdated:
            self = .entryUpdated(try container.decode(MultiplayerEntrySnapshot.self, forKey: .entry))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .stateSnapshot(let snapshot):
            try container.encode(Kind.stateSnapshot, forKey: .type)
            try container.encode(snapshot, forKey: .snapshot)
        case .snapshotRequested:
            try container.encode(Kind.snapshotRequested, forKey: .type)
        case .selectionUpdated(let selection):
            try container.encode(Kind.selectionUpdated, forKey: .type)
            try container.encodeIfPresent(selection, forKey: .selection)
        case .entryUpdated(let entry):
            try container.encode(Kind.entryUpdated, forKey: .type)
            try container.encode(entry, forKey: .entry)
        }
    }

    var debugName: String {
        switch self {
        case .stateSnapshot:
            return "stateSnapshot"
        case .snapshotRequested:
            return "snapshotRequested"
        case .selectionUpdated:
            return "selectionUpdated"
        case .entryUpdated:
            return "entryUpdated"
        }
    }
}
