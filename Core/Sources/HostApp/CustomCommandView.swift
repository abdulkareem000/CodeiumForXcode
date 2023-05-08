import Preferences
import SwiftUI

extension List {
    @ViewBuilder
    func removeBackground() -> some View {
        if #available(macOS 13.0, *) {
            scrollContentBackground(.hidden)
        } else {
            background(Color.clear)
        }
    }
}

struct CustomCommandView: View {
    final class Settings: ObservableObject {
        @AppStorage(\.customCommands) var customCommands
        var illegalNames: [String] {
            let existed = customCommands.map(\.name)
            let builtin: [String] = [
                "Get Suggestions",
                "Accept Suggestion",
                "Reject Suggestion",
                "Next Suggestion",
                "Previous Suggestion",
                "Toggle Real-time Suggestions",
                "Real-time Suggestions",
                "Prefetch Suggestions",
                "Chat with Selection",
                "Prompt to Code",
            ]

            return existed + builtin
        }

        init(customCommands: AppStorage<[CustomCommand]>? = nil) {
            if let list = customCommands {
                _customCommands = list
            }
        }
    }

    struct EditingCommand {
        var isNew: Bool
        var command: CustomCommand
    }

    @State var editingCommand: EditingCommand?

    @StateObject var settings = Settings()

    var body: some View {
        HStack(spacing: 0) {
            List {
                ForEach(settings.customCommands, id: \.name) { command in
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal")

                        VStack(alignment: .leading) {
                            Text(command.name)
                                .foregroundStyle(.primary)

                            Group {
                                switch command.feature {
                                case .chatWithSelection:
                                    Text("Chat with Selection")
                                case .customChat:
                                    Text("Custom Chat")
                                case .promptToCode:
                                    Text("Prompt to Code")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingCommand = .init(isNew: false, command: command)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                    .background(
                        editingCommand?.command.id == command.id
                            ? Color.primary.opacity(0.05)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .contextMenu {
                        Button("Remove") {
                            settings.customCommands.removeAll(
                                where: { $0.name == command.name }
                            )
                        }
                    }
                }
                .onMove(perform: { indices, newOffset in
                    settings.customCommands.move(fromOffsets: indices, toOffset: newOffset)
                })
            }
            .removeBackground()
            .padding(.vertical, 4)
            .listStyle(.plain)
            .frame(width: 200)
            .background(Color.primary.opacity(0.05))
            .overlay {
                if settings.customCommands.isEmpty {
                    Text("""
                    Empty
                    Add command with "+" button
                    """)
                    .multilineTextAlignment(.center)
                }
            }

            Divider()

            if let editingCommand {
                EditCustomCommandView(
                    editingCommand: $editingCommand,
                    settings: settings
                ).id(editingCommand.command.id)
            } else {
                Color.clear
            }
        }
    }
}

struct EditCustomCommandView: View {
    @Binding var editingCommand: CustomCommandView.EditingCommand?
    var settings: CustomCommandView.Settings
    let originalName: String
    @State var commandType: CommandType

    @State var name: String
    @State var prompt: String
    @State var systemPrompt: String
    @State var continuousMode: Bool
    @State var errorMessage: String?

    enum CommandType: Int, CaseIterable {
        case chatWithSelection
        case promptToCode
        case customChat
    }

    init(
        editingCommand: Binding<CustomCommandView.EditingCommand?>,
        settings: CustomCommandView.Settings
    ) {
        _editingCommand = editingCommand
        self.settings = settings
        originalName = editingCommand.wrappedValue?.command.name ?? ""
        name = originalName
        switch editingCommand.wrappedValue?.command.feature {
        case let .chatWithSelection(extraSystemPrompt, prompt):
            commandType = .chatWithSelection
            self.prompt = prompt ?? ""
            systemPrompt = extraSystemPrompt ?? ""
            continuousMode = false
        case let .customChat(systemPrompt, prompt):
            commandType = .customChat
            self.systemPrompt = systemPrompt ?? ""
            self.prompt = prompt ?? ""
            continuousMode = false
        case let .promptToCode(extraSystemPrompt, prompt, continuousMode):
            commandType = .promptToCode
            self.prompt = prompt ?? ""
            systemPrompt = extraSystemPrompt ?? ""
            self.continuousMode = continuousMode ?? false
        case .none:
            commandType = .chatWithSelection
            prompt = ""
            systemPrompt = ""
            continuousMode = false
        }
    }

    var body: some View {
        ScrollView {
            Form {
                TextField("Name", text: $name)

                Picker("Command Type", selection: $commandType) {
                    ForEach(CommandType.allCases, id: \.rawValue) { commandType in
                        Text({
                            switch commandType {
                            case .chatWithSelection:
                                return "Chat with Selection"
                            case .promptToCode:
                                return "Prompt to Code"
                            case .customChat:
                                return "Custom Chat"
                            }
                        }() as String).tag(commandType)
                    }
                }

                switch commandType {
                case .chatWithSelection:
                    systemPromptTextField(title: "Extra System Prompt")
                    promptTextField
                case .promptToCode:
                    systemPromptTextField(title: "Extra System Prompt")
                    promptTextField
                    continuousModeToggle
                case .customChat:
                    systemPromptTextField()
                    promptTextField
                }
            }.padding()
        }.safeAreaInset(edge: .bottom) {
            VStack {
                Divider()

                VStack {
                    Text(
                        "After renaming or adding a custom command, please restart Xcode to refresh the menu."
                    )
                    .foregroundStyle(.secondary)

                    if let errorMessage {
                        Text(errorMessage).foregroundColor(.red)
                    }

                    HStack {
                        Spacer()
                        Button("Cancel") {
                            editingCommand = nil
                        }

                        lazy var newCommand = CustomCommand(
                            commandId: editingCommand?.command.id ?? UUID().uuidString,
                            name: name,
                            feature: {
                                switch commandType {
                                case .chatWithSelection:
                                    return .chatWithSelection(
                                        extraSystemPrompt: systemPrompt,
                                        prompt: prompt
                                    )
                                case .promptToCode:
                                    return .promptToCode(
                                        extraSystemPrompt: systemPrompt,
                                        prompt: prompt,
                                        continuousMode: continuousMode
                                    )
                                case .customChat:
                                    return .customChat(systemPrompt: systemPrompt, prompt: prompt)
                                }
                            }()
                        )

                        if editingCommand?.isNew ?? true {
                            Button("Add") {
                                guard !settings.illegalNames.contains(newCommand.name) else {
                                    errorMessage = "Command name is illegal."
                                    return
                                }
                                guard !newCommand.name.isEmpty else {
                                    errorMessage = "Command name cannot be empty."
                                    return
                                }
                                settings.customCommands.append(newCommand)
                                editingCommand = nil
                            }
                        } else {
                            Button("Update") {
                                guard !settings.illegalNames.contains(newCommand.name)
                                    || newCommand.name == originalName
                                else {
                                    errorMessage = "Command name is illegal."
                                    return
                                }
                                guard !newCommand.name.isEmpty else {
                                    errorMessage = "Command name cannot be empty."
                                    return
                                }

                                if let index = settings.customCommands.firstIndex(where: {
                                    $0.id == newCommand.id
                                }) {
                                    settings.customCommands[index] = newCommand
                                } else {
                                    settings.customCommands.append(newCommand)
                                }
                                editingCommand = nil
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
            .background(.regularMaterial)
        }
    }

    @ViewBuilder
    var promptTextField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Prompt")
            TextEditor(text: $prompt)
                .font(Font.system(.body, design: .monospaced))
                .padding(2)
                .frame(minHeight: 120)
                .multilineTextAlignment(.leading)
                .overlay(
                    RoundedRectangle(cornerRadius: 1)
                        .stroke(.black, lineWidth: 1 / 3)
                        .opacity(0.3)
                )
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    func systemPromptTextField(title: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title ?? "System Prompt")
            TextEditor(text: $systemPrompt)
                .font(Font.system(.body, design: .monospaced))
                .padding(2)
                .frame(minHeight: 120)
                .multilineTextAlignment(.leading)
                .overlay(
                    RoundedRectangle(cornerRadius: 1)
                        .stroke(.black, lineWidth: 1 / 3)
                        .opacity(0.3)
                )
        }
        .padding(.vertical, 4)
    }

    var continuousModeToggle: some View {
        Toggle("Continuous Mode", isOn: $continuousMode)
    }
}

// MARK: - Previews

struct CustomCommandView_Preview: PreviewProvider {
    static var previews: some View {
        CustomCommandView(
            editingCommand: .init(isNew: false, command: .init(
                commandId: "1",
                name: "Explain Code",
                feature: .chatWithSelection(extraSystemPrompt: nil, prompt: "Hello")
            )),
            settings: .init(customCommands: .init(wrappedValue: [
                .init(
                    commandId: "1",
                    name: "Explain Code",
                    feature: .chatWithSelection(extraSystemPrompt: nil, prompt: "Hello")
                ),
                .init(
                    commandId: "2",
                    name: "Refactor Code",
                    feature: .promptToCode(
                        extraSystemPrompt: nil,
                        prompt: "Refactor",
                        continuousMode: false
                    )
                ),
            ], "CustomCommandView_Preview"))
        )
    }
}

struct EditCustomCommandView_Preview: PreviewProvider {
    static var previews: some View {
        EditCustomCommandView(
            editingCommand: .constant(CustomCommandView.EditingCommand(
                isNew: false,
                command: .init(
                    commandId: "4",
                    name: "Explain Code",
                    feature: .promptToCode(
                        extraSystemPrompt: nil,
                        prompt: "Hello",
                        continuousMode: false
                    )
                )
            )),
            settings: .init(customCommands: .init(wrappedValue: [], "CustomCommandView_Preview"))
        )
        .frame(width: 800)
    }
}

