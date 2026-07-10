//  CombatState.swift
//  Live, per-session combat state layered on top of the static derived sheet.
//  In-memory only (survives navigation via CombatStore; resets when the app quits —
//  persistence is step 4). The derived sheet stays pure; this holds only what changes
//  during a fight.
//
//  DICE PILLAR: the app NEVER rolls. recharge(rolled:) takes the physical d6 result
//  the kid tapped in; there is no RNG anywhere in this file.
//
//  Powers-audit pass:
//   • usedAbilityIDs (Set) -> abilityUsesSpent (counts), same shape as spells, so
//     Unbreakable's "Shield works twice" is just two boxes.
//   • Spending a use FIRES the ability's hints: self/allies-in-sight modifier hints
//     push tracker chips ("make it easy on the kid"), resetAbility re-arms its
//     target (Elemental Teleport -> Fire Explosion), rechargeSpells refills the
//     given Ready casts (Spell Master). Un-spending retracts that ability's chips.
//   • recharge(rolled: 6) now also refills the passed non-t3 Ready spell casts and
//     honors the book's free spell swap via the honor system (the ⋯ menu is always
//     open — the popover just reminds the kid).
//   • RULING — Rest IS the adventure boundary: rest() rebuilds CombatState from
//     scratch, so oncePerAdventure and rest powers reset identically by design.
//   • Beast Mode (petTransform hint): a TEMPORARY targeted pet buff whose lifetime
//     IS its "This Fight" tracker chip — tap the chip to shrink the pet back
//     (the use box stays spent), un-check the box to retract everything (mis-tap),
//     Rest clears it like everything else. pruneOrphanedTransforms() keeps the
//     chip and the transform in lockstep no matter which path removed the chip.

import Foundation

/// A live, temporary pet buff (Beast Mode). Its lifetime is the tracker chip with
/// `modifierID` — when that chip goes away (tapped, retracted, or Rest), the
/// transform ends and the pet's HP clamps back to its normal max.
struct PetTransform: Hashable, Sendable {
    let maxHP: Int          // transformed max (already max()ed vs normal)
    let damage: Int         // transformed bite
    let normalMaxHP: Int    // derived max to clamp back to when it ends
    let modifierID: UUID    // the "This Fight" chip that owns this transform
}

struct CombatState: Hashable {
    var currentHP: Int
    var conditions: Set<ConditionKind> = []
    var abilityUsesSpent: [String: Int] = [:] // abilityID -> uses spent
    var spellUsesSpent: [String: Int] = [:]   // spellID -> casts spent
    var modifiers: [Modifier] = []            // the tracker's chips (all three scopes)
    var petHP: [UUID: Int] = [:]              // PetChoice.id -> current HP
    var petTransforms: [UUID: PetTransform] = [:]  // PetChoice.id -> live Beast Mode

    func remainingCasts(_ spellID: String, of total: Int) -> Int {
        max(0, total - (spellUsesSpent[spellID] ?? 0))
    }

    func spentUses(_ abilityID: String) -> Int { abilityUsesSpent[abilityID] ?? 0 }

    func isFullySpent(_ abilityID: String, of total: Int) -> Bool {
        total > 0 && spentUses(abilityID) >= total
    }

    /// Transforms whose owning chip is gone end NOW: clamp the pet back to its
    /// normal max and drop the transform. Called after every chip removal path.
    mutating func pruneOrphanedTransforms() {
        let liveChipIDs = Set(modifiers.map(\.id))
        for (petID, t) in petTransforms where !liveChipIDs.contains(t.modifierID) {
            petHP[petID] = min(t.normalMaxHP, petHP[petID] ?? t.normalMaxHP)
            petTransforms[petID] = nil
        }
    }
}

/// The pet a petTransform ability was aimed at — chosen by the kid in the view
/// ("Who grows?!") because CombatStore never presents UI.
struct TransformTarget: Hashable {
    let petID: UUID
    let petName: String
    let normalMaxHP: Int
}

/// The chips an ability pushes onto ITS OWN sheet when a use is spent.
/// RULING: hints apply to the user when `affects` is selfTarget OR alliesInSight —
/// "friends within sight" includes the shouter, so Battle Cry buffs the Warlord too.
/// oneAlly buffs (Warlord's Eye, Great Blessing) target somebody ELSE: the receiving
/// kid adds the chip on their own sheet via the tracker's "+" (Recipient doc, Core.swift).
func onUseChips(for ability: AbilityDefinition) -> [Modifier] {
    guard ability.affects == .selfTarget || ability.affects == .alliesInSight else { return [] }
    var chips: [Modifier] = []
    for hint in ability.effects {
        switch hint {
        case let .modifier(value, target, scope, requires):
            let sign = value >= 0 ? "+" : ""
            var label = "\(sign)\(value) \(rollTargetName(target))"
            if !requires.isEmpty {
                label += " (vs \(requires.map { $0.rawValue.capitalized }.joined(separator: "/")))"
            }
            chips.append(Modifier(label: label, value: value, target: target,
                                  scope: scope, source: .ability(id: ability.id)))
        case let .maxDamage(addStat):
            // No integer value — a label-only reminder chip on the next attack.
            let label = addStat.map { "Max damage + \($0.rawValue.capitalized)" } ?? "Max damage"
            chips.append(Modifier(label: label, value: 0, target: .damage,
                                  scope: .nextAttack, source: .ability(id: ability.id)))
        default:
            break
        }
    }
    return chips
}

@MainActor
@Observable
final class CombatStore {
    var states: [UUID: CombatState] = [:]

    /// Create resting state the first time a hero's sheet opens.
    func seed(_ id: UUID, maxHP: Int) {
        if states[id] == nil { states[id] = CombatState(currentHP: maxHP) }
    }

    func damage(_ id: UUID, _ amount: Int) {
        guard var s = states[id] else { return }
        s.currentHP = max(0, s.currentHP - amount)
        states[id] = s
    }

    func heal(_ id: UUID, _ amount: Int, maxHP: Int) {
        guard var s = states[id] else { return }
        s.currentHP = min(maxHP, s.currentHP + amount)
        states[id] = s
    }

    /// Gear or level changed Max HP: shift current by the same delta (equipping armor
    /// feels good immediately; unequipping doesn't silently wound), clamped to new max.
    func adjustMaxHP(_ id: UUID, delta: Int, newMaxHP: Int) {
        guard var s = states[id] else { return }
        s.currentHP = max(0, min(newMaxHP, s.currentHP + delta))
        states[id] = s
    }

    func toggleCondition(_ id: UUID, _ k: ConditionKind) {
        guard var s = states[id] else { return }
        if s.conditions.contains(k) { s.conditions.remove(k) } else { s.conditions.insert(k) }
        states[id] = s
    }

    // MARK: Ability uses

    /// Spend/restore ability uses by tapping boxes — same fill/empty semantics as
    /// spell casts. SPENDING fires the ability's on-use hints (chips push into the
    /// tracker, resetAbility re-arms its target, rechargeSpells refills the passed
    /// Ready casts). UN-spending (kids mis-tap) retracts every chip this ability
    /// pushed; other side effects are left alone (un-recharging spells would be
    /// weirder than the mis-tap).
    func setAbilitySpent(_ id: UUID, ability: AbilityDefinition, toBoxIndex index: Int,
                         total: Int, rechargeSpellIDs: [String],
                         transformPet: TransformTarget? = nil) {
        guard var s = states[id] else { return }
        let spent = s.abilityUsesSpent[ability.id] ?? 0
        let newSpent = (index < spent) ? index : min(total, index + 1)
        guard newSpent != spent else { return }
        s.abilityUsesSpent[ability.id] = newSpent

        if newSpent > spent {
            s.modifiers.append(contentsOf: onUseChips(for: ability))
            for hint in ability.effects {
                switch hint {
                case .resetAbility(let targetID):
                    s.abilityUsesSpent[targetID] = 0
                case .rechargeSpells:
                    rechargeSpellIDs.forEach { s.spellUsesSpent[$0] = nil }
                case let .petTransform(maxHP, damage):
                    guard let t = transformPet else { break }
                    let chip = Modifier(label: "Beast Mode: \(t.petName)", value: 0,
                                        target: .any, scope: .thisFight,
                                        source: .ability(id: ability.id))
                    s.modifiers.append(chip)
                    // Grow: max() so an already-buffed pet never shrinks; current HP
                    // grows with the max (same feel as equipping armor).
                    let newMax = max(t.normalMaxHP, maxHP)
                    let current = s.petHP[t.petID] ?? t.normalMaxHP
                    s.petHP[t.petID] = min(newMax, current + (newMax - t.normalMaxHP))
                    s.petTransforms[t.petID] = PetTransform(
                        maxHP: newMax, damage: damage,
                        normalMaxHP: t.normalMaxHP, modifierID: chip.id)
                default:
                    break
                }
            }
        } else {
            s.modifiers.removeAll { $0.source == .ability(id: ability.id) }
            s.pruneOrphanedTransforms()
        }
        states[id] = s
    }

    /// Spend/restore casts by tapping the boxes. Tapping box `index` fills up to it,
    /// tapping an already-filled box empties back down to it.
    func setSpent(_ id: UUID, _ spellID: String, toBoxIndex index: Int, total: Int) {
        guard var s = states[id] else { return }
        let spent = s.spellUsesSpent[spellID] ?? 0
        s.spellUsesSpent[spellID] = (index < spent) ? index : min(total, index + 1)
        states[id] = s
    }

    // MARK: Tracker chips

    func addModifier(_ id: UUID, _ m: Modifier) {
        guard var s = states[id] else { return }
        s.modifiers.append(m)
        states[id] = s
    }

    func removeModifier(_ id: UUID, modifierID: UUID) {
        guard var s = states[id] else { return }
        s.modifiers.removeAll { $0.id == modifierID }
        s.pruneOrphanedTransforms()   // tapping the Beast Mode chip ends the transform
        states[id] = s
    }

    /// Apply a turn event and let RollRules expire the right chips.
    func apply(_ id: UUID, event: TurnEvent) {
        guard var s = states[id] else { return }
        s.modifiers = RollRules.surviving(s.modifiers, after: event)
        s.pruneOrphanedTransforms()
        states[id] = s
    }

    // MARK: Pets

    func seedPet(_ id: UUID, petID: UUID, maxHP: Int = 5) {
        guard var s = states[id] else { return }
        if s.petHP[petID] == nil { s.petHP[petID] = maxHP }
        states[id] = s
    }

    func adjustPetHP(_ id: UUID, petID: UUID, by delta: Int, maxHP: Int = 5) {
        guard var s = states[id] else { return }
        s.petHP[petID] = max(0, min(maxHP, (s.petHP[petID] ?? maxHP) + delta))
        states[id] = s
    }

    // MARK: Rest / Recharge

    /// Rest: full reset (HP, conditions, used powers, spent casts, chips, pet HP).
    /// RULING: Rest is also the adventure boundary — oncePerAdventure powers reset
    /// here too, by design, because CombatState is rebuilt from scratch.
    func rest(_ id: UUID, maxHP: Int) {
        states[id] = CombatState(currentHP: maxHP)
    }

    /// Recharge: the KID rolls the physical d6 and taps the result. On a 6, every
    /// (Recharge)-reset power re-arms AND every rechargeable (non-t3) Ready spell's
    /// casts refill. No RNG in the app — dice are the fun.
    func recharge(_ id: UUID, rolled: Int,
                  rechargeAbilityIDs: [String], rechargeSpellIDs: [String]) {
        guard rolled == 6, var s = states[id] else { return }
        rechargeAbilityIDs.forEach { s.abilityUsesSpent[$0] = nil }
        rechargeSpellIDs.forEach { s.spellUsesSpent[$0] = nil }
        states[id] = s
    }
}
