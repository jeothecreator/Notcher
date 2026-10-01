import Foundation

public struct MinerState: Codable, Equatable, Sendable {
    public var coins: Double = 0
    public var lifetime: Double = 0
    public var pickaxe = 1
    public var workers = 0
    public var speed = 0
    public var storage = 0
    public var hits = 0
    public var lastUpdate: Date

    public init(now: Date = Date()) {
        lastUpdate = now
    }
}

/// Idle mining. Workers keep digging while you are away (up to the storage cap).
public final class MinerEngine: EngineBase, GameEngine {
    public enum Upgrade: Int, CaseIterable, Sendable {
        case pickaxe, workers, speed, storage

        public var title: String {
            switch self {
            case .pickaxe: return "Pickaxe"
            case .workers: return "Workers"
            case .speed: return "Speed"
            case .storage: return "Storage"
            }
        }

        public var detail: String {
            switch self {
            case .pickaxe: return "More coins per hit"
            case .workers: return "Dig automatically"
            case .speed: return "Workers dig faster"
            case .storage: return "Longer offline mining"
            }
        }
    }

    public static let hitsPerGem = 12

    public private(set) var state: MinerState
    public private(set) var selected: Upgrade = .pickaxe
    /// Coins earned while away, shown once as a welcome-back banner.
    public private(set) var offlineEarnings: Double = 0
    /// 1 right after a manual hit, decays.
    public private(set) var swing = 0.0
    public struct Popup: Identifiable, Sendable {
        public let id: Int
        public let amount: Double
        public var age: Double
    }

    /// Floating "+12" labels.
    public private(set) var popups: [Popup] = []
    public private(set) var particles = ParticleField()
    /// Upgrade that was just bought, for a flash.
    public private(set) var lastPurchase: (upgrade: Upgrade, at: Double)?

    private let date: () -> Date
    private var rng = SeededRandom(seed: SeededRandom.randomSeed())
    private var popupID = 0
    private var autoTimer = 0.0
    private var persistTimer = 0.0

    /// Called whenever the state should be saved.
    public var onPersist: ((MinerState) -> Void)?

    public init(state: MinerState, date: @escaping () -> Date = { Date() }) {
        self.state = state
        self.date = date
        super.init(boardKey: GameID.miner.rawValue)
        phase = .playing
        offlineEarnings = catchUp(to: date())
    }

    // MARK: Economy

    public static func coinsPerHit(pickaxe: Int) -> Double {
        (5 * pow(1.35, Double(pickaxe - 1))).rounded()
    }

    public static func rate(for s: MinerState) -> Double {
        coinsPerHit(pickaxe: s.pickaxe) * Double(s.workers) * 0.5 * (1 + 0.25 * Double(s.speed))
    }

    /// Hours of passive mining kept while away.
    public static func storageHours(_ level: Int) -> Double {
        min(24, 1 + Double(level) * 1.5)
    }

    public static func cost(of upgrade: Upgrade, level: Int) -> Double {
        switch upgrade {
        case .pickaxe: return (25 * pow(1.55, Double(level - 1))).rounded()
        case .workers: return (40 * pow(1.6, Double(level))).rounded()
        case .speed: return (150 * pow(1.75, Double(level))).rounded()
        case .storage: return (400 * pow(2.2, Double(level))).rounded()
        }
    }

    public var coinsPerHit: Double { Self.coinsPerHit(pickaxe: state.pickaxe) }
    public var rate: Double { Self.rate(for: state) }

    public func level(of upgrade: Upgrade) -> Int {
        switch upgrade {
        case .pickaxe: return state.pickaxe
        case .workers: return state.workers
        case .speed: return state.speed
        case .storage: return state.storage
        }
    }

    public func cost(of upgrade: Upgrade) -> Double {
        Self.cost(of: upgrade, level: level(of: upgrade))
    }

    public func canAfford(_ upgrade: Upgrade) -> Bool {
        state.coins >= cost(of: upgrade)
    }

    /// Coins the state will hold at `date`, including passive mining. Pure.
    public static func projectedCoins(_ s: MinerState, at date: Date) -> Double {
        let elapsed = max(0, date.timeIntervalSince(s.lastUpdate))
        let capped = min(elapsed, storageHours(s.storage) * 3600)
        return s.coins + capped * rate(for: s)
    }

    /// Applies passive income since the last update. Returns coins gained.
    @discardableResult
    func catchUp(to now: Date) -> Double {
        let before = state.coins
        let after = Self.projectedCoins(state, at: now)
        state.coins = after
        state.lifetime += after - before
        state.lastUpdate = now
        return after - before
    }

    // MARK: Engine

    public func restart() {
        // Idle progress is never thrown away.
    }

    public override func pause() {}
    public override func resume() {}

    public func dismissOfflineBanner() {
        offlineEarnings = 0
    }

    public func tick(_ dt: Double, input: InputState) {
        advanceClock(dt)
        particles.update(dt, drag: 1.5)
        swing = max(0, swing - dt * 5)
        for i in popups.indices { popups[i].age += dt }
        popups.removeAll { $0.age > 1.1 }

        let gained = catchUp(to: date())
        if state.workers > 0 {
            autoTimer += dt
            let interval = 1 / max(0.2, 0.5 * Double(state.workers) * (1 + 0.25 * Double(state.speed)))
            if autoTimer >= max(0.25, interval) {
                autoTimer = 0
                addPopup(gained > 0 ? coinsPerHit : 0)
            }
        }

        persistTimer += dt
        if persistTimer > 5 {
            persistTimer = 0
            persist()
        }
        score = Int(state.coins)
    }

    private func addPopup(_ amount: Double) {
        guard amount > 0 else { return }
        popups.append(Popup(id: popupID, amount: amount, age: 0))
        popupID += 1
        if popups.count > 6 { popups.removeFirst() }
    }

    public func persist() {
        onPersist?(state)
        emit(.maximum("miner.lifetime", Int(state.lifetime)))
    }

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        if offlineEarnings > 0 && (key == .primary || key == .confirm) {
            offlineEarnings = 0
            return true
        }
        switch key {
        case .primary:
            mine()
        case .up:
            let all = Upgrade.allCases
            selected = all[(selected.rawValue + all.count - 1) % all.count]
            play(.tick)
        case .down:
            let all = Upgrade.allCases
            selected = all[(selected.rawValue + 1) % all.count]
            play(.tick)
        case .confirm:
            if !isRepeat { buy(selected) }
        case .number(let n):
            if let upgrade = Upgrade(rawValue: n - 1) {
                selected = upgrade
                buy(upgrade)
            }
        default:
            return false
        }
        return true
    }

    public func mine() {
        state.hits += 1
        var amount = coinsPerHit
        swing = 1
        let gem = state.hits % Self.hitsPerGem == 0
        if gem {
            amount *= 10
            play(.bonus)
            particles.burst(at: Vec2(150, 120), count: 22, speed: 60...200, life: 0.4...0.9, size: 2...4, tint: 1, gravity: 300, rng: &rng)
        } else {
            play(.hit)
            particles.burst(at: Vec2(150, 120), count: 6, speed: 40...140, life: 0.25...0.5, size: 1.5...3, tint: 0, gravity: 400, rng: &rng)
        }
        state.coins += amount
        state.lifetime += amount
        addPopup(amount)
        emit(.count("miner.hits", 1))
        emit(.maximum("miner.lifetime", Int(state.lifetime)))
    }

    public func select(_ upgrade: Upgrade) {
        selected = upgrade
    }

    @discardableResult
    public func buy(_ upgrade: Upgrade) -> Bool {
        let price = cost(of: upgrade)
        guard state.coins >= price else {
            play(.error)
            return false
        }
        state.coins -= price
        switch upgrade {
        case .pickaxe: state.pickaxe += 1
        case .workers: state.workers += 1
        case .speed: state.speed += 1
        case .storage: state.storage += 1
        }
        lastPurchase = (upgrade, clock)
        play(.buy)
        emit(.count("miner.upgrades", 1))
        emit(.maximum("miner.pickaxe", state.pickaxe))
        persist()
        return true
    }
}
