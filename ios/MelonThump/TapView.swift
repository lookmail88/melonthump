import SwiftUI

/// Main screen: record a tap, upload, show the verdict.
/// UI v4 — Stephanie's design: her original watermelon & cat artwork
/// (Assets.xcassets), her palette (MelonTheme), iPhone portrait layout.
@MainActor
struct TapView: View {
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var wallet = CreditWallet()
    @AppStorage("serverEnvironment") private var serverEnvironment: ServerEnvironment = .prod
    @State private var result: TapResult?
    @State private var errorMessage: String?
    @State private var isAnalyzing = false
    @State private var recordingStartedAt: Date?
    @State private var showOutOfCredits = false
    @State private var showPromoGate = false

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            content
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Out of credits", isPresented: $showOutOfCredits) {
            Button("Watch an ad (+\(wallet.creditPerAd))") { earnWithAd() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Watch a short ad to earn credits for more thumps.")
        }
        .alert("Launch promo", isPresented: $showPromoGate) {
            Button("Watch an ad") { earnWithAd() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("First thump of the day: watch one short ad and thump free for the rest of today.")
        }
        .task {
            await recorder.prepareSession()
            await wallet.refreshPolicy(environment: serverEnvironment)
        }
        .onChange(of: serverEnvironment) { _, env in
            Task { await wallet.refreshPolicy(environment: env) }
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
            RecordingView(recorder: recorder, startedAt: recordingStartedAt ?? Date(), onStop: toggleRecording)
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

            Text("One good thump — it stops itself at 5 seconds")
                .font(.caption)
                .foregroundColor(MelonTheme.inkSoft)
                .padding(.top, 10)

            creditsRow
                .padding(.top, 8)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }

            DisclosureGroup("Server") {
                Picker("Server", selection: $serverEnvironment) {
                    ForEach(ServerEnvironment.allCases) { env in
                        Text(env.displayName).tag(env)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .font(.footnote)
            .foregroundColor(MelonTheme.inkSoft)
            .padding(.top, 14)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Credits

    @ViewBuilder
    private var creditsRow: some View {
        if wallet.needsPromoAd {
            Button {
                earnWithAd()
            } label: {
                Text("Launch promo — watch one ad, thump free all day")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(MelonTheme.buttonGreen)
            }
        } else if wallet.isPromoActive && wallet.isPromoUnlockedToday {
            Text("Promo unlocked — unlimited thumps today")
                .font(.footnote.weight(.semibold))
                .foregroundColor(MelonTheme.deepGreen)
        } else if wallet.isFreeDay {
            Text("Free day — unlimited thumps, no ads today")
                .font(.footnote.weight(.semibold))
                .foregroundColor(MelonTheme.deepGreen)
        } else if wallet.balance > 0 {
            Text("Credits: \(wallet.balance)")
                .font(.footnote)
                .foregroundColor(MelonTheme.inkSoft)
        } else if wallet.canEarnFromAd {
            Button {
                earnWithAd()
            } label: {
                Text("Out of credits — watch an ad to earn +\(wallet.creditPerAd)")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(MelonTheme.buttonGreen)
            }
        } else {
            Text("Out of credits — daily ad limit reached, come back tomorrow")
                .font(.footnote)
                .foregroundColor(MelonTheme.inkSoft)
        }
    }

    private func earnWithAd() {
        Task {
            if await AdsManager.shared.showRewarded() {
                if wallet.needsPromoAd {
                    wallet.unlockPromoForToday()
                } else {
                    wallet.grantFromAd()
                }
            } else if !AdsManager.shared.rewardedReady {
                errorMessage = "The ad is still loading — give it a few seconds and try again."
            }
        }
    }

    // MARK: - Actions (unchanged from v1)

    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stopRecording()
            recordingStartedAt = nil
            analyze()
        } else {
            guard wallet.canThump else {
                if wallet.needsPromoAd {
                    showPromoGate = true
                } else {
                    showOutOfCredits = true
                }
                return
            }
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
        isAnalyzing = true
        errorMessage = nil
        Task {
            defer { isAnalyzing = false }
            do {
                // Analysis runs fully on-device; nothing is uploaded.
                result = try LocalAnalyzer.analyze(audioURL: audioURL)
                // One credit per completed analysis; an UNKNOWN (too
                // noisy to judge) result is free.
                if let verdict = result?.verdict, verdict != "UNKNOWN" {
                    wallet.spendOne()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Recording

struct RecordingView: View {
    @ObservedObject var recorder: AudioRecorder
    let startedAt: Date
    let onStop: () -> Void
    @State private var pulsing = false
    /// Rolling history of live mic levels, oldest → newest (real waveform).
    @State private var levels: [Double] = []
    /// Seconds since recording started, ticked by the countdown task.
    @State private var elapsed: Double = 0

    /// Recording is capped at 5 seconds, counted down on screen.
    private var secondsLeft: Int { max(0, Int(ceil(5 - elapsed))) }
    /// The user may stop manually once past the third second.
    private var canStop: Bool { elapsed > 3 }

    private let barCount = 36

    private func barHeight(at index: Int) -> CGFloat {
        let level = index < levels.count ? levels[index] : 0
        return 6 + CGFloat(level) * 56
    }

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

            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(MelonTheme.deepGreen)
                        .frame(width: 6, height: barHeight(at: i))
                }
            }
            .frame(height: 64)
            .padding(.top, 18)
            .onChange(of: recorder.audioLevel) { _, newLevel in
                levels.append(newLevel)
                if levels.count > barCount {
                    levels.removeFirst(levels.count - barCount)
                }
            }

            VStack(spacing: 0) {
                Text("\(secondsLeft)")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundColor(MelonTheme.ink)
                Text(secondsLeft == 1 ? "second left" : "seconds left")
                    .font(.caption)
                    .foregroundColor(MelonTheme.inkSoft)
            }
            .padding(.top, 10)

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
            .disabled(!canStop)
            .opacity(canStop ? 1 : 0.55)
            Text(canStop ? "Auto-stops when the countdown ends" : "You can stop after 3 seconds")
                .font(.caption)
                .foregroundColor(MelonTheme.inkSoft)
                .padding(.top, 10)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
        .task {
            // 5-second countdown: tick the elapsed clock, unlock the
            // stop button after 3s (canStop), and stop & analyze
            // automatically when the countdown runs out.
            while !Task.isCancelled {
                elapsed = max(0, Date().timeIntervalSince(startedAt))
                if elapsed >= 5 {
                    onStop()
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
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
                if let debug = result.debugSummary {
                    Text(debug)
                        .font(.caption2.monospaced())
                        .foregroundColor(MelonTheme.inkSoft)
                        .multilineTextAlignment(.center)
                }
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
/// The axis runs high → low frequency, matching the labels and the
/// physics: a high "ping" is unripe (left), a low thud is overripe
/// (right). Green spans the ripe band, 160–280 Hz.
struct ZoneBar: View {
    let hz: Double
    let accent: Color

    private var position: Double {
        min(0.98, max(0.02, (350 - hz) / (350 - 100)))
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
                            stops: [
                                .init(color: Color(red: 0.91, green: 0.83, blue: 0.30), location: 0),
                                .init(color: Color(red: 0.56, green: 0.80, blue: 0.42), location: 0.28),
                                .init(color: Color(red: 0.56, green: 0.80, blue: 0.42), location: 0.76),
                                .init(color: Color(red: 0.75, green: 0.52, blue: 0.32), location: 1),
                            ],
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
