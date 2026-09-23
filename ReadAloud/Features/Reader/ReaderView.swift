import SwiftUI

struct ReaderView: View {
    @State private var viewModel = ReaderViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextEditor(text: $viewModel.text)
                    .font(.body)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

                HStack {
                    Button("Read") {
                        // Kokoro integration is added in a later phase.
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(true)

                    Spacer()

                    Text("Kokoro not integrated yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .navigationTitle("ReadAloud")
        }
    }
}

#Preview {
    ReaderView()
}
