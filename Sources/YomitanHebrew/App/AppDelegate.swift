import AppKit
import Combine
import YomitanCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let selectedTextReader = SelectedTextReader()

    private lazy var model = LookupViewModel(settings: settings)
    private lazy var panelController = LookupPanelController(model: model)

    private var statusItem: NSStatusItem?
    private weak var lookupMenuItem: NSMenuItem?
    private var hotKey: GlobalHotKey?
    private var activeHotKeyConfiguration: HotKeyConfiguration?
    private var hotKeyUpdateToIgnore: HotKeyConfiguration?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        observeHotKeySettings()
        replaceHotKey(with: settings.hotKey, showPanelOnFailure: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey?.invalidate()
        hotKey = nil
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = StatusBarIcon.make()
            button.imageScaling = .scaleProportionallyDown
            button.imagePosition = .imageOnly
            button.toolTip = "Yomitan Hebrew"
            button.setAccessibilityLabel("Yomitan Hebrew")
            button.setAccessibilityHelp("Открыть меню Yomitan Hebrew")
        }

        let menu = NSMenu()
        let lookupItem = NSMenuItem(
            title: lookupMenuTitle(for: settings.hotKey),
            action: #selector(lookUpSelectionFromMenu),
            keyEquivalent: ""
        )
        lookupItem.target = self
        menu.addItem(lookupItem)
        self.lookupMenuItem = lookupItem

        let openItem = NSMenuItem(
            title: "Открыть окно",
            action: #selector(openWindow),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(
            title: "Настройки…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Завершить Yomitan Hebrew",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    private func observeHotKeySettings() {
        settings.$hotKey
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] configuration in
                Task { @MainActor in
                    guard let self else { return }
                    if self.hotKeyUpdateToIgnore == configuration {
                        self.hotKeyUpdateToIgnore = nil
                        return
                    }
                    guard !self.settings.isRecordingHotKey else { return }
                    self.replaceHotKey(with: configuration)
                }
            }
            .store(in: &cancellables)

        settings.$isRecordingHotKey
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] isRecording in
                Task { @MainActor in
                    guard let self else { return }
                    if isRecording {
                        self.settings.hotKeyRegistrationError = nil
                        self.hotKey?.invalidate()
                        self.hotKey = nil
                    } else {
                        self.replaceHotKey(with: self.settings.hotKey)
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func replaceHotKey(
        with configuration: HotKeyConfiguration,
        showPanelOnFailure: Bool = false
    ) {
        if configuration == activeHotKeyConfiguration, hotKey != nil {
            settings.hotKeyRegistrationError = nil
            updateLookupMenu(for: configuration)
            return
        }

        let previous = activeHotKeyConfiguration
        hotKey?.invalidate()
        hotKey = nil

        do {
            hotKey = try makeHotKey(configuration)
            activeHotKeyConfiguration = configuration
            settings.hotKeyRegistrationError = nil
            updateLookupMenu(for: configuration)
        } catch {
            let message = "Сочетание \(configuration.displayString) недоступно: \(error.localizedDescription)"
            settings.hotKeyRegistrationError = message

            if let previous {
                hotKey = try? makeHotKey(previous)
                activeHotKeyConfiguration = hotKey == nil ? nil : previous
                updateLookupMenu(for: previous)

                if settings.hotKey != previous {
                    hotKeyUpdateToIgnore = previous
                    settings.hotKey = previous
                }
            } else {
                activeHotKeyConfiguration = nil
            }

            if showPanelOnFailure {
                model.showsSettings = true
                panelController.show()
            }
        }
    }

    private func makeHotKey(_ configuration: HotKeyConfiguration) throws -> GlobalHotKey {
        try GlobalHotKey(configuration: configuration) { [weak self] in
            self?.lookUpSelection()
        }
    }

    private func updateLookupMenu(for configuration: HotKeyConfiguration) {
        lookupMenuItem?.title = lookupMenuTitle(for: configuration)
    }

    private func lookupMenuTitle(for configuration: HotKeyConfiguration) -> String {
        "Найти выделенное слово — \(configuration.displayString)"
    }

    @objc private func lookUpSelectionFromMenu() {
        lookUpSelection()
    }

    private func lookUpSelection() {
        model.beginReadingSelection()
        Task { @MainActor in
            do {
                // Capture before activating our own panel so the source app keeps focus.
                let selection = try await selectedTextReader.readSelection()
                panelController.show()
                await model.lookup(selection)
            } catch {
                model.show(error: error)
                panelController.show()
            }
        }
    }

    @objc private func openWindow() {
        model.showsSettings = false
        panelController.show()
    }

    @objc private func openSettings() {
        model.showsSettings = true
        panelController.show()
    }
}
