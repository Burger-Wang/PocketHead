#if canImport(CoreMedia)
import CoreMedia
import Foundation

/// Own this value on one serial video queue. Input is a complete HEVC AU split
/// into raw NALs by the existing transport helpers, without Annex-B start codes.
public struct LiveVideoSampleBuilder {
    public enum Failure: Error, Equatable {
        case malformedNAL, oversizedAccessUnit
        case invalidFormat(Int32), invalidSample(Int32)
    }

    public struct Picture {
        public let sample: CMSampleBuffer
        public let isRandomAccess: Bool
        public let formatChanged: Bool
        public let requiresDecoderReset: Bool
        public let dimensions: CMVideoDimensions
    }

    public private(set) var format: CMVideoFormatDescription?
    private var vps: [UInt8]?
    private var sps: [UInt8]?
    private var pps: [UInt8]?
    private var frameIndex: Int64 = 0
    private var formatChanged = false
    private var requiresDecoderReset = false

    public init() {}

    public mutating func reset() { self = Self() }

    public mutating func makePicture(nals: [[UInt8]]) throws -> Picture? {
        guard !nals.isEmpty else { return nil }
        guard nals.reduce(0, { $0 + $1.count + 4 }) <= 4 * 1024 * 1024 else {
            throw Failure.oversizedAccessUnit
        }
        // Validate the whole AU before replacing any accepted parameter sets.
        guard nals.allSatisfy({ $0.count >= 2 && $0[0] & 0x80 == 0 && $0[1] & 7 != 0 }) else {
            throw Failure.malformedNAL
        }
        var changed = false
        var hasPicture = false
        var randomAccess = false
        for nal in nals {
            let type = Int((nal[0] >> 1) & 0x3f)
            switch type {
            case 32: if vps != nal { vps = nal; changed = true }
            case 33: if sps != nal { sps = nal; changed = true }
            case 34: if pps != nal { pps = nal; changed = true }
            case 0...31:
                hasPicture = true
                randomAccess = randomAccess || (16...21).contains(type)
            default: break
            }
        }
        if changed || format == nil {
            guard let vps, let sps, let pps else { return nil }
            var next: CMFormatDescription?
            let status = vps.withUnsafeBufferPointer { v in
                sps.withUnsafeBufferPointer { s in
                    pps.withUnsafeBufferPointer { p in
                        let pointers = [v.baseAddress!, s.baseAddress!, p.baseAddress!]
                        let sizes = [vps.count, sps.count, pps.count]
                        return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                            allocator: kCFAllocatorDefault, parameterSetCount: 3,
                            parameterSetPointers: pointers, parameterSetSizes: sizes,
                            nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &next)
                    }
                }
            }
            guard status == noErr, let next else {
                format = nil
                throw Failure.invalidFormat(status)
            }
            formatChanged = formatChanged || format != nil
            if let format {
                let old = CMVideoFormatDescriptionGetDimensions(format)
                let new = CMVideoFormatDescriptionGetDimensions(next)
                requiresDecoderReset = requiresDecoderReset || old.width != new.width || old.height != new.height
            }
            format = next
        }
        guard hasPicture, let format else { return nil }

        var payload = Data()
        for nal in nals {
            var length = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: &length) { payload.append(contentsOf: $0) }
            payload.append(contentsOf: nal)
        }
        var block: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: payload.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: payload.count, flags: 0, blockBufferOut: &block)
        guard blockStatus == noErr, let block else { throw Failure.invalidSample(blockStatus) }
        let copyStatus = payload.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: payload.count)
        }
        guard copyStatus == noErr else { throw Failure.invalidSample(copyStatus) }
        frameIndex += 1
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 60_000),
                                        presentationTimeStamp: CMTime(value: frameIndex, timescale: 60_000),
                                        decodeTimeStamp: .invalid)
        var size = payload.count
        var sample: CMSampleBuffer?
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        guard status == noErr, let sample else { throw Failure.invalidSample(status) }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            CFDictionarySetValue(dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                Unmanaged.passUnretained(randomAccess ? kCFBooleanFalse : kCFBooleanTrue).toOpaque())
        }
        let result = Picture(sample: sample, isRandomAccess: randomAccess,
                             formatChanged: formatChanged,
                             requiresDecoderReset: requiresDecoderReset,
                             dimensions: CMVideoFormatDescriptionGetDimensions(format))
        formatChanged = false
        requiresDecoderReset = false
        return result
    }
}
#endif
