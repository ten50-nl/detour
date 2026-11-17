import AppKit
import Combine
import DetourCore
import SwiftUI

enum Links {
    static let website = URL(string: "https://detour.ten50.nl")!
    static let github = URL(string: "https://github.com/ten50nl/detour")!
    static let rulesDocs = URL(string: "https://github.com/ten50nl/detour/blob/main/docs/rules.md")!
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var tab = ProcessInfo.processInfo.environment["DETOUR_SETTINGS_TAB"] ?? "general"

    var body: some View {
        TabView(selection: $tab) {
            GeneralTab(state: state).tabItem { Label("General", systemImage: "gearshape") }.tag("general")
            DestinationsTab(state: state).tabItem { Label("Destinations", systemImage: "arrow.triangle.branch") }.tag("destinations")
            LearnedTab(state: state).tabItem { Label("Learned", systemImage: "brain") }.tag("learned")
            TestTab(state: state).tabItem { Label("Test a link", systemImage: "magnifyingglass") }.tag("test")
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 520)
    }
}

struct StatusRow: View {
    let ok: Bool
    let title: String
    let detail: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let actionTitle, let action { Button(actionTitle, action: action) }
        }
    }
}

private struct GeneralTab: View {
    @ObservedObject var state: AppState
    @AppStorage(MenuBarController.showIconKey) private var showIcon = true
    @State private var isDefault = Permissions.isDefaultBrowser
    @State private var loginItem = Permissions.launchesAtLogin
    @State private var fda = Permissions.hasFullDiskAccess
    @State private var ax = Permissions.hasAccessibility
    @State private var error: String?
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section { statusRows }
            Section { toggles }
            Section { about }
            if let error {
                Text(error).foregroundStyle(.red).font(.caption)
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in refresh() }
    }

    @ViewBuilder private var statusRows: some View {
        StatusRow(ok: isDefault, title: "Default browser", detail: isDefault ? "Links from other apps go through Detour." : "macOS still sends links to another app.",
                  actionTitle: isDefault ? nil : "Make default browser", action: makeDefault)
        StatusRow(ok: fda, title: "Full Disk Access", detail: historyDetail, actionTitle: fda ? "Rebuild index" : "Open privacy settings", action: fdaAction)
        StatusRow(ok: ax, title: "Accessibility", detail: ax ? "Window titles of the app you click in help as a tie-breaker." : "Optional. Lets Detour tell which chat inside an all-in-one messenger a link came from.",
                  actionTitle: ax ? nil : "Allow", action: { Permissions.requestAccessibility() })
        ForEach(state.profileWarnings.keys.sorted(), id: \.self) { id in
            StatusRow(ok: false, title: "Profile for \(state.label(id))", detail: state.profileWarnings[id] ?? "")
        }
        if let rulesError = state.rulesError {
            StatusRow(ok: false, title: "Rules file", detail: rulesError)
        }
    }

    @ViewBuilder private var toggles: some View {
        Toggle("Open at login", isOn: $loginItem)
            .onChange(of: loginItem) { _, on in setLogin(on) }
            .disabled(!Permissions.canUseLoginItem)
        Toggle("Show menu bar icon", isOn: $showIcon)
        Text("With the icon hidden, open Detour again from Finder or Spotlight to get back here.")
            .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private var about: some View {
        HStack {
            Text("Detour \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
            Text("Free and open source, made by ten50").foregroundStyle(.secondary)
            Spacer()
            Button("Website") { NSWorkspace.shared.open(Links.website) }
            Button("GitHub") { NSWorkspace.shared.open(Links.github) }
        }
    }

    private var historyDetail: String {
        switch state.historyStatus {
        case .unknown: "Checking browser history…"
        case .noAccess: "Needed to see your browser profiles and learn from your history. Rules work without it."
        case .building: "Reading your browser history…"
        case .ready(let hosts, let builtAt): "History of \(hosts) sites indexed at \(builtAt.formatted(date: .omitted, time: .shortened))."
        case .failed(let message): "Indexing failed: \(message)"
        }
    }

    private func refresh() {
        isDefault = Permissions.isDefaultBrowser
        fda = Permissions.hasFullDiskAccess
        ax = Permissions.hasAccessibility
    }

    private func makeDefault() {
        Task {
            do { try await Permissions.makeDefaultBrowser() } catch { self.error = error.localizedDescription }
            refresh()
        }
    }

    private func fdaAction() {
        if fda { state.rebuildHistory() } else { Permissions.openFullDiskAccessSettings() }
    }

    private func setLogin(_ on: Bool) {
        do { try Permissions.setLaunchAtLogin(on) } catch { self.error = error.localizedDescription }
        loginItem = Permissions.launchesAtLogin
    }
}

private struct DestinationsTab: View {
    @ObservedObject var state: AppState
    @State private var draft: RulesConfig = .empty
    @State private var selection: DestinationID?
    @State private var patternsText = ""
    @State private var dirty = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                List(selection: $selection) {
                    ForEach(draft.destinations) { dest in
                        DestinationRow(dest: dest, isDefault: dest.id == draft.defaultDestination)
                            .tag(dest.id)
                    }
                    .onMove { from, to in
                        draft.destinations.move(fromOffsets: from, toOffset: to)
                        dirty = true
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: false))
                HStack(spacing: 4) {
                    Menu {
                        ForEach(addable) { dest in
                            Button(dest.isProfile ? "\(dest.name) (\(URL(fileURLWithPath: dest.appPath).deletingPathExtension().lastPathComponent))" : dest.name) { add(dest) }
                        }
                    } label: { Image(systemName: "plus") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(addable.isEmpty || draft.destinations.count >= RulesConfig.maxDestinations)
                    Button { remove() } label: { Image(systemName: "minus") }
                        .buttonStyle(.borderless)
                        .disabled(selection == nil || draft.destinations.count <= 1)
                    Spacer()
                }
                Text("Rules are checked from top to bottom. Drag to reorder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 250)

            VStack(spacing: 10) {
                detail
                HStack {
                    Button("Open rules.json") { NSWorkspace.shared.open(Paths.rules) }
                    Spacer()
                    Button("Revert") { load() }.disabled(!dirty)
                    Button("Save") { save() }.keyboardShortcut("s").buttonStyle(.borderedProminent).disabled(!dirty)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            addable = scanAddable()
            load()
        }
        .onChange(of: selection) { _, _ in syncPatternsFromDraft() }
        .onChange(of: state.engine.rules) { _, _ in if !dirty { load() } }
    }

    @ViewBuilder private var detail: some View {
        if let index = draft.destinations.firstIndex(where: { $0.id == selection }) {
            Form {
                TextField("Name", text: binding(index, \.name))
                ColorPicker("Color", selection: Binding(
                    get: { Color(hex: draft.destinations[index].color) },
                    set: { draft.destinations[index].color = NSColor($0).hexString; dirty = true }))
                LabeledContent("Opens in", value: opensIn(draft.destinations[index]))
                if let account = draft.destinations[index].account { LabeledContent("Signed in as", value: account) }
                Toggle("Default for everything else", isOn: Binding(
                    get: { draft.defaultDestination == draft.destinations[index].id },
                    set: { if $0 { draft.defaultDestination = draft.destinations[index].id; dirty = true } }))
                Section {
                    TextEditor(text: $patternsText)
                        .font(.system(.callout, design: .monospaced))
                        .frame(minHeight: 150)
                        .onChange(of: patternsText) { _, text in
                            guard let i = draft.destinations.firstIndex(where: { $0.id == selection }) else { return }
                            let new = lines(text)
                            if new != draft.destinations[i].patterns {
                                draft.destinations[i].patterns = new
                                dirty = true
                            }
                        }
                } header: {
                    Text("Always open here")
                } footer: {
                    HStack {
                        Text("One per line. example.com includes its subdomains, ~word matches any site containing it.")
                        Link("More", destination: Links.rulesDocs)
                    }
                    .font(.caption)
                }
            }
            .formStyle(.grouped)
        } else {
            Text("Select a destination")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @State private var addable: [Destination] = []

    private func scanAddable() -> [Destination] {
        let existing = Set(draft.destinations.map(DestinationMerge.key))
        return BrowserScanner.candidates().filter { !existing.contains(DestinationMerge.key($0)) }
    }

    private func binding(_ index: Int, _ key: WritableKeyPath<Destination, String>) -> Binding<String> {
        Binding(get: { draft.destinations[index][keyPath: key] }, set: { draft.destinations[index][keyPath: key] = $0; dirty = true })
    }

    private func opensIn(_ dest: Destination) -> String {
        let app = URL(fileURLWithPath: dest.appPath).deletingPathExtension().lastPathComponent
        if let dir = dest.profileDir { return "\(app), profile \(dest.profileName ?? dir)" }
        return app
    }

    private func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func load() {
        draft = state.rules
        if selection == nil || draft.destination(selection!) == nil { selection = draft.destinations.first?.id }
        syncPatternsFromDraft()
        dirty = false
    }

    private func syncPatternsFromDraft() {
        patternsText = (draft.destinations.first { $0.id == selection }?.patterns ?? []).joined(separator: "\n")
    }

    private func add(_ dest: Destination) {
        var dest = dest
        var id = dest.id
        var n = 2
        while draft.destination(id) != nil { id = "\(dest.id)-\(n)"; n += 1 }
        dest.id = id
        dest.color = BrowserDiscovery.palette[draft.destinations.count % BrowserDiscovery.palette.count]
        draft.destinations.append(dest)
        if draft.defaultDestination.isEmpty { draft.defaultDestination = id }
        selection = id
        addable = scanAddable()
        dirty = true
    }

    private func remove() {
        guard let selection, draft.destinations.count > 1 else { return }
        draft.destinations.removeAll { $0.id == selection }
        if draft.defaultDestination == selection { draft.defaultDestination = draft.destinations.first?.id ?? "" }
        self.selection = draft.destinations.first?.id
        addable = scanAddable()
        dirty = true
    }

    private func save() {
        state.updateRules(draft)
        dirty = false
    }
}

struct DestinationRow: View {
    let dest: Destination
    var isDefault = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: dest.appPath)).resizable().frame(width: 22, height: 22)
                Circle().fill(Color(hex: dest.color)).frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(dest.name)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if isDefault { Text("default").font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private var subtitle: String {
        let app = URL(fileURLWithPath: dest.appPath).deletingPathExtension().lastPathComponent
        if let account = dest.account { return "\(app) · \(account)" }
        if let dir = dest.profileDir { return "\(app) · \(dir)" }
        return app
    }
}

private struct LearnedTab: View {
    @ObservedObject var state: AppState

    private struct Row: Identifiable {
        var id: String { kind + key }
        let kind: String
        let key: String
        let target: DestinationID
    }

    private var rows: [Row] {
        state.engine.learned.hosts.map { Row(kind: "site", key: $0.key, target: $0.value) }.sorted { $0.key < $1.key }
            + state.engine.learned.fileIDs.map { Row(kind: "file", key: $0.key, target: $0.value) }.sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Choices you made in the picker or with \"Open in\" from the menu bar.")
                .font(.caption).foregroundStyle(.secondary)
            if rows.isEmpty {
                Spacer()
                Text("Nothing learned yet").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                Table(rows) {
                    TableColumn("Type") { Text($0.kind) }.width(50)
                    TableColumn("Site or file") { Text($0.key).lineLimit(1).truncationMode(.middle) }
                    TableColumn("Opens in") { Text(state.label($0.target)) }.width(110)
                    TableColumn("") { row in
                        Button("Forget") {
                            if row.kind == "site" { state.forget(host: row.key) } else { state.forget(fileID: row.key) }
                        }
                    }.width(70)
                }
            }
        }
    }
}

private struct TestTab: View {
    @ObservedObject var state: AppState
    @State private var url = ProcessInfo.processInfo.environment["DETOUR_TEST_URL"] ?? ""
    @State private var app = ""
    @State private var title = ""
    @State private var showSource = false
    @State private var opened = false

    private var quickPicks: [String] {
        let recent = state.recent.compactMap { $0.url.absoluteString }.reduce(into: [String]()) { if !$0.contains($1) && $0.count < 4 { $0.append($1) } }
        return recent.isEmpty ? ["https://www.youtube.com/watch?v=1", "https://github.com", "https://docs.google.com/document/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit"] : recent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Type or paste a link to see where Detour would open it, and why.")
                .foregroundStyle(.secondary)
            TextField("https://", text: $url)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .controlSize(.large)
                .onChange(of: url) { _, _ in opened = false }
            HStack(spacing: 6) {
                Text(state.recent.isEmpty ? "Try:" : "Recent:").font(.caption).foregroundStyle(.secondary)
                ForEach(quickPicks, id: \.self) { pick in
                    Button(URL(string: pick).flatMap { normalizedHost($0) } ?? pick) { url = pick }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            DisclosureGroup("Pretend it came from an app", isExpanded: $showSource) {
                Form {
                    TextField("App name", text: $app, prompt: Text("Slack"))
                    TextField("Window title", text: $title, prompt: Text("Ferdium - Mattermost - general"))
                }
                .formStyle(.grouped)
            }
            .font(.callout)

            if let parsed, let decision = state.engine.decide(LinkContext(url: parsed, sourceApp: app.isEmpty ? nil : app, sourceWindowTitle: title.isEmpty ? nil : title)) as Decision? {
                result(parsed, decision)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder private func result(_ link: URL, _ decision: Decision) -> some View {
        let dest = state.rules.destination(decision.target)
        GroupBox {
            HStack(alignment: .top, spacing: 14) {
                if let dest {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: dest.appPath)).resizable().frame(width: 44, height: 44)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(decision.askUser ? "Asks you, suggesting \(state.label(decision.target))" : "Opens in \(state.label(decision.target))")
                        .font(.title3.weight(.semibold))
                    LabeledContent("Decided by", value: stageLabel(decision.stage))
                    LabeledContent("Why", value: decision.reason)
                    if let dest {
                        LabeledContent("Browser", value: dest.profileDir.map { "\(URL(fileURLWithPath: dest.appPath).deletingPathExtension().lastPathComponent), profile \(dest.profileName ?? $0)" } ?? URL(fileURLWithPath: dest.appPath).deletingPathExtension().lastPathComponent)
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Button(opened ? "Opened" : "Open it") {
                        state.handle(LinkContext(url: link, sourceApp: app.isEmpty ? "Detour" : app, sourceWindowTitle: title.isEmpty ? nil : title))
                        opened = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(opened)
                }
            }
            .padding(8)
        }
        Spacer()
    }

    private var parsed: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 3 else { return nil }
        let candidate = LinkParser.parse(trimmed.contains("://") ? trimmed : "https://\(trimmed)")
        return candidate.flatMap { normalizedHost($0) == nil ? nil : $0 }
    }

    private func stageLabel(_ stage: Stage) -> String {
        switch stage {
        case .forced: "You held option"
        case .rule: "One of your rules"
        case .decoder: "The Google account or file in the link"
        case .learned: "A choice you taught it"
        case .history: "Your browsing history"
        case .source: "The app you clicked in"
        case .ambiguous: "Not sure, so it asks"
        case .fallback: "Your default"
        }
    }
}
