//
//  KeyboardInputView.swift
//  xword
//

import SwiftUI

struct KeyboardInputView: View {
    @Binding var isFocused: Bool
    @Binding var selectedMode: InputPanelMode
    let onInsertText: (String) -> Void
    let onDeleteBackward: () -> Void

    private let topRow: [String] = ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"]
    private let middleRow: [String] = ["A", "S", "D", "F", "G", "H", "J", "K", "L"]
    private let bottomRow: [String] = ["Z", "X", "C", "V", "B", "N", "M"]

    var body: some View {
        VStack(spacing: 8) {
            letterRow(topRow)

            HStack(spacing: 6) {
                Spacer(minLength: 18)
                letterKeys(middleRow)
                Spacer(minLength: 18)
            }

            HStack(spacing: 6) {
                utilityKey(systemName: "keyboard.chevron.compact.down", width: 62) {
                    isFocused = false
                }

                letterKeys(bottomRow)

                utilityKey(systemName: "delete.left", width: 62) {
                    onDeleteBackward()
                }
            }

            Picker("Input Mode", selection: $selectedMode) {
                Text("Keyboard").tag(InputPanelMode.keyboard)
                Text("Clues").tag(InputPanelMode.clues)
                Text("Settings").tag(InputPanelMode.settings)
            }
            .pickerStyle(.segmented)
            .padding(.top, 2)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    @ViewBuilder
    private func letterRow(_ letters: [String]) -> some View {
        HStack(spacing: 6) {
            letterKeys(letters)
        }
    }

    @ViewBuilder
    private func letterKeys(_ letters: [String]) -> some View {
        ForEach(letters, id: \.self) { letter in
            key(letter) {
                onInsertText(letter)
            }
        }
    }

    private func key(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .foregroundStyle(.primary)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }

    private func utilityKey(systemName: String, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: width, height: 36)
                .foregroundStyle(.primary)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                )
        }
        .buttonStyle(.plain)
    }
}
