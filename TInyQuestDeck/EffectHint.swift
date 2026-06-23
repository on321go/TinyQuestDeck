//  EffectHint.swift
//  TinyQuestContent — the declarative bridge from authored content to live Modifier chips.
//
//  Wire format is a "kind"-tagged union:
//    {"kind":"modifier","value":3,"target":"damage","scope":"nextAttack",
//     "requires":["hurt","stuck","frightened"]}
//
//  Forward-compat rule: any unrecognized "kind" decodes to `.unknown` rather than
//  throwing, so content can ship hints the code doesn't understand yet (§6).

import Foundation

public enum EffectHint: Hashable, Sendable {
    /// `requires` is ANY-OF (empty = unconditional). Finishing Blow: +3 dmg vs Hurt OR Stuck OR Frightened.
    case modifier(value: Int, target: RollTarget, scope: ModifierScope, requires: [ConditionKind])
    /// Champion's Strike: max weapon dice + Might -> addStat:.might. Overcharge: spell max dice -> addStat:nil.
    case maxDamage(addStat: Stat?)
    /// Brave Heart -> conditionImmunity(.frightened).
    case conditionImmunity(ConditionKind)
    /// Human "Try Anything Once" -> reroll(.any, .better).
    case reroll(target: RollTarget, keep: KeepRule)
    /// Wild Scout / future pets. Designed now; instances encoded later.
    case companion(CompanionDefinition)
    /// On-hit / on-cast condition. Frostbolt -> applyCondition(.stuck, toSelf:false).
    case applyCondition(ConditionKind, toSelf: Bool)
    /// Armor/shield Max-HP, Lizardfolk sun-rest heal, etc.
    case maxHP(delta: Int)
    /// Loremaster Spell Master -> readySpellCap(8). Derivation takes max(baseCap, active caps).
    case readySpellCap(Int)
    /// Graceful fallback for content the running binary doesn't recognize.
    case unknown
}

extension EffectHint: Codable {
    private enum Kind: String, Codable {
        case modifier, maxDamage, conditionImmunity, reroll, companion
        case applyCondition, maxHP, readySpellCap, unknown
    }
    private enum K: String, CodingKey {
        case kind
        case value, target, scope, requires   // modifier
        case addStat                           // maxDamage
        case condition, toSelf                 // conditionImmunity / applyCondition
        case keep                              // reroll
        case companion                         // companion
        case delta                             // maxHP
        case cap                               // readySpellCap
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        // Unknown discriminators must not throw — map to .unknown.
        guard let kindRaw = try? c.decode(String.self, forKey: .kind),
              let kind = Kind(rawValue: kindRaw) else {
            self = .unknown; return
        }
        switch kind {
        case .modifier:
            self = .modifier(
                value: try c.decode(Int.self, forKey: .value),
                target: try c.decode(RollTarget.self, forKey: .target),
                scope: try c.decode(ModifierScope.self, forKey: .scope),
                requires: try c.decodeIfPresent([ConditionKind].self, forKey: .requires) ?? [])
        case .maxDamage:
            self = .maxDamage(addStat: try c.decodeIfPresent(Stat.self, forKey: .addStat))
        case .conditionImmunity:
            self = .conditionImmunity(try c.decode(ConditionKind.self, forKey: .condition))
        case .reroll:
            self = .reroll(target: try c.decode(RollTarget.self, forKey: .target),
                           keep: try c.decode(KeepRule.self, forKey: .keep))
        case .companion:
            self = .companion(try c.decode(CompanionDefinition.self, forKey: .companion))
        case .applyCondition:
            self = .applyCondition(try c.decode(ConditionKind.self, forKey: .condition),
                                   toSelf: try c.decodeIfPresent(Bool.self, forKey: .toSelf) ?? false)
        case .maxHP:
            self = .maxHP(delta: try c.decode(Int.self, forKey: .delta))
        case .readySpellCap:
            self = .readySpellCap(try c.decode(Int.self, forKey: .cap))
        case .unknown:
            self = .unknown
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        switch self {
        case let .modifier(value, target, scope, requires):
            try c.encode(Kind.modifier, forKey: .kind)
            try c.encode(value, forKey: .value)
            try c.encode(target, forKey: .target)
            try c.encode(scope, forKey: .scope)
            if !requires.isEmpty { try c.encode(requires, forKey: .requires) }
        case let .maxDamage(addStat):
            try c.encode(Kind.maxDamage, forKey: .kind)
            try c.encodeIfPresent(addStat, forKey: .addStat)
        case let .conditionImmunity(cond):
            try c.encode(Kind.conditionImmunity, forKey: .kind)
            try c.encode(cond, forKey: .condition)
        case let .reroll(target, keep):
            try c.encode(Kind.reroll, forKey: .kind)
            try c.encode(target, forKey: .target)
            try c.encode(keep, forKey: .keep)
        case let .companion(def):
            try c.encode(Kind.companion, forKey: .kind)
            try c.encode(def, forKey: .companion)
        case let .applyCondition(cond, toSelf):
            try c.encode(Kind.applyCondition, forKey: .kind)
            try c.encode(cond, forKey: .condition)
            try c.encode(toSelf, forKey: .toSelf)
        case let .maxHP(delta):
            try c.encode(Kind.maxHP, forKey: .kind)
            try c.encode(delta, forKey: .delta)
        case let .readySpellCap(cap):
            try c.encode(Kind.readySpellCap, forKey: .kind)
            try c.encode(cap, forKey: .cap)
        case .unknown:
            try c.encode(Kind.unknown, forKey: .kind)
        }
    }
}
