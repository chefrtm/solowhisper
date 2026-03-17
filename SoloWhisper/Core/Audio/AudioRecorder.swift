import AVFoundation
import Foundation
import os.lock

enum AudioRecorderError: LocalizedError {
    case permissionDenied
    case engineStartFailed
    case noAudioData

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access denied. Please enable in System Settings."
        case .engineStartFailed:
            return "Failed to start audio engine."
        case .noAudioData:
            return "No audio data recorded."
        }
    }
}

@MainActor
final class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var isRecording = false

    private let sampleRate: Double = 16000
    private let channels: AVAudioChannelCount = 1

    // Thread-safe audio buffer — accessed from audio tap thread and main thread
    private let audioBuffer = AudioBuffer()

    func startRecording() throws {
        guard !isRecording else { return }

        let permission = AVCaptureDevice.authorizationStatus(for: .audio)
        guard permission == .authorized else {
            if permission == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in }
            }
            throw AudioRecorderError.permissionDenied
        }

        audioBuffer.reset()
        audioEngine = AVAudioEngine()

        guard let audioEngine = audioEngine else {
            throw AudioRecorderError.engineStartFailed
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )!

        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        let targetRate = sampleRate

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [audioBuffer] buffer, _ in
            AudioRecorder.processAudioBuffer(
                buffer,
                converter: converter,
                outputFormat: outputFormat,
                targetRate: targetRate,
                into: audioBuffer
            )
        }

        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            audioEngine.stop()
            inputNode.removeTap(onBus: 0)
            throw AudioRecorderError.engineStartFailed
        }
    }

    func stopRecording() async throws -> Data {
        guard isRecording, let audioEngine = audioEngine else {
            throw AudioRecorderError.noAudioData
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false

        let pcmData = audioBuffer.getData()
        let wavData = createWAVFile(from: pcmData)
        self.audioEngine = nil

        return wavData
    }

    // Static method — no self capture, safe to call from audio thread
    private static func processAudioBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter?,
        outputFormat: AVAudioFormat,
        targetRate: Double,
        into audioBuffer: AudioBuffer
    ) {
        guard let converter = converter else { return }

        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * targetRate / buffer.format.sampleRate
        )

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: frameCapacity
        ) else { return }

        var error: NSError?
        let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        if status == .haveData {
            audioBuffer.appendFloat(convertedBuffer)
        }
    }

    private func createWAVFile(from pcmData: Data) -> Data {
        var wavData = Data()

        let sampleRateInt = UInt32(sampleRate)
        let bitsPerSample: UInt16 = 16
        let numChannels: UInt16 = UInt16(channels)
        let byteRate = sampleRateInt * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)

        // Convert float32 to int16
        var int16Data = Data()
        pcmData.withUnsafeBytes { (floatPtr: UnsafeRawBufferPointer) in
            let floatBuffer = floatPtr.bindMemory(to: Float.self)
            for i in 0..<floatBuffer.count {
                let clampedValue = max(-1.0, min(1.0, floatBuffer[i]))
                var int16Value = Int16(clampedValue * 32767)
                int16Data.append(Data(bytes: &int16Value, count: 2))
            }
        }

        let dataSize = UInt32(int16Data.count)
        let fileSize = dataSize + 36

        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        wavData.append("WAVE".data(using: .ascii)!)

        // fmt chunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: sampleRateInt.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })

        // data chunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        wavData.append(int16Data)

        return wavData
    }
}

// Thread-safe audio data accumulator
private final class AudioBuffer: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Data())

    func reset() {
        lock.withLock { $0 = Data() }
    }

    func appendFloat(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)

        // Build data chunk outside the lock
        var chunk = Data(capacity: frameLength * 4)
        for i in 0..<frameLength {
            var sample = channelData[i]
            chunk.append(Data(bytes: &sample, count: 4))
        }

        lock.withLock { $0.append(chunk) }
    }

    func getData() -> Data {
        lock.withLock { $0 }
    }
}
