//  AudioBlock.swift
//  MyNotes
//
//  Roadmap item 13 — Voice Notes: an audio block that records and
//  plays back a voice note inside a page. One coordinator per
//  PageView owns the AVAudioRecorder / AVAudioPlayer, so only one
//  block records or plays at a time — starting a new recording or
//  playback stops whatever is running (a stopped recording is saved
//  as a take, never lost). Audio is AAC (.m4a) data stored in the
//  block (Block.audioData), so it rides along in the saved page JSON
//  and the iCloud snapshot — long recordings make the dataset
//  bigger, there is no separate audio file store in v1.
//
//  Microphone permission: recording needs NSMicrophoneUsageDescription
//  in the app's Info. The project uses a generated Info.plist
//  (GENERATE_INFOPLIST_FILE = YES), so the key is added in Xcode:
//  app target -> Info tab -> add NSMicrophoneUsageDescription with a
//  plain-English reason. Until it is added, recording fails and the
//  block shows a message instead of crashing.

import SwiftUI
import AVFoundation

// MARK: - Audio Coordinator

/// Owns the AVAudioRecorder / AVAudioPlayer for voice-note blocks.
final class AudioBlockCoordinator: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    /// The block currently recording, if any.
    @Published var recordingBlockID: UUID?
    /// Elapsed recording time, updated ~4x/second while recording.
    @Published var recordingElapsed: TimeInterval = 0
    /// The block currently playing, if any.
    @Published var playingBlockID: UUID?
    /// Elapsed playback time, updated ~4x/second while playing.
    @Published var playingElapsed: TimeInterval = 0
    /// Set when the user tried to record but microphone access is
    /// denied. The block view shows a message with an Open Settings
    /// button instead of crashing.
    @Published var permissionDenied = false
    /// Set when recording could not start for a reason other than
    /// permission (e.g. no microphone — the simulator may not have
    /// one). The block view shows a different message, so a
    /// simulator limitation is not mistaken for a permission problem.
    @Published var recordingFailed = false

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    /// The closure that receives a finished recording. Stored so a
    /// recording stopped by starting another one (or by an incoming
    /// call) still saves its take.
    private var recordingFinish: ((Data) -> Void)?
    private var timer: Timer?

    // MARK: - Recording

    /// Starts recording into the given block. Requests microphone
    /// permission first when it has not been decided yet. When
    /// recording stops (stop button, another block starting, or an
    /// interruption), the AAC data is handed to `onFinish` — the
    /// caller writes it into the block by id.
    func startRecording(blockID: UUID, onFinish: @escaping (Data) -> Void) {
        // A recording already in progress (another block) is stopped
        // first — stopRecording() saves its take via its own finish
        // closure, so nothing is lost.
        if recordingBlockID != nil { stopRecording() }
        stopPlayback()
        permissionDenied = false
        recordingFailed = false
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            beginRecording(blockID: blockID, onFinish: onFinish)
        case .denied:
            permissionDenied = true
        case .undetermined:
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                // The permission callback arrives on an arbitrary
                // queue — hop back to the main thread before
                // touching the recorder or the published state.
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.beginRecording(blockID: blockID, onFinish: onFinish)
                    } else {
                        self.permissionDenied = true
                    }
                }
            }
        @unknown default:
            permissionDenied = true
        }
    }

    private func beginRecording(blockID: UUID, onFinish: @escaping (Data) -> Void) {
        do {
            let session = AVAudioSession.sharedInstance()
            // .playAndRecord with .defaultToSpeaker so playback comes
            // out of the speaker, not the earpiece.
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("voice-note-\(blockID.uuidString).m4a")
            // AAC in an .m4a container, mono — compact enough to
            // store in the page JSON.
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            self.recorder = recorder
            recordingBlockID = blockID
            recordingFinish = onFinish
            recordingElapsed = 0
            // record() returns false when recording cannot start
            // (e.g. no microphone on the simulator) — show the
            // message instead of a stuck recording state.
            guard recorder.record() else {
                self.recorder = nil
                recordingBlockID = nil
                recordingFinish = nil
                recordingFailed = true
                try? FileManager.default.removeItem(at: url)
                return
            }
            startTimer()
        } catch {
            // Session setup or recorder creation failed (no mic, or
            // the NSMicrophoneUsageDescription key is missing) —
            // message, not a crash.
            recordingFailed = true
            recordingBlockID = nil
            recordingFinish = nil
        }
    }

    /// Stops the recording and hands the AAC data to the finish
    /// closure, which writes it into the block. A no-op when
    /// nothing is recording.
    func stopRecording() {
        guard let recorder else { return }
        recorder.stop()
        stopTimer()
        recordingElapsed = 0
        recordingBlockID = nil
        let url = recorder.url
        self.recorder = nil
        if let data = try? Data(contentsOf: url) {
            recordingFinish?(data)
        }
        recordingFinish = nil
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Playback

    /// Plays the given block's audio, or stops it when it is already
    /// playing. Starting playback stops any recording (saving its
    /// take) and any other playing block.
    func togglePlayback(blockID: UUID, data: Data) {
        if playingBlockID == blockID {
            stopPlayback()
            return
        }
        if recordingBlockID != nil { stopRecording() }
        stopPlayback()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            playingBlockID = blockID
            playingElapsed = 0
            player.play()
            startTimer()
        } catch {
            playingBlockID = nil
        }
    }

    /// Stops playback. A no-op when nothing is playing.
    func stopPlayback() {
        player?.stop()
        player = nil
        playingBlockID = nil
        playingElapsed = 0
        if recordingBlockID == nil { stopTimer() }
    }

    deinit {
        // The timer is retained by the run loop, not by self — it
        // must be invalidated here or it keeps firing after the
        // coordinator is gone.
        timer?.invalidate()
    }

    /// Stops everything (recording and playback). PageView calls
    /// this when it disappears, so audio never keeps playing after
    /// leaving the page — a recording in progress is saved as a
    /// take rather than discarded.
    func stopAll() {
        if recordingBlockID != nil { stopRecording() }
        stopPlayback()
        stopTimer()
    }

    // MARK: - Delegates

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // This also fires after our own stopRecording(), but by then
        // recordingBlockID is nil — so this only runs for an
        // unexpected stop (e.g. an incoming call interrupted the
        // recording). Save the take when it finished cleanly.
        guard recordingBlockID != nil else { return }
        let url = recorder.url
        stopTimer()
        recordingElapsed = 0
        recordingBlockID = nil
        self.recorder = nil
        if flag, let data = try? Data(contentsOf: url) {
            recordingFinish?(data)
        }
        recordingFinish = nil
        try? FileManager.default.removeItem(at: url)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Only clear the state for the player that is actually
        // playing — a stale callback from a replaced player must not
        // kill the new playback.
        guard player === self.player else { return }
        stopPlayback()
    }

    // MARK: - Timer

    /// A 0.25s timer that mirrors the recorder/player's currentTime
    /// into the published elapsed values, so the UI counts up.
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let recorder = self.recorder, recorder.isRecording {
                self.recordingElapsed = recorder.currentTime
            } else if let player = self.player, player.isPlaying {
                self.playingElapsed = player.currentTime
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Helpers

    /// The duration of recorded audio, or 0 when there is none or
    /// it cannot be decoded. Used to show the length on the block
    /// without storing a duration in the model.
    static func duration(of data: Data?) -> TimeInterval {
        guard let data, let player = try? AVAudioPlayer(data: data) else { return 0 }
        return player.duration
    }

    /// "0:07", "1:23" — the length shown on the block.
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

// MARK: - Audio Block View

/// The voice-note block: a compact row with four states.
/// (a) Empty — a record button + "Tap to record". (b) Recording —
/// a red stop button + live elapsed time. (c) Recorded — play/pause
/// + duration + a Re-record button that clears the take. (d) Mic
/// unavailable — a message (denied permission, or recording could
/// not start) instead of a dead button.
struct AudioBlockView: View {
    @Binding var block: Block
    @ObservedObject var coordinator: AudioBlockCoordinator
    var accentColor: Color
    /// Called with the finished AAC data when a recording stops.
    /// The caller (PageView) writes it into the block by id, so a
    /// block deleted mid-recording is a no-op instead of a crash
    /// through a stale binding.
    var onRecordingFinished: (Data) -> Void

    /// The recorded take's length, computed from the audio data when
    /// the view appears (and whenever the data changes) — the model
    /// stores no duration field.
    @State private var duration: TimeInterval = 0

    var body: some View {
        HStack(spacing: 12) {
            if coordinator.recordingBlockID == block.id {
                // (b) Recording
                Button {
                    coordinator.stopRecording()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.red)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Text("Recording…")
                            .font(.subheadline).bold()
                    }
                    Text(AudioBlockCoordinator.formatDuration(coordinator.recordingElapsed))
                        .font(.subheadline)
                        .foregroundStyle(Color.appMutedText)
                        .monospacedDigit()
                }
                Spacer()
            } else if let data = block.audioData {
                // (c) Recorded
                Button {
                    coordinator.togglePlayback(blockID: block.id, data: data)
                } label: {
                    Image(systemName: coordinator.playingBlockID == block.id ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(accentColor)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voice note")
                        .font(.subheadline).bold()
                    Text(coordinator.playingBlockID == block.id
                         ? "\(AudioBlockCoordinator.formatDuration(coordinator.playingElapsed)) / \(AudioBlockCoordinator.formatDuration(duration))"
                         : AudioBlockCoordinator.formatDuration(duration))
                        .font(.subheadline)
                        .foregroundStyle(Color.appMutedText)
                        .monospacedDigit()
                }
                Spacer()
                Button("Re-record") {
                    // Stop playback first so the old take does not
                    // keep playing with no UI; then clear the take
                    // and fall back to the empty state.
                    if coordinator.playingBlockID == block.id { coordinator.stopPlayback() }
                    block.audioData = nil
                    duration = 0
                }
                .font(.caption)
                .buttonStyle(.bordered)
            } else if coordinator.permissionDenied {
                // (d) Microphone access denied
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "mic.slash")
                            .foregroundStyle(Color.appMutedText)
                        Text("Microphone access is off")
                            .font(.subheadline).bold()
                    }
                    Text("Allow microphone access in Settings to record voice notes.")
                        .font(.caption)
                        .foregroundStyle(Color.appMutedText)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            } else if coordinator.recordingFailed {
                // (d) Recording could not start (no mic, or the
                // NSMicrophoneUsageDescription key is missing — see
                // the file header). A simulator limitation, not a
                // permission problem: try it on a real device.
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "mic.slash")
                            .foregroundStyle(Color.appMutedText)
                        Text("Couldn't start recording")
                            .font(.subheadline).bold()
                    }
                    Text("Recording may not work on the simulator — try it on a real device. If it fails there too, check the NSMicrophoneUsageDescription key in the app target's Info tab.")
                        .font(.caption)
                        .foregroundStyle(Color.appMutedText)
                }
                .padding(.vertical, 4)
            } else {
                // (a) Empty — ready to record
                Button {
                    coordinator.startRecording(blockID: block.id, onFinish: onRecordingFinished)
                } label: {
                    Image(systemName: "mic")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(accentColor)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                Text("Tap to record a voice note")
                    .font(.subheadline)
                    .foregroundStyle(Color.appMutedText)
                Spacer()
            }
        }
        .padding(12)
        .background(Color.appCardBackground)
        .cornerRadius(12)
        .onAppear { refreshDuration() }
        .onChange(of: block.audioData) { _, newData in
            duration = AudioBlockCoordinator.duration(of: newData)
        }
    }

    private func refreshDuration() {
        duration = AudioBlockCoordinator.duration(of: block.audioData)
    }
}
