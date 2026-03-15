import AppKit
import SwiftUI

@MainActor
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int

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
        context.coordinator.update(text: $text)
        context.coordinator.applyText(text, to: textView, preserveSelection: false)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownEditingTextView else { return }
        context.coordinator.textView = textView
        context.coordinator.update(text: $text)

        if textView.string != text, textView.markedRange().location == NSNotFound {
            context.coordinator.applyText(text, to: textView, preserveSelection: true)
        } else {
            context.coordinator.refreshTypingAttributes(for: textView)
        }

        context.coordinator.applyFocusIfNeeded(token: focusToken, to: textView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        fileprivate weak var textView: MarkdownEditingTextView?

        private var isApplyingStyle = false
        private var lastAppliedFocusToken = Int.min
        private var lastCursorLineRange = NSRange(location: NSNotFound, length: 0)
        private var lastRender = MarkdownInlineStyler.RenderResult(
            attributedString: NSAttributedString(string: ""),
            hiddenRanges: []
        )

        init(text: Binding<String>) {
            _text = text
        }

        func update(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !isApplyingStyle else { return }
            text = textView.string

            // Avoid re-styling in the middle of IME composition.
            guard textView.markedRange().location == NSNotFound else { return }
            applyStyles(to: textView, preserveSelection: true)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView, !isApplyingStyle, textView.markedRange().location == NSNotFound else { return }

            let nsString = textView.string as NSString
            let cursorLocation = textView.selectedRange().location
            if nsString.length > 0 {
                let clampedCursor = min(cursorLocation, nsString.length - 1)
                let cursorLineRange = nsString.lineRange(for: NSRange(location: clampedCursor, length: 0))
                if cursorLineRange != lastCursorLineRange {
                    lastCursorLineRange = cursorLineRange
                    reapplyHiddenRanges(to: textView)
                }
            }

            refreshTypingAttributes(for: textView)
        }

        fileprivate func applyFocusIfNeeded(token: Int, to textView: MarkdownEditingTextView) {
            guard token != lastAppliedFocusToken else { return }
            lastAppliedFocusToken = token

            guard textView.window?.firstResponder !== textView else { return }
            DispatchQueue.main.async { [weak textView] in
                textView?.window?.makeFirstResponder(textView)
            }
        }

        fileprivate func refreshTypingAttributes(for textView: MarkdownEditingTextView) {
            textView.typingAttributes = MarkdownInlineStyler.typingAttributes(
                forInsertionAt: textView.selectedRange().location,
                in: textView.string,
                textStorage: textView.textStorage,
                hiddenRanges: lastRender.hiddenRanges
            )
        }

        fileprivate func applyText(_ text: String, to textView: MarkdownEditingTextView, preserveSelection: Bool) {
            isApplyingStyle = true
            textView.string = text
            isApplyingStyle = false
            applyStyles(to: textView, preserveSelection: preserveSelection)
        }

        private func applyStyles(to textView: MarkdownEditingTextView, preserveSelection: Bool) {
            let previousSelection = preserveSelection ? textView.selectedRange() : NSRange(location: NSNotFound, length: 0)
            let rendered = MarkdownInlineStyler.render(textView.string)
            lastRender = rendered

            isApplyingStyle = true
            textView.textStorage?.beginEditing()
            textView.textStorage?.setAttributedString(rendered.attributedString)
            textView.textStorage?.endEditing()

            let cursorLoc = preserveSelection ? previousSelection.location : textView.selectedRange().location
            let effectiveHiddenRanges = hiddenRangesExcludingCursorLine(
                rendered.hiddenRanges,
                cursorLocation: cursorLoc,
                in: textView.string
            )
            updateCursorLineRange(cursorLocation: cursorLoc, in: textView.string)
            applyHiddenRanges(effectiveHiddenRanges, to: textView, fullReset: false)

            if preserveSelection {
                textView.setSelectedRange(clampedRange(previousSelection, maxLength: (textView.string as NSString).length))
            }
            refreshTypingAttributes(for: textView)
            isApplyingStyle = false
        }

        private func reapplyHiddenRanges(to textView: MarkdownEditingTextView) {
            isApplyingStyle = true
            let previousSelection = textView.selectedRange()
            let effectiveHiddenRanges = hiddenRangesExcludingCursorLine(
                lastRender.hiddenRanges,
                cursorLocation: previousSelection.location,
                in: textView.string
            )
            applyHiddenRanges(effectiveHiddenRanges, to: textView, fullReset: true)
            textView.setSelectedRange(previousSelection)
            refreshTypingAttributes(for: textView)
            isApplyingStyle = false
        }

        private func hiddenRangesExcludingCursorLine(
            _ ranges: [NSRange],
            cursorLocation: Int,
            in source: String
        ) -> [NSRange] {
            let nsSource = source as NSString
            guard nsSource.length > 0, cursorLocation >= 0, cursorLocation != NSNotFound else { return ranges }
            let clampedCursor = min(cursorLocation, max(0, nsSource.length - 1))
            let cursorLineRange = nsSource.lineRange(for: NSRange(location: clampedCursor, length: 0))
            return ranges.filter { NSIntersectionRange($0, cursorLineRange).length == 0 }
        }

        private func updateCursorLineRange(cursorLocation: Int, in source: String) {
            let nsSource = source as NSString
            guard nsSource.length > 0, cursorLocation >= 0, cursorLocation != NSNotFound else {
                lastCursorLineRange = NSRange(location: NSNotFound, length: 0)
                return
            }
            let clampedCursor = min(cursorLocation, max(0, nsSource.length - 1))
            lastCursorLineRange = nsSource.lineRange(for: NSRange(location: clampedCursor, length: 0))
        }

        private func applyHiddenRanges(_ hiddenRanges: [NSRange], to textView: MarkdownEditingTextView, fullReset: Bool) {
            guard let layoutManager = textView.layoutManager else { return }

            let textLength = (textView.string as NSString).length
            guard textLength > 0 else { return }
            let fullCharacterRange = NSRange(location: 0, length: textLength)
            let fullGlyphRange = layoutManager.glyphRange(forCharacterRange: fullCharacterRange, actualCharacterRange: nil)

            if fullReset, fullGlyphRange.location != NSNotFound {
                for glyphIndex in fullGlyphRange.location..<NSMaxRange(fullGlyphRange) {
                    if layoutManager.notShownAttribute(forGlyphAt: glyphIndex) {
                        layoutManager.setNotShownAttribute(false, forGlyphAt: glyphIndex)
                    }
                }
            }

            for range in hiddenRanges {
                let clamped = clampedRange(range, maxLength: textLength)
                guard clamped.length > 0 else { continue }
                let glyphRange = layoutManager.glyphRange(forCharacterRange: clamped, actualCharacterRange: nil)
                guard glyphRange.location != NSNotFound else { continue }

                for glyphIndex in glyphRange.location..<NSMaxRange(glyphRange) {
                    layoutManager.setNotShownAttribute(true, forGlyphAt: glyphIndex)
                }
            }

            if fullGlyphRange.location != NSNotFound {
                layoutManager.invalidateDisplay(forGlyphRange: fullGlyphRange)
            }
        }

        private func clampedRange(_ range: NSRange, maxLength: Int) -> NSRange {
            guard range.location != NSNotFound else { return range }
            let location = min(max(0, range.location), maxLength)
            let remainingLength = maxLength - location
            let length = min(max(0, range.length), remainingLength)
            return NSRange(location: location, length: length)
        }
    }
}

@MainActor
fileprivate final class MarkdownEditingTextView: NSTextView {}

@MainActor
fileprivate enum MarkdownInlineStyler {
    struct RenderResult {
        let attributedString: NSAttributedString
        let hiddenRanges: [NSRange]

    }

    static let bodyFont = NSFont.systemFont(ofSize: 16)
    static let codeFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    static let italicBodyFont = NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask)
    static let baseParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5
        style.paragraphSpacing = 9
        return style
    }()
    static let quoteParagraphStyle: NSParagraphStyle = {
        let style = (baseParagraphStyle.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.firstLineHeadIndent = 16
        style.headIndent = 16
        return style
    }()

    static let baseTypingAttributes: [NSAttributedString.Key: Any] = [
        .font: bodyFont,
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: baseParagraphStyle
    ]

    static func render(_ source: String) -> RenderResult {
        let attributed = NSMutableAttributedString(string: source, attributes: baseTypingAttributes)
        var hiddenRanges: [NSRange] = []

        let protectedRanges = applyCodeStyles(to: attributed, source: source, hiddenRanges: &hiddenRanges)
        applyHeadingStyles(to: attributed, source: source, protectedRanges: protectedRanges, hiddenRanges: &hiddenRanges)
        applyQuoteStyles(to: attributed, source: source, protectedRanges: protectedRanges, hiddenRanges: &hiddenRanges)
        applyListStyles(to: attributed, source: source, protectedRanges: protectedRanges)
        applyTaskListStyles(to: attributed, source: source, protectedRanges: protectedRanges)
        applyDelimitedStyle(
            pattern: #"\*\*([^\n]+?)\*\*"#,
            markerLength: 2,
            font: .boldSystemFont(ofSize: 16),
            to: attributed,
            source: source,
            protectedRanges: protectedRanges,
            hiddenRanges: &hiddenRanges
        )
        applyDelimitedStyle(
            pattern: #"__([^\n]+?)__"#,
            markerLength: 2,
            font: .boldSystemFont(ofSize: 16),
            to: attributed,
            source: source,
            protectedRanges: protectedRanges,
            hiddenRanges: &hiddenRanges
        )
        applyDelimitedStyle(
            pattern: #"(?<!\*)\*([^*\n]+?)\*(?!\*)"#,
            markerLength: 1,
            font: italicBodyFont,
            to: attributed,
            source: source,
            protectedRanges: protectedRanges,
            hiddenRanges: &hiddenRanges
        )
        applyDelimitedStyle(
            pattern: #"(?<!_)_([^_\n]+?)_(?!_)"#,
            markerLength: 1,
            font: italicBodyFont,
            to: attributed,
            source: source,
            protectedRanges: protectedRanges,
            hiddenRanges: &hiddenRanges
        )
        applyStrikethroughStyles(to: attributed, source: source, protectedRanges: protectedRanges, hiddenRanges: &hiddenRanges)
        applyLinkStyles(to: attributed, source: source, protectedRanges: protectedRanges, hiddenRanges: &hiddenRanges)

        return RenderResult(
            attributedString: attributed,
            hiddenRanges: mergedRanges(hiddenRanges)
        )
    }

    static func typingAttributes(
        forInsertionAt location: Int,
        in source: String,
        textStorage: NSTextStorage?,
        hiddenRanges: [NSRange]
    ) -> [NSAttributedString.Key: Any] {
        if let blockAttributes = blockTypingAttributes(forInsertionAt: location, in: source) {
            return blockAttributes
        }

        if let inheritedAttributes = inheritedTypingAttributes(
            forInsertionAt: location,
            textStorage: textStorage,
            hiddenRanges: hiddenRanges
        ) {
            return inheritedAttributes
        }

        return baseTypingAttributes
    }

    private static func applyHeadingStyles(
        to attributed: NSMutableAttributedString,
        source: String,
        protectedRanges: [NSRange],
        hiddenRanges: inout [NSRange]
    ) {
        let sizes: [CGFloat] = [30, 26, 23, 21, 19, 18]
        for match in matches(of: #"(?m)^(#{1,6})([ \t]+)(.*)$"#, in: source) {
            guard !intersectsProtectedRange(match.range, protectedRanges: protectedRanges) else { continue }

            let level = max(1, min(6, match.range(at: 1).length))
            let markerRange = NSRange(location: match.range.location, length: match.range(at: 1).length + match.range(at: 2).length)
            hideMarkerRange(markerRange, in: attributed, hiddenRanges: &hiddenRanges)
            attributed.addAttributes(
                headingAttributes(level: level, size: sizes[level - 1]),
                range: match.range(at: 3)
            )
        }
    }

    private static func applyQuoteStyles(
        to attributed: NSMutableAttributedString,
        source: String,
        protectedRanges: [NSRange],
        hiddenRanges: inout [NSRange]
    ) {
        for match in matches(of: #"(?m)^(>)([ \t]?)(.*)$"#, in: source) {
            guard !intersectsProtectedRange(match.range, protectedRanges: protectedRanges) else { continue }

            let markerRange = NSRange(location: match.range.location, length: match.range(at: 1).length + match.range(at: 2).length)
            hideMarkerRange(markerRange, in: attributed, hiddenRanges: &hiddenRanges)
            attributed.addAttributes(
                [
                    .font: NSFont.systemFont(ofSize: 16, weight: .medium),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: quoteParagraphStyle
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
        protectedRanges: [NSRange],
        hiddenRanges: inout [NSRange]
    ) {
        for match in matches(of: pattern, in: source) {
            guard !intersectsProtectedRange(match.range, protectedRanges: protectedRanges) else { continue }

            let contentRange = match.range(at: 1)
            let leadingMarkerRange = NSRange(location: match.range.location, length: markerLength)
            let trailingMarkerRange = NSRange(location: match.range.location + match.range.length - markerLength, length: markerLength)
            hideMarkerRange(leadingMarkerRange, in: attributed, hiddenRanges: &hiddenRanges)
            hideMarkerRange(trailingMarkerRange, in: attributed, hiddenRanges: &hiddenRanges)
            attributed.addAttributes([.font: font, .foregroundColor: NSColor.labelColor], range: contentRange)
        }
    }

    private static func applyStrikethroughStyles(
        to attributed: NSMutableAttributedString,
        source: String,
        protectedRanges: [NSRange],
        hiddenRanges: inout [NSRange]
    ) {
        for match in matches(of: #"~~([^~\n]+?)~~"#, in: source) {
            guard !intersectsProtectedRange(match.range, protectedRanges: protectedRanges) else { continue }

            let contentRange = match.range(at: 1)
            hideMarkerRange(NSRange(location: match.range.location, length: 2), in: attributed, hiddenRanges: &hiddenRanges)
            hideMarkerRange(NSRange(location: match.range.location + match.range.length - 2, length: 2), in: attributed, hiddenRanges: &hiddenRanges)
            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
        }
    }

    private static func applyLinkStyles(
        to attributed: NSMutableAttributedString,
        source: String,
        protectedRanges: [NSRange],
        hiddenRanges: inout [NSRange]
    ) {
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
            let trailingRange = NSRange(
                location: afterTextLocation,
                length: fullRange.location + fullRange.length - afterTextLocation
            )
            hideMarkerRange(openingRange, in: attributed, hiddenRanges: &hiddenRanges)
            hideMarkerRange(trailingRange, in: attributed, hiddenRanges: &hiddenRanges)
        }
    }

    private static func applyCodeStyles(
        to attributed: NSMutableAttributedString,
        source: String,
        hiddenRanges: inout [NSRange]
    ) -> [NSRange] {
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
            hideMarkerRange(NSRange(location: match.range.location, length: min(3, match.range.length)), in: attributed, hiddenRanges: &hiddenRanges)
            if match.range.length >= 6 {
                hideMarkerRange(
                    NSRange(location: match.range.location + match.range.length - 3, length: 3),
                    in: attributed,
                    hiddenRanges: &hiddenRanges
                )
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
            hideMarkerRange(NSRange(location: match.range.location, length: 1), in: attributed, hiddenRanges: &hiddenRanges)
            hideMarkerRange(
                NSRange(location: match.range.location + match.range.length - 1, length: 1),
                in: attributed,
                hiddenRanges: &hiddenRanges
            )
        }

        return protectedRanges
    }

    private static func headingAttributes(level: Int, size: CGFloat) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: size, weight: .bold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: baseParagraphStyle
        ]
    }

    private static func blockTypingAttributes(
        forInsertionAt location: Int,
        in source: String
    ) -> [NSAttributedString.Key: Any]? {
        let prefix = linePrefix(upTo: location, in: source)

        if let match = firstMatch(of: #"^(#{1,6})[ \t]+$"#, in: prefix) {
            let level = max(1, min(6, match.range(at: 1).length))
            let sizes: [CGFloat] = [30, 26, 23, 21, 19, 18]
            return headingAttributes(level: level, size: sizes[level - 1])
        }

        if firstMatch(of: #"^>[ \t]?$"#, in: prefix) != nil {
            return [
                .font: NSFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: quoteParagraphStyle
            ]
        }

        if let match = firstMatch(of: #"^([ \t]*[-*+][ \t]+\[[ xX]\])[ \t]*$"#, in: prefix) {
            let marker = (prefix as NSString).substring(with: match.range(at: 1))
            if marker.contains("[x]") || marker.contains("[X]") {
                return [
                    .font: bodyFont,
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: baseParagraphStyle,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue
                ]
            }
            return baseTypingAttributes
        }

        if firstMatch(of: #"^([ \t]*[-*+]|\d+\.)[ \t]+$"#, in: prefix) != nil {
            return baseTypingAttributes
        }

        return nil
    }

    private static func inheritedTypingAttributes(
        forInsertionAt location: Int,
        textStorage: NSTextStorage?,
        hiddenRanges: [NSRange]
    ) -> [NSAttributedString.Key: Any]? {
        guard let textStorage, textStorage.length > 0 else { return nil }

        let length = textStorage.length
        let forwardIndex = min(location, length - 1)
        if !isHiddenCharacter(at: forwardIndex, hiddenRanges: hiddenRanges) {
            return sanitizedTypingAttributes(textStorage.attributes(at: forwardIndex, effectiveRange: nil))
        }

        var index = min(max(0, location - 1), length - 1)
        while index >= 0 {
            if !isHiddenCharacter(at: index, hiddenRanges: hiddenRanges) {
                return sanitizedTypingAttributes(textStorage.attributes(at: index, effectiveRange: nil))
            }
            if index == 0 { break }
            index -= 1
        }

        return nil
    }

    private static func sanitizedTypingAttributes(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var typingAttributes = baseTypingAttributes
        let allowedKeys: [NSAttributedString.Key] = [
            .font,
            .foregroundColor,
            .backgroundColor,
            .paragraphStyle,
            .underlineStyle,
            .underlineColor,
            .strikethroughStyle,
            .baselineOffset
        ]

        for key in allowedKeys {
            if let value = attributes[key] {
                typingAttributes[key] = value
            }
        }

        return typingAttributes
    }

    /// Marks a range as a markdown marker: dims it and records it for potential hiding.
    /// On lines where the cursor is active, markers stay visible but dimmed.
    /// On other lines, markers are hidden entirely.
    private static func hideMarkerRange(_ range: NSRange, in attributed: NSMutableAttributedString, hiddenRanges: inout [NSRange]) {
        guard range.location != NSNotFound, range.length > 0 else { return }
        hiddenRanges.append(range)
        attributed.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
    }

    private static func mergedRanges(_ ranges: [NSRange]) -> [NSRange] {
        let sortedRanges = ranges
            .filter { $0.location != NSNotFound && $0.length > 0 }
            .sorted { lhs, rhs in
                if lhs.location == rhs.location {
                    return lhs.length < rhs.length
                }
                return lhs.location < rhs.location
            }

        var merged: [NSRange] = []
        for range in sortedRanges {
            guard var last = merged.last else {
                merged.append(range)
                continue
            }

            let lastEnd = last.location + last.length
            let rangeEnd = range.location + range.length
            if range.location <= lastEnd {
                last.length = max(lastEnd, rangeEnd) - last.location
                merged[merged.count - 1] = last
            } else {
                merged.append(range)
            }
        }

        return merged
    }

    private static func linePrefix(upTo location: Int, in source: String) -> String {
        let nsSource = source as NSString
        guard nsSource.length > 0 else { return "" }

        let clampedLocation = min(max(0, location), nsSource.length)
        let anchor = min(max(0, clampedLocation == nsSource.length ? clampedLocation - 1 : clampedLocation), nsSource.length - 1)
        let lineRange = nsSource.lineRange(for: NSRange(location: anchor, length: 0))
        let prefixRange = NSRange(location: lineRange.location, length: clampedLocation - lineRange.location)
        return nsSource.substring(with: prefixRange)
    }

    private static func isHiddenCharacter(at index: Int, hiddenRanges: [NSRange]) -> Bool {
        hiddenRanges.contains { NSLocationInRange(index, $0) }
    }

    private static func matches(of pattern: String, in source: String) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let range = NSRange(location: 0, length: (source as NSString).length)
        return expression.matches(in: source, options: [], range: range)
    }

    private static func firstMatch(of pattern: String, in source: String) -> NSTextCheckingResult? {
        matches(of: pattern, in: source).first
    }

    private static func intersectsProtectedRange(_ range: NSRange, protectedRanges: [NSRange]) -> Bool {
        protectedRanges.contains { NSIntersectionRange(range, $0).length > 0 }
    }
}
