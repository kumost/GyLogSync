// ProResTimingFixer.swift
// Copyright (C) 2026 Kumo, Inc.
// Licensed under the GNU General Public License v3.0
// https://github.com/kumost/GyLogSync

import Foundation

/// Fixes variable frame timing (stts atom) in ProRes RAW MOV files
/// recorded by the Blackmagic Camera app on iPhone.
///
/// IMPORTANT: The original file is NEVER modified. A copy is created
/// with "_fixed" suffix and the fix is applied to the copy only.
class ProResTimingFixer {

    struct FixResult {
        let filename: String
        let totalFrames: Int
        let anomalousFrames: Int
        let wasFixed: Bool
        let message: String
        /// URL of the fixed copy (nil if no fix was needed or on error)
        let fixedURL: URL?
    }

    /// Inspect the stts atom. If VFR is detected, create a fixed COPY.
    /// The original file is never modified.
    static func fixIfNeeded(url: URL) -> FixResult {
        let filename = url.lastPathComponent

        guard url.pathExtension.lowercased() == "mov" else {
            return FixResult(filename: filename, totalFrames: 0, anomalousFrames: 0,
                           wasFixed: false, message: "Not a MOV file", fixedURL: nil)
        }

        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return FixResult(filename: filename, totalFrames: 0, anomalousFrames: 0,
                           wasFixed: false, message: "File is not readable", fixedURL: nil)
        }

        do {
            // Open the ORIGINAL as read-only for analysis
            let readHandle = try FileHandle(forReadingFrom: url)
            defer { try? readHandle.close() }

            let fileSize = readHandle.seekToEndOfFile()
            guard fileSize >= 8 else {
                return FixResult(filename: filename, totalFrames: 0, anomalousFrames: 0,
                               wasFixed: false, message: "File too small", fixedURL: nil)
            }

            // 1. Find moov atom
            guard let (moovOffset, moovSize) = findMoovAtom(fileHandle: readHandle, fileSize: fileSize) else {
                return FixResult(filename: filename, totalFrames: 0, anomalousFrames: 0,
                               wasFixed: false, message: "No moov atom found", fixedURL: nil)
            }

            // 2. Find video track's stts using proper atom traversal
            guard let sttsOffset = findVideoStts(fileHandle: readHandle, moovOffset: moovOffset, moovSize: moovSize) else {
                return FixResult(filename: filename, totalFrames: 0, anomalousFrames: 0,
                               wasFixed: false, message: "No video stts found", fixedURL: nil)
            }

            // 3. Analyze stts
            guard let sttsInfo = analyzeStts(fileHandle: readHandle, sttsOffset: sttsOffset) else {
                return FixResult(filename: filename, totalFrames: 0, anomalousFrames: 0,
                               wasFixed: false, message: "Failed to parse stts", fixedURL: nil)
            }

            // 4. Check if fix is needed
            if sttsInfo.entryCount <= 1 {
                return FixResult(filename: filename, totalFrames: sttsInfo.totalSamples, anomalousFrames: 0,
                               wasFixed: false, message: "Already CFR", fixedURL: nil)
            }

            let anomalousFrames = sttsInfo.entries
                .filter { $0.delta != sttsInfo.dominantDelta }
                .reduce(0) { $0 + $1.count }

            if anomalousFrames == 0 {
                return FixResult(filename: filename, totalFrames: sttsInfo.totalSamples, anomalousFrames: 0,
                               wasFixed: false, message: "No anomalies", fixedURL: nil)
            }

            guard sttsInfo.totalSamples > 0, sttsInfo.totalSamples <= Int(UInt32.max) else {
                return FixResult(filename: filename, totalFrames: sttsInfo.totalSamples, anomalousFrames: anomalousFrames,
                               wasFixed: false, message: "Invalid sample count", fixedURL: nil)
            }

            // Close read handle before copying
            try? readHandle.close()

            // 5. Create a COPY — never touch the original
            let baseName = url.deletingPathExtension().lastPathComponent
            let fixedName = baseName + "_fixed.mov"
            let fixedURL = url.deletingLastPathComponent().appendingPathComponent(fixedName)

            // Remove old fixed copy if exists
            if FileManager.default.fileExists(atPath: fixedURL.path) {
                try FileManager.default.removeItem(at: fixedURL)
            }

            try FileManager.default.copyItem(at: url, to: fixedURL)

            // 6. Open the COPY for writing and apply fix
            let writeHandle = try FileHandle(forUpdating: fixedURL)
            defer { try? writeHandle.close() }

            writeHandle.seek(toFileOffset: UInt64(sttsOffset + 12)) // size(4) + 'stts'(4) + version+flags(4)

            let entryCount: UInt32 = 1
            let sampleCount: UInt32 = UInt32(sttsInfo.totalSamples)
            let sampleDelta: UInt32 = UInt32(sttsInfo.dominantDelta)

            var data = Data()
            data.append(contentsOf: withUnsafeBytes(of: entryCount.bigEndian) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: sampleCount.bigEndian) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: sampleDelta.bigEndian) { Array($0) })

            writeHandle.write(data)

            // Zero out remaining entry space
            let remainingBytes = (sttsInfo.entryCount - 1) * 8
            if remainingBytes > 0 {
                writeHandle.write(Data(count: remainingBytes))
            }

            // Flush to disk
            writeHandle.synchronizeFile()

            // Verify the copy is valid (not truncated)
            let fixedSize = writeHandle.seekToEndOfFile()
            guard fixedSize == fileSize else {
                // Something went wrong — delete the bad copy
                try? writeHandle.close()
                try? FileManager.default.removeItem(at: fixedURL)
                return FixResult(filename: filename, totalFrames: sttsInfo.totalSamples,
                               anomalousFrames: anomalousFrames, wasFixed: false,
                               message: "Fixed copy size mismatch — discarded", fixedURL: nil)
            }

            print("Fixed stts: \(filename) → \(fixedName) (\(anomalousFrames) frames corrected)")

            return FixResult(filename: filename, totalFrames: sttsInfo.totalSamples,
                           anomalousFrames: anomalousFrames, wasFixed: true,
                           message: "\(anomalousFrames) frames fixed", fixedURL: fixedURL)

        } catch {
            return FixResult(filename: filename, totalFrames: 0, anomalousFrames: 0,
                           wasFixed: false, message: "Error: \(error.localizedDescription)", fixedURL: nil)
        }
    }

    // MARK: - Private helpers

    private struct SttsEntry {
        let count: Int
        let delta: Int
    }

    private struct SttsInfo {
        let offset: Int
        let size: Int
        let entryCount: Int
        let entries: [SttsEntry]
        let totalSamples: Int
        let dominantDelta: Int
    }

    /// Find the moov atom by walking top-level atoms
    private static func findMoovAtom(fileHandle: FileHandle, fileSize: UInt64) -> (Int, Int)? {
        var pos: UInt64 = 0

        while pos + 8 <= fileSize {
            fileHandle.seek(toFileOffset: pos)
            let headerData = fileHandle.readData(ofLength: 8)
            guard headerData.count == 8 else { break }

            let size = UInt64(readUInt32BE(headerData, offset: 0))
            let atomType = String(data: headerData[4..<8], encoding: .ascii) ?? ""

            var actualSize = size
            if size == 1 {
                let extData = fileHandle.readData(ofLength: 8)
                guard extData.count == 8 else { break }
                actualSize = readUInt64BE(extData, offset: 0)
            }

            guard actualSize >= 8 else { break }

            if atomType == "moov" {
                return (Int(pos), Int(actualSize))
            }

            pos += actualSize
        }

        return nil
    }

    /// Walk the atom tree properly: moov > trak > mdia > hdlr/minf > stbl > stts
    private static func findVideoStts(fileHandle: FileHandle, moovOffset: Int, moovSize: Int) -> Int? {
        let moovBodyOffset = moovOffset + 8
        let moovBodySize = moovSize - 8

        fileHandle.seek(toFileOffset: UInt64(moovBodyOffset))
        let moovData = fileHandle.readData(ofLength: moovBodySize)

        // Walk trak atoms inside moov
        var pos = 0
        while pos + 8 <= moovData.count {
            let size = Int(readUInt32BE(moovData, offset: pos))
            guard size >= 8, pos + size <= moovData.count else { break }

            let atomType = readAtomType(moovData, offset: pos + 4)

            if atomType == "trak" {
                if let sttsFileOffset = findSttsInVideoTrak(moovData: moovData, trakOffset: pos, trakSize: size, moovBodyFileOffset: moovBodyOffset) {
                    return sttsFileOffset
                }
            }

            pos += size
        }

        return nil
    }

    /// Check if a trak is a video track by walking mdia > hdlr, then find stts in mdia > minf > stbl
    private static func findSttsInVideoTrak(moovData: Data, trakOffset: Int, trakSize: Int, moovBodyFileOffset: Int) -> Int? {
        let trakBodyStart = trakOffset + 8
        let trakBodyEnd = trakOffset + trakSize

        var pos = trakBodyStart
        while pos + 8 <= trakBodyEnd {
            let size = Int(readUInt32BE(moovData, offset: pos))
            guard size >= 8, pos + size <= trakBodyEnd else { break }

            let atomType = readAtomType(moovData, offset: pos + 4)

            if atomType == "mdia" {
                if let sttsOffset = findSttsInMdia(moovData: moovData, mdiaOffset: pos, mdiaSize: size, moovBodyFileOffset: moovBodyFileOffset) {
                    return sttsOffset
                }
            }

            pos += size
        }

        return nil
    }

    /// Inside mdia: find hdlr to verify video, then find minf > stbl > stts
    private static func findSttsInMdia(moovData: Data, mdiaOffset: Int, mdiaSize: Int, moovBodyFileOffset: Int) -> Int? {
        let mdiaBodyStart = mdiaOffset + 8
        let mdiaBodyEnd = mdiaOffset + mdiaSize

        var isVideoTrack = false
        var minfOffset = -1
        var minfSize = 0

        var pos = mdiaBodyStart
        while pos + 8 <= mdiaBodyEnd {
            let size = Int(readUInt32BE(moovData, offset: pos))
            guard size >= 8, pos + size <= mdiaBodyEnd else { break }

            let atomType = readAtomType(moovData, offset: pos + 4)

            if atomType == "hdlr" {
                let handlerTypeOffset = pos + 8 + 4 + 4
                if handlerTypeOffset + 4 <= pos + size {
                    let handlerType = readAtomType(moovData, offset: handlerTypeOffset)
                    isVideoTrack = (handlerType == "vide")
                }
            } else if atomType == "minf" {
                minfOffset = pos
                minfSize = size
            }

            pos += size
        }

        guard isVideoTrack, minfOffset >= 0 else { return nil }

        return findSttsInMinf(moovData: moovData, minfOffset: minfOffset, minfSize: minfSize, moovBodyFileOffset: moovBodyFileOffset)
    }

    /// Inside minf: find stbl > stts
    private static func findSttsInMinf(moovData: Data, minfOffset: Int, minfSize: Int, moovBodyFileOffset: Int) -> Int? {
        let minfBodyStart = minfOffset + 8
        let minfBodyEnd = minfOffset + minfSize

        var pos = minfBodyStart
        while pos + 8 <= minfBodyEnd {
            let size = Int(readUInt32BE(moovData, offset: pos))
            guard size >= 8, pos + size <= minfBodyEnd else { break }

            let atomType = readAtomType(moovData, offset: pos + 4)

            if atomType == "stbl" {
                let stblBodyStart = pos + 8
                let stblBodyEnd = pos + size

                var innerPos = stblBodyStart
                while innerPos + 8 <= stblBodyEnd {
                    let innerSize = Int(readUInt32BE(moovData, offset: innerPos))
                    guard innerSize >= 8, innerPos + innerSize <= stblBodyEnd else { break }

                    let innerType = readAtomType(moovData, offset: innerPos + 4)

                    if innerType == "stts" {
                        return moovBodyFileOffset + innerPos
                    }

                    innerPos += innerSize
                }
            }

            pos += size
        }

        return nil
    }

    private static func analyzeStts(fileHandle: FileHandle, sttsOffset: Int) -> SttsInfo? {
        fileHandle.seek(toFileOffset: UInt64(sttsOffset))
        let headerData = fileHandle.readData(ofLength: 8)
        guard headerData.count == 8 else { return nil }

        let size = Int(readUInt32BE(headerData, offset: 0))
        let atomType = readAtomType(headerData, offset: 4)
        guard atomType == "stts" else { return nil }

        let vfData = fileHandle.readData(ofLength: 4)
        guard vfData.count == 4 else { return nil }

        let ecData = fileHandle.readData(ofLength: 4)
        guard ecData.count == 4 else { return nil }
        let entryCount = Int(readUInt32BE(ecData, offset: 0))

        guard entryCount > 0, entryCount < 100000 else { return nil }

        var entries: [SttsEntry] = []
        for _ in 0..<entryCount {
            let entryData = fileHandle.readData(ofLength: 8)
            guard entryData.count == 8 else { break }
            let count = Int(readUInt32BE(entryData, offset: 0))
            let delta = Int(readUInt32BE(entryData, offset: 4))
            entries.append(SttsEntry(count: count, delta: delta))
        }

        let totalSamples = entries.reduce(0) { $0 + $1.count }

        var deltaCounts: [Int: Int] = [:]
        for entry in entries {
            deltaCounts[entry.delta, default: 0] += entry.count
        }
        let dominantDelta = deltaCounts.max(by: { $0.value < $1.value })?.key ?? entries.first?.delta ?? 0

        return SttsInfo(
            offset: sttsOffset,
            size: size,
            entryCount: entryCount,
            entries: entries,
            totalSamples: totalSamples,
            dominantDelta: dominantDelta
        )
    }

    // MARK: - Binary helpers

    private static func readUInt32BE(_ data: Data, offset: Int) -> UInt32 {
        let start = data.startIndex + offset
        return UInt32(data[start]) << 24 |
               UInt32(data[start+1]) << 16 |
               UInt32(data[start+2]) << 8 |
               UInt32(data[start+3])
    }

    private static func readUInt64BE(_ data: Data, offset: Int) -> UInt64 {
        let start = data.startIndex + offset
        return UInt64(data[start]) << 56 |
               UInt64(data[start+1]) << 48 |
               UInt64(data[start+2]) << 40 |
               UInt64(data[start+3]) << 32 |
               UInt64(data[start+4]) << 24 |
               UInt64(data[start+5]) << 16 |
               UInt64(data[start+6]) << 8 |
               UInt64(data[start+7])
    }

    private static func readAtomType(_ data: Data, offset: Int) -> String {
        let start = data.startIndex + offset
        guard start + 4 <= data.endIndex else { return "" }
        return String(data: data[start..<start+4], encoding: .ascii) ?? ""
    }
}
