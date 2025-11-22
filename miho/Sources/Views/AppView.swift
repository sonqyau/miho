import ComposableArchitecture
import SwiftUI

struct AppView: View {
  let store: StoreOf<AppFeature>

  var body: some View {
    DashboardView(store: store.scope(state: \.dashboard, action: \.dashboard))
  }
}
