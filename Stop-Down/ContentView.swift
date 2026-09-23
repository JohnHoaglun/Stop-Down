import SwiftUI

struct ContentView: View {
    @State private var controller: MeteringController

    @MainActor
    init() {
        _controller = State(initialValue: MeteringController())
    }

    var body: some View {
        MeterScreen(controller: controller)
    }
}

#Preview {
    ContentView()
}
