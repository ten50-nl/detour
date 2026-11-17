import AppKit
import DetourCore
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            StepDots(steps: model.visibleSteps, current: model.step)
                .padding(.top, 18)
            Group {
                switch model.step {
                case .welcome: WelcomeStep(model: model)
                case .fullDiskAccess: FullDiskAccessStep(model: model)
                case .destinations: DestinationsStep(model: model)
                case .smartStart: SmartStartStep(model: model)
                case .defaultBrowser: DefaultBrowserStep(model: model)
                case .finishing: FinishingStep(model: model)
                case .done: DoneStep(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
            Divider()
            footer
        }
        .frame(width: 680, height: 560)
        .onAppear { model.startPolling() }
    }

    private var footer: some View {
        HStack {
            if model.step != .welcome && model.step != .done {
                Button("Back") { model.back() }
            }
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
            }
            Spacer()
            switch model.step {
            case .welcome:
                Button("Get started") { model.next() }.keyboardShortcut(.defaultAction)
            case .fullDiskAccess:
                if !model.fda { Button("Skip for now") { model.next() } }
                Button("Continue") { model.next() }.keyboardShortcut(.defaultAction).disabled(!model.fda)
            case .defaultBrowser:
                if !model.isDefault { Button("Skip") { model.next() } }
                Button("Continue") { model.next() }.keyboardShortcut(.defaultAction).disabled(!model.isDefault)
            case .done:
                Button("Finish") { model.finish() }.keyboardShortcut(.defaultAction)
            default:
                Button("Continue") { model.next() }.keyboardShortcut(.defaultAction).disabled(!model.canContinue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

private struct StepDots: View {
    let steps: [OnboardingModel.Step]
    let current: OnboardingModel.Step

    var body: some View {
        HStack(spacing: 6) {
            ForEach(steps, id: \.self) { s in
                Capsule()
                    .fill(s == current ? Color.accentColor : Color.secondary.opacity(s.rawValue < current.rawValue ? 0.6 : 0.25))
                    .frame(width: s == current ? 20 : 7, height: 7)
            }
        }
        .animation(.snappy, value: current)
    }
}

private struct StepHeader: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.tint)
            Text(title).font(.title2.weight(.semibold))
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 520)
    }
}

private struct WelcomeStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
            Text("Welcome to Detour").font(.largeTitle.weight(.semibold))
            Text("Every link opens in the right browser and profile. Automatically.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 10) {
                Point(symbol: "list.bullet.rectangle", text: "Follows your rules: work sites in your work profile, video in your ad-free browser.")
                Point(symbol: "clock.arrow.circlepath", text: "Learns from where you opened sites before, so most links need no rule at all.")
                Point(symbol: "hand.raised", text: "Asks only when it really can't tell. Hold ⌥ while clicking to choose yourself.")
                Point(symbol: "lock", text: "Everything stays on your Mac. No account, no tracking, free and open source.")
            }
            .padding(.top, 6)
            if model.canImport {
                GroupBox {
                    HStack {
                        Text("LinkRouter settings found on this Mac.")
                        Spacer()
                        Button("Import and continue") { model.importLegacy() }
                    }
                }
                .frame(maxWidth: 520)
            }
        }
    }
}

private struct Point: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 20)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 500, alignment: .leading)
    }
}

private struct FullDiskAccessStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 22) {
            StepHeader(symbol: "externaldrive.badge.checkmark", title: "Let Detour see your browsers",
                       text: "macOS keeps browser profiles and history behind Full Disk Access. Detour reads them to show your profiles and to learn where you open each site. Nothing leaves your Mac.")
            if model.fda {
                Label("Full Disk Access is on", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Instruction(n: 1, text: "Click the button below to open Privacy & Security.")
                    Instruction(n: 2, text: "Turn on Detour in the list. If it's missing, click + and choose Detour in Applications.")
                    Instruction(n: 3, text: "Come back here. This page notices it by itself.")
                }
                .frame(maxWidth: 440)
                Button("Open System Settings") { Permissions.openFullDiskAccessSettings() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                Text("You can skip this. Detour then works with browsers only, without profiles or history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct Instruction: View {
    let n: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor.opacity(0.18)))
            Text(text)
        }
    }
}

private struct DestinationsStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 14) {
            StepHeader(symbol: "arrow.triangle.branch", title: "Where can links go?",
                       text: "Tick the browsers and profiles you use, give them names you recognize, and pick the default for everything without a rule. Drag to reorder.")
            List {
                ForEach($model.candidates) { $dest in
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { model.selected.contains(dest.id) },
                            set: { on in
                                if on { model.selected.insert(dest.id) } else { model.selected.remove(dest.id) }
                                if !model.selected.contains(model.defaultID) { model.defaultID = model.candidates.first { model.selected.contains($0.id) }?.id ?? "" }
                            }))
                            .labelsHidden()
                            .disabled(!model.selected.contains(dest.id) && model.selected.count >= RulesConfig.maxDestinations)
                        DestinationRow(dest: dest)
                            .frame(width: 210, alignment: .leading)
                        TextField("Name", text: $dest.name)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!model.selected.contains(dest.id))
                        Button {
                            model.defaultID = dest.id
                        } label: {
                            Image(systemName: model.defaultID == dest.id ? "star.fill" : "star")
                                .foregroundStyle(model.defaultID == dest.id ? Color.yellow : Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Use for everything else")
                        .disabled(!model.selected.contains(dest.id))
                    }
                    .padding(.vertical, 2)
                }
                .onMove { model.move(from: $0, to: $1) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            HStack {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
                Text("is your default: links without a rule or history open there.")
                Spacer()
                Text("\(model.selected.count) of max \(RulesConfig.maxDestinations)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct SmartStartStep: View {
    @ObservedObject var model: OnboardingModel

    private var groups: [(Destination, [RuleSuggestion])] {
        model.state.destinations.compactMap { dest in
            guard let list = model.suggestions[dest.id], !list.isEmpty else { return nil }
            return (dest, list)
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            StepHeader(symbol: "wand.and.stars", title: "A head start from your history",
                       text: "These sites almost always open in the same place. Keep the ones you want as rules. You can change them later in settings.")
            if model.loadingSuggestions {
                ProgressView("Reading your browser history…").frame(maxHeight: .infinity)
            } else {
                List {
                    if groups.isEmpty {
                        Text("No clear patterns yet. Detour will learn as you go.").foregroundStyle(.secondary)
                    }
                    ForEach(groups, id: \.0.id) { dest, list in
                        Section {
                            ForEach(list) { s in
                                Toggle(isOn: Binding(
                                    get: { model.accepted.contains("\(dest.id)|\(s.host)") },
                                    set: { if $0 { model.accepted.insert("\(dest.id)|\(s.host)") } else { model.accepted.remove("\(dest.id)|\(s.host)") } })) {
                                    HStack {
                                        Text(s.host)
                                        Spacer()
                                        Text("\(s.visits) visits, \(Int(s.share * 100))% here").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Circle().fill(Color(hex: dest.color)).frame(width: 8, height: 8)
                                Text("Always open in \(dest.name)")
                            }
                        }
                    }
                    let accounts = model.state.rules.accountMap.sorted { $0.key < $1.key }
                    if !accounts.isEmpty {
                        Section("Google links for these accounts") {
                            ForEach(accounts, id: \.key) { key, id in
                                LabeledContent(key, value: model.state.label(id))
                            }
                        }
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: false))
                if !model.videoCandidates.isEmpty {
                    HStack {
                        Text("Send video sites (YouTube, Twitch, Vimeo) to")
                        Picker("", selection: $model.videoTarget) {
                            Text("don't").tag(DestinationID?.none)
                            ForEach(model.videoCandidates) { Text($0.name).tag(Optional($0.id)) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Spacer()
                    }
                    .font(.callout)
                }
            }
        }
    }
}

private struct DefaultBrowserStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 22) {
            StepHeader(symbol: "link", title: "Make Detour your default browser",
                       text: "Detour sits between your apps and your browsers. macOS asks you to confirm the switch. Your browsers stay exactly as they are.")
            if model.isDefault {
                Label("Detour is your default browser", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            } else {
                Button("Make Detour the default") { model.makeDefault() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                Text("Without this, links keep going straight to your old browser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FinishingStep: View {
    @ObservedObject var model: OnboardingModel
    @AppStorage(MenuBarController.showIconKey) private var showIcon = true

    var body: some View {
        VStack(spacing: 22) {
            StepHeader(symbol: "slider.horizontal.3", title: "Finishing touches", text: "A few small choices. All of them can be changed later in settings.")
            Form {
                Toggle("Open Detour at login", isOn: $model.launchAtLogin)
                    .disabled(!Permissions.canUseLoginItem)
                Toggle("Show the menu bar icon", isOn: $showIcon)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility (optional)")
                        Text("Lets Detour see which window a link came from, for example which chat inside an all-in-one messenger.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.accessibility {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Allow") { Permissions.requestAccessibility() }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: 520, maxHeight: 220)
        }
    }
}

private struct DoneStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 18) {
            StepHeader(symbol: "checkmark.seal", title: "You're all set",
                       text: "Click links anywhere as usual. Detour sends each one to the right place and shows the last ones in the menu bar, where you can move a link somewhere else.")
            HStack(spacing: 10) {
                ForEach(model.state.destinations.prefix(5)) { dest in
                    VStack(spacing: 4) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: dest.appPath)).resizable().frame(width: 36, height: 36)
                        Text(dest.name).font(.caption).lineLimit(1)
                        Circle().fill(Color(hex: dest.color)).frame(width: 6, height: 6)
                    }
                    .frame(width: 84)
                }
            }
            Button("Try it with a link") { model.tryLink() }
                .controlSize(.large)
            if let result = model.tryResult {
                Text(result).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            HStack(spacing: 4) {
                Image(systemName: "option")
                Text("Hold option while clicking a link to pick the destination yourself.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Link("detour.ten50.nl", destination: Links.website).font(.caption)
        }
    }
}
