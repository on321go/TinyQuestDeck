//  CombatState.swift
//  Live, per-session combat state layered on top of the static derived sheet.
//  In-memory only (survives navigation via CombatStore; resets when the app quits —
//  persistence is step 4). The derived sheet stays pure; this holds only what changes
//  during a fight.

import Foundation

struct CombatState: Hashable {
    var currentHP: Int
    var conditions: Set<ConditionKind> = []
    var usedAbilityIDs: Set<String> = []
    var spellUsesSpent: [String: Int] = [:]   // spellID -> casts spent

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

    /// Rest: full reset (HP, conditions, used powers, spent casts) — the long-rest valve.
    func rest(_ id: UUID, maxHP: Int) {
        states[id] = CombatState(currentHP: maxHP)
    }

    /// Recharge: roll a d6; on a 6, re-arm every (Recharge)-reset power. Returns the roll.
    @discardableResult
    func recharge(_ id: UUID, rechargeAbilityIDs: [String]) -> Int {
        let roll = Int.random(in: 1...6)
        if roll == 6, var s = states[id] {
            rechargeAbilityIDs.forEach { s.usedAbilityIDs.remove($0) }
            states[id] = s
        }
        return roll
    }
}
