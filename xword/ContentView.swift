//
//  ContentView.swift
//  xword
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit
import AVFoundation

enum AppColorScheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    static let storageKey = "appColorScheme"

    var id: String { rawValue }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum InputPanelMode: String, CaseIterable, Identifiable {
    case keyboard = "Keyboard"
    case clues = "Clues"
    case multiplayer = "Multiplayer"
    case settings = "Settings"

    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var game: CrosswordGame
    @AppStorage(AppColorScheme.storageKey) private var colorSchemePreference = AppColorScheme.system.rawValue
    @AppStorage(CrosswordSettings.maximumGridDimensionStorageKey) private var maximumGridDimension = CrosswordSettings.defaultMaximumGridDimension
    @State private var isKeyboardFocused = false
    @State private var inputPanelMode: InputPanelMode = .keyboard
    @State private var presentedSheet: InputPanelMode?
    @State private var clueTransitionDirection: HorizontalEdge = .trailing
    @State private var multiplayerMode: MultiplayerSheetMode = .join
    @State private var multiplayerJoinPin = ""
    @State private var isShowingQRScanner = false

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
            .overlay(alignment: .top) {
                if let toast = game.multiplayerToast {
                    ToastBanner(message: toast.message)
                        .padding(.top, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
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
            .onChange(of: game.multiplayerDismissSequence) { _, _ in
                presentedSheet = nil
                inputPanelMode = .keyboard
                isKeyboardFocused = game.selectedCell != nil
            }
            .onChange(of: inputPanelMode) { _, newValue in
                switch newValue {
                case .keyboard:
                    presentedSheet = nil
                case .clues, .multiplayer, .settings:
                    presentedSheet = newValue
                }
            }
            .sheet(item: $presentedSheet, onDismiss: {
                inputPanelMode = .keyboard
            }) { sheet in
                if sheet == .clues, let puzzle = game.puzzle {
                    clueSheet(for: puzzle)
                } else if sheet == .multiplayer {
                    multiplayerSheet
                } else if sheet == .settings {
                    settingsSheet
                }
            }
            .sheet(isPresented: Binding(
                get: { game.isShowingCompletionSheet },
                set: { if !$0 { game.dismissCompletionSheet() } }
            )) {
                completionSheet
            }
            .onOpenURL { url in
                multiplayerJoinPin = formatScannedMultiplayerPin(url.absoluteString)
                game.handleDeepLink(url)
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
                .contentShape(Rectangle())
                .onTapGesture(count: 10) {
                    game.solvePuzzle()
                }

            Spacer()

            if game.canLoadNewPuzzle {
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
                            isHighlighted: highlightedCells.contains(cell.coordinate),
                            remoteSelectedColor: game.remoteSelectedColor(at: cell.coordinate)?.swiftUIColor,
                            remoteHighlightedColor: game.remoteHighlightedColor(at: cell.coordinate)?.swiftUIColor,
                            isIncorrect: game.showsIncorrectEntry(at: cell.coordinate)
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
        ZStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(game.currentClue?.label ?? "No clue selected")
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(.secondary)
                Text(game.currentClue?.prompt ?? "Tap a square to begin.")
                    .font(.title3.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(game.currentClue?.id ?? "no-clue")
            .transition(clueBannerTransition)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Color.accentColor.opacity(0.1))
        .overlay(alignment: .top) {
            Divider()
        }
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else {
                        return
                    }

                    if value.translation.width < 0 {
                        clueTransitionDirection = .trailing
                        withAnimation(.easeInOut(duration: 0.22)) {
                            game.selectNextClue()
                        }
                    } else {
                        clueTransitionDirection = .leading
                        withAnimation(.easeInOut(duration: 0.22)) {
                            game.selectPreviousClue()
                        }
                    }
                    isKeyboardFocused = true
                }
        )
    }

    private var clueBannerTransition: AnyTransition {
        let insertionEdge: Edge = clueTransitionDirection == .trailing ? .trailing : .leading
        let removalEdge: Edge = clueTransitionDirection == .trailing ? .leading : .trailing

        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
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
        .background(Color.clear)
        .presentationDetents([.fraction(0.4), .large])
        .presentationContentInteraction(.scrolls)
        .presentationBackground(.ultraThinMaterial)
    }

    private var settingsSheet: some View {
        NavigationStack {
            List {
                Section("Appearance") {
                    Picker("Color Scheme", selection: $colorSchemePreference) {
                        ForEach(AppColorScheme.allCases) { scheme in
                            Text(scheme.rawValue).tag(scheme.rawValue)
                        }
                    }
                }

                Section("Puzzle") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Max crossword size")
                            Spacer()
                            Text("\(maximumGridDimension)")
                                .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(maximumGridDimension) },
                                set: { maximumGridDimension = Int($0.rounded()) }
                            ),
                            in: Double(CrosswordSettings.minimumGridDimension)...Double(CrosswordSettings.maximumGridDimension),
                            step: 1
                        )

                        Text("Allow puzzles up to \(maximumGridDimension)x\(maximumGridDimension) cells.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Checking") {
                    Toggle("Check as I type", isOn: $game.checkAsYouType)

                    Button("Check now") {
                        game.checkNow()
                        presentedSheet = nil
                        inputPanelMode = .keyboard
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
        .presentationDetents([.large])
        .presentationBackground(.ultraThinMaterial)
    }

    private var multiplayerSheet: some View {
        NavigationStack {
            multiplayerSheetContent
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }

    private var multiplayerSheetContent: some View {
        Group {
            if game.isJoinedLobby {
                joinedLobbyView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Picker("Multiplayer Mode", selection: $multiplayerMode) {
                            Text(game.hasConnectedGuests ? "Lobby" : "Join").tag(MultiplayerSheetMode.join)
                            Text("Host").tag(MultiplayerSheetMode.host)
                        }
                        .pickerStyle(.segmented)

                        switch multiplayerMode {
                        case .join:
                            if game.hasConnectedGuests {
                                hostLobbyView
                            } else {
                                multiplayerJoinView
                            }
                        case .host:
                            multiplayerHostView
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(Color.clear)
        .sheet(isPresented: $isShowingQRScanner) {
            QRScannerView { scannedValue in
                let formatted = formatScannedMultiplayerPin(scannedValue)
                guard isValidMultiplayerPin(formatted) else {
                    return
                }

                multiplayerJoinPin = formatted
                isShowingQRScanner = false
                game.joinLobby(pin: formatted)
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(.ultraThinMaterial)
        }
        .onChange(of: multiplayerJoinPin) { _, newValue in
            let formatted = formatMultiplayerPinInput(newValue)
            if formatted != newValue {
                multiplayerJoinPin = formatted
            }
        }
        .onChange(of: multiplayerMode) { _, newValue in
            if newValue == .host {
                game.connectAsHost()
            }
        }
    }

    private var multiplayerJoinView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Enter a game PIN to join an existing lobby.")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 18) {
                TextField("ABC-DEF", text: $multiplayerJoinPin)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.center)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .tracking(2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 1)
                    }

                Button {
                    game.joinLobby(pin: multiplayerJoinPin)
                } label: {
                    Text("Join")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isValidMultiplayerJoinPin ? Color.accentColor : Color.white.opacity(0.12))
                )
                .foregroundStyle(isValidMultiplayerJoinPin ? .white : .secondary)
                .disabled(!isValidMultiplayerJoinPin)

                HStack(spacing: 12) {
                    Divider()
                    Text("or")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Divider()
                }

                Button {
                    isShowingQRScanner = true
                } label: {
                    Label("Scan a QR", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.45), lineWidth: 1)
                }
                .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var multiplayerHostView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("3 ways to host: share the QR, share the game PIN, or send a link!")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            multiplayerOptionSection(title: "Share the QR", subtitle: "Someone nearby can scan this to join.") {
                QRCodeView(payload: game.multiplayerLobbyPin)
                    .frame(width: 220, height: 220)
                    .frame(maxWidth: .infinity)
            }

            Divider()

            multiplayerOptionSection(title: "Share the game PIN", subtitle: "Enter this code on another device.") {
                VStack(spacing: 8) {
                    Text("Game PIN")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(game.multiplayerLobbyPin)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .tracking(2)
                }
                .frame(maxWidth: .infinity)
            }

            Divider()

            multiplayerOptionSection(title: "Send a link", subtitle: "Send a one-tap join link to someone") {
                if let joinURL = game.multiplayerJoinURL {
                    ShareLink(item: joinURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.accentColor)
                    )
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            game.connectAsHost()
        }
    }

    private var hostLobbyView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Lobby")
                .font(.title3.weight(.semibold))

            VStack(spacing: 12) {
                ForEach(Array(game.orderedLobbyPlayers.enumerated()), id: \.element.id) { index, player in
                    playerLobbyRow(player: player, index: index)
                }
            }

            Color.clear.frame(height: 8)

            Button {
                game.endLobby()
            } label: {
                Text("End lobby")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.red.opacity(0.16))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.red.opacity(0.35), lineWidth: 1)
            }
            .foregroundStyle(.red)
        }
    }

    private var joinedLobbyView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("You're connected to a lobby.")
                .font(.title3.weight(.semibold))

            Button {
                game.leaveLobby()
            } label: {
                Text("Leave lobby")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.red.opacity(0.16))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.red.opacity(0.35), lineWidth: 1)
            }
            .foregroundStyle(.red)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func multiplayerOptionSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func playerLobbyRow(player: MultiplayerLobbyPlayer, index: Int) -> some View {
        let isLocalPlayer = player.id == game.multiplayerLocalPlayerID
        let title = isLocalPlayer ? "Player \(index + 1) (you)" : "Player \(index + 1)"
        let backgroundColor = game.lobbyRowColor(for: player)

        return HStack {
            Text(title)
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(backgroundColor.opacity(0.2))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(backgroundColor.opacity(0.45), lineWidth: 1)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if game.isHostingLobby && !isLocalPlayer {
                Button(role: .destructive) {
                    game.kick(playerID: player.id)
                } label: {
                    Text("Kick")
                }
            }
        }
    }

    private var isValidMultiplayerJoinPin: Bool {
        isValidMultiplayerPin(multiplayerJoinPin)
    }

    private func formatMultiplayerPinInput(_ value: String) -> String {
        let allowedCharacters = Set("23456789ABCDEFGHJKMNPQRSTVWXYZ")
        let cleaned = value.uppercased().filter { allowedCharacters.contains($0) }
        let trimmed = String(cleaned.prefix(6))

        if trimmed.count <= 3 {
            return trimmed
        }

        let prefix = trimmed.prefix(3)
        let suffix = trimmed.suffix(trimmed.count - 3)
        return "\(prefix)-\(suffix)"
    }

    private func isValidMultiplayerPin(_ value: String) -> Bool {
        let components = value.split(separator: "-")
        guard components.count == 2,
              components.allSatisfy({ $0.count == 3 }) else {
            return false
        }

        let allowedCharacters = Set("23456789ABCDEFGHJKMNPQRSTVWXYZ")
        return components.joined().allSatisfy { allowedCharacters.contains($0) }
    }

    private func formatScannedMultiplayerPin(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: trimmed),
           let candidate = url.queryParameters["pin"] ?? url.pathComponents.last,
           isValidMultiplayerPin(candidate.uppercased()) {
            return candidate.uppercased()
        }

        return formatMultiplayerPinInput(trimmed)
    }

    private func clueSection(title: String, clues: [CrosswordClue]) -> some View {
        Section {
            clueList(clues: clues)
        } header: {
            Text(title)
                .font(.system(size: 24, weight: .semibold, design: .serif))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .padding(.horizontal, 4)
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
                    presentedSheet = nil
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

    private var completionSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("Puzzle completed")
                    .font(.system(size: 30, weight: .semibold, design: .serif))

                Text("Everything checks out.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            Button {
                isKeyboardFocused = false
                presentedSheet = nil
                inputPanelMode = .keyboard
                game.loadNextPuzzleFromCompletionSheet()
            } label: {
                Text("Start a new puzzle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor)
            )
            .foregroundStyle(.white)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .presentationDetents([.fraction(0.34)])
        .presentationDragIndicator(.visible)
    }

}

private enum MultiplayerSheetMode: String, CaseIterable, Identifiable {
    case join = "Join"
    case host = "Host"

    var id: String { rawValue }
}

private struct CrosswordCellView: View {
    let cell: CrosswordCell
    let entry: String
    let size: CGFloat
    let isSelected: Bool
    let isHighlighted: Bool
    let remoteSelectedColor: Color?
    let remoteHighlightedColor: Color?
    let isIncorrect: Bool
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
                    .foregroundStyle(isIncorrect ? .red : .primary)
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
            return MultiplayerPlayerColor.localPlayer.opacity(0.52)
        }

        if isHighlighted {
            return MultiplayerPlayerColor.localPlayer.opacity(0.18)
        }

        if let remoteSelectedColor {
            return remoteSelectedColor.opacity(0.46)
        }

        if let remoteHighlightedColor {
            return remoteHighlightedColor.opacity(0.18)
        }

        return Color(uiColor: .systemBackground)
    }
}

private struct ToastBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.82))
            )
            .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
    }
}

private struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {
        uiViewController.onScan = onScan
    }
}

private final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasScanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureCaptureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !captureSession.isRunning {
            captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    private func configureCaptureSession() {
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice),
              captureSession.canAddInput(videoInput) else {
            return
        }

        captureSession.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(metadataOutput) else {
            return
        }

        captureSession.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        metadataOutput.metadataObjectTypes = [.qr]

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.layer.bounds
        view.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasScanned,
              let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              metadataObject.type == .qr,
              let scanned = metadataObject.stringValue else {
            return
        }

        hasScanned = true
        captureSession.stopRunning()
        onScan?(scanned)
    }
}

private struct QRCodeView: View {
    let payload: String

    var body: some View {
        Group {
            if let image = qrImage {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(0.08))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white)
        )
    }

    private var qrImage: UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}

private extension URL {
    var queryParameters: [String: String] {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .reduce(into: [:]) { partialResult, item in
                partialResult[item.name.lowercased()] = item.value
            } ?? [:]
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
