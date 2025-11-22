import ComposableArchitecture
import Perception
import SwiftUI

struct RulesView: View {
  let store: StoreOf<RulesFeature>
  @Bindable private var bindableStore: StoreOf<RulesFeature>
  @FocusState private var isSearchFocused: Bool

  init(store: StoreOf<RulesFeature>) {
    self.store = store
    _bindableStore = Bindable(wrappedValue: store)
  }

  private var searchBinding: Binding<String> {
    Binding(
      get: { bindableStore.searchText },
      set: { bindableStore.send(.updateSearch($0)) },
    )
  }

  var body: some View {
    Form {
      summarySection
      controlsSection
      rulesTableSection
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .navigationTitle("Rule analytics")
    .task { bindableStore.send(.onAppear) }
    .onDisappear { bindableStore.send(.onDisappear) }
  }

  private var summarySection: some View {
    Section {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 24) {
          LabeledContent("Active Rules") {
            Text("\(bindableStore.summary.activeRules)")
              .font(.title3)
          }

          LabeledContent("Total Connections") {
            Text("\(bindableStore.summary.totalConnections)")
              .font(.title3)
          }

          if bindableStore.summary.filteredRules > 0 {
            LabeledContent("Filtered") {
              Text("\(bindableStore.summary.filteredRules)")
            }
          }
        }
      }
      .padding(.vertical, 4)
    } header: {
      Label("Rule Overview", systemImage: "list.bullet")
    }
  }

  private var controlsSection: some View {
    Section {
      VStack(alignment: .leading, spacing: 12) {
        TextField("Filter rules", text: searchBinding)
          .textFieldStyle(.roundedBorder)
          .focused($isSearchFocused)
          .onChange(of: isSearchFocused) { _, focused in
            bindableStore.send(.setSearchFocus(focused))
          }

        Button {
          isSearchFocused = true
        } label: {
          Label("Focus Filter", systemImage: "text.cursor")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)

        if !bindableStore.searchText.isEmpty {
          Button("Clear Filter") {
            bindableStore.send(.updateSearch(""))
          }
          .buttonStyle(.borderless)
          .controlSize(.small)
        }
      }
      .padding(.vertical, 4)
    } header: {
      Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
    }
  }

  private var rulesTableSection: some View {
    Section {
      Table(bindableStore.rules) {
        TableColumn("Rule") { stat in
          Text(stat.rule)
            .font(.system(.body, design: .monospaced))
        }
        .width(min: 250, ideal: 450)

        TableColumn("Connections") { stat in
          Text("\(stat.count)")
        }
        .width(ideal: 140)

        TableColumn("Download") { stat in
          Text(ByteCountFormatter.string(fromByteCount: stat.totalDownload, countStyle: .binary))
            .font(.caption)
        }
        .width(ideal: 130)

        TableColumn("Upload") { stat in
          Text(ByteCountFormatter.string(fromByteCount: stat.totalUpload, countStyle: .binary))
            .font(.caption)
        }
        .width(ideal: 130)

        TableColumn("Total Traffic") { stat in
          let total = stat.totalDownload + stat.totalUpload
          Text(ByteCountFormatter.string(fromByteCount: total, countStyle: .binary))
            .font(.caption)
        }
        .width(ideal: 140)
      }
      .frame(minHeight: 320)
    } header: {
      Label("Rule Usage", systemImage: "chart.bar.doc.horizontal")
    }
  }
}
