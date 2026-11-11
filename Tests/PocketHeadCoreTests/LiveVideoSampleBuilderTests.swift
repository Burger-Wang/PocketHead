#if canImport(CoreMedia)
import CoreMedia
import VideoToolbox
import XCTest
@testable import PocketHeadCore

final class LiveVideoSampleBuilderTests: XCTestCase {
    private func pictures(_ name: String = "color-bars") throws -> [[[UInt8]]] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "hevc", subdirectory: "Fixtures"))
        let bytes = [UInt8](try Data(contentsOf: url))
        let starts = (0..<(bytes.count - 3)).filter {
            Array(bytes[$0..<($0 + 4)]) == [0, 0, 0, 1]
        }
        var result: [[[UInt8]]] = []
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1] : bytes.count
            let nal = Array(bytes[(start + 4)..<end])
            if (nal[0] >> 1) & 0x3f == 32 { result.append([]) }
            if !result.isEmpty { result[result.count - 1].append(nal) }
        }
        return result
    }

    func testParameterSetsAloneDoNotClaimAPicture() throws {
        let nals = try XCTUnwrap(pictures().first)
        var builder = LiveVideoSampleBuilder()
        for type: UInt8 in [32, 33, 34] {
            let nal = try XCTUnwrap(nals.first { ($0[0] >> 1) & 0x3f == type })
            XCTAssertNil(try builder.makePicture(nals: [nal]))
        }
        XCTAssertNotNil(builder.format)
    }

    func testHEVCFixtureBuildsDisplayableSamplesWithCorrectDimensions() throws {
        let units = try pictures()
        XCTAssertEqual(units.count, 12)
        var builder = LiveVideoSampleBuilder()
        var previousTime = CMTime.invalid
        for unit in units {
            let picture = try XCTUnwrap(builder.makePicture(nals: unit))
            XCTAssertEqual(picture.dimensions.width, 320)
            XCTAssertEqual(picture.dimensions.height, 180)
            XCTAssertTrue(picture.isRandomAccess)
            XCTAssertFalse(picture.formatChanged, "Identical parameter sets must not reset the decoder")
            XCTAssertTrue(CMSampleBufferDataIsReady(picture.sample))
            XCTAssertEqual(CMSampleBufferGetNumSamples(picture.sample), 1)
            let block = try XCTUnwrap(CMSampleBufferGetDataBuffer(picture.sample))
            XCTAssertEqual(CMBlockBufferGetDataLength(block), unit.reduce(0) { $0 + $1.count + 4 })
            let time = CMSampleBufferGetPresentationTimeStamp(picture.sample)
            if previousTime.isValid { XCTAssertGreaterThan(CMTimeCompare(time, previousTime), 0) }
            previousTime = time
        }
    }

    func testResetRequiresFreshParameterSets() throws {
        let unit = try XCTUnwrap(pictures().first)
        let slices = unit.filter { ($0[0] >> 1) & 0x3f < 32 }
        var builder = LiveVideoSampleBuilder()
        XCTAssertNotNil(try builder.makePicture(nals: unit))
        builder.reset()
        XCTAssertNil(try builder.makePicture(nals: slices))
        XCTAssertNotNil(try builder.makePicture(nals: unit))
    }

    func testNewRasterSignalsOneDecoderReset() throws {
        var builder = LiveVideoSampleBuilder()
        _ = try builder.makePicture(nals: XCTUnwrap(pictures().first))
        let small = try pictures("color-bars-small")
        let changed = try XCTUnwrap(builder.makePicture(nals: small[0]))
        XCTAssertEqual(changed.dimensions.width, 160)
        XCTAssertEqual(changed.dimensions.height, 90)
        XCTAssertTrue(changed.formatChanged)
        XCTAssertTrue(changed.requiresDecoderReset)
        XCTAssertFalse(try XCTUnwrap(builder.makePicture(nals: small[1])).formatChanged)
    }

    func testSeparateParameterUpdateIsRememberedUntilTheNextPicture() throws {
        var builder = LiveVideoSampleBuilder()
        _ = try builder.makePicture(nals: XCTUnwrap(pictures().first))
        let small = try XCTUnwrap(pictures("color-bars-small").first)
        let parameters = small.filter { (32...34).contains(Int(($0[0] >> 1) & 0x3f)) }
        let slices = small.filter { Int(($0[0] >> 1) & 0x3f) < 32 }
        XCTAssertNil(try builder.makePicture(nals: parameters))
        let changed = try XCTUnwrap(builder.makePicture(nals: slices))
        XCTAssertTrue(changed.formatChanged)
        XCTAssertEqual(changed.dimensions.width, 160)
    }

    func testMalformedAccessUnitCannotPoisonAcceptedParameterSets() throws {
        var builder = LiveVideoSampleBuilder()
        _ = try builder.makePicture(nals: XCTUnwrap(pictures().first))
        let small = try XCTUnwrap(pictures("color-bars-small").first)
        XCTAssertThrowsError(try builder.makePicture(nals: small + [[0x40]]))
        let recovered = try XCTUnwrap(builder.makePicture(nals: small))
        XCTAssertEqual(recovered.dimensions.width, 160)
        XCTAssertTrue(recovered.requiresDecoderReset)
    }

    func testBuiltHEVCSampleActuallyDecodes() throws {
        var builder = LiveVideoSampleBuilder()
        let picture = try XCTUnwrap(builder.makePicture(nals: XCTUnwrap(pictures().first)))
        let format = try XCTUnwrap(builder.format)
        var session: VTDecompressionSession?
        let creation = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault, formatDescription: format,
            decoderSpecification: nil, imageBufferAttributes: nil,
            outputCallback: nil, decompressionSessionOut: &session)
        XCTAssertEqual(creation, noErr)
        let decoder = try XCTUnwrap(session)
        defer { VTDecompressionSessionInvalidate(decoder) }
        let decoded = expectation(description: "The generated HEVC sample produces a real pixel buffer")
        let status = VTDecompressionSessionDecodeFrame(
            decoder, sampleBuffer: picture.sample, flags: [], infoFlagsOut: nil
        ) { status, _, image, _, _ in
            XCTAssertEqual(status, noErr)
            XCTAssertEqual(image.map(CVPixelBufferGetWidth), 320)
            XCTAssertEqual(image.map(CVPixelBufferGetHeight), 180)
            decoded.fulfill()
        }
        XCTAssertEqual(status, noErr)
        wait(for: [decoded], timeout: 5)
    }

    func testRejectsTruncatedNALAndOversizedInput() throws {
        var builder = LiveVideoSampleBuilder()
        XCTAssertThrowsError(try builder.makePicture(nals: [[0x40]])) {
            XCTAssertEqual($0 as? LiveVideoSampleBuilder.Failure, .malformedNAL)
        }
        XCTAssertThrowsError(try builder.makePicture(nals: [[0x40, 0]]))
        XCTAssertThrowsError(try builder.makePicture(nals: [Array(repeating: 1, count: 4 * 1024 * 1024)])) {
            XCTAssertEqual($0 as? LiveVideoSampleBuilder.Failure, .oversizedAccessUnit)
        }
    }
}
#endif
