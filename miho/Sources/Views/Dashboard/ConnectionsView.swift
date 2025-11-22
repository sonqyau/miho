import ComposableArchitecture
import Perception
import SwiftUI

struct ConnectionsView: View {
  let store: StoreOf<ConnectionsFeature>
  @Bindable private var bindableStore: StoreOf<ConnectionsFeature>
  @State
  private var sortOrder = [
    KeyPathComparator(
      \ConnectionSnapshot.Connection.start,
      order: .reverse,
    ),
  ]
  @FocusState private var isSearchFocused: Bool

  init(store: StoreOf<ConnectionsFeature>) {
    self.store = store
    _bindableStore = Bindable(wrappedValue: store)
  }

  private var searchBinding: Binding<String> {
    Binding(
      get: { bindableStore.searchText },
      set: { bindableStore.send(.updateSearch($0)) },
    )
  }

  private var filterBinding: Binding<ConnectionFilter> {
    Binding(
      get: { bindableStore.selectedFilter },
      set: { bindableStore.send(.selectFilter($0)) },
    )
  }

  private var filteredConnections: [ConnectionSnapshot.Connection] {
    var conns = bindableStore.connections

    let filter = bindableStore.selectedFilter
    if filter != .all {
      conns = conns.filter { filter.matches($0.metadata.type) }
    }

    if !bindableStore.searchText.isEmpty {
      let term = bindableStore.searchText
      conns = conns.filter { connection in
        connection.displayHost.localizedCaseInsensitiveContains(term) ||
          connection.metadata.process.localizedCaseInsensitiveContains(term) ||
          connection.chainString.localizedCaseInsensitiveContains(term) ||
          connection.ruleString.localizedCaseInsensitiveContains(term)
      }
    }

    return conns
  }

  var body: some View {
    Form {
      statusSection
      controlsSection
      connectionsSection
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .navigationTitle("Connection monitor")
    .task { bindableStore.send(.onAppear) }
    .onDisappear { bindableStore.send(.onDisappear) }
    .alert(
      "Error",
      isPresented: Binding(
        get: { bindableStore.alerts.errorMessage != nil },
        set: { presented in if !presented { bindableStore.send(.dismissError) } },
      ),
    ) {
      Button("OK") { bindableStore.send(.dismissError) }
    } message: {
      if let message = bindableStore.alerts.errorMessage {
        Text(message)
      }
    }
  }

  private var statusSection: some View {
    Section {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 16) {
          LabeledContent("Active") {
            Text("\(bindableStore.connections.count)")
          }

          if !bindableStore.searchText.isEmpty || bindableStore.selectedFilter != .all {
            LabeledContent("Filtered results") {
              Text("\(filteredConnections.count)")
            }
          }

          Spacer()

          LabeledContent("Download") {
            Text(totalDownload)
              .font(.system(.callout, design: .monospaced))
          }

          LabeledContent("Upload") {
            Text(totalUpload)
              .font(.system(.callout, design: .monospaced))
          }
        }
      }
      .padding(.vertical, 4)
    } header: {
      Label("Status overview", systemImage: "dot.radiowaves.left.and.right")
    }
  }

  private var controlsSection: some View {
    Section {
      VStack(spacing: 12) {
        HStack(spacing: 8) {
          TextField("Filter connections", text: searchBinding)
            .textFieldStyle(.roundedBorder)
            .focused($isSearchFocused)

          if !bindableStore.searchText.isEmpty {
            Button("Clear filter") { bindableStore.send(.updateSearch("")) }
              .buttonStyle(.borderless)
          }
        }

        Picker("Connection type", selection: filterBinding) {
          ForEach(ConnectionFilter.allCases, id: \.self) { filter in
            Text(filter.displayName).tag(filter)
          }
        }
        .pickerStyle(.segmented)

        if bindableStore.selectedFilter != .all {
          Button(role: .destructive) {
            bindableStore.send(.selectFilter(.all))
          } label: {
            Label("Reset filters", systemImage: "xmark.circle")
          }
          .buttonStyle(.bordered)
        }

        Button {
          bindableStore.send(.closeAll)
        } label: {
          Label("Terminate all connections", systemImage: "network")
        }
        .buttonStyle(.borderedProminent)
        .disabled(bindableStore.connections.isEmpty || bindableStore.isClosingAll)
      }
      .padding(.vertical, 4)
    } header: {
      Label("Controls", systemImage: "slider.horizontal.3")
    }
  }

  // swiftlint:disable closure_body_length
  private var connectionsSection: some View {
    Section {
      Table(
        filteredConnections,
        selection: .constant(Set<ConnectionSnapshot.Connection.ID>()),
        sortOrder: $sortOrder,
      ) {
        TableColumn("Host") { connection in
          VStack(alignment: .leading, spacing: 4) {
            Text(connection.displayDestination)
              .font(.system(.body, design: .monospaced))
              .lineLimit(1)

            if !connection.metadata.process.isEmpty {
              Text(connection.metadata.process)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
        }
        .width(min: 200, ideal: 300)

        TableColumn("Type") { connection in
          Text("\(connection.metadata.type)(\(connection.metadata.network))")
            .font(.caption)
        }
        .width(ideal: 130)

        TableColumn("Chain") { connection in
          Text(connection.chainString)
            .font(.caption)
            .lineLimit(1)
        }
        .width(min: 150, ideal: 220)

        TableColumn("Rule") { connection in
          Text(connection.ruleString)
            .font(.caption)
            .lineLimit(1)
        }
        .width(min: 150, ideal: 250)

        TableColumn("Download", value: \.download) { connection in
          Text(
            ByteCountFormatter.string(
              fromByteCount: connection.download,
              countStyle: .binary,
            ),
          )
          .font(.caption)
        }
        .width(ideal: 110)

        TableColumn("Upload", value: \.upload) { connection in
          Text(
            ByteCountFormatter.string(
              fromByteCount: connection.upload,
              countStyle: .binary,
            ),
          )
          .font(.caption)
        }
        .width(ideal: 110)

        TableColumn("Duration", value: \.start) { connection in
          Text(connection.start, style: .relative)
            .font(.caption)
        }
        .width(ideal: 90)

        TableColumn("Actions") { connection in
          if bindableStore.closingConnections.contains(connection.id) {
            ProgressView()
              .controlSize(.small)
          } else {
            Button {
              bindableStore.send(.closeConnection(connection.id))
            } label: {
              Image(systemName: "xmark.circle")
                .foregroundStyle(.red)
                .accessibilityLabel("Terminate connection")
            }
            .buttonStyle(.plain)
            .help("Terminate this connection")
          }
        }
        .width(ideal: 60)
      }
      .frame(minHeight: 300)
    } header: {
      Label("Active connections", systemImage: "list.bullet.rectangle")
    }
  }

  // swiftlint:enable closure_body_length

  private func typeIcon(for type: String) -> String {
    let lowercasedType = type.lowercased()
    return lowercasedType == "http" || lowercasedType == "https"
      ? "globe"
      : lowercasedType.hasPrefix("socks") ? "network" : "info.circle"
  }

  private var totalDownload: String {
    ByteCountFormatter.string(
      fromByteCount: filteredConnections.reduce(0) { $0 + $1.download },
      countStyle: .binary,
    )
  }

  private var totalUpload: String {
    ByteCountFormatter.string(
      fromByteCount: filteredConnections.reduce(0) { $0 + $1.upload },
      countStyle: .binary,
    )
  }
}
