import AppKit
import Combine
import SwiftUI

@MainActor
final class RecordingOverlayController {
    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var hostingView: NSHostingView<AnyView>?
    private var isShowing = false

    // Pill is 64x32, panel has padding for shadow
    private let panelSize = CGSize(width: 96, height: 64)

    func bind(to appState: AppState) {
        Publishers.CombineLatest4(
            appState.$isRecording,
            appState.$statusMessage,
            appState.$audioLevel,
            appState.$showRecordingPill
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] isRecording, status, level, pillEnabled in
            guard let self else { return }

            if !pillEnabled {
                self.hide()
                return
            }

            if isRecording {
                self.show(state: .recording, audioLevel: level)
            } else if status == "Transcribing..." || status == "Processing..." {
                self.show(state: .transcribing, audioLevel: 0)
            } else {
                self.hide()
            }
        }
        .store(in: &cancellables)
    }

    private func show(state: RecordingPillState, audioLevel: Float) {
        if panel == nil {
            createPanel()
        }

        isShowing = true

        let pillView = RecordingPillView(state: state, audioLevel: audioLevel)
        hostingView?.rootView = AnyView(pillView)

        guard let panel else { return }

        // Place on the screen where the mouse cursor is
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(mouseLocation)
        }) ?? NSScreen.main ?? NSScreen.screens.first

        guard let screen else { return }

        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - panelSize.width / 2
        let y = screenFrame.minY + 50

        panel.setFrame(
            NSRect(origin: CGPoint(x: x, y: y), size: panelSize),
            display: true
        )
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    private func hide() {
        guard isShowing else { return }
        isShowing = false

        guard let panel else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, !self.isShowing else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func createPanel() {
        let wrappedView = AnyView(RecordingPillView(state: .recording, audioLevel: 0))
        let hosting = NSHostingView(rootView: wrappedView)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting

        self.panel = panel
        self.hostingView = hosting
    }
}
