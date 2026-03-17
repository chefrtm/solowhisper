import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedRecord: TranscriptionRecord?
    @State private var showProcessed = true

    var body: some View {
        VStack(spacing: 0) {
            if appState.historyStore.records.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No transcriptions yet")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    // List
                    List(appState.historyStore.records, selection: $selectedRecord) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(record.presetName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(record.date, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(record.rawText)
                                .lineLimit(2)
                                .font(.body)
                        }
                        .padding(.vertical, 2)
                        .tag(record)
                    }
                    .listStyle(.plain)
                    .frame(minWidth: 200)

                    // Detail
                    if let record = selectedRecord {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(record.presetName)
                                    .font(.headline)
                                Spacer()
                                Text(record.date, format: .dateTime)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if record.processedText != nil {
                                Picker("Show", selection: $showProcessed) {
                                    Text("Processed").tag(true)
                                    Text("Original").tag(false)
                                }
                                .pickerStyle(.segmented)
                            }

                            ScrollView {
                                Text(showProcessed ? (record.processedText ?? record.rawText) : record.rawText)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Button("Copy to Clipboard") {
                                let text = showProcessed ? (record.processedText ?? record.rawText) : record.rawText
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                            }
                        }
                        .padding()
                        .frame(minWidth: 250)
                    } else {
                        Text("Select a transcription")
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                Divider()

                HStack {
                    Text("\(appState.historyStore.records.count) records")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear All", role: .destructive) {
                        appState.historyStore.clearAll()
                        selectedRecord = nil
                    }
                }
                .padding(8)
            }
        }
    }
}
