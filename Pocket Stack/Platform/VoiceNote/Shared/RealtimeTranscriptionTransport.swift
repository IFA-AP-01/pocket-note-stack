import Foundation

protocol RealtimeTranscriptionTransport: Sendable {
    func sendAudio(_ data: Data) async
    func finishAudioAndWaitForFinal() async
    func close() async
}
