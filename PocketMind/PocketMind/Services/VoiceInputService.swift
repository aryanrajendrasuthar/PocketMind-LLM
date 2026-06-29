//
// PocketMind — On-Device Private LLM for iPhone
// Copyright (c) 2026 Aryan Suthar. All Rights Reserved.
//
// PROPRIETARY AND CONFIDENTIAL
// Unauthorized copying, distribution, modification, or use of this file,
// via any medium, is strictly prohibited without the express written
// permission of the copyright owner.
//
// For licensing inquiries: aryanrajendrasuthar@gmail.com
//

import AVFoundation
import Foundation
import os.log
import Speech

/// On-device speech-to-text using Apple's Speech framework with local recognition.
///
/// Audio never leaves the device — `SFSpeechAudioBufferRecognitionRequest` is
/// configured with `requiresOnDeviceRecognition = true`.
@MainActor
final class VoiceInputService: ObservableObject {

    // MARK: - Published state

    @Published var isRecording = false
    @Published var transcript = ""
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var error: String?

    // MARK: - Private state

    private let recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private let audioEngine = AVAudioEngine()
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "VoiceInputService")

    // MARK: - Init

    init() {
        recognizer = SFSpeechRecognizer(locale: .current)
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }

    // MARK: - Public API

    /// Request microphone + speech recognition permissions.
    func requestPermissions() async {
        authorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Start recording and streaming transcript updates to `self.transcript`.
    func startRecording() {
        guard !isRecording else { return }
        guard authorizationStatus == .authorized else {
            error = "Speech recognition permission is required for voice input."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            error = "Speech recognition is not available on this device."
            return
        }

        transcript = ""
        error = nil

        do {
            try beginAudioSession()
            try startRecognition(recognizer: recognizer)
            isRecording = true
        } catch {
            self.error = error.localizedDescription
            stopRecording()
        }
    }

    /// Stop the current recording session and finalize the transcript.
    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.warning("Failed to deactivate audio session: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private helpers

    private func beginAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startRecognition(recognizer: SFSpeechRecognizer) throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device only — audio never sent to Apple's servers
        if #available(iOS 13, *) {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.transcript = result.bestTranscription.formattedString
                }
            }
            if let error {
                let nsError = error as NSError
                // Code 203 = recognition cancelled — not a real error
                guard nsError.code != 203 else { return }
                Task { @MainActor in
                    self.error = error.localizedDescription
                    self.stopRecording()
                }
            }
            if result?.isFinal == true {
                Task { @MainActor in self.stopRecording() }
            }
        }
    }
}
