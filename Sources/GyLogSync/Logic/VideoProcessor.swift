import Foundation
import AVFoundation

struct VideoFile: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let creationDate: Date
    let duration: TimeInterval
    
    // Calculated timestamps
    // Note: creationDate represents the START time of recording
    var startTime: TimeInterval { creationDate.timeIntervalSince1970 }
    var endTime: TimeInterval { startTime + duration }
}

class VideoProcessor {
    static func analyze(url: URL) async -> VideoFile? {
        let asset = AVURLAsset(url: url)
        
        do {
            let duration = try await asset.load(.duration).seconds
            
            // Try to get date from Metadata
            var creationDate: Date?
            var method = ""

            // 1. PRIORITY: Try asset.creationDate property (works for Sony cameras)
            if let assetCreationDate = try? await asset.load(.creationDate)?.dateValue {
                creationDate = assetCreationDate
                method = "asset.creationDate"
            }

            // 2. Fallback: Common Metadata (for other formats)
            if creationDate == nil {
                let commonMetadata = try await asset.load(.commonMetadata)
                for item in commonMetadata {
                     if item.commonKey == .commonKeyCreationDate {
                         if let dateValue = try? await item.load(.value) as? Date {
                             creationDate = dateValue
                             method = "commonKeyCreationDate (Date)"
                             break
                         }
                         if let dateString = try? await item.load(.value) as? String {
                             if let date = ISO8601DateFormatter().date(from: dateString) {
                                 creationDate = date
                                 method = "commonKeyCreationDate (String)"
                                 break
                             }
                         }
                     }
                }
            }

            // 3. Last Resort: File System Attributes
            if creationDate == nil {
                print("⚠️ Metadata date not found for \(url.lastPathComponent). Using file system date.")
                let resources = try url.resourceValues(forKeys: [.creationDateKey])
                creationDate = resources.creationDate
                method = "file system (FALLBACK)"
            }
            
            let finalDate = creationDate ?? Date()
            print("Video: \(url.lastPathComponent) -> Date: \(finalDate) [\(method)]")
            
            return VideoFile(url: url, name: url.lastPathComponent, creationDate: finalDate, duration: duration)
        } catch {
            print("Error processing video \(url.lastPathComponent): \(error)")
            // Fallback for non-video files or errors
            return nil
        }
    }
}
