import Foundation

public struct SpringParameters: Equatable, Sendable {
    public var dampingRatio: Double
    public var response: Double

    public var angularFrequency: Double {
        (2.0 * .pi) / max(response, 1e-4)
    }

    public init(dampingRatio: Double, response: Double) {
        self.dampingRatio = max(0.01, dampingRatio)
        self.response = max(1e-4, response)
    }

    public init(mass: Double, stiffness: Double, damping: Double) {
        let m = max(mass, 1e-6)
        let k = max(stiffness, 1e-6)
        let omega = sqrt(k / m)
        self.response = (2.0 * .pi) / omega
        self.dampingRatio = max(0.01, damping / (2.0 * sqrt(k * m)))
    }

    public static func lerp(_ a: SpringParameters, _ b: SpringParameters, t: Double) -> SpringParameters {
        let u = max(0.0, min(1.0, t))
        return SpringParameters(
            dampingRatio: a.dampingRatio + (b.dampingRatio - a.dampingRatio) * u,
            response: a.response + (b.response - a.response) * u
        )
    }
}

/// Unconditionally stable analytical closed-form 1D damped harmonic oscillator.
public struct Spring1D: Equatable, Sendable {
    public var value: Double
    public var velocity: Double

    public init(value: Double, velocity: Double = 0.0) {
        self.value = value
        self.velocity = velocity
    }

    public mutating func reset(to value: Double, velocity: Double = 0.0) {
        self.value = value
        self.velocity = velocity
    }

    public mutating func step(to target: Double, dt rawDt: Double, parameters: SpringParameters) {
        guard rawDt > 0 else { return }
        let dt = min(rawDt, 0.05)

        let y0 = value - target
        let v0 = velocity
        let omega = parameters.angularFrequency
        let zeta = parameters.dampingRatio

        if abs(y0) < 1e-6 && abs(v0) < 1e-6 {
            value = target
            velocity = 0.0
            return
        }

        let y: Double
        let v: Double

        if abs(zeta - 1.0) < 1e-4 {
            // Critically damped
            let decay = exp(-omega * dt)
            let b = v0 + omega * y0
            y = decay * (y0 + b * dt)
            v = decay * (v0 - omega * b * dt)
        } else if zeta < 1.0 {
            // Underdamped
            let omegaD = omega * sqrt(1.0 - zeta * zeta)
            let decay = exp(-zeta * omega * dt)
            let sinTerm = sin(omegaD * dt)
            let cosTerm = cos(omegaD * dt)
            let a = y0
            let b = (v0 + zeta * omega * y0) / omegaD
            y = decay * (a * cosTerm + b * sinTerm)
            v = decay * (v0 * cosTerm - ((omega * omega * y0 + zeta * omega * v0) / omegaD) * sinTerm)
        } else {
            // Overdamped
            let gamma = omega * sqrt(zeta * zeta - 1.0)
            let r1 = -zeta * omega + gamma
            let r2 = -zeta * omega - gamma
            let c1 = (v0 - r2 * y0) / (2.0 * gamma)
            let c2 = y0 - c1
            let e1 = exp(r1 * dt)
            let e2 = exp(r2 * dt)
            y = c1 * e1 + c2 * e2
            v = c1 * r1 * e1 + c2 * r2 * e2
        }

        value = target + y
        velocity = v
    }
}
