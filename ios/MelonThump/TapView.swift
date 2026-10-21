import SwiftUI

/// Main screen: record a tap, upload, show the verdict.
/// UI v4 — Stephanie's design: her original watermelon & cat artwork
/// (Assets.xcassets), her palette (MelonTheme), iPhone portrait layout.
@MainActor
struct TapView: View {
    @StateObject private var recorder = AudioRecorder()
    @State private var serverURL = "http://localhost:8080"
    @State private var result: TapResult?
    @State private var errorMessage: String?
    @State private var isAnalyzing = false
    @State private var recordingStartedAt: Date?

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            content
        }
    }

    private var backgroundColor: Color {
        if let result {
            return Ripeness(verdict: result.verdict).screenTint
        }
        return MelonTheme.background
    }

    @ViewBuilder
    private var content: some View {
        if isAnalyzing {
            AnalyzingView()
        } else if recorder.isRecording {
            RecordingView(startedAt: recordingStartedAt ?? Date(), onStop: toggleRecording)
        } else if let result {
            ResultView(result: result, errorMessage: errorMessage) {
                self.result = nil
                self.errorMessage = nil
            }
        } else {
            homeView
        }
    }

    // MARK: - Home (idle)

    private var homeView: some View {
        VStack(spacing: 0) {
            Text("MelonThump")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(MelonTheme.ink)
            Text("thump it & know it!")
                .font(.custom("Snell Roundhand", size: 21))
                .fontWeight(.bold)
                .foregroundColor(MelonTheme.deepGreen)
                .padding(.top, 2)

            Image("HeroMelon")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 290)
                .padding(.top, 26)

            VStack(alignment: .leading, spacing: 4) {
                Text("How it works")
                    .font(.headline)
                    .foregroundColor(MelonTheme.ink)
                Text("Hold your phone near a watermelon, thump it once, and we'll listen to how ripe it is.")
                    .font(.subheadline)
                    .foregroundColor(MelonTheme.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(MelonTheme.cream)
            .cornerRadius(24)
            .shadow(color: MelonTheme.ink.opacity(0.13), radius: 8, y: 4)
            .padding(.top, 26)

            Spacer()

            HStack(alignment: .bottom) {
                Image("CatLeft").resizable().scaledToFit().frame(width: 54)
                Spacer()
                Image("CatOrange").resizable().scaledToFit().frame(width: 54)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, -6)

            Button(action: toggleRecording) {
                HStack(spacing: 9) {
                    Circle().fill(Color.white).frame(width: 12, height: 12)
                    Text("Start Recording")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(MelonTheme.buttonGreen)
                .foregroundColor(.white)
                .cornerRadius(999)
                .shadow(color: MelonTheme.buttonGreen.opacity(0.35), radius: 10, y: 5)
            }

            Text("Tap, thump, done — about 3 seconds")
                .font(.caption)
                .foregroundColor(MelonTheme.inkSoft)
                .padding(.top, 10)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }

            DisclosureGroup("Server") {
                TextField("Server URL", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote)
            }
            .font(.footnote)
            .foregroundColor(MelonTheme.inkSoft)
            .padding(.top, 14)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Actions (unchanged from v1)

    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stopRecording()
            recordingStartedAt = nil
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
                    recordingStartedAt = Date()
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

// MARK: - Recording

struct RecordingView: View {
    let startedAt: Date
    let onStop: () -> Void
    @State private var pulsing = false

    var body: some View {
        VStack(spacing: 0) {
            Text("listening…")
                .font(.custom("Snell Roundhand", size: 32))
                .fontWeight(.bold)
                .foregroundColor(MelonTheme.deepGreen)
                .padding(.top, 24)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.75), lineWidth: 2.5)
                    .frame(width: 238, height: 238)
                    .scaleEffect(pulsing ? 1.05 : 0.96)
                    .opacity(pulsing ? 0.4 : 0.9)
                Circle()
                    .stroke(Color.white.opacity(0.7), lineWidth: 2.5)
                    .frame(width: 188, height: 188)
                    .scaleEffect(pulsing ? 0.97 : 1.04)
                    .opacity(pulsing ? 0.9 : 0.5)
                Image("HeroMelon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 228)
            }
            .padding(.top, 30)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }

            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(alignment: .center, spacing: 5) {
                    ForEach(0..<11, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(MelonTheme.deepGreen)
                            .frame(width: 7, height: 30 + 22 * (0.5 + 0.5 * sin(t * 6 + Double(i) * 0.9)))
                    }
                }
                .frame(height: 64)
            }
            .padding(.top, 18)

            TimelineView(.periodic(from: startedAt, by: 0.1)) { context in
                let elapsed = max(0, context.date.timeIntervalSince(startedAt))
                Text(String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60))
                    .font(.title3.weight(.bold))
                    .foregroundColor(MelonTheme.ink)
            }
            .padding(.top, 6)

            Text("Thump the melon now —\none good knock is enough")
                .font(.subheadline)
                .foregroundColor(MelonTheme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            Spacer()

            Button(action: onStop) {
                Text("■  Stop & Analyze")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(MelonTheme.recordRed)
                    .foregroundColor(.white)
                    .cornerRadius(999)
                    .shadow(color: MelonTheme.recordRed.opacity(0.35), radius: 10, y: 5)
            }
            Text("Recording… keep the phone close")
                .font(.caption)
                .foregroundColor(MelonTheme.inkSoft)
                .padding(.top, 10)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
    }
}

// MARK: - Analyzing ("please wait" — Stephanie's page)

struct AnalyzingView: View {
    @State private var sheen = false

    var body: some View {
        VStack(spacing: 0) {
            Image("PleaseWaitArt")
                .resizable()
                .scaledToFit()
                .cornerRadius(16)
                .shadow(color: MelonTheme.ink.opacity(0.25), radius: 12, y: 6)
                .padding(.top, 16)

            Text("Her original page, kept as-is —\nthe cats are listening to your thump…")
                .font(.subheadline)
                .foregroundColor(MelonTheme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.top, 24)

            Spacer()

            Image("LoadingBar")
                .resizable()
                .scaledToFit()
                .overlay {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.45), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.35)
                        .offset(x: sheen ? geo.size.width * 0.8 : -geo.size.width * 0.4)
                    }
                }
                .clipped()
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        sheen = true
                    }
                }

            Text("Analyzing…")
                .font(.caption)
                .foregroundColor(MelonTheme.inkSoft)
                .padding(.top, 10)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
    }
}

// MARK: - Result

struct ResultView: View {
    let result: TapResult
    let errorMessage: String?
    let onAgain: () -> Void

    private var ripeness: Ripeness { Ripeness(verdict: result.verdict) }

    var body: some View {
        VStack(spacing: 0) {
            Text("RESULT")
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(ripeness.accent)
                .cornerRadius(999)
                .padding(.top, 20)

            Image(ripeness.catAsset)
                .resizable()
                .scaledToFit()
                .frame(height: 118)
                .padding(.top, 18)

            Text(ripeness.displayName)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(ripeness.accent)
                .padding(.top, 12)

            Text(ripeness.tagline)
                .font(.subheadline)
                .foregroundColor(MelonTheme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    stat(value: String(format: "%.0f Hz", result.dominantFrequencyHz), label: "DOMINANT")
                    stat(value: "\(Int(result.confidence * 100))%", label: "CONFIDENCE")
                    stat(value: String(format: "%.0f ms", result.decayTimeMs), label: "DECAY")
                }
                ZoneBar(hz: result.dominantFrequencyHz, accent: ripeness.accent)
                Text(thresholdNote)
                    .font(.caption2)
                    .foregroundColor(MelonTheme.inkSoft)
            }
            .padding(16)
            .background(MelonTheme.cream)
            .cornerRadius(24)
            .shadow(color: MelonTheme.ink.opacity(0.13), radius: 8, y: 4)
            .padding(.top, 20)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }

            Spacer()

            Button(action: onAgain) {
                Text("Thump Another Melon")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(MelonTheme.buttonGreen)
                    .foregroundColor(.white)
                    .cornerRadius(999)
                    .shadow(color: MelonTheme.buttonGreen.opacity(0.35), radius: 10, y: 5)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundColor(MelonTheme.ink)
            Text(label)
                .font(.caption2)
                .foregroundColor(MelonTheme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(MelonTheme.background.opacity(0.45))
        .cornerRadius(16)
    }

    private var thresholdNote: String {
        switch ripeness {
        case .ripe: return "160–280 Hz = ripe · placeholder thresholds, v1"
        case .unripe: return "above 280 Hz = not ripe yet · placeholder thresholds, v1"
        case .overripe: return "below 160 Hz = overripe · placeholder thresholds, v1"
        case .unknown: return "placeholder thresholds, v1"
        }
    }
}

/// Gradient scale from unripe (yellow) through ripe (green) to overripe
/// (brown), with a marker at the measured dominant frequency.
struct ZoneBar: View {
    let hz: Double
    let accent: Color

    private var position: Double {
        min(0.98, max(0.02, (hz - 100) / (350 - 100)))
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("unripe").font(.caption2).foregroundColor(MelonTheme.inkSoft)
                Spacer()
                Text("ripe").font(.caption2).foregroundColor(MelonTheme.inkSoft)
                Spacer()
                Text("overripe").font(.caption2).foregroundColor(MelonTheme.inkSoft)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(
                            colors: [Color(red: 0.91, green: 0.83, blue: 0.30),
                                     Color(red: 0.56, green: 0.80, blue: 0.42),
                                     Color(red: 0.56, green: 0.80, blue: 0.42),
                                     Color(red: 0.75, green: 0.52, blue: 0.32)],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(height: 10)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(accent, lineWidth: 3.5))
                        .offset(x: position * (geo.size.width - 18))
                }
            }
            .frame(height: 18)
        }
    }
}
