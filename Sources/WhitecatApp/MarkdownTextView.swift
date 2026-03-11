import AppKit
import SwiftUI

struct MarkdownTextView: View {
    @Binding var text: String
    var isFocused: Bool
    @AppStorage("showsMarkdownPreview") private var showsPreview = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Markdown")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(showsPreview ? "隐藏预览" : "显示预览") {
                    showsPreview.toggle()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)

            GeometryReader { geometry in
                if showsPreview {
                    if geometry.size.width >= 920 {
                        HSplitView {
                            editor
                                .frame(minWidth: 0, maxWidth: .infinity)
                            preview
                                .frame(minWidth: 300, maxWidth: .infinity)
                        }
                    } else {
                        VStack(spacing: 0) {
                            editor
                            Divider()
                            preview
                                .frame(minHeight: max(220, geometry.size.height * 0.35))
                        }
                    }
                } else {
                    editor
                }
            }
        }
    }

    private var editor: some View {
        MarkdownEditorTextView(text: $text, isFocused: isFocused)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var preview: some View {
        MarkdownPreviewView(text: text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MarkdownEditorTextView: NSViewRepresentable {
    @Binding var text: String
    var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.usesFindBar = true
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.textContainerInset = NSSize(width: 0, height: 12)
        textView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.drawsBackground = false
        textView.string = text
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        if isFocused, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            text = textView.string
        }
    }
}

private struct MarkdownPreviewView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.usesFindBar = true
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.importsGraphics = false
        textView.textContainerInset = NSSize(width: 0, height: 12)
        textView.drawsBackground = false
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.textStorage?.setAttributedString(Self.renderedMarkdown(text))
    }

    private static func renderedMarkdown(_ text: String) -> NSAttributedString {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return NSAttributedString(
                string: "开始输入后，这里会实时渲染 Markdown。",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 14),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
        }

        do {
            let options = AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
            let parsed = try AttributedString(markdown: text, options: options)
            let rendered = NSMutableAttributedString(attributedString: NSAttributedString(parsed))
            let fullRange = NSRange(location: 0, length: rendered.length)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            paragraphStyle.paragraphSpacing = 8
            rendered.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
            rendered.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
            return rendered
        } catch {
            return NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 15),
                    .foregroundColor: NSColor.labelColor
                ]
            )
        }
    }
}
