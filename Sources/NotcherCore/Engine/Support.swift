import Foundation

/// SplitMix64: tiny, fast and seedable, so daily challenges are identical for
/// every player and engine tests are deterministic.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    public static func randomSeed() -> UInt64 {
        UInt64.random(in: 1...UInt64.max)
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform double in [0, 1).
    public mutating func unit() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    public mutating func double(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit()
    }

    public mutating func int(_ range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &self)
    }

    public mutating func chance(_ probability: Double) -> Bool {
        unit() < probability
    }
}

public struct Vec2: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
    public var length: Double { (x * x + y * y).squareRoot() }
}

/// Axis-aligned box in screen space (y grows downward).
public struct Box: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public var minX: Double { x }
    public var maxX: Double { x + w }
    public var minY: Double { y }
    public var maxY: Double { y + h }
    public var midX: Double { x + w / 2 }
    public var midY: Double { y + h / 2 }

    public func intersects(_ o: Box) -> Bool {
        minX < o.maxX && maxX > o.minX && minY < o.maxY && maxY > o.minY
    }

    public func insetBy(_ d: Double) -> Box {
        Box(x: x + d, y: y + d, w: max(0, w - 2 * d), h: max(0, h - 2 * d))
    }

    public func contains(_ p: Vec2) -> Bool {
        p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
    }

    /// Circle vs box overlap; returns the push-out normal when they overlap.
    public func circleHit(center c: Vec2, radius r: Double) -> Vec2? {
        let cx = min(max(c.x, minX), maxX)
        let cy = min(max(c.y, minY), maxY)
        let dx = c.x - cx
        let dy = c.y - cy
        guard dx * dx + dy * dy <= r * r else { return nil }
        if dx == 0 && dy == 0 {
            // Center inside the box: push out along the shallowest axis.
            let left = c.x - minX, right = maxX - c.x, top = c.y - minY, bottom = maxY - c.y
            let m = min(left, right, top, bottom)
            if m == left { return Vec2(-1, 0) }
            if m == right { return Vec2(1, 0) }
            if m == top { return Vec2(0, -1) }
            return Vec2(0, 1)
        }
        if abs(dx) > abs(dy) { return Vec2(dx > 0 ? 1 : -1, 0) }
        return Vec2(0, dy > 0 ? 1 : -1)
    }
}

/// Lightweight particle used by engines for sparks, dust and confetti.
/// Engines own particles so that effects stay in sync with the simulation.
public struct Particle: Sendable {
    public var position: Vec2
    public var velocity: Vec2
    public var life: Double
    public var maxLife: Double
    public var size: Double
    /// Interpreted by each game's renderer (usually a palette index).
    public var tint: Int
    public var gravity: Double

    public var progress: Double { 1 - max(0, life) / maxLife }
}

public struct ParticleField: Sendable {
    public private(set) var particles: [Particle] = []

    public init() {}

    public mutating func burst(
        at p: Vec2, count: Int, speed: ClosedRange<Double>, life: ClosedRange<Double>,
        size: ClosedRange<Double>, tint: Int, gravity: Double = 0,
        spread: ClosedRange<Double> = 0...(2 * .pi), rng: inout SeededRandom
    ) {
        for _ in 0..<count {
            let angle = rng.double(spread)
            let s = rng.double(speed)
            let l = rng.double(life)
            particles.append(Particle(
                position: p,
                velocity: Vec2(cos(angle) * s, sin(angle) * s),
                life: l, maxLife: l, size: rng.double(size), tint: tint, gravity: gravity
            ))
        }
        if particles.count > 400 { particles.removeFirst(particles.count - 400) }
    }

    public mutating func update(_ dt: Double, drag: Double = 0) {
        guard !particles.isEmpty else { return }
        for i in particles.indices {
            particles[i].life -= dt
            particles[i].velocity.y += particles[i].gravity * dt
            if drag > 0 {
                particles[i].velocity = particles[i].velocity * max(0, 1 - drag * dt)
            }
            particles[i].position = particles[i].position + particles[i].velocity * dt
        }
        particles.removeAll { $0.life <= 0 }
    }

    public mutating func removeAll() { particles.removeAll() }
}

@inline(__always) func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
    min(max(v, lo), hi)
}

@inline(__always) func approach(_ value: Double, _ target: Double, _ rate: Double, _ dt: Double) -> Double {
    value + (target - value) * min(1, rate * dt)
}
