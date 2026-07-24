import Foundation

public extension OLAdjustments {

    /// Approximates decoded legacy Aperture edit operations as OpenLens
    /// adjustment parameters, so old edits can be reproduced and re-edited
    /// with our Core Image pipeline (rendered from the master).
    ///
    /// Mappings (from observed real data):
    /// - Exposure: `inputEV` maps directly (EV is EV).
    /// - White balance: Aperture stores Kelvin; our renderer's temperature
    ///   slider maps t → target 6500 − 30·t, so t = (6500 − K) / 30.
    ///   `inputTint` maps directly (both are CITemperatureAndTint y-offsets).
    /// - Enhance: Aperture contrast is −1…1 around 0 → ours is 0.5…1.5
    ///   around 1; saturation maps directly.
    /// - Highlights & Shadows: Aperture amounts are 0…100 → ours are 0…1.
    /// - Crop/straighten/retouch have no OLAdjustments equivalent (geometry
    ///   and brushes) and are skipped.
    init(approximating operations: [ApertureEditOperation]) {
        self.init()
        for op in operations where op.enabled {
            let p = op.parameters
            switch op.identifier {
            case "RKExposureOperation":
                if let ev = p["inputEV"] {
                    exposure = min(2, max(-2, ev))
                }
            case "RKWhiteBalanceOperation":
                if let kelvin = p["inputTemperature"] {
                    temperature = min(100, max(-100, (6500 - kelvin) / 30))
                }
                if let t = p["inputTint"] {
                    tint = min(100, max(-100, t))
                }
            case "RKEnhanceOperation":
                if let c = p["inputContrast"] {
                    contrast = min(1.5, max(0.5, 1 + c * 0.5))
                }
                if let s = p["inputSaturation"] {
                    saturation = min(2, max(0, s))
                }
            case "RKShadowHighlightOperation":
                if let s = p["inputShadowAmount"] {
                    shadows = min(1, max(0, s / 100))
                }
                if let h = p["inputHighlightAmount"] {
                    highlights = min(1, max(0, h / 100))
                }
            default:
                break   // crop/straighten/retouch/etc. — not representable yet
            }
        }
    }
}
