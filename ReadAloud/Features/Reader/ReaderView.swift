import SwiftUI

struct ReaderView: View {
    @State private var viewModel = ReaderViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    controls
                    editor
                    actions
                    status
                    MetricsView(metrics: viewModel.metrics)
                    eventLog
                }
                .padding()
            }
            .navigationTitle("ReadAloud")
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Menu("Samples") {
                ForEach(viewModel.samples) { sample in
                    Button(sample.title) {
                        viewModel.loadSample(sample)
                    }
                }
            }
            .disabled(viewModel.isBusy)

            Picker("Voice", selection: $viewModel.selectedVoiceID) {
                ForEach(viewModel.voices) { voice in
                    Text(voice.name)
                        .tag(voice.id)
                }
            }
            .pickerStyle(.menu)
            .disabled(viewModel.isBusy)

            Picker("Speed", selection: $viewModel.selectedSpeed) {
                ForEach(viewModel.speedOptions, id: \.self) { speed in
                    Text(String(format: "%.1f×", speed))
                        .tag(speed)
                }
            }
            .pickerStyle(.menu)
            .disabled(viewModel.isBusy)
        }
    }

    private var editor: some View {
        TextEditor(text: $viewModel.text)
            .font(.body)
            .frame(minHeight: 240)
            .padding(8)
            .scrollContentBackground(.hidden)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            .disabled(viewModel.isBusy)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button("Read") {
                viewModel.read()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canRead)

            Button("Stop") {
                viewModel.stop()
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canStop)

            Button("Warm Up") {
                viewModel.warmUp()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isBusy)

            Spacer()
        }
    }

    private var status: some View {
        HStack(spacing: 8) {
            if viewModel.isBusy {
                ProgressView()
                    .controlSize(.small)
            }

            Text(viewModel.statusText)
                .font(.subheadline)
                .foregroundStyle(
                    viewModel.statusText.hasPrefix("Error:")
                        ? .red
                        : .secondary
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eventLog: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Event Log")
                .font(.headline)

            if viewModel.eventLog.isEmpty {
                Text("No events yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(
                        Array(viewModel.eventLog.enumerated()),
                        id: \.offset
                    ) { _, event in
                        Text(event)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

#Preview {
    ReaderView()
}
