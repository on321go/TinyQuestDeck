//  CombatState.swift
//  Live, per-session combat state layered on top of the static derived sheet.
//  In-memory only (survives navigation via CombatStore; resets when the app quits —
//  persistence is step 4). The derived sheet stays pure; this holds only what changes
//  during a fight.
//
//  DICE PILLAR: the app NEVER rolls. recharge(rolled:) takes the physical d6 result
//  the kid tapped in; there is no RNG anywhere in this file.

import Foundation

struct CombatState: Hashable {
    var currentHP: Int
    var conditions: Set<ConditionKind> = []
    var usedAbilityIDs: Set<String> = []
    var spellUsesSpent: [String: Int] = [:]   // spellID -> casts spent
    var modifiers: [Modifier] = []            // the tracker's chips (all three scopes)
    var petHP: [UUID: Int] = [:]              // PetChoice.id -> current HP (max 5 standard)

    func remainingCasts(_ spellID: String, of total: Int) -> Int {
        max(0, total - (spellUsesSpent[spellID] ?? 0))
    }
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

    func toggleUsed(_ id: UUID, _ abilityID: String) {
        guard var s = states[id] else { return }
        if s.usedAbilityIDs.contains(abilityID) { s.usedAbilityIDs.remove(abilityID) }
        else { s.usedAbilityIDs.insert(abilityID) }
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
        states[id] = s
    }

    /// Apply a turn event and let RollRules expire the right chips.
    func apply(_ id: UUID, event: TurnEvent) {
        guard var s = states[id] else { return }
        s.modifiers = RollRules.surviving(s.modifiers, after: event)
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
    func rest(_ id: UUID, maxHP: Int) {
        states[id] = CombatState(currentHP: maxHP)
    }

    /// Recharge: the KID rolls the physical d6 and taps the result. On a 6, every
    /// (Recharge)-reset power re-arms. No RNG in the app — dice are the fun.
    func recharge(_ id: UUID, rolled: Int, rechargeAbilityIDs: [String]) {
        guard rolled == 6, var s = states[id] else { return }
        rechargeAbilityIDs.forEach { s.usedAbilityIDs.remove($0) }
        states[id] = s
    }
}
