import Darwin
import Foundation

protocol PCM16WAVWriting: Sendable {
    func write(samples: [Int16], sampleRate: Int, temporaryURL: URL, finalURL: URL) throws
}

enum PCM16WAVWriterError: LocalizedError {
    case emptySamples
    case invalidSampleRate
    case fileAlreadyExists
    case fileTooLarge
    case differentDirectories

    var errorDescription: String? {
        switch self {
        case .emptySamples: return "声音片段为空"
        case .invalidSampleRate: return "采样率无效"
        case .fileAlreadyExists: return "录音文件已经存在"
        case .fileTooLarge: return "声音片段超过 WAV 格式上限"
        case .differentDirectories: return "临时文件和录音文件必须位于同一目录"
        }
    }
}

struct PCM16WAVWriter: PCM16WAVWriting {
    func write(samples: [Int16], sampleRate: Int, temporaryURL: URL, finalURL: URL) throws {
        guard !samples.isEmpty else { throw PCM16WAVWriterError.emptySamples }
        guard sampleRate > 0, sampleRate <= Int(UInt32.max / 2) else {
            throw PCM16WAVWriterError.invalidSampleRate
        }
        guard samples.count <= Int((UInt32.max - 36) / 2) else {
            throw PCM16WAVWriterError.fileTooLarge
        }
        guard temporaryURL.deletingLastPathComponent() == finalURL.deletingLastPathComponent() else {
            throw PCM16WAVWriterError.differentDirectories
        }

        let files = FileManager.default
        guard !files.fileExists(atPath: finalURL.path),
              !files.fileExists(atPath: temporaryURL.path) else {
            throw PCM16WAVWriterError.fileAlreadyExists
        }
        try files.createDirectory(at: finalURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let descriptor = Darwin.open(temporaryURL.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var published = false
        defer {
            try? handle.close()
            if !published { try? files.removeItem(at: temporaryURL) }
        }

        var data = Data()
        data.reserveCapacity(44 + samples.count * 2)
        let audioByteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        data.appendLittleEndian(36 + audioByteCount)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(sampleRate * 2))
        data.appendLittleEndian(UInt16(2))
        data.appendLittleEndian(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        data.appendLittleEndian(audioByteCount)
        for sample in samples {
            data.appendLittleEndian(UInt16(bitPattern: sample))
        }

        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        guard !files.fileExists(atPath: finalURL.path) else {
            throw PCM16WAVWriterError.fileAlreadyExists
        }
        try files.moveItem(at: temporaryURL, to: finalURL)
        published = true
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }
}
