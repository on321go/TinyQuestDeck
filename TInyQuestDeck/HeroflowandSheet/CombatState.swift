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
//
//  Bug-fix pass:
//   • noteChip hints (Fire Armor, Great Blessing) push a label-only reminder chip on
//     use — value 0, no roll effect. Unlike modifier chips these fire regardless of
//     `affects` (they're the user's own table reminder), and retract on un-spend like
//     any other ability chip.
//
//  Druid "Voice of the Wild" pass:
//   • summon (Spirit Animal): a live, APP-summoned creature — NOT a PetChoice, so it
//     never touches stored choices, Rest wipes it for free, and SwiftData won't
//     persist it. One live at a time. Its own box shows HP + an end-of-round bite
//     REMINDER (display only — no auto-attack, no RNG). Unlike Beast Mode it has no
//     tracker chip: its own box (steppers + Sacrifice) is self-managing, so there's
//     nothing to keep in lockstep. Lifetime: until 0 HP, Sacrifice, or Rest.
//   • The mode pick (Roots / Bloom / Spirit) happens in the VIEW, mirroring Beast
//     Mode's "Who grows?!" — Roots/Bloom push manual note chips there; only Spirit
//     reaches this file, gated by a SummonSpec (parallel to TransformTarget). The
//     `.summon` hint carries the mechanical data; onUseChips stays dumb for it.

import Foundation
import SwiftData

/// A live, temporary pet buff (Beast Mode). Its lifetime is the tracker chip with
/// `modifierID` — when that chip goes away (tapped, retracted, or Rest), the
/// transform ends and the pet's HP clamps back to its normal max.
struct PetTransform: Codable, Hashable, Sendable {
    let maxHP: Int          // transformed max (already max()ed vs normal)
    let damage: Int         // transformed bite
    let normalMaxHP: Int    // derived max to clamp back to when it ends
    let modifierID: UUID    // the "This Fight" chip that owns this transform
}

/// A live, app-summoned creature (Voice of the Wild's Spirit Animal). NOT a
/// PetChoice — never in stored choices, so Rest wipes it for free (state is rebuilt)
/// and SwiftData never persists it. Its box shows HP + an end-of-round bite reminder
/// (display only — the app never rolls or auto-attacks). One live at a time.
struct Summon: Codable, Hashable, Sendable {
    var name: String
    let maxHP: Int
    var currentHP: Int
    let damage: Int              // end-of-round bite, shown as a reminder
    let sourceAbilityID: String  // so a mis-tap un-spend of that box can clear it
    let sourceBoxIndex: Int
}

/// The kid chose Spirit Animal in the view's picker; presence tells setAbilitySpent
/// to actually summon (parallel to TransformTarget gating Beast Mode).
struct SummonSpec: Hashable { let name: String }

struct CombatState: Codable, Hashable {
    var currentHP: Int
    var conditions: Set<ConditionKind> = []
    var abilityUsesSpent: [String: Int] = [:] // abilityID -> uses spent
    var spellUsesSpent: [String: Int] = [:]   // spellID -> casts spent
    var modifiers: [Modifier] = []            // the tracker's chips (all three scopes)
    var petHP: [UUID: Int] = [:]              // PetChoice.id -> current HP
    var petTransforms: [UUID: PetTransform] = [:]  // PetChoice.id -> live Beast Mode
    var summon: Summon? = nil                       // live Spirit Animal (one at a time)

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
///
/// Two families:
///   • NOTE chips (noteChip): label-only reminders (value 0). They fire on ANY use,
///     regardless of `affects`, because they're the user's own table reminder for
///     things the app doesn't simulate (enemy -to-hit, heal-over-time). Fire Armor,
///     Great Blessing.
///   • ROLL-MODIFIER chips (modifier / maxDamage): actually change the user's rolls,
///     so they apply only when `affects` is selfTarget OR alliesInSight — "friends
///     within sight" includes the shouter, so Battle Cry buffs the Warlord too.
///     oneAlly buffs (Warlord's Eye) target somebody ELSE: the receiving kid adds
///     the chip on their own sheet via the tracker's "+" (Recipient doc, Core.swift).
func onUseChips(for ability: AbilityDefinition) -> [Modifier] {
    var chips: [Modifier] = []

    // Note chips fire regardless of `affects`.
    for hint in ability.effects {
        if case let .noteChip(label, scope) = hint {
            chips.append(Modifier(label: label, value: 0, target: .any,
                                  scope: scope, source: .ability(id: ability.id)))
        }
    }

    // Roll-modifier chips only when the buff lands on the user.
    guard ability.affects == .selfTarget || ability.affects == .alliesInSight else { return chips }
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

    @ObservationIgnored private let context: ModelContext

    init() {
        context = ModelContext(PersistenceStore.container)
    }

    /// First time a hero's sheet opens: restore saved combat if present (an
    /// interrupted fight survives quit), else start fresh at full HP.
    func seed(_ id: UUID, maxHP: Int) {
        guard states[id] == nil else { return }
        if let saved = loadState(id) {
            states[id] = saved
        } else {
            states[id] = CombatState(currentHP: maxHP)
        }
    }

    func damage(_ id: UUID, _ amount: Int) {
        guard var s = states[id] else { return }
        s.currentHP = max(0, s.currentHP - amount)
        commit(id, s)
    }

    func heal(_ id: UUID, _ amount: Int, maxHP: Int) {
        guard var s = states[id] else { return }
        s.currentHP = min(maxHP, s.currentHP + amount)
        commit(id, s)
    }

    /// Gear or level changed Max HP: shift current by the same delta (equipping armor
    /// feels good immediately; unequipping doesn't silently wound), clamped to new max.
    func adjustMaxHP(_ id: UUID, delta: Int, newMaxHP: Int) {
        guard var s = states[id] else { return }
        s.currentHP = max(0, min(newMaxHP, s.currentHP + delta))
        commit(id, s)
    }

    func toggleCondition(_ id: UUID, _ k: ConditionKind) {
        guard var s = states[id] else { return }
        if s.conditions.contains(k) { s.conditions.remove(k) } else { s.conditions.insert(k) }
        commit(id, s)
    }

    // MARK: Ability uses

    /// Spend/restore ability uses by tapping boxes — same fill/empty semantics as
    /// spell casts. SPENDING fires the ability's on-use hints (chips push into the
    /// tracker, resetAbility re-arms its target, rechargeSpells refills the passed
    /// Ready casts, summon creates the Spirit Animal when the kid chose Spirit).
    /// UN-spending (kids mis-tap) retracts every chip this ability pushed and clears
    /// a spirit this box summoned; other side effects are left alone (un-recharging
    /// spells would be weirder than the mis-tap).
    func setAbilitySpent(_ id: UUID, ability: AbilityDefinition, toBoxIndex index: Int,
                         total: Int, rechargeSpellIDs: [String],
                         transformPet: TransformTarget? = nil,
                         summonSpec: SummonSpec? = nil) {
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
                case let .summon(maxHP, damage):
                    // Only summon if the kid chose Spirit AND nothing's already out.
                    guard let spec = summonSpec, s.summon == nil else { break }
                    s.summon = Summon(name: spec.name, maxHP: maxHP, currentHP: maxHP,
                                      damage: damage, sourceAbilityID: ability.id,
                                      sourceBoxIndex: index)
                default:
                    break
                }
            }
        } else {
            s.modifiers.removeAll { $0.source == .ability(id: ability.id) }
            s.pruneOrphanedTransforms()
            // Mis-tap undo: if un-checking freed the box that summoned the spirit,
            // the spirit goes with it. (Roots/Bloom chips are manual-source, so they
            // persist — the kid taps those away.)
            if let sm = s.summon, sm.sourceAbilityID == ability.id, sm.sourceBoxIndex >= newSpent {
                s.summon = nil
            }
        }
        commit(id, s)
    }

    /// Spend/restore casts by tapping the boxes. Tapping box `index` fills up to it,
    /// tapping an already-filled box empties back down to it.
    func setSpent(_ id: UUID, _ spellID: String, toBoxIndex index: Int, total: Int) {
        guard var s = states[id] else { return }
        let spent = s.spellUsesSpent[spellID] ?? 0
        s.spellUsesSpent[spellID] = (index < spent) ? index : min(total, index + 1)
        commit(id, s)
    }

    // MARK: Tracker chips

    func addModifier(_ id: UUID, _ m: Modifier) {
        guard var s = states[id] else { return }
        s.modifiers.append(m)
        commit(id, s)
    }

    func removeModifier(_ id: UUID, modifierID: UUID) {
        guard var s = states[id] else { return }
        s.modifiers.removeAll { $0.id == modifierID }
        s.pruneOrphanedTransforms()   // tapping the Beast Mode chip ends the transform
        commit(id, s)
    }

    /// Apply a turn event and let RollRules expire the right chips.
    func apply(_ id: UUID, event: TurnEvent) {
        guard var s = states[id] else { return }
        s.modifiers = RollRules.surviving(s.modifiers, after: event)
        s.pruneOrphanedTransforms()
        commit(id, s)
    }

    // MARK: Pets

    func seedPet(_ id: UUID, petID: UUID, maxHP: Int = 5) {
        guard var s = states[id] else { return }
        if s.petHP[petID] == nil { s.petHP[petID] = maxHP }
        commit(id, s)
    }

    func adjustPetHP(_ id: UUID, petID: UUID, by delta: Int, maxHP: Int = 5) {
        guard var s = states[id] else { return }
        s.petHP[petID] = max(0, min(maxHP, (s.petHP[petID] ?? maxHP) + delta))
        commit(id, s)
    }

    // MARK: Summoned creatures (Voice of the Wild's Spirit Animal)

    /// Step the spirit's HP. At 0 it dissipates (box disappears) — a temporary
    /// creature, unlike a pet which lingers at 0 until Rest.
    func adjustSummonHP(_ id: UUID, by delta: Int) {
        guard var s = states[id], var sm = s.summon else { return }
        let hp = max(0, min(sm.maxHP, sm.currentHP + delta))
        if hp <= 0 { s.summon = nil } else { sm.currentHP = hp; s.summon = sm }
        commit(id, s)
    }

    /// Sacrifice (Heart of the Grove): the view pushes the honor-system heal chip,
    /// then calls this to remove the spirit.
    func clearSummon(_ id: UUID) {
        guard var s = states[id] else { return }
        s.summon = nil
        commit(id, s)
    }

    // MARK: Rest / Recharge

    /// Rest: full reset (HP, conditions, used powers, spent casts, chips, pet HP,
    /// and any live summon). RULING: Rest is also the adventure boundary —
    /// oncePerAdventure powers reset here too, by design, because CombatState is
    /// rebuilt from scratch.
    func rest(_ id: UUID, maxHP: Int) {
        states[id] = CombatState(currentHP: maxHP)
        save(id)                     // persist the cleared state so the reset sticks
    }

    /// Recharge: the KID rolls the physical d6 and taps the result. On a 6, every
    /// (Recharge)-reset power re-arms AND every rechargeable (non-t3) Ready spell's
    /// casts refill. No RNG in the app — dice are the fun.
    func recharge(_ id: UUID, rolled: Int,
                  rechargeAbilityIDs: [String], rechargeSpellIDs: [String]) {
        guard rolled == 6, var s = states[id] else { return }
        rechargeAbilityIDs.forEach { s.abilityUsesSpent[$0] = nil }
        rechargeSpellIDs.forEach { s.spellUsesSpent[$0] = nil }
        commit(id, s)
    }

    // MARK: Persistence
    //
    // Every mutation routes through commit(), which assigns the new state AND saves it
    // (one hero's CombatState per StoredCombat row, keyed by heroID). seed() restores
    // on first sheet open; rest() saves the cleared state directly. Choices persist in
    // RosterStore; this is the live-fight layer.

    /// Assign the new state for a hero and persist it. The single write choke point.
    private func commit(_ id: UUID, _ s: CombatState) {
        states[id] = s
        save(id)
    }

    /// Encode one hero's combat state into its StoredCombat row (upsert by heroID).
    private func save(_ id: UUID) {
        guard let s = states[id], let data = try? JSONEncoder().encode(s) else { return }
        let existing = try? context.fetch(
            FetchDescriptor<StoredCombat>(predicate: #Predicate { $0.heroID == id }))
        if let row = existing?.first {
            row.data = data
        } else {
            context.insert(StoredCombat(heroID: id, data: data))
        }
        do {
            try context.save()
            print("💾 CombatStore: saved fight for \(id.uuidString.prefix(8))")
        } catch {
            print("❌ CombatStore: save failed — \(error)")
        }
    }

    /// Decode a hero's saved combat state, or nil if none / undecodable. Orphan pet or
    /// summon references decode harmlessly — the sheet only renders pets that still
    /// exist, so a stale entry is inert rather than a crash.
    private func loadState(_ id: UUID) -> CombatState? {
        let stored = try? context.fetch(
            FetchDescriptor<StoredCombat>(predicate: #Predicate { $0.heroID == id }))
        guard let data = stored?.first?.data,
              let s = try? JSONDecoder().decode(CombatState.self, from: data) else { return nil }
        print("📂 CombatStore: restored fight for \(id.uuidString.prefix(8))")
        return s
    }
}
