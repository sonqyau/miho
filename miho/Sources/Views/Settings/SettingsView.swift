import ComposableArchitecture
import Perception
import SwiftUI

struct SettingsView: View {
  @Bindable private var store: StoreOf<SettingsFeature>
  let persistenceStore: StoreOf<PersistenceFeature>

  init(store: StoreOf<SettingsFeature>, persistenceStore: StoreOf<PersistenceFeature>) {
    _store = Bindable(wrappedValue: store)
    self.persistenceStore = persistenceStore
  }

  var body: some View {
    NavigationStack {
      Form {
        statusSection
        systemProxySection
        trafficCaptureSection
        tunModeSection
        proxyModeSection
        launchAtLoginSection
        configurationSection
        advancedSection
        aboutSection
      }
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
      .overlay { progressOverlay }
      .navigationTitle("Settings")
    }
    .task {
      store.send(.onAppear)
    }
    .alert(
      "Error",
      isPresented: Binding(
        get: { store.state.alerts.errorMessage != nil },
        set: { presented in
          if !presented {
            store.send(.dismissError)
          }
        },
      ),
    ) {
      Button("OK") {
        store.send(.dismissError)
      }
    } message: {
      if let message = store.state.alerts.errorMessage {
        Text(message)
      }
    }
  }

  // swiftlint:disable closure_body_length
  private var trafficCaptureSection: some View {
    let capture = store.state.trafficCapture
    let drivers = capture.driversByMode[capture.mode] ?? []

    return Section {
      Picker(
        "Capture Mode",
        selection: Binding(
          get: { capture.mode },
          set: { mode in store.send(.selectTrafficCaptureMode(mode)) },
        ),
      ) {
        ForEach(TrafficCaptureMode.allCases, id: \.self) { mode in
          Text(mode.displayName).tag(mode)
        }
      }
      .pickerStyle(.segmented)

      Button {
        store.send(.toggleTrafficCaptureActivation)
      } label: {
        HStack {
          if capture.isActivating {
            ProgressView().scaleEffect(0.7)
          }
          Text(capture.isActive ? "Stop" : "Start")
          Spacer()
          Text(capture.mode.displayName)
            .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.borderedProminent)
      .disabled(capture.isActivating)

      if !drivers.isEmpty {
        Menu {
          Button("Auto Select") {
            store.send(.setTrafficCapturePreferredDriver(capture.mode, nil))
          }
          ForEach(drivers, id: \.id) { driver in
            Button {
              store.send(.setTrafficCapturePreferredDriver(capture.mode, driver.id))
            } label: {
              Label(
                driver.name,
                systemImage: driver.id == capture.preferredDriverID ? "checkmark" : "",
              )
            }
          }
        } label: {
          LabeledContent("Driver") {
            Text(capture.preferredDriverID.flatMap { id in
              drivers.first(where: { $0.id == id })?.name
            } ?? "Auto")
              .font(.subheadline)
          }
        }
        .buttonStyle(.plain)
      }

      Toggle(
        isOn: Binding(
          get: { capture.autoFallbackEnabled },
          set: { value in store.send(.toggleTrafficCaptureFallback(value)) },
        ),
      ) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Auto fallback")
            .font(.body.weight(.medium))
          Text("Try alternative drivers automatically when activation fails")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .toggleStyle(.switch)

      if let driverName = capture.activeDriverName, capture.isActive {
        LabeledContent("Active Driver") {
          Text(driverName).font(.callout.weight(.semibold))
        }
      }

      if let error = capture.lastErrorDescription {
        Text(error)
          .font(.footnote)
          .foregroundStyle(.red)
      }
    } header: {
      Label("Traffic Capture", systemImage: "shield.checkered")
    } footer: {
      Text("Select how macOS traffic is redirected into Mihomo and choose fallback drivers.")
        .foregroundStyle(.secondary)
    }
  }

  // swiftlint:enable closure_body_length

  private var statusSection: some View {
    let status = store.state.statusOverview

    return Section {
      HStack(spacing: 16) {
        Circle()
          .fill(status.indicatorIsActive ? Color.green.gradient : Color.secondary.gradient)
          .frame(width: 12, height: 12)
          .symbolEffect(.pulse, options: .repeating, isActive: status.indicatorIsActive)

        VStack(alignment: .leading, spacing: 2) {
          Text(status.summary)
            .font(.headline)

          if let hint = status.hint {
            Text(hint)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }

        Spacer()
      }
    } header: {
      Label("Status", systemImage: "info.circle")
    }
  }

  private var systemProxySection: some View {
    let proxy = store.state.systemProxy

    return Section {
      Toggle(
        isOn: Binding(
          get: { proxy.isEnabled },
          set: { _ in store.send(.toggleSystemProxy) },
        ),
      ) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Activate System Proxy")
            .font(.body.weight(.medium))
          Text("Expose HTTP, HTTPS, and SOCKS5 proxy services on localhost")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .toggleStyle(.switch)
      .disabled(store.state.isProcessing)

      if proxy.isEnabled {
        if let mixedPort = proxy.mixedPort {
          portInfoRow(title: "Mixed Port", value: "\(mixedPort)", detail: "HTTP(S) + SOCKS5")
        } else {
          portInfoRow(title: "HTTP Port", value: "\(proxy.httpPort)", detail: "HTTP/HTTPS")
          portInfoRow(title: "SOCKS Port", value: "\(proxy.socksPort)", detail: "SOCKS5")
        }
      }
    } header: {
      Label("System Proxy", systemImage: "globe")
    } footer: {
      Text("Adjust macOS network settings to route traffic through Mihomo.")
        .foregroundStyle(.secondary)
    }
  }

  private var tunModeSection: some View {
    let tun = store.state.tunMode

    return Section {
      Toggle(
        isOn: Binding(
          get: { tun.isEnabled },
          set: { _ in store.send(.toggleTunMode) },
        ),
      ) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Activate TUN Mode")
            .font(.body.weight(.medium))
          Text("Requires a privileged helper to be installed and approved")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .toggleStyle(.switch)
      .disabled(store.state.isProcessing)

      if tun.requiresHelperApproval {
        helperApprovalNotice()
        helperApprovalActions()
      } else if !tun.isHelperRegistered {
        Button {
          store.send(.installHelper)
        } label: {
          Label("Install Privileged Helper", systemImage: "arrow.down.circle.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(store.state.isProcessing)
      }
    } header: {
      Label("TUN Mode", systemImage: "shield.lefthalf.filled")
    } footer: {
      Text("TUN mode routes system traffic without manual proxy configuration.")
        .foregroundStyle(.secondary)
    }
  }

  private var proxyModeSection: some View {
    Section {
      Picker(
        "Mode",
        selection: Binding(
          get: { store.state.proxyMode.selection },
          set: { mode in store.send(.selectProxyMode(mode)) },
        ),
      ) {
        ForEach(ProxyMode.allCases, id: \.self) { mode in
          Text(mode.displayName).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .disabled(store.state.isProcessing)

      Text(store.state.proxyMode.description)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    } header: {
      Label("Proxy Mode", systemImage: "arrow.triangle.branch")
    } footer: {
      Text("Choose how Mihomo routes system traffic across proxies.")
        .foregroundStyle(.secondary)
    }
  }

  private var launchAtLoginSection: some View {
    let launch = store.state.launchAtLogin

    return Section {
      Toggle(
        "Launch at Login",
        isOn: Binding(
          get: { launch.isEnabled },
          set: { _ in store.send(.toggleLaunchAtLogin) },
        ),
      )
      .toggleStyle(.switch)
      .disabled(store.state.isProcessing)

      if launch.requiresApproval {
        helperApprovalNotice(text: "Authorize Mihomo under Login Items in System Settings")
        helperApprovalActions(needsStatusRefresh: true)
      }
    } header: {
      Label("Startup", systemImage: "power.circle")
    } footer: {
      Text("Start Miho automatically when you sign in to macOS.")
        .foregroundStyle(.secondary)
    }
  }

  private var configurationSection: some View {
    Section {
      NavigationLink {
        PersistenceView(store: persistenceStore)
      } label: {
        HStack {
          Label("Manage Configurations", systemImage: "doc.text.fill")
          Spacer()
          Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
        }
      }
      .buttonStyle(.plain)
    } header: {
      Label("Configuration", systemImage: "gear")
    } footer: {
      Text("Manage local and remote Mihomo configuration profiles.")
        .foregroundStyle(.secondary)
    }
  }

  private var advancedSection: some View {
    Section {
      Button {
        store.send(.reloadConfig)
      } label: {
        Label("Reload Configuration", systemImage: "arrow.clockwise")
      }
      .buttonStyle(.plain)
      .disabled(store.state.isProcessing)

      Button {
        store.send(.flushDNS)
      } label: {
        Label("Flush DNS Cache", systemImage: "trash")
      }
      .buttonStyle(.plain)
      .tint(.pink)
      .disabled(!store.state.tunMode.isHelperRegistered || store.state.isProcessing)

      Toggle(
        isOn: Binding(
          get: { store.state.allowLan },
          set: { value in store.send(.toggleAllowLAN(value)) },
        ),
      ) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Allow LAN Access")
            .font(.body.weight(.medium))
          Text("Allow devices on the local network to access the local core")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .toggleStyle(.switch)
      .tint(.blue)
      .disabled(store.state.isProcessing)
    } header: {
      Label("Advanced", systemImage: "gearshape.2")
    } footer: {
      Text("Control access to the local core from the local network.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var aboutSection: some View {
    Section {
      LabeledContent("Version") {
        Text("1.0.0")
          .font(.body.weight(.medium))
      }

      Link(
        destination:
        URL(string: "https://github.com/sonqyau/miho") ??
          URL(string: "https://github.com/sonqyau") ?? URL(fileURLWithPath: "/"),
      ) {
        HStack {
          Label("GitHub Repository", systemImage: "link")
          Spacer()
          Image(systemName: "arrow.up.right")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .accessibilityLabel("Opens in browser")
        }
      }
      .buttonStyle(.plain)
    } header: {
      Label("About", systemImage: "info.circle")
    }
  }

  @ViewBuilder private var progressOverlay: some View {
    if store.state.isProcessing {
      ZStack {
        Color.black.opacity(0.15)
          .ignoresSafeArea()

        VStack(spacing: 12) {
          ProgressView()
            .controlSize(.large)
          Text("Applying Changes…")
            .font(.body.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      }
      .transition(.opacity)
      .animation(.easeInOut(duration: 0.2), value: store.state.isProcessing)
    }
  }

  private func helperApprovalNotice(
    text: String = "Allow the helper under Privacy & Security → Developer Tools",
  ) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .accessibilityHidden(true)
        .foregroundStyle(.orange)
      Text(text)
        .font(.callout)
        .foregroundStyle(.orange)
    }
    .padding(12)
    .background(
      Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous),
    )
  }

  private func helperApprovalActions(needsStatusRefresh: Bool = false) -> some View {
    HStack(spacing: 12) {
      Button {
        store.send(.openSystemSettings)
      } label: {
        Label("Open System Settings", systemImage: "gear")
      }
      .buttonStyle(.borderedProminent)
      .disabled(store.state.isProcessing)

      Button {
        if needsStatusRefresh {
          store.send(.confirmLaunchAtLogin)
        } else {
          store.send(.checkHelperStatus)
        }
      } label: {
        Label(
          needsStatusRefresh ? "Refresh Status" : "Check Status", systemImage: "arrow.clockwise",
        )
      }
      .buttonStyle(.bordered)
      .disabled(store.state.isProcessing)
    }
  }

  private func portInfoRow(title: String, value: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(title)
          .font(.callout)
          .foregroundStyle(.secondary)
        Spacer()
        Text(value)
          .font(.callout.weight(.medium))
      }

      Text(detail)
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 4)
  }
}
