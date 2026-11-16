import AVFoundation
import AudioToolbox
import Combine
import Foundation

enum ResampleError: Error {
    case unsupported
    case failed
}

enum AudioResampler {
    static func resample(source: URL, sampleRate: Double) throws -> URL {
        let input = try AVAudioFile(forReading: source)
        let sourceFormat = input.processingFormat
        guard sourceFormat.channelCount > 0 else { throw ResampleError.unsupported }
        let stored = input.fileFormat.settings
        let bitDepth = (stored[AVLinearPCMBitDepthKey] as? NSNumber)?.intValue ?? 16
        let isFloat = (stored[AVLinearPCMIsFloatKey] as? NSNumber)?.boolValue ?? false
        let common: AVAudioCommonFormat
        let writeDepth: Int
        if isFloat || bitDepth >= 32 {
            common = .pcmFormatFloat32
            writeDepth = 32
        } else if bitDepth > 16 {
            common = .pcmFormatInt32
            writeDepth = 32
        } else {
            common = .pcmFormatInt16
            writeDepth = 16
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: Int(sourceFormat.channelCount),
            AVLinearPCMBitDepthKey: writeDepth,
            AVLinearPCMIsFloatKey: common == .pcmFormatFloat32,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("voxera-\(UUID().uuidString).wav")
        let output = try AVAudioFile(forWriting: destination, settings: settings, commonFormat: common, interleaved: true)
        guard let converter = AVAudioConverter(from: sourceFormat, to: output.processingFormat) else {
            throw ResampleError.unsupported
        }
        let capacity: AVAudioFrameCount = 8192
        while true {
            guard let inBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: capacity) else {
                throw ResampleError.unsupported
            }
            try input.read(into: inBuffer)
            if inBuffer.frameLength == 0 { break }
            let ratio = sampleRate / sourceFormat.sampleRate
            let outCapacity = AVAudioFrameCount(Double(inBuffer.frameLength) * ratio) + 64
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: max(outCapacity, capacity)) else {
                throw ResampleError.unsupported
            }
            var consumed = false
            var error: NSError?
            let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
                if consumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return inBuffer
            }
            if status == .error { throw error ?? ResampleError.failed }
            if outBuffer.frameLength > 0 {
                try output.write(from: outBuffer)
            }
        }
        return destination
    }
}

final class PlayerModel: ObservableObject {
    @Published var currentURL: URL?
    @Published var isPlaying = false
    @Published var progress = 0.0
    @Published var duration = 1.0
    @Published var scrubbing = false

    private var player: AVPlayer?
    private var token: Any?

    func isCurrent(_ url: URL) -> Bool { currentURL == url }

    func toggle(url: URL) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        if currentURL == url, let player {
            if player.timeControlStatus == .playing {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }
            return
        }
        if let token, let player {
            player.removeTimeObserver(token)
        }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        currentURL = url
        progress = 0
        isPlaying = true
        player.play()
        self.token = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let total = item.duration.seconds
            if total.isFinite, total > 0 {
                self.duration = total
                if !self.scrubbing {
                    self.progress = min(max(time.seconds / total, 0), 1)
                }
            }
            self.isPlaying = player.timeControlStatus == .playing
        }
    }

    func seek(fraction: Double) {
        progress = min(max(fraction, 0), 1)
        guard let player, let item = player.currentItem else { return }
        let total = item.duration.seconds
        guard total.isFinite, total > 0 else { return }
        player.seek(to: CMTime(seconds: total * progress, preferredTimescale: 600))
    }
}
