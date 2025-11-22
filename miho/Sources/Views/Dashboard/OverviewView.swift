import Charts
import ComposableArchitecture
import Perception
import SwiftUI

struct OverviewView: View {
  let store: StoreOf<OverviewFeature>
  @Bindable private var bindableStore: StoreOf<OverviewFeature>

  init(store: StoreOf<OverviewFeature>) {
    self.store = store
    _bindableStore = Bindable(wrappedValue: store)
  }

  var body: some View {
    Form {
      statsSection(summary: bindableStore.overviewSummary)
      trafficSection(history: bindableStore.trafficHistory)
      systemInfoSection(
        summary: bindableStore.overviewSummary,
        isConnected: bindableStore.isConnected,
      )
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .navigationTitle("System overview")
    .task { bindableStore.send(.onAppear) }
    .onDisappear { bindableStore.send(.onDisappear) }
  }

  private func statsSection(summary: OverviewFeature.State.OverviewSummary) -> some View {
    Section {
      VStack(spacing: 12) {
        OverviewMetricRow(
          title: "Download",
          value: summary.downloadSpeed,
          icon: "arrow.down.circle.fill",
          tint: .blue,
        )

        OverviewMetricRow(
          title: "Upload",
          value: summary.uploadSpeed,
          icon: "arrow.up.circle.fill",
          tint: .green,
        )

        OverviewMetricRow(
          title: "Connections",
          value: "\(summary.connectionCount)",
          icon: "network",
          tint: .purple,
        )

        OverviewMetricRow(
          title: "Memory",
          value: ByteCountFormatter.string(
            fromByteCount: summary.memoryUsage,
            countStyle: .memory,
          ),
          icon: "memorychip.fill",
          tint: .orange,
        )
      }
      .padding(.vertical, 6)
    } header: {
      Label("Current metrics", systemImage: "gauge.medium")
    }
  }

  private func trafficSection(history: [TrafficPoint]) -> some View {
    Section {
      VStack(spacing: 20) {
        trafficChart(title: "Download", history: history, keyPath: \.download, color: .blue)
        trafficChart(title: "Upload", history: history, keyPath: \.upload, color: .green)
      }
      .padding(.vertical, 6)
    } header: {
      Label("Traffic history", systemImage: "chart.xyaxis.line")
    }
  }

  private func systemInfoSection(
    summary: OverviewFeature.State.OverviewSummary,
    isConnected: Bool,
  ) -> some View {
    Section {
      VStack(alignment: .leading, spacing: 12) {
        if !summary.version.isEmpty {
          LabeledContent("Version") {
            Text(summary.version)
          }
        }

        LabeledContent("Status") {
          Text(isConnected ? "Connected" : "Disconnected")
            .foregroundStyle(isConnected ? .green : .red)
        }
      }
      .padding(.vertical, 6)
    } header: {
      Label("System information", systemImage: "info.circle.fill")
    }
  }

  private func trafficChart(
    title: String,
    history: [TrafficPoint],
    keyPath: KeyPath<TrafficPoint, Double>,
    color: Color,
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.headline)

      Chart(history) { point in
        LineMark(
          x: .value("Time", point.timestamp),
          y: .value(title, point[keyPath: keyPath]),
        )
        .foregroundStyle(color.gradient)
        .interpolationMethod(.catmullRom)

        AreaMark(
          x: .value("Time", point.timestamp),
          y: .value(title, point[keyPath: keyPath]),
        )
        .foregroundStyle(color.opacity(0.12).gradient)
        .interpolationMethod(.catmullRom)
      }
      .frame(height: 140)
      .chartYAxis {
        AxisMarks(position: .leading)
      }
    }
  }
}

private struct OverviewMetricRow: View {
  let title: String
  let value: String
  let icon: String
  let tint: Color

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.title3)
        .foregroundStyle(tint)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text(value)
          .font(.title3.weight(.semibold))
          .contentTransition(.numericText())

        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
    .padding(.vertical, 6)
  }
}
