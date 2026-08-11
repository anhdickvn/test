import SwiftUI
import UIKit

/// UITextField nhỏ có bắt phím Tab từ bàn phím vật lý để mô phỏng autocomplete Minecraft.
struct MCTabTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String
    var onSubmit: () -> Void
    var onTab: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> TabAwareUITextField {
        let field = TabAwareUITextField(frame: .zero)
        field.borderStyle = .roundedRect
        field.placeholder = placeholder
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.returnKeyType = .send
        field.delegate = context.coordinator
        field.onTab = onTab
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: TabAwareUITextField, context: Context) {
        context.coordinator.parent = self
        uiView.onTab = onTab
        if uiView.text != text {
            uiView.text = text
        }
        if isFocused && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFocused && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: MCTabTextField

        init(parent: MCTabTextField) {
            self.parent = parent
        }

        @objc func editingChanged(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.text = textField.text ?? ""
            parent.onSubmit()
            return false
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFocused = false
        }
    }
}

final class TabAwareUITextField: UITextField {
    var onTab: (() -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        var commands = super.keyCommands ?? []
        commands.append(UIKeyCommand(input: UIKeyCommand.inputTab,
                                     modifierFlags: [],
                                     action: #selector(handleTabKey)))
        return commands
    }

    @objc private func handleTabKey() {
        onTab?()
    }
}
