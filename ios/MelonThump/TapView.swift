import SwiftUI

/// Main screen: record a tap, upload, show the verdict.
/// UI is intentionally simple — Stephanie's design elements will drive the final look.
@MainActor
struct TapView: View {
    @StateObject private var recorder = AudioRecorder()
    @State private var serverURL = "http://localhost:8080"
    @State private var result: TapResult?
    @State private var errorMessage: String?
    @State private var isAnalyzing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("🍉")
                    .font(.system(size: 72))

                Text("Tap the watermelon, then stop to analyze.")
                    .foregroundColor(.secondary)

                Button(action: toggleRecording) {
                    Label(
                        recorder.isRecording ? "Stop & Analyze" : "Start Recording",
                        systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                    )
                    .font(.title2)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(recorder.isRecording ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                }
                .disabled(isAnalyzing)

                if isAnalyzing {
                    ProgressView("Analyzing…")
                }

                if let result {
                    VerdictCard(result: result)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                }

                Spacer()

                TextField("Server URL", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote)

                Text("v1 uses fixed heuristic thresholds — placeholders until labeled data arrives.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("MelonThump")
        }
    }

    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stopRecording()
            analyze()
        } else {
            errorMessage = nil
            result = nil
            Task {
                guard await recorder.requestPermission() else {
                    errorMessage = "Microphone permission denied."
                    return
                }
                do {
                    try recorder.startRecording()
                } catch {
                    errorMessage = "Failed to start recording: \(error.localizedDescription)"
                }
            }
        }
    }

    private func analyze() {
        guard let audioURL = recorder.lastRecordingURL else {
            errorMessage = "No recording found."
            return
        }
        guard let baseURL = URL(string: serverURL.trimmingCharacters(in: .whitespaces)),
              baseURL.scheme != nil else {
            errorMessage = "Invalid server URL."
            return
        }
        isAnalyzing = true
        errorMessage = nil
        Task {
            defer { isAnalyzing = false }
            do {
                let client = APIClient(baseURL: baseURL)
                result = try await client.analyzeTap(audioURL: audioURL)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct VerdictCard: View {
    let result: TapResult
    private var ripeness: Ripeness { Ripeness(verdict: result.verdict) }

    var body: some View {
        VStack(spacing: 8) {
            Text("\(ripeness.emoji) \(ripeness.displayName)")
                .font(.title2)
                .bold()
            Text("Confidence: \(Int(result.confidence * 100))% · \(result.modelVersion)")
                .font(.footnote)
                .foregroundColor(.secondary)
            Divider()
            HStack {
                VStack(alignment: .leading) {
                    Text("Dominant: \(String(format: "%.1f", result.dominantFrequencyHz)) Hz")
                    Text("Centroid: \(String(format: "%.1f", result.spectralCentroidHz)) Hz")
                    Text("Decay: \(String(format: "%.0f", result.decayTimeMs)) ms")
                }
                .font(.footnote)
                .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(ripeness.color.opacity(0.15))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(ripeness.color, lineWidth: 2)
        )
    }
}
