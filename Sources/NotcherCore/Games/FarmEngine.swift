import Foundation

public enum Crop: Int, CaseIterable, Codable, Sendable {
    case wheat, carrot, tomato, pumpkin, starfruit

    public var title: String {
        switch self {
        case .wheat: return "Wheat"
        case .carrot: return "Carrot"
        case .tomato: return "Tomato"
        case .pumpkin: return "Pumpkin"
        case .starfruit: return "Starfruit"
        }
    }

    public var seedCost: Int {
        switch self {
        case .wheat: return 5
        case .carrot: return 20
        case .tomato: return 60
        case .pumpkin: return 150
        case .starfruit: return 500
        }
    }

    public var growSeconds: Double {
        switch self {
        case .wheat: return 30
        case .carrot: return 120
        case .tomato: return 300
        case .pumpkin: return 900
        case .starfruit: return 2700
        }
    }

    public var sellPrice: Int {
        switch self {
        case .wheat: return 14
        case .carrot: return 60
        case .tomato: return 180
        case .pumpkin: return 500
        case .starfruit: return 1900
        }
    }
}

public struct FarmPlot: Codable, Equatable, Sendable {
    public var crop: Crop?
    public var plantedAt: Date?

    public init(crop: Crop? = nil, plantedAt: Date? = nil) {
        self.crop = crop
        self.plantedAt = plantedAt
    }

    /// 0…1 growth at `date`, nil when empty.
    public func growth(at date: Date) -> Double? {
        guard let crop, let plantedAt else { return nil }
        return min(1, max(0, date.timeIntervalSince(plantedAt) / crop.growSeconds))
    }

    public func isReady(at date: Date) -> Bool {
        (growth(at: date) ?? 0) >= 1
    }

    public func secondsLeft(at date: Date) -> Double {
        guard let crop, let plantedAt else { return 0 }
        return max(0, crop.growSeconds - date.timeIntervalSince(plantedAt))
    }
}

public struct FarmState: Codable, Equatable, Sendable {
    public static let plotCount = 8
    public var coins = 25
    public var lifetime = 0
    public var harvests = 0
    public var unlocked = 4
    public var plots: [FarmPlot] = Array(repeating: FarmPlot(), count: FarmState.plotCount)
    public var lastCrop: Crop = .wheat

    public init() {}

    public func readyCount(at date: Date) -> Int {
        plots.prefix(unlocked).filter { $0.isReady(at: date) }.count
    }
}

/// Real-time farm. Crops keep growing while the notch is closed.
public final class FarmEngine: EngineBase, GameEngine {
    public static let columns = 4

    public static func unlockCost(forPlot index: Int) -> Int {
        switch index {
        case 4: return 120
        case 5: return 350
        case 6: return 900
        default: return 2400
        }
    }

    public private(set) var state: FarmState
    public private(set) var cursor = 0
    public private(set) var crop: Crop
    public private(set) var particles = ParticleField()
    /// Floating labels such as "+60".
    public private(set) var popups: [MinerEngine.Popup] = []
    /// Plot index that just changed, with the clock time; drives a bounce.
    public private(set) var lastAction: (plot: Int, at: Double)?

    public var onPersist: ((FarmState) -> Void)?

    private let date: () -> Date
    private var rng = SeededRandom(seed: SeededRandom.randomSeed())
    private var popupID = 0

    public init(state: FarmState, date: @escaping () -> Date = { Date() }) {
        self.state = state
        self.date = date
        self.crop = state.lastCrop
        super.init(boardKey: GameID.farm.rawValue)
        phase = .playing
        score = state.coins
    }

    public var now: Date { date() }

    public func restart() {}
    public override func pause() {}
    public override func resume() {}

    public func tick(_ dt: Double, input: InputState) {
        advanceClock(dt)
        particles.update(dt, drag: 1.2)
        for i in popups.indices { popups[i].age += dt }
        popups.removeAll { $0.age > 1.1 }
        score = state.coins
    }

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        switch key {
        case .left: moveCursor(-1, 0)
        case .right: moveCursor(1, 0)
        case .up: moveCursor(0, -1)
        case .down: moveCursor(0, 1)
        case .primary, .confirm:
            if !isRepeat { interact(cursor) }
        case .cycle:
            selectCrop(Crop(rawValue: (crop.rawValue + 1) % Crop.allCases.count) ?? .wheat)
        case .auto:
            harvestAll()
        case .number(let n):
            if let c = Crop(rawValue: n - 1) { selectCrop(c) }
        default:
            return false
        }
        return true
    }

    private func moveCursor(_ dx: Int, _ dy: Int) {
        let rows = FarmState.plotCount / Self.columns
        var col = cursor % Self.columns + dx
        var row = cursor / Self.columns + dy
        col = (col + Self.columns) % Self.columns
        row = (row + rows) % rows
        cursor = row * Self.columns + col
        play(.tick)
    }

    public func setCursor(_ index: Int) {
        guard (0..<FarmState.plotCount).contains(index) else { return }
        cursor = index
    }

    public func selectCrop(_ c: Crop) {
        crop = c
        state.lastCrop = c
        play(.select)
    }

    /// Plant, harvest or unlock depending on the plot.
    public func interact(_ index: Int) {
        cursor = index
        let t = now
        if index >= state.unlocked {
            unlock(index)
            return
        }
        let plot = state.plots[index]
        if plot.crop == nil {
            plant(index, at: t)
        } else if plot.isReady(at: t) {
            harvest(index)
            persist()
        } else {
            play(.error)
        }
    }

    private func plant(_ index: Int, at t: Date) {
        guard state.coins >= crop.seedCost else {
            play(.error)
            return
        }
        state.coins -= crop.seedCost
        state.plots[index] = FarmPlot(crop: crop, plantedAt: t)
        lastAction = (index, clock)
        play(.plant)
        emit(.count("farm.planted", 1))
        persist()
    }

    private func harvest(_ index: Int) {
        guard let c = state.plots[index].crop else { return }
        state.plots[index] = FarmPlot()
        state.coins += c.sellPrice
        state.lifetime += c.sellPrice
        state.harvests += 1
        lastAction = (index, clock)
        let col = Double(index % Self.columns), row = Double(index / Self.columns)
        particles.burst(
            at: Vec2(col, row), count: 14, speed: 0.6...1.8, life: 0.35...0.8, size: 0.02...0.05,
            tint: c.rawValue, gravity: 2.5, rng: &rng
        )
        popups.append(MinerEngine.Popup(id: popupID, amount: Double(c.sellPrice), age: 0))
        popupID += 1
        play(.harvest)
        emit(.count("farm.harvests", 1))
        emit(.count("farm.\(c)", 1))
        emit(.maximum("farm.lifetime", state.lifetime))
    }

    public func harvestAll() {
        let t = now
        var any = false
        for i in 0..<state.unlocked where state.plots[i].isReady(at: t) {
            harvest(i)
            any = true
        }
        if any { persist() } else { play(.error) }
    }

    private func unlock(_ index: Int) {
        guard index == state.unlocked else {
            play(.error)
            return
        }
        let price = Self.unlockCost(forPlot: index)
        guard state.coins >= price else {
            play(.error)
            return
        }
        state.coins -= price
        state.unlocked += 1
        lastAction = (index, clock)
        play(.buy)
        emit(.maximum("farm.plots", state.unlocked))
        persist()
    }

    public func persist() {
        onPersist?(state)
    }
}
