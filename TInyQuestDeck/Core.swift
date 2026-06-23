//  Core.swift
//  TinyQuestKit — pure domain. No SwiftUI, no SwiftData. Reused verbatim by Parts 2/3.
//
//  JSON conventions enforced here:
//   • String-keyed stat maps           -> StatMap encodes {"might":2,"mind":1}
//   • Dice as compact strings          -> DiceExpr encodes "d6" / "2d4"
//   • Tagged-union for SpellTargets     -> {"kind":"multiple","count":3}
//  (EffectHint's tagged-union lives in TinyQuestContent, where the cases are defined.)

import Foundation

// MARK: - Atomic vocabulary (all String-raw -> synthesized Codable)

public enum Stat: String, Codable, CaseIterable, Sendable { case might, mind, speed }

public enum ConditionKind: String, Codable, CaseIterable, Sendable {
    case hurt, stuck, frightened, asleep
}

/// What a roll is for — drives which modifier chips apply (RollRules.advise).
public enum RollTarget: String, Codable, Sendable {
    case toHit, damage
    case mightCheck, mindCheck, speedCheck
    case any
}

/// Maps 1:1 to the sheet's bottom zones (+ ongoing). Drives chip expiry.
public enum ModifierScope: String, Codable, Sendable {
    case nextAttack       // "NEXT ATTACK"     — expires when an attack resolves
    case untilNextTurn    // "UNTIL NEXT TURN"  — expires at start of my next turn
    case thisFight        // "THIS FIGHT"       — expires on Rest / end of fight
    case untilCleared     // conditions & ongoing — manual clear
}

/// "advantage"/"disadvantage" without the D&D words. (Human "Try Anything Once".)
public enum KeepRule: String, Codable, Sendable { case better, worse }

// MARK: - Orthogonal usage axes (replaces the conflated §6 `Usage` enum)
//
// The single enum couldn't express the combos the rulebook leans on constantly:
// Shield = reaction + once-per-fight; Battle Cry = free + recharge. Split them.

/// What it costs on your turn. `.action` is the "do ONE thing" of the turn.
public enum ActionCost: String, Codable, Sendable {
    case passive, free, reaction, action
}

/// When the ability/spell re-arms. `.oncePerAdventure` has no auto-reset event in
/// Part 1 (TurnEvent stops at `fightEnded`/Rest) — the tracker clears it manually.
public enum ResetTrigger: String, Codable, Sendable {
    case atWill, recharge, oncePerFight, oncePerAdventure, rest, scene
}

/// Advisory recipient of a buff — shapes advice text and lets the receiving kid tap
/// the chip onto *their own* sheet. No cross-character state in Part 1.
public enum Recipient: String, Codable, Sendable {
    case selfTarget       // default
    case oneAlly          // Warlord's Eye
    case alliesInSight    // Battle Cry, Banner Bearer
}

// MARK: - StatMap  ({"might":2,"mind":1,"speed":1})

public struct StatMap: Hashable, Sendable {
    public private(set) var values: [Stat: Int]
    public init(_ values: [Stat: Int] = [:]) { self.values = values }
    public subscript(_ s: Stat) -> Int { values[s] ?? 0 }
    public var total: Int { values.values.reduce(0, +) }
}

extension StatMap: Codable {
    private struct K: CodingKey {
        var stringValue: String; var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        var v: [Stat: Int] = [:]
        for stat in Stat.allCases {
            if let key = K(stringValue: stat.rawValue),
               let n = try c.decodeIfPresent(Int.self, forKey: key) { v[stat] = n }
        }
        self.values = v
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        for stat in Stat.allCases where values[stat] != nil {
            if let key = K(stringValue: stat.rawValue) { try c.encode(values[stat]!, forKey: key) }
        }
    }
}

// MARK: - DiceExpr  ("d6", "2d4")

public struct DiceExpr: Hashable, Sendable {
    public let count: Int
    public let faces: Int
    public init(count: Int = 1, faces: Int) { self.count = count; self.faces = faces }
    /// Used by the maxDamage hint: the all-faces-up roll.
    public var maxRoll: Int { count * faces }
}

extension DiceExpr: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self).lowercased()
        let parts = raw.split(separator: "d", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let faces = Int(parts[1]) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Bad dice literal '\(raw)' (expected e.g. 'd6' or '2d4')"))
        }
        let count = parts[0].isEmpty ? 1 : (Int(parts[0]) ?? 1)
        self.init(count: count, faces: faces)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(count == 1 ? "d\(faces)" : "\(count)d\(faces)")
    }
}

// MARK: - SpellTargets (tagged union) and AttackProfile (shared by spells / weapons / companions)

public enum SpellTargets: Hashable, Sendable {
    case single
    case multiple(Int)       // Spark: "hits 3 targets"
    case cluster(max: Int)   // Fireball: "up to 6 clustered"
    case area                // Fire Explosion: "all enemies around you"
}

extension SpellTargets: Codable {
    private enum Kind: String, Codable { case single, multiple, cluster, area }
    private enum K: String, CodingKey { case kind, count, max }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .single:   self = .single
        case .area:     self = .area
        case .multiple: self = .multiple(try c.decode(Int.self, forKey: .count))
        case .cluster:  self = .cluster(max: try c.decode(Int.self, forKey: .max))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        switch self {
        case .single:        try c.encode(Kind.single, forKey: .kind)
        case .area:          try c.encode(Kind.area, forKey: .kind)
        case .multiple(let n): try c.encode(Kind.multiple, forKey: .kind); try c.encode(n, forKey: .count)
        case .cluster(let m):  try c.encode(Kind.cluster, forKey: .kind); try c.encode(m, forKey: .max)
        }
    }
}

/// One attack's machine-resolvable shape. `toHitStat == nil` means auto-hit (no d20):
/// Fire Explosion, Perfect Shot, Holy Fire. Reused by SpellDefinition.attack,
/// GearDefinition.attack (weapon categories), AbilityDefinition.attack, CompanionDefinition.attack.
public struct AttackProfile: Hashable, Sendable, Codable {
    public let toHitStat: Stat?
    public let damageDice: DiceExpr
    public let damageStat: Stat?
    public let targets: SpellTargets
    public init(toHitStat: Stat?, damageDice: DiceExpr, damageStat: Stat?, targets: SpellTargets) {
        self.toHitStat = toHitStat; self.damageDice = damageDice
        self.damageStat = damageStat; self.targets = targets
    }
}

// MARK: - Live combat values

public struct Modifier: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var label: String
    public var value: Int
    public var target: RollTarget
    public var scope: ModifierScope
    public var source: ModifierSource
    public init(id: UUID = UUID(), label: String, value: Int,
                target: RollTarget, scope: ModifierScope, source: ModifierSource) {
        self.id = id; self.label = label; self.value = value
        self.target = target; self.scope = scope; self.source = source
    }
}

public enum ModifierSource: Hashable, Sendable {
    case condition(ConditionKind)
    case ability(id: String)
    case spell(id: String)
    case manual
}

extension ModifierSource: Codable {
    private enum Kind: String, Codable { case condition, ability, spell, manual }
    private enum K: String, CodingKey { case kind, id, condition }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .condition: self = .condition(try c.decode(ConditionKind.self, forKey: .condition))
        case .ability:   self = .ability(id: try c.decode(String.self, forKey: .id))
        case .spell:     self = .spell(id: try c.decode(String.self, forKey: .id))
        case .manual:    self = .manual
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        switch self {
        case .condition(let k): try c.encode(Kind.condition, forKey: .kind); try c.encode(k, forKey: .condition)
        case .ability(let id):  try c.encode(Kind.ability, forKey: .kind); try c.encode(id, forKey: .id)
        case .spell(let id):    try c.encode(Kind.spell, forKey: .kind); try c.encode(id, forKey: .id)
        case .manual:           try c.encode(Kind.manual, forKey: .kind)
        }
    }
}

// MARK: - Roll resolution (the core Parts 2/3 reuse)

public struct RollAdvice: Equatable, Sendable {
    public let base: Int
    public let applied: [Modifier]
    public var bonus: Int { base + applied.reduce(0) { $0 + $1.value } }
}

public enum TurnEvent: Sendable { case myTurnStarted, attackResolved, fightEnded /* = Rest */ }

public enum RollRules {
    public static func advise(_ target: RollTarget, baseStat: Int, active: [Modifier]) -> RollAdvice {
        let applied = active.filter { $0.target == target || $0.target == .any }
        return RollAdvice(base: baseStat, applied: applied)
    }
    /// Pure expiry: given an event, return the survivors.
    public static func surviving(_ mods: [Modifier], after event: TurnEvent) -> [Modifier] {
        mods.filter { m in
            switch (m.scope, event) {
            case (.nextAttack, .attackResolved):   return false
            case (.untilNextTurn, .myTurnStarted): return false
            case (.thisFight, .fightEnded),
                 (.nextAttack, .fightEnded),
                 (.untilNextTurn, .fightEnded):     return false
            case (.untilCleared, _):                return true
            default:                                return true
            }
        }
    }
}
