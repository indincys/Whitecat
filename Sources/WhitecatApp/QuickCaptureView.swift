import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class QuickCaptureViewModel: ObservableObject {
    @Published var text: String = ""
    @Published private(set) var focusTicket: Int = 0

    func requestFocus() {
        focusTicket += 1
    }

    func reset() {
        text = ""
        requestFocus()
    }
}

struct QuickCaptureView: View {
    @ObservedObject var viewModel: QuickCaptureViewModel
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            QuickCaptureTextView(
                text: $viewModel.text,
                focusTicket: viewModel.focusTicket,
                onSubmit: onSubmit,
                onCancel: onCancel
            )

            if viewModel.text.isEmpty {
                Text("直接输入正文，按 Command-Enter 保存，按 Esc 关闭")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                    .padding(.top, 18)
                    .allowsHitTesting(false)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 260)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct QuickCaptureTextView: NSViewRepresentable {
    @Binding var text: String
    let focusTicket: Int
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        let contentSize = scrollView.contentSize

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: contentSize.width, height: .greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let captureTextView = QuickCaptureNSTextView(
            frame: NSRect(origin: .zero, size: contentSize),
            textContainer: textContainer
        )
        captureTextView.minSize = NSSize(width: 0, height: 0)
        captureTextView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        captureTextView.isVerticallyResizable = true
        captureTextView.isHorizontallyResizable = false
        captureTextView.autoresizingMask = [.width]
        captureTextView.textContainerInset = NSSize(width: 0, height: 12)
        captureTextView.font = .systemFont(ofSize: 17, weight: .regular)
        captureTextView.drawsBackground = false
        captureTextView.isRichText = false
        captureTextView.usesFindBar = false
        captureTextView.allowsUndo = true
        captureTextView.delegate = context.coordinator
        captureTextView.string = text
        captureTextView.onSubmit = onSubmit
        captureTextView.onCancel = onCancel
        context.coordinator.textView = captureTextView
        scrollView.documentView = captureTextView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? QuickCaptureNSTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        textView.onSubmit = onSubmit
        textView.onCancel = onCancel

        if context.coordinator.lastFocusTicket != focusTicket {
            context.coordinator.lastFocusTicket = focusTicket
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?
        var lastFocusTicket: Int = -1

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            text = textView.string
        }
    }
}

private final class QuickCaptureNSTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) && (event.keyCode == UInt16(kVK_Return) || event.keyCode == 76) {
            onSubmit?()
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }

        super.keyDown(with: event)
    }
}
