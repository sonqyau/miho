import ComposableArchitecture
import Perception
import SwiftUI

struct DaemonView: View {
  let store: StoreOf<DaemonFeature>
  @Bindable private var bindableStore: StoreOf<DaemonFeature>

  var body: some View {
    DaemonContentView(store: bindableStore)
      .frame(maxWidth: 500)
      .padding(32)
      .task { bindableStore.send(.onAppear) }
      .onDisappear { bindableStore.send(.onDisappear) }
      .alert(
        "Daemon Error",
        isPresented: Binding(
          get: { bindableStore.alerts.errorMessage != nil },
          set: { isPresented in
            if !isPresented {
              bindableStore.send(.dismissError)
            }
          },
        ),
      ) {
        Button("OK") {
          bindableStore.send(.dismissError)
        }
      } message: {
        Text(bindableStore.alerts.errorMessage ?? "An unexpected error occurred.")
      }
  }

  init(store: StoreOf<DaemonFeature>) {
    self.store = store
    _bindableStore = Bindable(wrappedValue: store)
  }

  private func statusDescription(for store: StoreOf<DaemonFeature>) -> String {
    if store.isRegistered {
      "The privileged helper is installed and operational."
    } else if store.requiresApproval {
      "Approve the privileged helper in System Settings to enable TUN mode."
    } else {
      "Miho requires a privileged helper to manage system proxy settings. Administrator approval is required."
    }
  }
}

private struct DaemonContentView: View {
  @Bindable var store: StoreOf<DaemonFeature>

  var body: some View {
    VStack(spacing: 24) {
      statusIcon
      statusText
      actionButtons
      processingIndicator
    }
  }

  @ViewBuilder private var statusIcon: some View {
    Image(systemName: store.isRegistered
      ? "checkmark.shield.fill"
      : "exclamationmark.shield.fill")
      .font(.system(size: 72))
      .foregroundStyle(
        store.isRegistered
          ? AnyShapeStyle(.green.gradient)
          : AnyShapeStyle(.orange.gradient),
      )
      .symbolEffect(.bounce, value: store.isRegistered)
      .padding(20)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
      .accessibilityLabel(store.isRegistered ? "Helper installed" : "Helper not installed")
  }

  private var statusText: some View {
    VStack(spacing: 12) {
      Text("System Proxy Service")
        .font(Font.title2.weight(.semibold))

      Text(statusDescription(for: store))
        .font(Font.body)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 24)
  }

  @ViewBuilder private var actionButtons: some View {
    VStack(spacing: 16) {
      if store.isRegistered {
        Button {
          store.send(.unregisterHelper)
        } label: {
          Label("Unregister Helper", systemImage: "trash")
            .frame(maxWidth: 280)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)

      } else if store.requiresApproval {
        Button {
          store.send(.openSystemSettings)
        } label: {
          Label("Open System Settings", systemImage: "gear")
            .frame(maxWidth: 280)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)

        Button {
          store.send(.refreshStatus)
        } label: {
          Label("Refresh Status", systemImage: "arrow.clockwise")
            .frame(maxWidth: 280)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)

      } else {
        Button {
          store.send(.registerHelper)
        } label: {
          Label("Install Helper", systemImage: "arrow.down.circle.fill")
            .frame(maxWidth: 280)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(store.isProcessing)
      }
    }
  }

  @ViewBuilder private var processingIndicator: some View {
    if store.isProcessing {
      ProgressView()
        .controlSize(.large)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
  }

  private func statusDescription(for store: StoreOf<DaemonFeature>) -> String {
    if store.isRegistered {
      "The privileged helper is active and ready."
    } else if store.requiresApproval {
      "Authorize the privileged helper in System Settings to enable TUN mode."
    } else {
      "Mihomo requires a privileged helper to manage system proxy configuration. Administrator authorization is required."
    }
  }
}
