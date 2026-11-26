import Foundation

/// Exact C-ABI layout matching QuartzCore's `CAColorMatrix` (20 contiguous 32-bit floats).
@frozen
public struct PointerColorMatrix: Equatable, Sendable {
    public var m11, m12, m13, m14, m15: Float
    public var m21, m22, m23, m24, m25: Float
    public var m31, m32, m33, m34, m35: Float
    public var m41, m42, m43, m44, m45: Float

    public init(
        _ m11: Float, _ m12: Float, _ m13: Float, _ m14: Float, _ m15: Float,
        _ m21: Float, _ m22: Float, _ m23: Float, _ m24: Float, _ m25: Float,
        _ m31: Float, _ m32: Float, _ m33: Float, _ m34: Float, _ m35: Float,
        _ m41: Float, _ m42: Float, _ m43: Float, _ m44: Float, _ m45: Float
    ) {
        self.m11 = m11; self.m12 = m12; self.m13 = m13; self.m14 = m14; self.m15 = m15
        self.m21 = m21; self.m22 = m22; self.m23 = m23; self.m24 = m24; self.m25 = m25
        self.m31 = m31; self.m32 = m32; self.m33 = m33; self.m34 = m34; self.m35 = m35
        self.m41 = m41; self.m42 = m42; self.m43 = m43; self.m44 = m44; self.m45 = m45
    }

    // MARK: - Classic iPadOS (_PSPointerVibrantColorMatrixForLuminance)

    /// Dark pointer tint matrix used over light backgrounds (`luminance == 1`, standard contrast).
    public static let classicLightBackground = PointerColorMatrix(
        0.31545, -0.264347, -0.051103, 0.0, 0.21,
        -0.134489, 0.185863, -0.051375, 0.0, 0.21,
        -0.134761, -0.263939, 0.3987, 0.0, 0.21,
        -0.16744, -0.32872, -0.06384, 1.0, 0.0
    )

    /// Dark pointer tint matrix used over light backgrounds (`luminance == 1`, increased contrast).
    public static let classicLightBackgroundHighContrast = PointerColorMatrix(
        0.10515, -0.088116, -0.017034, 0.0, 0.225,
        -0.04483, 0.061954, -0.017125, 0.0, 0.225,
        -0.04492, -0.08798, 0.1329, 0.0, 0.225,
        -0.0598, -0.1174, -0.0228, 1.0, 0.0
    )

    /// Light pointer tint matrix used over dark backgrounds (`luminance == 2`, standard contrast).
    public static let classicDarkBackground = PointerColorMatrix(
        0.033315, -0.140779, -0.027285, 0.0, 0.879425,
        -0.071671, -0.03573, -0.027349, 0.0, 0.879425,
        -0.071734, -0.140684, 0.077669, 0.0, 0.879425,
        0.207956, 0.231532, 0.045012, 1.0, -0.50335
    )

    /// Light pointer tint matrix used over dark backgrounds (`luminance == 2`, increased contrast).
    public static let classicDarkBackgroundHighContrast = PointerColorMatrix(
        0.05785, -0.16134, -0.03126, 0.0, 0.879425,
        -0.082131, -0.021274, -0.031345, 0.0, 0.879425,
        -0.082216, -0.161213, 0.108678, 0.0, 0.879425,
        0.11362, 0.22306, 0.04332, 1.0, -0.38
    )

    // MARK: - iPadOS 26/27 Liquid Glass (_PSPointerVibrantColorMatrixForLuminanceWithPlasmaEnabled)

    /// Glass matrix over light backgrounds (`luminance == 1`, standard contrast).
    public static let plasmaLightBackground = PointerColorMatrix(
        0.15, 0.1, 0.1, 0.0, 0.05,
        0.1, 0.15, 0.1, 0.0, 0.05,
        0.1, 0.1, 0.15, 0.0, 0.05,
        -0.025, -0.025, -0.025, 1.0, 0.0
    )

    /// Glass matrix over light backgrounds (`luminance == 1`, increased contrast).
    public static let plasmaLightBackgroundHighContrast = PointerColorMatrix(
        0.15, 0.05, 0.05, 0.0, 0.0,
        0.05, 0.15, 0.05, 0.0, 0.0,
        0.05, 0.07, 0.15, 0.0, 0.0,
        0.12, 0.12, 0.12, 1.0, 0.0
    )

    /// Glass matrix over dark backgrounds (`luminance == 2`, standard contrast).
    public static let plasmaDarkBackground = PointerColorMatrix(
        0.03331, -0.14078, -0.02729, 0.0, 0.95,
        -0.07167, -0.03573, -0.02735, 0.0, 0.95,
        -0.07173, -0.14068, 0.07767, 0.0, 0.95,
        0.20796, 0.23153, 0.04501, 1.0, -0.40335
    )

    /// Glass matrix over dark backgrounds (`luminance == 2`, increased contrast).
    public static let plasmaDarkBackgroundHighContrast = PointerColorMatrix(
        0.03331, -0.14078, -0.02729, 0.0, 1.05,
        -0.07167, -0.03573, -0.02735, 0.0, 1.05,
        -0.07173, -0.14068, 0.07767, 0.0, 1.05,
        0.20796, 0.23153, 0.04501, 1.0, -0.40335
    )

    // MARK: - Content Overlay (_PSContentOverlayVibrantColorMatrixForLuminance)

    /// Content overlay matrix over light backgrounds (`luminance != 2`).
    public static let contentOverlayLightBackground = PointerColorMatrix(
        0.8402, -0.117794, -0.022406, 0.0, 0.05,
        -0.059678, 0.782627, -0.022949, 0.0, 0.05,
        -0.060221, -0.116979, 0.8772, 0.0, 0.05,
        -0.19435, -0.38155, -0.0741, 1.0, 0.0
    )

    /// Content overlay matrix over dark backgrounds (`luminance == 2`).
    public static let contentOverlayDarkBackground = PointerColorMatrix(
        0.9304, -0.23526, -0.04514, 0.0, 0.275,
        -0.119457, 0.815232, -0.045774, 0.0, 0.275,
        -0.120091, -0.234309, 1.0044, 0.0, 0.275,
        0.1794, 0.3522, 0.0684, 1.0, -0.6
    )

    public static func resolve(preset: MaterialPreset, isDarkBackground: Bool, highContrast: Bool) -> PointerColorMatrix {
        switch (preset, isDarkBackground, highContrast) {
        case (.classicIPadOS, false, false): return .classicLightBackground
        case (.classicIPadOS, false, true): return .classicLightBackgroundHighContrast
        case (.classicIPadOS, true, false): return .classicDarkBackground
        case (.classicIPadOS, true, true): return .classicDarkBackgroundHighContrast
        case (.liquidGlass, false, false): return .plasmaLightBackground
        case (.liquidGlass, false, true): return .plasmaLightBackgroundHighContrast
        case (.liquidGlass, true, false): return .plasmaDarkBackground
        case (.liquidGlass, true, true): return .plasmaDarkBackgroundHighContrast
        }
    }

    public static func lerp(_ a: PointerColorMatrix, _ b: PointerColorMatrix, t: Float) -> PointerColorMatrix {
        let clamped = max(0.0, min(1.0, t))
        func mix(_ x: Float, _ y: Float) -> Float { x + (y - x) * clamped }
        return PointerColorMatrix(
            mix(a.m11, b.m11), mix(a.m12, b.m12), mix(a.m13, b.m13), mix(a.m14, b.m14), mix(a.m15, b.m15),
            mix(a.m21, b.m21), mix(a.m22, b.m22), mix(a.m23, b.m23), mix(a.m24, b.m24), mix(a.m25, b.m25),
            mix(a.m31, b.m31), mix(a.m32, b.m32), mix(a.m33, b.m33), mix(a.m34, b.m34), mix(a.m35, b.m35),
            mix(a.m41, b.m41), mix(a.m42, b.m42), mix(a.m43, b.m43), mix(a.m44, b.m44), mix(a.m45, b.m45)
        )
    }

    /// Tactile Apple-style contrast & density shift while the pointer button is pressed and held.
    public func applyingPressedContrast(isDarkBackground: Bool, isSnapped: Bool, amount: Float) -> PointerColorMatrix {
        let p = max(0.0, min(1.0, amount))
        guard p > 0.001 else { return self }
        let rgbShift: Float
        let alphaShift: Float
        if isSnapped {
            rgbShift = (isDarkBackground ? 0.065 : -0.045) * p
            alphaShift = (isDarkBackground ? 0.12 : 0.10) * p
        } else {
            rgbShift = (isDarkBackground ? 0.075 : -0.055) * p
            alphaShift = 0.12 * p
        }
        return PointerColorMatrix(
            m11, m12, m13, m14, m15 + rgbShift,
            m21, m22, m23, m24, m25 + rgbShift,
            m31, m32, m33, m34, m35 + rgbShift,
            m41, m42, m43, m44, m45 + alphaShift
        )
    }

    public func asNSValue() -> NSValue {
        var copy = self
        return NSValue(bytes: &copy, objCType: "{CAColorMatrix=ffffffffffffffffffff}")
    }
}
