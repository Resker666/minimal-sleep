import AVFoundation
import AudioToolbox
import Foundation

enum MicrophoneCaptureError: LocalizedError {
    case alreadyRunning
    case invalidInputFormat
    case converterUnavailable
    case conversionProducedNoAudio
    case bufferOverflow

    var errorDescription: String? {
        switch self {
        case .alreadyRunning: return "麦克风已在采集"
        case .invalidInputFormat: return "麦克风输入格式不可用"
        case .converterUnavailable: return "无法转换麦克风音频格式"
        case .conversionProducedNoAudio: return "麦克风音频转换失败"
        case .bufferOverflow: return "录音处理跟不上麦克风输入，夜间记录已停止"
        }
    }
}

@MainActor
final class AVAudioApplicationMicrophonePermission: MicrophonePermissionProviding {
    func status() -> MicrophonePermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .notDetermined
        }
    }

    func request() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

@MainActor
final class AVAudioEngineMicrophoneCaptureEngine: MicrophoneCapturing {
    private let engine = AVAudioEngine()
    private let conversionQueue = DispatchQueue(label: "MinimalSleep.microphone-conversion", qos: .userInitiated)
    private var conversionState: ConversionState?
    private var running = false

    func makeFrames() throws -> AsyncThrowingStream<[Int16], Error> {
        guard !running else { throw MicrophoneCaptureError.alreadyRunning }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw MicrophoneCaptureError.invalidInputFormat
        }
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw MicrophoneCaptureError.converterUnavailable
        }

        var streamContinuation: AsyncThrowingStream<[Int16], Error>.Continuation!
        let stream = AsyncThrowingStream<[Int16], Error>(bufferingPolicy: .bufferingNewest(64)) {
            streamContinuation = $0
        }
        let state = ConversionState(
            converter: converter,
            outputFormat: outputFormat,
            continuation: streamContinuation
        )
        conversionState = state

        input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [conversionQueue] buffer, _ in
            guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
                conversionQueue.async { state.fail(MicrophoneCaptureError.invalidInputFormat) }
                return
            }
            copy.frameLength = buffer.frameLength
            let sourceBuffers = UnsafeMutableAudioBufferListPointer(
                UnsafeMutablePointer(mutating: buffer.audioBufferList)
            )
            let targetBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
            guard sourceBuffers.count == targetBuffers.count else {
                conversionQueue.async { state.fail(MicrophoneCaptureError.invalidInputFormat) }
                return
            }
            for index in sourceBuffers.indices {
                let source = sourceBuffers[index]
                let target = targetBuffers[index]
                guard let sourceData = source.mData, let targetData = target.mData else {
                    conversionQueue.async { state.fail(MicrophoneCaptureError.invalidInputFormat) }
                    return
                }
                memcpy(targetData, sourceData, Int(source.mDataByteSize))
                targetBuffers[index].mDataByteSize = source.mDataByteSize
            }
            conversionQueue.async { state.consume(copy) }
        }

        do {
            engine.prepare()
            try engine.start()
            running = true
            return stream
        } catch {
            input.removeTap(onBus: 0)
            conversionState = nil
            conversionQueue.async { state.fail(error) }
            throw error
        }
    }

    func stop() {
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if let state = conversionState {
            conversionQueue.async { state.finish() }
        }
        conversionState = nil
    }
}

final class ConversionState: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let continuation: AsyncThrowingStream<[Int16], Error>.Continuation
    private var pendingSamples: [Int16] = []
    private var ended = false

    init(
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat,
        continuation: AsyncThrowingStream<[Int16], Error>.Continuation
    ) {
        self.converter = converter
        self.outputFormat = outputFormat
        self.continuation = continuation
    }

    func consume(_ input: AVAudioPCMBuffer) {
        guard !ended else { return }
        var supplied = false
        for _ in 0..<16 {
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4_096) else {
                fail(MicrophoneCaptureError.converterUnavailable)
                return
            }
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                guard !supplied else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                supplied = true
                inputStatus.pointee = .haveData
                return input
            }
            if let conversionError {
                fail(conversionError)
                return
            }
            appendOutput(output)
            if status != .haveData || output.frameLength == 0 { return }
        }
        fail(MicrophoneCaptureError.bufferOverflow)
    }

    func finish() {
        guard !ended else { return }
        for _ in 0..<16 {
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4_096) else {
                fail(MicrophoneCaptureError.converterUnavailable)
                return
            }
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                inputStatus.pointee = .endOfStream
                return nil
            }
            if let conversionError {
                fail(conversionError)
                return
            }
            appendOutput(output)
            if status != .haveData || output.frameLength == 0 { break }
        }
        guard !ended else { return }
        if !pendingSamples.isEmpty {
            emit(pendingSamples)
            pendingSamples.removeAll(keepingCapacity: false)
        }
        ended = true
        continuation.finish()
    }

    func fail(_ error: Error) {
        guard !ended else { return }
        ended = true
        continuation.finish(throwing: error)
    }

    private func emitFullFrames() {
        while pendingSamples.count >= 1_024, !ended {
            emit(Array(pendingSamples.prefix(1_024)))
            pendingSamples.removeFirst(1_024)
        }
    }

    private func appendOutput(_ output: AVAudioPCMBuffer) {
        guard output.frameLength > 0 else { return }
        guard let pointer = output.int16ChannelData?.pointee else {
            fail(MicrophoneCaptureError.conversionProducedNoAudio)
            return
        }
        pendingSamples.append(contentsOf: UnsafeBufferPointer(
            start: pointer, count: Int(output.frameLength)
        ))
        emitFullFrames()
    }

    private func emit(_ frame: [Int16]) {
        if case .dropped = continuation.yield(frame) {
            fail(MicrophoneCaptureError.bufferOverflow)
        }
    }
}
