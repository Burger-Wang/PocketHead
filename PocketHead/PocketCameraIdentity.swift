import OpenCineDJI

enum PocketCameraIdentity {
    static func supports(modelId: Int?, name: String) -> Bool {
        // An explicit manufacturer ID wins over a name that can be renamed.
        if let modelId { return modelId == 0x0022 }
        return CameraModel.resolve(modelId: nil, name: name).isPocket4Pro
    }

    static func directModel(ssid: String?) -> CameraModel? {
        guard let ssid, !ssid.isEmpty else { return nil }
        let model = CameraModel.resolve(modelId: nil, name: ssid)
        return model.isPocket4Pro ? model : nil
    }
}
