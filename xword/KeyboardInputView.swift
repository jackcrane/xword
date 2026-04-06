//
//  KeyboardInputView.swift
//  xword
//

import SwiftUI
import UIKit

struct KeyboardInputView: UIViewRepresentable {
    @Binding var isFocused: Bool
    let onInsertText: (String) -> Void
    let onDeleteBackward: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onInsertText: onInsertText, onDeleteBackward: onDeleteBackward)
    }

    func makeUIView(context: Context) -> InputTextField {
        let textField = InputTextField()
        textField.delegate = context.coordinator
        textField.deleteHandler = onDeleteBackward
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .allCharacters
        textField.keyboardType = .asciiCapable
        textField.spellCheckingType = .no
        textField.textColor = .clear
        textField.tintColor = .clear
        textField.backgroundColor = .clear
        textField.text = ""
        return textField
    }

    func updateUIView(_ uiView: InputTextField, context: Context) {
        uiView.deleteHandler = onDeleteBackward

        if isFocused, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFocused, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private let onInsertText: (String) -> Void
        private let onDeleteBackward: () -> Void

        init(
            onInsertText: @escaping (String) -> Void,
            onDeleteBackward: @escaping () -> Void
        ) {
            self.onInsertText = onInsertText
            self.onDeleteBackward = onDeleteBackward
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            if string.isEmpty {
                textField.text = ""
                return false
            }

            onInsertText(string)
            textField.text = ""
            return false
        }
    }
}

final class InputTextField: UITextField {
    var deleteHandler: (() -> Void)?

    override func deleteBackward() {
        deleteHandler?()
        text = ""
    }
}
