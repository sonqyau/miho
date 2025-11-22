import ComposableArchitecture
import Perception
import SwiftUI

struct PersistenceView: View {
  let store: StoreOf<PersistenceFeature>
  @Bindable private var bindableStore: StoreOf<PersistenceFeature>

  init(store: StoreOf<PersistenceFeature>) {
    self.store = store
    _bindableStore = Bindable(wrappedValue: store)
  }

  var body: some View {
    NavigationStack {
      ConfigDetailView(store: store)
    }
  }
}

struct ConfigDetailView: View {
  @Bindable var store: StoreOf<PersistenceFeature>

  var body: some View {
    Form {
      modeSection

      if store.isLocalMode {
        remoteConfigSection
      }

      remoteInstanceSection
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .navigationTitle("Configuration Profiles")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        if store.isLocalMode {
          Button(action: { store.send(.refreshAll) }) {
            Label("Refresh All", systemImage: "arrow.clockwise")
          }
          .disabled(store.isUpdatingAll || store.configs.isEmpty)
        }
      }
    }
    .sheet(
      isPresented: Binding(
        get: { store.showingAddConfig },
        set: { store.send(.showAddConfig($0)) },
      ),
    ) {
      AddRemoteConfigView()
    }
    .sheet(
      isPresented: Binding(
        get: { store.showingAddInstance },
        set: { store.send(.showAddInstance($0)) },
      ),
    ) {
      AddRemoteInstanceView()
    }
    .alert(
      "Error",
      isPresented: Binding(
        get: { store.alerts.errorMessage != nil },
        set: { presented in if !presented { store.send(.dismissError) } },
      ),
    ) {
      Button("OK") { store.send(.dismissError) }
    } message: {
      if let error = store.alerts.errorMessage {
        Text(error)
      }
    }
    .task { store.send(.onAppear) }
    .onDisappear { store.send(.onDisappear) }
  }

  private var modeSection: some View {
    Section {
      HStack {
        Image(systemName: store.isLocalMode ? "laptopcomputer" : "network")
          .accessibilityHidden(true)
          .foregroundStyle(store.isLocalMode ? .blue : .green)

        VStack(alignment: .leading, spacing: 4) {
          Text(store.isLocalMode ? "Local Mode" : "Remote Mode")
            .font(.headline)

          if let instance = store.activeRemoteInstance {
            Text("Connected to \(instance.name)")
              .foregroundStyle(.secondary)
          } else {
            Text("Managing the local Mihomo instance")
              .foregroundStyle(.secondary)
          }
        }
      }
    } header: {
      Label("Mode", systemImage: "switch.2")
    } footer: {
      Text(
        "Local mode manages the on-device Mihomo kernel. Remote mode connects to an external Mihomo instance.",
      )
      .foregroundStyle(.secondary)
    }
  }

  private var remoteConfigSection: some View {
    Section {
      if store.configs.isEmpty {
        ContentUnavailableView {
          Label("No Remote Configurations", systemImage: "tray")
        } description: {
          Text("Add a remote configuration URL to begin.")
        } actions: {
          Button("Add Configuration") { store.send(.showAddConfig(true)) }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
        .listRowBackground(Color.clear)
      } else {
        ForEach(store.configs, id: \.id) { config in
          RemoteConfigRow(config: config) {
            store.send(.activateConfig(config))
          } onUpdate: {
            store.send(.updateConfig(config))
          } onDelete: {
            store.send(.deleteConfig(config))
          }
          .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
          .listRowBackground(Color.clear)
        }
      }
    } header: {
      HStack {
        Label("Remote Configurations", systemImage: "cloud")
          .font(.headline)

        Spacer()

        Button(action: { store.send(.showAddConfig(true)) }) {
          Image(systemName: "plus.circle.fill")
            .accessibilityLabel("Add configuration")
        }
        .buttonStyle(.plain)
      }
    } footer: {
      Text("Remote configurations refresh every two hours.")
        .foregroundStyle(.secondary)
    }
  }

  private var remoteInstanceSection: some View {
    Section {
      Button(action: { store.send(.activateInstance(nil)) }) {
        HStack {
          Image(systemName: "laptopcomputer")
            .accessibilityHidden(true)
            .foregroundStyle(store.isLocalMode ? .green : .secondary)

          Text("Local Instance")
            .font(.body)

          Spacer()

          if store.isLocalMode {
            Image(systemName: "checkmark.circle.fill")
              .accessibilityHidden(true)
              .foregroundStyle(.green)
          }
        }
      }
      .buttonStyle(.plain)

      ForEach(store.remoteInstances, id: \.id) { instance in
        RemoteInstanceRow(instance: instance) {
          store.send(.activateInstance(instance))
        } onDelete: {
          store.send(.deleteInstance(instance))
        }
      }
    } header: {
      HStack {
        Label("Control Panel", systemImage: "server.rack")
          .font(.headline)

        Spacer()

        Button(action: { store.send(.showAddInstance(true)) }) {
          Image(systemName: "plus.circle.fill")
            .accessibilityLabel("Add instance")
        }
        .buttonStyle(.plain)
      }
    } footer: {
      Text(
        "Connect to remote Mihomo instances. System proxy and TUN controls are disabled while in remote mode.",
      )
      .foregroundStyle(.secondary)
    }
  }
}

struct RemoteConfigRow: View {
  let config: PersistenceModel
  let onActivate: () -> Void
  let onUpdate: () -> Void
  let onDelete: () -> Void

  // swiftlint:disable closure_body_length
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Image(systemName: config.isActive ? "cloud.fill" : "cloud")
          .accessibilityHidden(true)
          .foregroundStyle(accentColor)
          .imageScale(.large)

        VStack(alignment: .leading, spacing: 4) {
          Text(config.name)
            .font(.headline)

          Text(config.url)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }

        Spacer()

        if config.isActive {
          Text("Active")
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
              Capsule(style: .continuous)
                .fill(accentColor.opacity(0.16))
            }
            .foregroundStyle(accentColor)
        }
      }

      HStack(spacing: 12) {
        Label(config.displayTimeString(), systemImage: "clock")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        if config.autoUpdate {
          Label("Automatic Updates", systemImage: "arrow.clockwise")
            .font(.subheadline)
            .foregroundStyle(accentColor)
        }
      }

      Divider()

      HStack(spacing: 12) {
        if !config.isActive {
          Button(action: onActivate) {
            Label("Activate", systemImage: "checkmark.circle")
          }
          .buttonStyle(.borderedProminent)
          .tint(accentColor)
        }

        Spacer(minLength: 0)

        Button(action: onUpdate) {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .tint(accentColor)

        Button(role: .destructive, action: onDelete) {
          Label("Delete", systemImage: "trash")
        }
        .buttonStyle(.bordered)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(
          accentColor.opacity(config.isActive ? 0.5 : 0.2), lineWidth: config.isActive ? 1.5 : 1,
        )
    }
    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  // swiftlint:enable closure_body_length

  private var accentColor: Color {
    config.isActive ? .green : .blue
  }
}

struct RemoteInstanceRow: View {
  let instance: RemoteInstance
  let onActivate: () -> Void
  let onDelete: () -> Void

  var body: some View {
    Button(action: onActivate) {
      HStack {
        Image(systemName: "server.rack")
          .accessibilityHidden(true)
          .foregroundStyle(instance.isActive ? .green : .secondary)

        VStack(alignment: .leading, spacing: 4) {
          Text(instance.name)
            .font(.headline)

          Text(instance.apiURL)
            .foregroundStyle(.secondary)
        }

        Spacer()

        if instance.isActive {
          Image(systemName: "checkmark.circle.fill")
            .accessibilityHidden(true)
            .foregroundStyle(.green)
        }

        Button(action: onDelete) {
          Image(systemName: "trash")
            .accessibilityLabel("Delete instance")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .foregroundStyle(.red)
      }
    }
    .buttonStyle(.plain)
    .padding(.vertical, 4)
  }
}

struct AddRemoteConfigView: View {
  @Environment(\.dismiss)
  private var dismiss
  @State
  private var name = ""
  @State
  private var url = ""
  @State
  private var autoUpdate = true
  @State
  private var isAdding = false
  @State
  private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name", text: $name)
            .textFieldStyle(.roundedBorder)

          TextField("URL", text: $url)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()

          Toggle("Enable Automatic Updates", isOn: $autoUpdate)
        } header: {
          Text("Configuration Details")
        } footer: {
          Text("Enter the subscription URL issued by your proxy service.")
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Add Remote Configuration")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }

        ToolbarItem(placement: .confirmationAction) {
          Button("Add") {
            Task {
              await addConfig()
            }
          }
          .disabled(name.isEmpty || url.isEmpty || isAdding)
        }
      }
      .alert("Error", isPresented: .constant(errorMessage != nil)) {
        Button("OK") {
          errorMessage = nil
        }
      } message: {
        if let error = errorMessage {
          Text(error)
        }
      }
    }
  }

  private func addConfig() async {
    isAdding = true

    do {
      try await PersistenceDomain.shared.addConfig(name: name, url: url)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }

    isAdding = false
  }
}

struct AddRemoteInstanceView: View {
  @Environment(\.dismiss)
  private var dismiss
  @State
  private var name = ""
  @State
  private var apiURL = "http://"
  @State
  private var secret = ""
  @State
  private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name", text: $name)
            .textFieldStyle(.roundedBorder)

          TextField("API URL", text: $apiURL)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()

          SecureField("Controller Secret (Optional)", text: $secret)
            .textFieldStyle(.roundedBorder)
        } header: {
          Text("Instance Details")
        } footer: {
          Text(
            "Enter the external controller URL and secret provided by the remote Mihomo instance.",
          )
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Add Remote Instance")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }

        ToolbarItem(placement: .confirmationAction) {
          Button("Add") {
            addInstance()
          }
          .disabled(name.isEmpty || apiURL.isEmpty)
        }
      }
      .alert("Error", isPresented: .constant(errorMessage != nil)) {
        Button("OK") {
          errorMessage = nil
        }
      } message: {
        if let error = errorMessage {
          Text(error)
        }
      }
    }
  }

  private func addInstance() {
    do {
      try PersistenceDomain.shared.addRemoteInstance(
        name: name,
        apiURL: apiURL,
        secret: secret.isEmpty ? nil : secret,
      )
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
