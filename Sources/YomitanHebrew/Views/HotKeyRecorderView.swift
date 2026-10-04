import AppKit
import SwiftUI
import YomitanCore

/// Native key recorder embedded in SwiftUI. While it is active the app's current
/// Carbon hotkey is temporarily released, allowing the same combination to be
/// recorded again and preventing an accidental lookup.
struct HotKeyRecorderView: NSViewRepresentable {
    @Binding var configuration: HotKeyConfiguration
    @Binding var isRecording: Bool
    @Binding var validationMessage: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            configuration: $configuration,
            isRecording: $isRecording,
            validationMessage: $validationMessage
        )
    }

    func makeNSView(context: Context) -> HotKeyRecorderButton {
        let button = HotKeyRecorderButton(configuration: configuration)
        button.onConfiguration = { [weak coordinator = context.coordinator] value in
            coordinator?.record(value)
        }
        button.onRecordingChanged = { [weak coordinator = context.coordinator] value in
            coordinator?.setRecording(value)
        }
        button.onValidation = { [weak coordinator = context.coordinator] message in
            coordinator?.setValidation(message)
        }
        return button
    }

    func updateNSView(_ button: HotKeyRecorderButton, context: Context) {
        context.coordinator.update(
            configuration: $configuration,
            isRecording: $isRecording,
            validationMessage: $validationMessage
        )
        button.configuration = configuration
        if !isRecording, button.isRecording {
            button.cancelRecording(notify: false)
        }
    }

    static func dismantleNSView(_ button: HotKeyRecorderButton, coordinator: Coordinator) {
        button.cancelRecording()
    }

    @MainActor
    final class Coordinator {
        private var configuration: Binding<HotKeyConfiguration>
        private var isRecording: Binding<Bool>
        private var validationMessage: Binding<String?>

        init(
            configuration: Binding<HotKeyConfiguration>,
            isRecording: Binding<Bool>,
            validationMessage: Binding<String?>
        ) {
            self.configuration = configuration
            self.isRecording = isRecording
            self.validationMessage = validationMessage
        }

        func update(
            configuration: Binding<HotKeyConfiguration>,
            isRecording: Binding<Bool>,
            validationMessage: Binding<String?>
        ) {
            self.configuration = configuration
            self.isRecording = isRecording
            self.validationMessage = validationMessage
        }

        func record(_ value: HotKeyConfiguration) {
            configuration.wrappedValue = value
            validationMessage.wrappedValue = nil
        }

        func setRecording(_ value: Bool) {
            isRecording.wrappedValue = value
            if value {
                validationMessage.wrappedValue = nil
            }
        }

        func setValidation(_ message: String?) {
            validationMessage.wrappedValue = message
        }
    }
}

@MainActor
final class HotKeyRecorderButton: NSButton {
    var configuration: HotKeyConfiguration {
        didSet { updateTitle() }
    }

    private(set) var isRecording = false
    var onConfiguration: ((HotKeyConfiguration) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    var onValidation: ((String?) -> Void)?

    init(configuration: HotKeyConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        bezelStyle = .rounded
        controlSize = .large
        font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        target = self
        action = #selector(beginRecording)
        toolTip = "Нажмите, затем введите новое сочетание клавиш"
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        onRecordingChanged?(true)
        onValidation?(nil)
        updateTitle()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        let keyCode = UInt32(event.keyCode)
        if keyCode == 53 { // Escape cancels recording.
            cancelRecording()
            return
        }

        guard !Self.modifierKeyCodes.contains(event.keyCode) else {
            NSSound.beep()
            return
        }

        let modifiers = Self.modifiers(from: event.modifierFlags)
        let hasSafeModifier = modifiers.contains(.command)
            || modifiers.contains(.option)
            || modifiers.contains(.control)
        guard hasSafeModifier || Self.functionKeyCodes.contains(event.keyCode) else {
            NSSound.beep()
            onValidation?("Добавьте ⌘, ⌥ или ⌃ — либо используйте F‑клавишу.")
            title = "Нажмите другое сочетание…"
            return
        }

        let label = HotKeyConfiguration.keyLabel(
            for: keyCode,
            characters: event.charactersIgnoringModifiers
        )
        let value = HotKeyConfiguration(
            keyCode: keyCode,
            modifiers: modifiers,
            keyLabel: label
        )
        configuration = value
        onConfiguration?(value)
        finishRecording()
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if isRecording {
            cancelRecording()
        }
        return result
    }

    func cancelRecording(notify: Bool = true) {
        guard isRecording else { return }
        isRecording = false
        updateTitle()
        if notify {
            onRecordingChanged?(false)
        }
    }

    private func finishRecording() {
        isRecording = false
        updateTitle()
        onRecordingChanged?(false)
        window?.makeFirstResponder(nil)
    }

    private func updateTitle() {
        title = isRecording ? "Нажмите сочетание…" : configuration.displayString
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> HotKeyModifiers {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var value: HotKeyModifiers = []
        if flags.contains(.command) { value.insert(.command) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.control) { value.insert(.control) }
        if flags.contains(.shift) { value.insert(.shift) }
        return value
    }

    private static let modifierKeyCodes: Set<UInt16> = [
        54, 55, // Command
        56, 60, // Shift
        57,     // Caps Lock
        58, 61, // Option
        59, 62, // Control
        63      // Function
    ]

    private static let functionKeyCodes: Set<UInt16> = [
        64, 79, 80, 90, 96, 97, 98, 99, 100, 101,
        103, 105, 106, 107, 109, 111, 113, 118, 120, 122
    ]
}
