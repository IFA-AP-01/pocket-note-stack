import Foundation
import AppKit

final class AttachmentManager {
    static let shared = AttachmentManager()
    
    private let fileManager = FileManager.default
    private lazy var attachmentsDirectory: URL = {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.pocketstack.app")
        let attachDir = appDir.appendingPathComponent("Attachments")
        
        if !fileManager.fileExists(atPath: attachDir.path) {
            try? fileManager.createDirectory(at: attachDir, withIntermediateDirectories: true)
        }
        
        return attachDir
    }()
    
    func saveImage(_ image: NSImage) -> String? {
        guard let tiffRepresentation = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        let filename = UUID().uuidString + ".png"
        let fileURL = attachmentsDirectory.appendingPathComponent(filename)
        
        do {
            try pngData.write(to: fileURL)
            return filename
        } catch {
            print("Failed to save image: \(error)")
            return nil
        }
    }
    
    func saveFile(from url: URL) -> String? {
        let filename = UUID().uuidString + "-" + url.lastPathComponent
        let destURL = attachmentsDirectory.appendingPathComponent(filename)
        do {
            try fileManager.copyItem(at: url, to: destURL)
            return filename
        } catch {
            print("Failed to copy file: \(error)")
            return nil
        }
    }
    
    func loadImage(named filename: String) -> NSImage? {
        guard let fileURL = attachmentURL(named: filename) else { return nil }
        return NSImage(contentsOf: fileURL)
    }

    func attachmentURL(named filename: String) -> URL? {
        guard !filename.isEmpty,
              filename == (filename as NSString).lastPathComponent else { return nil }
        let url = attachmentsDirectory.appendingPathComponent(filename).standardizedFileURL
        guard url.deletingLastPathComponent() == attachmentsDirectory.standardizedFileURL,
              fileManager.fileExists(atPath: url.path) else { return nil }
        return url
    }
}
