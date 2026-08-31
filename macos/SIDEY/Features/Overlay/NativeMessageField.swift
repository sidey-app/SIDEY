import AppKit
import SwiftUI

final class VerticallyCenteredMessageTextView: NSTextView {
    override func layout() {
        super.layout()
        updateVerticalInset()
    }

    func updateVerticalInset() {
        guard let layoutManager, let textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)

        let availableHeight = enclosingScrollView?.contentSize.height ?? bounds.height
        let usedHeight = ceil(layoutManager.usedRect(for: textContainer).height)
        let shouldCenter = !string.contains("\n") && usedHeight <= availableHeight
        let inset = shouldCenter ? max(3, floor((availableHeight - usedHeight) / 2)) : 3

        guard abs(textContainerInset.height - inset) > 0.5 else { return }
        textContainerInset = NSSize(width: 0, height: inset)
    }
}

struct NativeMessageField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let textView = VerticallyCenteredMessageTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 15, weight: .regular)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.identifier = NSUserInterfaceItemIdentifier("sidey.message-field")
        textView.textContainerInset = NSSize(width: 0, height: 3)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = true
        textView.textContainer?.maximumNumberOfLines = MessageValidator.maximumLines
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.string = text
        context.coordinator.lastValidText = text
        scrollView.documentView = textView
        textView.frame = scrollView.contentView.bounds

        DispatchQueue.main.async {
            textView.frame = scrollView.contentView.bounds
            textView.updateVerticalInset()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? VerticallyCenteredMessageTextView else { return }
        textView.frame = scrollView.contentView.bounds
        guard !textView.hasMarkedText(), textView.string != text else {
            textView.updateVerticalInset()
            return
        }
        let selection = textView.selectedRange()
        textView.string = text
        textView.setSelectedRange(NSRange(
            location: min(selection.location, (text as NSString).length),
            length: 0
        ))
        context.coordinator.lastValidText = text
        textView.updateVerticalInset()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeMessageField
        var lastValidText = ""

        init(parent: NativeMessageField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  !textView.hasMarkedText()
            else { return }
            let candidate = textView.string
            guard MessageValidator.isValidDraft(candidate) else {
                NSSound.beep()
                textView.string = lastValidText
                textView.setSelectedRange(NSRange(location: (lastValidText as NSString).length, length: 0))
                return
            }
            lastValidText = candidate
            parent.text = candidate
            (textView as? VerticallyCenteredMessageTextView)?.updateVerticalInset()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            if NSApplication.shared.currentEvent?.modifierFlags.contains(.shift) == true {
                let candidate = (textView.string as NSString).replacingCharacters(
                    in: textView.selectedRange(),
                    with: "\n"
                )
                guard MessageValidator.isValidDraft(candidate) else {
                    NSSound.beep()
                    return true
                }
                textView.insertText("\n", replacementRange: textView.selectedRange())
            } else {
                parent.onSubmit()
            }
            return true
        }
    }
}
