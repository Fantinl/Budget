#if os(macOS)
import AppKit
import Carbon.HIToolbox
import ServiceManagement

extension Notification.Name {
    /// Demande l'ouverture de la fenêtre principale (écoutée par l'étiquette du MenuBarExtra).
    static let openMainWindow = Notification.Name("budget.openMainWindow")
}

/// Clés des réglages de la barre des menus.
enum MenuBarSettings {
    static let enabled = "menuBarEnabled"
    static let hotKey = "menuBarHotKeyEnabled"
}

/// Raccourci global ⌥⌘B via Carbon (aucune permission d'accessibilité requise).
@MainActor
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) { self.action = action }

    var isRegistered: Bool { hotKeyRef != nil }

    func register() {
        guard hotKeyRef == nil else { return }
        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let context = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { hotKey.action() }
                return noErr
            }, 1, &spec, context, &handlerRef)
        }
        let id = EventHotKeyID(signature: OSType(0x4244_4754), id: 1) // « BDGT »
        RegisterEventHotKey(UInt32(kVK_ANSI_B), UInt32(cmdKey | optionKey), id,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    deinit {
        // Le gestionnaire vit autant que l'app ; on libère seulement ce qui est possible ici.
    }
}

/// Garde la barre des menus cohérente avec les réglages, même fenêtre principale fermée :
/// raccourci global, ouverture au démarrage, ouverture du panneau.
@MainActor
final class MenuBarCoordinator {
    static let shared = MenuBarCoordinator()

    private var hotKey: GlobalHotKey!
    private var observer: NSObjectProtocol?

    private init() {
        hotKey = GlobalHotKey { [weak self] in self?.togglePanel() }
    }

    /// À appeler au lancement : applique les réglages puis les suit.
    func start() {
        guard observer == nil else { return }
        sync()
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
    }

    private func sync() {
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: MenuBarSettings.enabled)
        let hotKeyOn = defaults.object(forKey: MenuBarSettings.hotKey) as? Bool ?? true
        if enabled && hotKeyOn { hotKey.register() } else { hotKey.unregister() }
        // Désactivée : on retire aussi l'ouverture au démarrage.
        if !enabled, SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
            try? SMAppService.mainApp.unregister()
        }
    }

    /// Ouvre ou ferme le panneau en simulant un clic sur l'icône ; à défaut, ouvre la fenêtre principale.
    func togglePanel() {
        if let button = statusButton() {
            button.performClick(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .openMainWindow, object: nil)
        }
    }

    /// Retrouve le bouton de l'icône du MenuBarExtra (pas d'API officielle).
    private func statusButton() -> NSStatusBarButton? {
        for window in NSApp.windows where String(describing: type(of: window)).contains("NSStatusBarWindow") {
            if window.responds(to: NSSelectorFromString("statusItem")),
               let item = window.value(forKey: "statusItem") as? NSStatusItem, let button = item.button {
                return button
            }
            if let button = findButton(in: window.contentView) { return button }
        }
        return nil
    }

    private func findButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for sub in view.subviews { if let found = findButton(in: sub) { return found } }
        return nil
    }
}
#endif
