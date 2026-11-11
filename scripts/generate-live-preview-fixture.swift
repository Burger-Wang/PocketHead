// Generates synthetic HEVC test images with the macOS VideoToolbox encoder.
import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

final class Output {
    let lock = NSLock()
    var units: [(Int, Data)] = []
    var failures: [OSStatus] = []
    func receive(status: OSStatus, sample: CMSampleBuffer?) {
        lock.lock(); defer { lock.unlock() }
        guard status == noErr, let sample, let format = CMSampleBufferGetFormatDescription(sample),
              let block = CMSampleBufferGetDataBuffer(sample) else { failures.append(status); return }
        var unit = Data()
        for index in 0..<3 {
            var pointer: UnsafePointer<UInt8>?
            var size = 0
            let result = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format, parameterSetIndex: index,
                parameterSetPointerOut: &pointer, parameterSetSizeOut: &size,
                parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
            guard result == noErr, let pointer else { failures.append(result); return }
            unit.append(contentsOf: [0,0,0,1]); unit.append(pointer, count: size)
        }
        let count = CMBlockBufferGetDataLength(block)
        var bytes = [UInt8](repeating: 0, count: count)
        guard CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count, destination: &bytes) == noErr else { return }
        var offset = 0
        while offset + 4 <= bytes.count {
            let length = (0..<4).reduce(0) { ($0 << 8) | Int(bytes[offset+$1]) }
            offset += 4
            guard length > 0, offset + length <= bytes.count else { failures.append(-1); return }
            unit.append(contentsOf: [0,0,0,1]); unit.append(contentsOf: bytes[offset..<(offset+length)])
            offset += length
        }
        let index = Int(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)) * 25 + 0.5)
        units.append((index,unit))
    }
}
guard CommandLine.arguments.count >= 2 else {
    fatalError("Usage: swift generate-live-preview-fixture.swift <output.hevc> [width height]")
}
let width = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 320
let height = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3])! : 180
precondition(width > 0 && height > 0 && width <= 1920 && height <= 1080)
let output = Output()
var session: VTCompressionSession?
let create = VTCompressionSessionCreate(allocator: kCFAllocatorDefault, width: Int32(width), height: Int32(height),
    codecType: kCMVideoCodecType_HEVC, encoderSpecification: nil, imageBufferAttributes: nil,
    compressedDataAllocator: nil, outputCallback: { ref, _, status, _, sample in
        guard let ref else { return }
        Unmanaged<Output>.fromOpaque(ref).takeUnretainedValue().receive(status: status, sample: sample)
    }, refcon: Unmanaged.passUnretained(output).toOpaque(), compressionSessionOut: &session)
guard create == noErr, let session else { fatalError("Encoder unavailable: \(create)") }
VTSessionSetProperty(session,key:kVTCompressionPropertyKey_RealTime,value:kCFBooleanTrue)
VTSessionSetProperty(session,key:kVTCompressionPropertyKey_AllowFrameReordering,value:kCFBooleanFalse)
VTSessionSetProperty(session,key:kVTCompressionPropertyKey_MaxKeyFrameInterval,value:1 as CFNumber)
VTSessionSetProperty(session,key:kVTCompressionPropertyKey_AverageBitRate,value:400_000 as CFNumber)
VTCompressionSessionPrepareToEncodeFrames(session)
for frame in 0..<12 {
    var buffer: CVPixelBuffer?
    let attrs = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary
    CVPixelBufferCreate(kCFAllocatorDefault,width,height,kCVPixelFormatType_32BGRA,attrs,&buffer)
    guard let buffer else { fatalError("No image buffer") }
    CVPixelBufferLockBaseAddress(buffer, [])
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let bars: [(UInt8,UInt8,UInt8)] = [(230,230,230),(30,225,225),(225,225,30),(30,215,30),(210,40,210),(30,40,220),(220,40,30)]
    for y in 0..<height { for x in 0..<width {
        let bar = bars[min(6,x*7/width)]
        let p = base+y*stride+x*4
        let marker = y > height*7/10 && abs(x-(width/12+frame*width/15)) < max(2,width/30)
        p[0] = marker ? 255 : bar.0; p[1] = marker ? 255 : bar.1; p[2] = marker ? 255 : bar.2; p[3] = 255
    }}
    CVPixelBufferUnlockBaseAddress(buffer, [])
    let status = VTCompressionSessionEncodeFrame(session,imageBuffer:buffer,presentationTimeStamp:CMTime(value:Int64(frame),timescale:25),duration:CMTime(value:1,timescale:25),frameProperties:nil,sourceFrameRefcon:nil,infoFlagsOut:nil)
    guard status == noErr else { fatalError("Encode failed \(status)") }
}
VTCompressionSessionCompleteFrames(session,untilPresentationTimeStamp:.invalid)
VTCompressionSessionInvalidate(session)
guard output.failures.isEmpty, output.units.count == 12 else { fatalError("Bad output \(output.failures), frames \(output.units.count)") }
var data = Data()
for (_,unit) in output.units.sorted(by:{$0.0<$1.0}) { data.append(unit) }
let path = CommandLine.arguments[1]
try data.write(to:URL(fileURLWithPath:path))
print("Generated SIMULATED \(width)x\(height) HEVC color bars: \(output.units.count) independent pictures, \(data.count) bytes")
