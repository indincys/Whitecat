import AppKit
import SwiftUI

@MainActor
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(width: contentSize.width, height: .greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)
        layoutManager.addTextContainer(textContainer)

        let textView = MarkdownEditingTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.textContainerInset = NSSize(width: 0, height: 12)
        textView.font = MarkdownInlineStyler.bodyFont
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.typingAttributes = MarkdownInlineStyler.baseTypingAttributes

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.applyText(text, to: textView, preserveSelection: false)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownEditingTextView else { return }
        context.coordinator.textView = textView

        if textView.string != text, textView.markedRange().location == NSNotFound {
            context.coordinator.applyText(text, to: textView, preserveSelection: true)
        }

        if isFocused, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        fileprivate weak var textView: MarkdownEditingTextView?
        private var isApplyingStyle = false

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !isApplyingStyle else { return }
            text = textView.string

            // Do not disturb IME composition while the user is still choosing characters.
            guard textView.markedRange().location == NSNotFound else { return }
            applyStyles(to: textView, preserveSelection: true)
        }

        fileprivate func applyText(_ text: String, to textView: MarkdownEditingTextView, preserveSelection: Bool) {
            isApplyingStyle = true
            textView.string = text
            isApplyingStyle = false
            applyStyles(to: textView, preserveSelection: preserveSelection)
        }

        private func applyStyles(to textView: MarkdownEditingTextView, preserveSelection: Bool) {
            let selectedRanges = preserveSelection ? textView.selectedRanges : []
            let rendered = MarkdownInlineStyler.render(textView.string)

            isApplyingStyle = true
            textView.textStorage?.beginEditing()
            textView.textStorage?.setAttributedString(rendered)
            textView.textStorage?.endEditing()
            textView.typingAttributes = MarkdownInlineStyler.baseTypingAttributes
            if preserveSelection {
                textView.selectedRanges = selectedRanges
            }
            isApplyingStyle = false
        }
    }
}

@MainActor
fileprivate final class MarkdownEditingTextView: NSTextView {}

@MainActor
fileprivate enum MarkdownInlineStyler {
    static let bodyFont = NSFont.systemFont(ofSize: 16)
    static let codeFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    static let italicBodyFont = NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask)
    static let baseParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5
        style.paragraphSpacing = 9
        return style
    }()

    static let baseTypingAttributes: [NSAttributedString.Key: Any] = [
        .font: bodyFont,
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: baseParagraphStyle
    ]

    static func render(_ source: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: source, attributes: baseTypingAttributes)
        let protectedRanges = applyCodeStyles(to: attributed, source: source)
        applyHeadingStyles(to: attributed, source: source, protectedRanges: protectedRanges)
        applyQuoteStyles(to: attributed, source: source, protectedRanges: protectedRanges)
        applyListStyles(to: attributed, source: source, protectedRanges: protectedRanges)
        applyTaskListStyles(to: attributed, source: source, protectedRanges: protectedRanges)
        applyDelimitedStyle(pattern: #"\*\*([^\n]+?)\*\*"#, markerLength: 2, font: .boldSystemFont(ofSize: 16), to: attributed, source: source, protectedRanges: protectedRanges)
        applyDelimitedStyle(pattern: #"__([^\n]+?)__"#, markerLength: 2, font: .boldSystemFont(ofSize: 16), to: attributed, source: source, protectedRanges: protectedRanges)
        applyDelimitedStyle(pattern: #"(?<!\*)\*([^*\n]+?)\*(?!\*)"#, markerLength: 1, font: italicBodyFont, to: attributed, source: source, protectedRanges: protectedRanges)
        applyDelimitedStyle(pattern: #"(?<!_)_([^_\n]+?)_(?!_)"#, markerLength: 1, font: italicBodyFont, to: attributed, source: source, protectedRanges: protectedRanges)
        applyStrikethroughStyles(to: attributed, source: source, protectedRanges: protectedRanges)
        applyLinkStyles(to: attributed, source: source, protectedRanges: protectedRanges)
        return attributed
    }

    private static func applyHeadingStyles(to attributed: NSMutableAttributedString, source: String, protectedRanges: [NSRange]) {
        let sizes: [CGFloat] = [30, 26, 23, 21, 19, 18]
        for match in matches(of: #"(?m)^(#{1,6})([ \t]+)(.*)$"#, in: source) {
            guard !intersectsProtectedRange(match.range, protectedRanges: protectedRanges) else { continue }
            let level = max(1, min(6, match.range(at: 1).length))
            let markerRange = NSRange(location: match.range.location, length: match.range(at: 1).length + match.range(at: 2).length)
            styleMarkerRange(markerRange, in: attributed)
            attributed.addAttributes(
                [
                    .font: NSFont.systemFont(ofSize: sizes[level - 1], weight: .bold),
                    .foregroundColor: NSColor.labelColor
                ],
                range: match.range(at: 3)
            )
        }
    }

    private static func applyQuoteStyles(to attributed: NSMutableAttributedString, source: String, protectedRanges: [NSRange]) {
        for match in matches(of: #"(?m)^(>)([ \t]?)(.*)$"#, in: source) {
            guard !intersectsProtectedRange(match.range, protectedRanges: protectedRanges) else { continue }
            let markerRange = NSRange(location: match.range.location, length: match.range(at: 1).length + match.range(at: 2).length)
            styleMarkerRange(markerRange, in: attributed)
            attributed.addAttributes(
                [
                    .font: NSFont.systemFont(ofSize: 16, weight: .medium),
                    .foregroundColor: NSColor.secondaryLabelColor
                ],
                range: match.range(at: 3)
            )
        }
    }

    private static func applyListStyles(to attributed: NSMutableAttributedString, source: String, protectedRanges: [NSRange]) {
        for match in matches(of: #"(?m)^([ \t]*)([-*+]|\d+\.)([ \t]+)"#, in: source) {
            guard !intersectsProtectedRange(match.range, protectedRanges: protectedRanges) else { continue }
            attributed.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: match.range(at: 2))
        }
    }

    private static func applyTaskListStyles(to attributed: NSMutableAttributedString, source: String, protectedRanges: [NSRange]) {
        for match in matches(of: #"(?m)^([ \t]*[-*+][ \t]+\[[ xX]\])([ \t]*)(.*)$"#, in: source) {
            guard !intersectsProtectedRange(match.range, protectedRanges: protectedRanges) else { continue }
            styleMarkerRange(NSRange(location: match.range.location, length: match.range(at: 1).length + match.range(at: 2).length), in: attributed)
            let marker = (source as NSString).substring(with: match.range(at: 1))
            if marker.contains("[x]") || marker.contains("[X]") {
                attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: match.range(at: 3))
                attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range(at: 3))
            }
        }
    }

    private static func applyDelimitedStyle(
        pattern: String,
        markerLength: Int,
        font: NSFont,
        to attributed: NSMutableAttributedString,
        source: String,
        protectedRanges: [NSRange]
    ) {
        for match in matches(of: pattern, in: source) {
            guard !intersectsProtectedRange(match.range, protectedRanges: protectedRanges) else { continue }
            let contentRange = match.range(at: 1)
            let leadingMarkerRange = NSRange(location: match.range.location, length: markerLength)
            let trailingMarkerRange = NSRange(location: match.range.location + match.range.length - markerLength, length: markerLength)
            styleMarkerRange(leadingMarkerRange, in: attributed)
            styleMarkerRange(trailingMarkerRange, in: attributed)
            attributed.addAttributes([.font: font, .foregroundColor: NSColor.labelColor], range: contentRange)
        }
    }

    private static func applyStrikethroughStyles(to attributed: NSMutableAttributedString, source: String, protectedRanges: [NSRange]) {
        for match in matches(of: #"~~([^~\n]+?)~~"#, in: source) {
            guard !intersectsProtectedRange(match.range, protectedRanges: protectedRanges) else { continue }
            let contentRange = match.range(at: 1)
            styleMarkerRange(NSRange(location: match.range.location, length: 2), in: attributed)
            styleMarkerRange(NSRange(location: match.range.location + match.range.length - 2, length: 2), in: attributed)
            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
        }
    }

    private static func applyLinkStyles(to attributed: NSMutableAttributedString, source: String, protectedRanges: [NSRange]) {
        for match in matches(of: #"\[([^\]]+)\]\(([^)]+)\)"#, in: source) {
            guard !intersectsProtectedRange(match.range, protectedRanges: protectedRanges) else { continue }
            let textRange = match.range(at: 1)
            attributed.addAttributes(
                [
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ],
                range: textRange
            )
            let fullRange = match.range
            let openingRange = NSRange(location: fullRange.location, length: 1)
            let afterTextLocation = textRange.location + textRange.length
            let trailingRange = NSRange(location: afterTextLocation, length: fullRange.location + fullRange.length - afterTextLocation)
            styleMarkerRange(openingRange, in: attributed)
            styleMarkerRange(trailingRange, in: attributed)
        }
    }

    private static func applyCodeStyles(to attributed: NSMutableAttributedString, source: String) -> [NSRange] {
        var protectedRanges: [NSRange] = []

        for match in matches(of: #"(?ms)```.*?```"#, in: source) {
            protectedRanges.append(match.range)
            attributed.addAttributes(
                [
                    .font: codeFont,
                    .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.12),
                    .foregroundColor: NSColor.labelColor
                ],
                range: match.range
            )
            styleMarkerRange(NSRange(location: match.range.location, length: min(3, match.range.length)), in: attributed)
            if match.range.length >= 6 {
                styleMarkerRange(NSRange(location: match.range.location + match.range.length - 3, length: 3), in: attributed)
            }
        }

        for match in matches(of: #"`([^`\n]+)`"#, in: source) {
            guard !intersectsProtectedRange(match.range, protectedRanges: protectedRanges) else { continue }
            protectedRanges.append(match.range)
            attributed.addAttributes(
                [
                    .font: codeFont,
                    .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.18),
                    .foregroundColor: NSColor.labelColor
                ],
                range: match.range
            )
            styleMarkerRange(NSRange(location: match.range.location, length: 1), in: attributed)
            styleMarkerRange(NSRange(location: match.range.location + match.range.length - 1, length: 1), in: attributed)
        }

        return protectedRanges
    }

    private static func styleMarkerRange(_ range: NSRange, in attributed: NSMutableAttributedString) {
        guard range.location != NSNotFound, range.length > 0 else { return }
        attributed.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
    }

    private static func matches(of pattern: String, in source: String) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let range = NSRange(location: 0, length: (source as NSString).length)
        return expression.matches(in: source, options: [], range: range)
    }

    private static func intersectsProtectedRange(_ range: NSRange, protectedRanges: [NSRange]) -> Bool {
        protectedRanges.contains { NSIntersectionRange(range, $0).length > 0 }
    }
}
