//
//  ContentView.swift
//  xword
//

import SwiftUI

enum InputPanelMode: String, CaseIterable, Identifiable {
    case keyboard = "Keyboard"
    case clues = "Clues"

    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var game: CrosswordGame
    @State private var isKeyboardFocused = false
    @State private var inputPanelMode: InputPanelMode = .keyboard
    @State private var isClueSheetPresented = false

    @MainActor
    init() {
        _game = StateObject(wrappedValue: CrosswordGame())
    }

    init(game: CrosswordGame) {
        _game = StateObject(wrappedValue: game)
    }

    var body: some View {
        NavigationStack {
            content
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if game.selectedCell != nil && isKeyboardFocused {
                    VStack(spacing: 0) {
                        currentClueBanner
                        KeyboardInputView(
                            isFocused: $isKeyboardFocused,
                            selectedMode: $inputPanelMode,
                            onInsertText: { text in
                                game.insert(text: text)
                            },
                            onDeleteBackward: {
                                game.deleteSelectedEntry()
                            }
                        )
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: isKeyboardFocused)
            .onChange(of: game.selectedCell) { _, newValue in
                isKeyboardFocused = newValue != nil
            }
            .onChange(of: inputPanelMode) { _, newValue in
                if newValue == .clues {
                    isClueSheetPresented = true
                }
            }
            .sheet(isPresented: $isClueSheetPresented, onDismiss: {
                inputPanelMode = .keyboard
            }) {
                if let puzzle = game.puzzle {
                    clueSheet(for: puzzle)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let puzzle = game.puzzle {
            puzzleContent(for: puzzle)
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

    private func puzzleContent(for puzzle: CrosswordPuzzle) -> some View {
        GeometryReader { geometry in
            let contentWidth = max(1, geometry.size.width - 24)

            VStack(alignment: .leading, spacing: 18) {
                header
                board(for: puzzle, width: contentWidth)
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
        let borderWidth: CGFloat = 1
        let availableWidth = max(0, width - (borderWidth * 2) - spacing * CGFloat(puzzle.width - 1))
        let rawCellSize = availableWidth / CGFloat(max(puzzle.width, 1))
        let cellSize = max(1, floor(rawCellSize.isFinite ? rawCellSize : 1))
        let boardHeight = cellSize * CGFloat(puzzle.height) + spacing * CGFloat(puzzle.height - 1)
        let highlightedCells = game.currentClueCells
        let gridLineColor = Color(uiColor: .separator).opacity(0.55)

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
        .padding(borderWidth)
        .background(gridLineColor)
        .frame(width: width, height: boardHeight + (borderWidth * 2), alignment: .topLeading)
    }

    private var currentClueBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(game.currentClue?.label ?? "No clue selected")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(game.currentClue?.prompt ?? "Tap a square to begin.")
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func clueSheet(for puzzle: CrosswordPuzzle) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                clueSection(title: "Across", clues: puzzle.acrossClues)
                clueSection(title: "Down", clues: puzzle.downClues)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .presentationDetents([.fraction(0.4), .large])
        .presentationContentInteraction(.scrolls)
    }

    private func clueSection(title: String, clues: [CrosswordClue]) -> some View {
        Section {
            clueList(clues: clues)
        } header: {
            Text(title)
                .font(.system(size: 24, weight: .semibold, design: .serif))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .padding(.horizontal, 4)
                .background(.regularMaterial)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func clueList(clues: [CrosswordClue]) -> some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(clues) { clue in
                Button {
                    game.selectClue(clue)
                    isKeyboardFocused = true
                    inputPanelMode = .keyboard
                    isClueSheetPresented = false
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
                    .fill(Color(uiColor: .secondaryLabel).opacity(0.72))
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
