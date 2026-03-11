import AppKit
import Carbon.HIToolbox
import Combine
import NotesCore
import SwiftUI

@MainActor
final class QuickCaptureController: ObservableObject {
    static let shortcutDisplay = "\u{2325}\u{2318}N"

    private weak var model: AppModel?
    private let viewModel = QuickCaptureViewModel()
    private var didConfigure = false
    private var appearanceObserver: AnyCancellable?

    private lazy var hotKeyMonitor = GlobalHotKeyMonitor(
        keyCode: UInt32(kVK_ANSI_N),
        modifiers: UInt32(optionKey | cmdKey)
    ) { [weak self] in
        Task { @MainActor in
            self?.show()
        }
    }

    private lazy var panelController = QuickCapturePanelController(
        viewModel: viewModel,
        onSubmit: { [weak self] in
            self?.submit()
        },
        onCancel: { [weak self] in
            self?.hide()
        }
    )

    func configure(model: AppModel) {
        self.model = model
        panelController.applyAppearance(model.appearancePreference)
        appearanceObserver = model.$snapshot
            .map(\.preferences.appearance)
            .removeDuplicates()
            .sink { [weak self] appearance in
                self?.panelController.applyAppearance(appearance)
            }

        guard !didConfigure else { return }
        hotKeyMonitor.start()
        didConfigure = true
    }

    func show() {
        viewModel.requestFocus()
        panelController.applyAppearance(model?.appearancePreference ?? .system)
        NSApp.activate(ignoringOtherApps: true)
        panelController.show()
    }

    func hide() {
        panelController.hide()
        viewModel.reset()
    }

    private func submit() {
        let body = viewModel.text
        hide()

        Task { @MainActor [weak self] in
            await self?.model?.saveQuickCaptureNote(body: body)
        }
    }
}

@MainActor
private final class QuickCapturePanelController: NSWindowController {
    init(
        viewModel: QuickCaptureViewModel,
        onSubmit: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        let panel = QuickCapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 260),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let contentView = QuickCaptureView(
            viewModel: viewModel,
            onSubmit: onSubmit,
            onCancel: onCancel
        )
        panel.contentViewController = NSHostingController(rootView: contentView)

        super.init(window: panel)
        shouldCascadeWindows = false
        window?.setFrameAutosaveName("WhitecatQuickCapture")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func applyAppearance(_ appearance: AppAppearancePreference) {
        window?.appearance = appearance.nsAppearance
    }

    func hide() {
        close()
    }
}

private final class QuickCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class GlobalHotKeyMonitor {
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let handler: @Sendable () -> Void
    private let hotKeyID = EventHotKeyID(signature: 0x57435451, id: 1)

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    init(
        keyCode: UInt32,
        modifiers: UInt32,
        handler: @escaping @Sendable () -> Void
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.handler = handler
    }

    func start() {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }

                let monitor = Unmanaged<GlobalHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr else { return status }
                guard hotKeyID.signature == monitor.hotKeyID.signature,
                      hotKeyID.id == monitor.hotKeyID.id
                else {
                    return noErr
                }

                monitor.handler()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
