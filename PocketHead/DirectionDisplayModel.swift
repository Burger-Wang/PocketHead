import Foundation

/// Display precision only. The tracking engine and native targets retain the
/// original sensor/pose precision and 40 ms control cadence.
@MainActor
final class DirectionDisplayModel: ObservableObject {
    struct Snapshot: Equatable {
        var head = LookAngles.zero
        var cameraLook: LookAngles?
        var cameraPose: GimbalPose?
    }

    @Published private(set) var snapshot = Snapshot()

    func update(head: LookAngles, cameraLook: LookAngles?, cameraPose: GimbalPose?) {
        func angle(_ value: Double) -> Double { (value * 10).rounded() / 10 }
        func look(_ value: LookAngles) -> LookAngles {
            LookAngles(rightDegrees: angle(value.rightDegrees), upDegrees: angle(value.upDegrees))
        }
        let next = Snapshot(head: look(head), cameraLook: cameraLook.map(look),
                            cameraPose: cameraPose.map {
            GimbalPose(panDegrees: angle($0.panDegrees), tiltDegrees: angle($0.tiltDegrees))
        })
        if next != snapshot { snapshot = next }
    }
}
