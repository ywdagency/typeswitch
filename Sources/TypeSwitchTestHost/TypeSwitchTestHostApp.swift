import AppKit
import SwiftUI

@main
struct TypeSwitchTestHostApp: App {
    var body: some Scene {
        Window("TypeSwitch Controlled Test Host", id: "controlled-test-host") {
            ControlledTestHostView()
        }
        .defaultSize(width: 760, height: 760)
        .windowResizability(.contentSize)
    }
}

private struct ControlledTestHostView: View {
    @State private var swiftUIText = ""
    @State private var swiftUIMultilineText = ""
    @State private var secureText = ""
    @State private var appKitText = ""
    @State private var appKitMultilineText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Controlled Rewrite Test Host")
                        .font(.title2.weight(.semibold))
                    Text("With TypeSwitch auto-fix enabled, type ghbdtn followed by Space. Editable fields should become привет. Secure and read-only fields must never be rewritten.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                GroupBox("SwiftUI controls") {
                    VStack(alignment: .leading, spacing: 14) {
                        LabeledContent("TextField") {
                            TextField("Type ghbdtn and press Space", text: $swiftUIText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 420)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("TextEditor")
                            TextEditor(text: $swiftUIMultilineText)
                                .font(.body)
                                .frame(height: 90)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(.separator)
                                }
                        }

                        LabeledContent("SecureField — must refuse") {
                            SecureField("Type ghbdtn and press Space", text: $secureText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 420)
                        }
                    }
                    .padding(10)
                }

                GroupBox("AppKit controls") {
                    VStack(alignment: .leading, spacing: 14) {
                        LabeledContent("NSTextField") {
                            AppKitTextField(text: $appKitText)
                                .frame(width: 420, height: 24)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("NSTextView")
                            AppKitTextView(text: $appKitMultilineText)
                                .frame(height: 90)
                        }

                        LabeledContent("Read-only NSTextField — must refuse") {
                            AppKitReadOnlyTextField(text: "ghbdtn must remain unchanged")
                                .frame(width: 420, height: 24)
                        }
                    }
                    .padding(10)
                }

                HStack {
                    Spacer()
                    Button("Clear Editable Fields") {
                        swiftUIText = ""
                        swiftUIMultilineText = ""
                        secureText = ""
                        appKitText = ""
                        appKitMultilineText = ""
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 760, height: 760)
    }
}

private struct AppKitTextField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = "Type ghbdtn and press Space"
        field.delegate = context.coordinator
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

private struct AppKitReadOnlyTextField: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isEditable = false
        field.isSelectable = true
        field.isBezeled = true
        field.drawsBackground = true
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.stringValue = text
    }
}

private struct AppKitTextView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
