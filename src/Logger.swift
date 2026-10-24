import Foundation

func LogDebug(_ message: String) {
    let text = "[\(Date())] \(message)\n"
    if let data = text.data(using: .utf8) {
        if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/lattice.log")) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: URL(fileURLWithPath: "/tmp/lattice.log"))
        }
    }
}
