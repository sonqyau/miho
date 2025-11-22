import ComposableArchitecture
import Perception
import SwiftUI

struct MenuBarIconView: View {
  let store: StoreOf<MenuBarFeature>
  @Bindable private var bindableStore: StoreOf<MenuBarFeature>

  private var isActive: Bool {
    bindableStore.isSystemProxyEnabled || bindableStore.isTunModeEnabled
  }

  private var statusColor: Color {
    isActive ? .green : .red
  }

  init(store: StoreOf<MenuBarFeature>) {
    self.store = store
    _bindableStore = Bindable(wrappedValue: store)
  }

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(statusColor)
        .frame(width: 6, height: 6)
        .accessibilityHidden(true)

      VStack(alignment: .trailing, spacing: 0) {
        speedRow(icon: "arrow.up", speed: bindableStore.uploadSpeed)
        speedRow(icon: "arrow.down", speed: bindableStore.downloadSpeed)
      }
    }
    .font(.system(size: 9, weight: .regular, design: .monospaced))
    .foregroundStyle(statusColor)
    .contentTransition(.numericText())
    .task { bindableStore.send(.onAppear) }
    .onDisappear { bindableStore.send(.onDisappear) }
  }

  private func speedRow(icon: String, speed: String) -> some View {
    HStack(spacing: 4) {
      Image(systemName: icon)
        .font(.system(size: 7))
        .accessibilityHidden(true)
      Text(speed)
    }
  }
}

struct MenuBarContentView: View {
  let store: StoreOf<MenuBarFeature>
  @Bindable private var bindableStore: StoreOf<MenuBarFeature>
  @Environment(\.openWindow)
  private var openWindow

  private var isActive: Bool {
    bindableStore.isSystemProxyEnabled || bindableStore.isTunModeEnabled
  }

  private var statusColor: Color {
    isActive ? .green : .secondary
  }

  init(store: StoreOf<MenuBarFeature>) {
    self.store = store
    _bindableStore = Bindable(wrappedValue: store)
  }

  var body: some View {
    Form {
      statusSection
      quickActionsSection

      if !bindableStore.selectorGroups.isEmpty {
        proxyGroupsSection
      }

      navigationSection
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .frame(width: 360)
    .fixedSize(horizontal: false, vertical: true)
    .task { bindableStore.send(.onAppear) }
    .onDisappear { bindableStore.send(.onDisappear) }
    .alert(
      "Menu Bar Error",
      isPresented: Binding(
        get: { bindableStore.alerts.errorMessage != nil },
        set: { presented in
          if !presented {
            bindableStore.send(.dismissError)
          }
        },
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
      statusSectionContent
    } header: {
      Label("Status", systemImage: "info.circle")
    }
  }

  // swiftlint:disable closure_body_length
  @ViewBuilder private var statusSectionContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Circle()
          .fill(statusColor.gradient)
          .frame(width: 10, height: 10)
          .symbolEffect(.pulse, options: .repeating, isActive: isActive)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 4) {
          Text(bindableStore.statusDescription)
            .font(.headline)

          Text(bindableStore.statusSubtitle)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        Spacer()
      }

      if bindableStore.activeFeatures.systemProxy || bindableStore.activeFeatures.tunMode {
        HStack(spacing: 8) {
          if bindableStore.activeFeatures.systemProxy {
            MenuBarStatusBadge(text: "System Proxy", color: .blue)
          }
          if bindableStore.activeFeatures.tunMode {
            MenuBarStatusBadge(text: "TUN", color: .green)
          }
          if bindableStore.isTrafficCaptureActive {
            MenuBarStatusBadge(
              text: bindableStore.captureMode.displayName,
              color: .purple,
            )
          } else if bindableStore.isTrafficCaptureActivating {
            MenuBarStatusBadge(text: "Activating…", color: .orange)
          }
        }
      }

      if bindableStore.isTrafficCaptureActive ||
        bindableStore.isTrafficCaptureActivating
      {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Image(systemName: "shield.checkered")
              .foregroundStyle(.purple)
              .accessibilityHidden(true)
            Text("Traffic Capture")
              .font(.subheadline.weight(.semibold))
            if bindableStore.isTrafficCaptureActivating {
              ProgressView().scaleEffect(0.6)
            }
          }

          Text(bindableStore.activeTrafficDriverName ?? "Auto driver")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
      }

      VStack(spacing: 12) {
        HStack(spacing: 16) {
          trafficStat(
            icon: "arrow.down",
            value: bindableStore.downloadSpeed,
            color: .blue,
          )
          Divider().frame(height: 20)
          trafficStat(
            icon: "arrow.up",
            value: bindableStore.uploadSpeed,
            color: .green,
          )
        }

        HStack(spacing: 8) {
          Image(systemName: modeIcon(for: bindableStore.currentMode))
            .font(.caption)
            .accessibilityHidden(true)
          Text(bindableStore.currentMode.displayName)
            .font(.caption)
            .fontWeight(.semibold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
      }

      if let interface = bindableStore.networkInterface,
         let ipAddress = bindableStore.ipAddress
      {
        HStack(spacing: 8) {
          Image(systemName: "network")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
          Text("\(interface):")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(ipAddress)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
      }
    }
    .padding(.vertical, 4)
  }

  // swiftlint:enable closure_body_length

  private func trafficStat(icon: String, value: String, color: Color) -> some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .foregroundColor(color)
        .font(.caption)
        .accessibilityHidden(true)
      Text(value)
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .contentTransition(.numericText())
    }
    .frame(maxWidth: .infinity)
  }

  private var quickActionsSection: some View {
    Section {
      quickActionsContent
    } header: {
      Label("Quick actions", systemImage: "bolt.fill")
    }
  }

  // swiftlint:disable closure_body_length
  @ViewBuilder private var quickActionsContent: some View {
    VStack(spacing: 12) {
      actionButton(
        title: bindableStore
          .isSystemProxyEnabled ? "Disable System Proxy" : "Enable System Proxy",
        icon: bindableStore.isSystemProxyEnabled ? "wifi.slash" : "wifi",
        isActive: bindableStore.isSystemProxyEnabled,
        activeColor: .blue,
      ) {
        bindableStore.send(.toggleSystemProxy)
      }

      actionButton(
        title: bindableStore.isTunModeEnabled ? "Disable TUN Mode" : "Enable TUN Mode",
        icon: bindableStore.isTunModeEnabled ? "lock.open" : "shield.fill",
        isActive: bindableStore.isTunModeEnabled,
        activeColor: .green,
      ) {
        bindableStore.send(.toggleTunMode)
      }

      actionButton(
        title: bindableStore.isTrafficCaptureActive
          ? "Stop traffic capture"
          : "Start traffic capture",
        icon: bindableStore.isTrafficCaptureActive ? "pause.circle.fill" : "play.circle.fill",
        isActive: bindableStore.isTrafficCaptureActive,
        activeColor: .purple,
      ) {
        bindableStore.send(.toggleTrafficCapture)
      }

      HStack(spacing: 12) {
        Menu {
          ForEach(ProxyMode.allCases, id: \.self) { mode in
            Button { bindableStore.send(.switchMode(mode)) } label: {
              Label(mode.displayName, systemImage: modeIcon(for: mode))
            }
          }
        } label: {
          filterTile(title: "Mode", icon: "arrow.triangle.branch")
        }
        .buttonStyle(.plain)

        Menu {
          ForEach(TrafficCaptureMode.allCases, id: \.self) { mode in
            Button { bindableStore.send(.selectTrafficCaptureMode(mode)) } label: {
              Label(
                mode.displayName,
                systemImage: bindableStore.captureMode == mode ? "checkmark" : "",
              )
            }
          }
        } label: {
          filterTile(title: bindableStore.captureMode.displayName, icon: "shield")
        }
        .buttonStyle(.plain)
      }

      if !bindableStore.availableTrafficDrivers.isEmpty {
        Menu {
          Button("Auto Select") { bindableStore.send(.setPreferredTrafficDriver(nil)) }
            .labelStyle(.titleAndIcon)
            .tag(UUID())
            .buttonStyle(.plain)
          ForEach(bindableStore.availableTrafficDrivers, id: \.id) { driver in
            Button {
              bindableStore.send(.setPreferredTrafficDriver(driver.id))
            } label: {
              Label(
                driver.name,
                systemImage: driver.name == bindableStore.activeTrafficDriverName
                  ? "checkmark"
                  : "",
              )
            }
          }
        } label: {
          filterTile(title: "Driver", icon: "gearshape")
        }
        .buttonStyle(.plain)
      }

      Toggle(
        isOn: Binding(
          get: { bindableStore.autoFallbackEnabled },
          set: { bindableStore.send(.toggleTrafficFallback($0)) },
        ),
      ) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Auto fallback")
            .font(.body.weight(.medium))
          Text("Automatically try a different driver if activation fails")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .toggleStyle(.switch)

      if let error = bindableStore.trafficCaptureError {
        Text(error)
          .font(.footnote)
          .foregroundStyle(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      Button { bindableStore.send(.reloadConfig) } label: {
        filterTile(title: "Reload Configuration", icon: "arrow.clockwise")
      }
      .buttonStyle(.plain)
    }
    .padding(.vertical, 4)
  }

  // swiftlint:enable closure_body_length

  private func actionButton(
    title: String,
    icon: String,
    isActive: Bool,
    activeColor: Color,
    action: @escaping () -> Void,
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: icon)
          .foregroundStyle(isActive ? activeColor : .secondary)
          .accessibilityHidden(true)
        Text(title)
          .font(.body.weight(.medium))
        Spacer()
      }
      .padding(.vertical, 10)
      .padding(.horizontal, 14)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(isActive ? activeColor.opacity(0.15) : Color.secondary.opacity(0.08)),
      )
    }
    .buttonStyle(.plain)
  }

  private func filterTile(title: String, icon: String) -> some View {
    VStack(spacing: 4) {
      Image(systemName: icon)
        .font(.title3)
        .accessibilityHidden(true)
      Text(title)
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
    .frame(maxWidth: .infinity)
  }

  private var proxyGroupsSection: some View {
    Section {
      ForEach(bindableStore.selectorGroups) { proxyGroup in
        MenuBarProxyGroupRow(
          group: proxyGroup,
          proxies: bindableStore.proxies,
          onSelect: { groupName, proxy in
            bindableStore.send(.selectProxy(group: groupName, proxy: proxy))
          },
        )
      }
    } header: {
      Label("Proxy groups", systemImage: "server.rack")
    }
  }

  private var navigationSection: some View {
    Section {
      VStack(spacing: 6) {
        MenuBarNavigationButton(title: "Open dashboard", icon: "square.grid.2x2.fill") {
          openWindow(id: "dashboardWindow")
        }

        MenuBarNavigationButton(title: "Open settings", icon: "gear") {
          openWindow(id: "settingsWindow")
        }

        MenuBarNavigationButton(
          title: "Quit Mihomo",
          icon: "power",
          tint: .red,
          showsChevron: false,
          role: .destructive,
        ) {
          NSApplication.shared.terminate(nil)
        }
      }
    } header: {
      Label("Shortcuts", systemImage: "arrowshape.turn.up.right.circle")
    }
  }

  private func modeIcon(for mode: ProxyMode) -> String {
    switch mode {
    case .rule: "list.bullet.circle"
    case .global: "globe"
    case .direct: "arrow.right.circle"
    }
  }
}

struct MenuBarStatusBadge: View {
  let text: String
  let color: Color

  var body: some View {
    Text(text)
      .font(.caption2)
      .fontWeight(.semibold)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .foregroundColor(color)
      .background(color.opacity(0.15))
      .clipShape(Capsule())
  }
}

struct MenuBarNavigationButton: View {
  let title: String
  let icon: String
  var tint: Color?
  var showsChevron: Bool
  var role: ButtonRole?
  let action: () -> Void

  init(
    title: String,
    icon: String,
    tint: Color? = nil,
    showsChevron: Bool = true,
    role: ButtonRole? = nil,
    action: @escaping () -> Void,
  ) {
    self.title = title
    self.icon = icon
    self.tint = tint
    self.showsChevron = showsChevron
    self.role = role
    self.action = action
  }

  var body: some View {
    Button(role: role, action: action) {
      HStack(spacing: 8) {
        Label(title, systemImage: icon)
          .foregroundStyle(tint ?? .primary)
        Spacer()
        if showsChevron {
          Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundColor(.secondary)
            .accessibilityHidden(true)
        }
      }
      .padding(.vertical, 8)
      .padding(.horizontal, 12)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill((tint ?? Color.secondary).opacity(0.08)),
      )
    }
    .buttonStyle(.plain)
  }
}

private struct MenuBarProxyGroupRow: View {
  let group: MenuBarFeature.State.ProxySelectorGroup
  let proxies: [String: ProxyInfo]
  let onSelect: (String, String) -> Void

  @State
  private var isExpanded = false

  var body: some View {
    VStack(spacing: 0) {
      Button {
        withAnimation(.snappy) {
          isExpanded.toggle()
        }
      } label: {
        HStack {
          Image(systemName: "chevron.right")
            .font(.caption)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .foregroundColor(.secondary)
            .accessibilityHidden(true)

          Text(group.info.name)
            .font(.headline)

          Spacer()

          if let active = group.info.now {
            Text(active)
              .font(.caption.weight(.semibold))
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Color.accentColor.opacity(0.12), in: Capsule())
          } else {
            Text("Not Connected")
              .foregroundColor(.secondary)
          }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      .buttonStyle(.plain)

      if isExpanded {
        VStack(spacing: 4) {
          ForEach(group.info.all, id: \.self) { proxyName in
            MenuBarProxyNodeRow(
              proxyName: proxyName,
              isSelected: proxyName == group.info.now,
              proxyInfo: proxies[proxyName],
            ) {
              onSelect(group.id, proxyName)
            }
          }
        }
        .padding(.top, 4)
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
      }
    }
  }
}

private struct MenuBarProxyNodeRow: View {
  let proxyName: String
  let isSelected: Bool
  let proxyInfo: ProxyInfo?
  let onSelect: () -> Void

  var body: some View {
    Button(action: onSelect) {
      HStack {
        Circle()
          .fill(statusColor)
          .frame(width: 8, height: 8)
          .overlay(
            Circle()
              .stroke(Color.secondary.opacity(0.3), lineWidth: 1),
          )

        Text(proxyName)
          .font(.body)
          .fontWeight(isSelected ? .semibold : .regular)

        Spacer()

        Text(delayDisplay)
          .font(.system(size: 11, weight: .medium, design: .monospaced))
          .foregroundStyle(delayColor)
      }
      .padding(.vertical, 6)
      .padding(.horizontal, 12)
      .padding(.leading, 8)
      .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
      .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    .buttonStyle(.plain)
  }

  private var delay: Int? {
    proxyInfo?.history.last?.delay
  }

  private var delayDisplay: String {
    guard let delay else {
      return "--"
    }
    if delay == 0 {
      return "Timeout"
    }
    return "\(delay)ms"
  }

  private var delayColor: Color {
    guard let delay else {
      return .secondary
    }
    if delay == 0 {
      return .red
    }
    if delay < 300 {
      return .green
    }
    return .orange
  }

  private var statusColor: Color {
    if isSelected {
      return .accentColor
    }
    return delayColor == .secondary ? Color.secondary.opacity(0.6) : delayColor
  }
}

enum MenuBarView { }
