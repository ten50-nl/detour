import DetourCore
import SwiftUI

@MainActor
final class PickerModel: ObservableObject {
    let host: String
    let reason: String
    let destinations: [Destination]
    let rememberLabel: String
    @Published var selected: DestinationID
    @Published var remember = true
    var choose: (DestinationID) -> Void = { _ in }

    init(host: String, reason: String, selected: DestinationID, destinations: [Destination], rememberLabel: String) {
        self.host = host
        self.reason = reason
        self.destinations = destinations
        self.rememberLabel = rememberLabel
        self.selected = destinations.contains { $0.id == selected } ? selected : (destinations.first?.id ?? selected)
    }

    func move(_ delta: Int) {
        guard let i = destinations.firstIndex(where: { $0.id == selected }), !destinations.isEmpty else { return }
        selected = destinations[(i + delta + destinations.count) % destinations.count].id
    }
}

struct PickerView: View {
    @ObservedObject var model: PickerModel

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: min(max(model.destinations.count, 1), 4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.host)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(model.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(model.destinations.enumerated()), id: \.element.id) { index, dest in
                    DestinationButton(dest: dest, number: index + 1, selected: model.selected == dest.id) {
                        model.choose(dest.id)
                    }
                    .onHover { if $0 { model.selected = dest.id } }
                }
            }
            HStack {
                Toggle(model.rememberLabel, isOn: $model.remember)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                Text("esc to cancel")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(width: model.destinations.count > 3 ? 460 : 380)
    }
}

private struct DestinationButton: View {
    let dest: Destination
    let number: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: dest.appPath))
                        .resizable()
                        .frame(width: 30, height: 30)
                    if dest.isProfile {
                        Circle().fill(Color(hex: dest.color)).frame(width: 11, height: 11)
                            .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                    }
                }
                Text(dest.name)
                    .font(.callout)
                    .lineLimit(1)
                Text("\(number)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color(hex: dest.color).opacity(0.22) : Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color(hex: dest.color) : .clear, lineWidth: 1.5)
        )
    }
}
