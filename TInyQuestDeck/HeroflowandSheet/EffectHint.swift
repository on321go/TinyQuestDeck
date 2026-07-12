//  EffectHint.swift
//  TinyQuestContent — the declarative bridge from authored content to live Modifier chips.
//
//  Wire format is a "kind"-tagged union:
//    {"kind":"modifier","value":3,"target":"damage","scope":"nextAttack",
//     "requires":["hurt","stuck","frightened"]}
//
//  Forward-compat rule: any unrecognized "kind" decodes to `.unknown` rather than
//  throwing, so content can ship hints the code doesn't understand yet (§6).
//
//  Added in the powers-audit pass:
//    • extraUses         — Unbreakable ("Shield works twice per fight")
//    • rechargeSpells    — Spell Master's once-per-rest spell refill
//    • resetAbility      — Elemental Teleport re-arms Fire Explosion
//    • companionUpgrade  — Pack Tactics (pet HP 8, bite 3), custom pets only
//
//  Added in the bug-fix pass:
//    • noteChip          — Fire Armor / Great Blessing: a label-only, honor-system
//                          reminder chip (value 0, no roll effect) on the user's tracker.

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
    /// A granted pet. Wild's Bonded Companion carries the 5 HP bonded friend here;
    /// the L2 level-up detects this hint and pops the naming flow.
    case companion(CompanionDefinition)
    /// On-hit / on-cast condition. Frostbolt -> applyCondition(.stuck, toSelf:false).
    case applyCondition(ConditionKind, toSelf: Bool)
    /// Armor/shield Max-HP, Lizardfolk sun-rest heal, etc.
    case maxHP(delta: Int)
    /// Archmage Spell Master -> readySpellCap(8). Derivation takes max(baseCap, active caps).
    case readySpellCap(Int)
    /// Grants extra use-boxes to ANOTHER ability. Unbreakable -> extraUses("shield", 1)
    /// = Shield renders two checkboxes. Applies only while the granting ability isAvailable.
    case extraUses(abilityID: String, count: Int)
    /// On use, refill every rechargeable (non-t3) Ready spell's cast boxes.
    /// Spell Master's "once per adventure, recharge your spells."
    case rechargeSpells
    /// On use, the named ability's spent boxes clear. Elemental Teleport ->
    /// resetAbility("fire-explosion") — "even if it's on cooldown."
    case resetAbility(abilityID: String)
    /// Pack Tactics -> companionUpgrade(maxHP:8, damage:3). Folded into derivePetStats
    /// for CUSTOM pets only (book companions are named characters and keep their
    /// printed statlines). Never downgrades: max(base, upgrade).
    case companionUpgrade(maxHP: Int?, damage: Int?)
    /// Beast Mode -> petTransform(maxHP:10, damage:4). A TEMPORARY, targeted buff:
    /// on use the kid picks which pet grows, and a "This Fight" tracker chip becomes
    /// the transform's lifetime — tap the chip when the fight ends to shrink back.
    /// Applies to ANY of the hero's pets (kid's choice), max() semantics, and Rest
    /// clears it automatically. Live state, not derived — see CombatState.PetTransform.
    case petTransform(maxHP: Int, damage: Int)
    /// A label-only REMINDER chip, no roll math (value 0). Fire Armor ->
    /// noteChip("Fire Armor: foes -2 to hit", .thisFight); Great Blessing ->
    /// noteChip("+2 heals · 3 turns", .thisFight). Unlike modifier chips, note chips
    /// fire regardless of `affects` and live on the USER's own tracker as a table
    /// reminder (the app doesn't track enemy rolls or heal-over-time — honor system).
    /// `scope` drives expiry like any other chip.
    case noteChip(label: String, scope: ModifierScope)
    /// Voice of the Wild's Spirit Animal -> summon(maxHP:5, endOfRoundDamage:2). A
    /// TEMPORARY app-summoned creature (its own live box, NOT a PetChoice): it never
    /// touches stored choices, so Rest wipes it for free and SwiftData won't persist
    /// it. Lifetime: until 0 HP, Sacrifice, or Rest. Ruling: ONE live at a time.
    case summon(maxHP: Int, endOfRoundDamage: Int)
    /// Heart of the Grove -> summonSacrifice(players:3, dice:"d6", addStat:.mind).
    /// Presence flags the summon box's Sacrifice button (folded to
    /// CharacterSheet.summonSacrifice). Honor-system heal — Druid picks who; no
    /// cross-character state. Distinct from `.companion` so the L2 naming flow
    /// (which scans for `.companion`) never fires on Voice of the Wild.
    case summonSacrifice(players: Int, dice: DiceExpr, addStat: Stat?)
    /// Graceful fallback for content the running binary doesn't recognize.
    
    case unknown
}

extension EffectHint: Codable {
    private enum Kind: String, Codable {
        case modifier, maxDamage, conditionImmunity, reroll, companion
        case applyCondition, maxHP, readySpellCap
        case extraUses, rechargeSpells, resetAbility, companionUpgrade, petTransform
        case noteChip
        case summon, summonSacrifice
        case unknown
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
        case abilityID, count                  // extraUses / resetAbility
        case maxHP_ = "maxHP", damage          // companionUpgrade
        case label                             // noteChip
        case players, dice                     // summon/summonSacrifice (maxHP_, damage, addStat reused)
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
        case .extraUses:
            self = .extraUses(abilityID: try c.decode(String.self, forKey: .abilityID),
                              count: try c.decodeIfPresent(Int.self, forKey: .count) ?? 1)
        case .rechargeSpells:
            self = .rechargeSpells
        case .resetAbility:
            self = .resetAbility(abilityID: try c.decode(String.self, forKey: .abilityID))
        case .companionUpgrade:
            self = .companionUpgrade(maxHP: try c.decodeIfPresent(Int.self, forKey: .maxHP_),
                                     damage: try c.decodeIfPresent(Int.self, forKey: .damage))
        case .petTransform:
            self = .petTransform(maxHP: try c.decode(Int.self, forKey: .maxHP_),
                                 damage: try c.decode(Int.self, forKey: .damage))
        case .noteChip:
            self = .noteChip(label: try c.decode(String.self, forKey: .label),
                             scope: try c.decode(ModifierScope.self, forKey: .scope))
        case .summon:
            self = .summon(maxHP: try c.decode(Int.self, forKey: .maxHP_),
                           endOfRoundDamage: try c.decode(Int.self, forKey: .damage))
        case .summonSacrifice:
            self = .summonSacrifice(players: try c.decode(Int.self, forKey: .players),
                                    dice: try c.decode(DiceExpr.self, forKey: .dice),
                                    addStat: try c.decodeIfPresent(Stat.self, forKey: .addStat))
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
        case let .extraUses(abilityID, count):
            try c.encode(Kind.extraUses, forKey: .kind)
            try c.encode(abilityID, forKey: .abilityID)
            try c.encode(count, forKey: .count)
        case .rechargeSpells:
            try c.encode(Kind.rechargeSpells, forKey: .kind)
        case let .resetAbility(abilityID):
            try c.encode(Kind.resetAbility, forKey: .kind)
            try c.encode(abilityID, forKey: .abilityID)
        case let .companionUpgrade(maxHP, damage):
            try c.encode(Kind.companionUpgrade, forKey: .kind)
            try c.encodeIfPresent(maxHP, forKey: .maxHP_)
            try c.encodeIfPresent(damage, forKey: .damage)
        case let .petTransform(maxHP, damage):
            try c.encode(Kind.petTransform, forKey: .kind)
            try c.encode(maxHP, forKey: .maxHP_)
            try c.encode(damage, forKey: .damage)
        case let .noteChip(label, scope):
            try c.encode(Kind.noteChip, forKey: .kind)
            try c.encode(label, forKey: .label)
            try c.encode(scope, forKey: .scope)
        case let .summon(maxHP, endOfRoundDamage):
            try c.encode(Kind.summon, forKey: .kind)
            try c.encode(maxHP, forKey: .maxHP_)
            try c.encode(endOfRoundDamage, forKey: .damage)
        case let .summonSacrifice(players, dice, addStat):
            try c.encode(Kind.summonSacrifice, forKey: .kind)
            try c.encode(players, forKey: .players)
            try c.encode(dice, forKey: .dice)
            try c.encodeIfPresent(addStat, forKey: .addStat)
        case .unknown:
            try c.encode(Kind.unknown, forKey: .kind)
        }
    }
}
