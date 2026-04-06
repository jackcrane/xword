//
//  ContentView.swift
//  xword
//

import SwiftUI

struct ContentView: View {
    @StateObject private var game: CrosswordGame
    @State private var isKeyboardFocused = false

    @MainActor
    init() {
        _game = StateObject(wrappedValue: CrosswordGame())
    }

    init(game: CrosswordGame) {
        _game = StateObject(wrappedValue: game)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let puzzle = game.puzzle {
                    GeometryReader { geometry in
                        let contentWidth = max(1, geometry.size.width - 24)

                        VStack(alignment: .leading, spacing: 18) {
                            header
                            board(for: puzzle, width: contentWidth)
                            currentClueCard

                            ScrollView {
                                clueSections(for: puzzle)
                                    .padding(.bottom, 20)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 20)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .onAppear {
                            if game.selectedCell != nil {
                                isKeyboardFocused = true
                            }
                        }
                    }
                } else if game.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        "Crossword Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(game.errorMessage ?? "The puzzle could not be loaded.")
                    )
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .topLeading) {
                KeyboardInputView(
                    isFocused: $isKeyboardFocused,
                    onInsertText: { text in
                        game.insert(text: text)
                    },
                    onDeleteBackward: {
                        game.deleteSelectedEntry()
                    }
                )
                .frame(width: 1, height: 1)
                .opacity(0.01)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Crossword")
                .font(.system(size: 36, weight: .semibold, design: .serif))

            Spacer()

            Menu {
                Section {
                    Button("New Puzzle") {
                        isKeyboardFocused = false
                        game.loadRandomPuzzle()
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    private func board(for puzzle: CrosswordPuzzle, width: CGFloat) -> some View {
        let spacing: CGFloat = 1
        let availableWidth = max(0, width - 12 - spacing * CGFloat(puzzle.width - 1))
        let rawCellSize = availableWidth / CGFloat(max(puzzle.width, 1))
        let cellSize = max(1, floor(rawCellSize.isFinite ? rawCellSize : 1))
        let boardHeight = cellSize * CGFloat(puzzle.height) + spacing * CGFloat(puzzle.height - 1)
        let highlightedCells = game.currentClueCells

        return VStack(spacing: 0) {
            ForEach(0..<puzzle.height, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<puzzle.width, id: \.self) { column in
                        let cell = puzzle.grid[row][column]

                        CrosswordCellView(
                            cell: cell,
                            entry: game.entry(for: cell.coordinate),
                            size: cellSize,
                            isSelected: game.selectedCell == cell.coordinate,
                            isHighlighted: highlightedCells.contains(cell.coordinate)
                        ) {
                            game.selectCell(cell.coordinate)
                            isKeyboardFocused = !cell.isBlock
                        }
                    }
                }
                if row < puzzle.height - 1 {
                    Color.clear.frame(height: spacing)
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .frame(width: width, height: boardHeight + 12, alignment: .topLeading)
    }

    private var currentClueCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(game.currentClue?.label ?? "No clue selected")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                if game.currentClue != nil {
                    Button(game.selectedDirection == .across ? "Down" : "Across") {
                        game.toggleDirection()
                        isKeyboardFocused = true
                    }
                    .font(.subheadline.weight(.medium))
                }
            }

            Text(game.currentClue?.prompt ?? "Tap a square to begin.")
                .font(.title3.weight(.semibold))

            Text(game.completionText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private func clueSections(for puzzle: CrosswordPuzzle) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            clueList(title: "Across", clues: puzzle.acrossClues)
            clueList(title: "Down", clues: puzzle.downClues)
        }
    }

    private func clueList(title: String, clues: [CrosswordClue]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 24, weight: .semibold, design: .serif))

            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(clues) { clue in
                    Button {
                        game.selectClue(clue)
                        isKeyboardFocused = true
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(clue.number)")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .leading)

                            Text(clue.prompt)
                                .font(.body)
                                .multilineTextAlignment(.leading)

                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(clue.id == game.currentClue?.id ? Color.primary.opacity(0.08) : Color(uiColor: .secondarySystemBackground))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

private struct CrosswordCellView: View {
    let cell: CrosswordCell
    let entry: String
    let size: CGFloat
    let isSelected: Bool
    let isHighlighted: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if cell.isBlock {
                Rectangle()
                    .fill(Color.primary)
            } else {
                Rectangle()
                    .fill(backgroundColor)

                if cell.isCircled {
                    Circle()
                        .stroke(Color.primary.opacity(0.45), lineWidth: 1.5)
                        .padding(size * 0.12)
                }

                Text(entry)
                    .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let number = cell.number {
                    Text("\(number)")
                        .font(.system(size: size * 0.18, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                        .padding(.leading, 3)
                }
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !cell.isBlock else {
                return
            }

            onTap()
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.5)
        }

        if isHighlighted {
            return Color.accentColor.opacity(0.18)
        }

        return Color(uiColor: .systemBackground)
    }
}

#Preview("Loaded Puzzle") {
    let sample = """
    Title: Preview Grid
    Author: Preview
    Date: 2026-04-06


    SUN
    ERA
    NET


    A1. Bright day source ~ SUN
    A4. Historical period ~ ERA
    A5. Mesh material ~ NET
    D1. Simple preview down clue ~ SEN
    D2. Vague uncertainty sound ~ URE
    D3. National park service, briefly? ~ NAT
    """
    let puzzle = try! CrosswordParser().parse(contents: sample)

    return ContentView(
        game: CrosswordGame(
            puzzle: puzzle,
            entries: [
                CrosswordCoordinate(row: 0, column: 0): "S",
                CrosswordCoordinate(row: 0, column: 1): "U",
                CrosswordCoordinate(row: 1, column: 0): "E",
                CrosswordCoordinate(row: 1, column: 1): "R",
                CrosswordCoordinate(row: 2, column: 0): "N"
            ],
            selectedCell: CrosswordCoordinate(row: 0, column: 0),
            selectedDirection: .across
        )
    )
}

#Preview("Loading") {
    ContentView(
        game: CrosswordGame(
            puzzle: try! CrosswordParser().parse(contents: """
            Title: Preview Grid


            A


            A1. First letter ~ A
            D1. First letter ~ A
            """),
            entries: [:]
        )
    )
}
