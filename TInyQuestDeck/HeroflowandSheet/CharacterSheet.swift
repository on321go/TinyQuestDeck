//  CharacterSheet.swift
//  The derived sheet: choices + content -> the numbers read at the table. Pure, no
//  SwiftUI, fully testable. Nothing here is stored; it's recomputed from CharacterChoices.
//
//  GRANT-ALL: at L1 the character has class core + path core (L1 slot) + race
//  abilities; L2 adds ALL pathPowerIDs; L3 adds ALL signaturePowerIDs. No choice
//  fields exist anywhere — if a power is missing on the sheet, the bug is here
//  or in content, never in selection state.
//
//  Powers-audit pass:
//   • Every trackable ability carries totalUses (1 + active extraUses hints naming
//     it): Unbreakable makes Shield render TWO checkboxes with no view-side IDs.
//   • RULING — spell recharge is DERIVED from tier: every non-t3 Ready spell refills
//     on a rolled 6 (rechargeSpellIDs). No stored per-spell axis until one breaks the rule.
//   • Pet stats are DERIVED too (derivePetStats): book companions keep their printed
//     statlines; custom pets take the granted companion hint (Bonded Companion) as
//     their base and fold companionUpgrade hints (Pack Tactics) on top, never downgrading.
//
//  Bug-fix pass:
//   • showsSignatureBox now reads PathDefinition.signatureBox (Wild only), not
//     ClassDefinition (which used to opt in every Scout). Path-level gating.
//
//  Druid "Voice of the Wild" pass:
//   • summonSacrifice: a DERIVED flag+data, non-nil only while Heart of the Grove
//     (Druid L3) is active. It enables the summon box's Sacrifice button and carries
//     the honor-system heal reminder copy. Like every other resting number it's read
//     off a passive EffectHint; the live Spirit Animal itself is in CombatState, not
//     here (it isn't a resting number — it's summoned mid-fight).

import Foundation

enum AbilitySource: String, Hashable { case core, race, pathPower, signature }

struct SheetAbility: Hashable {
    let ability: AbilityDefinition
    let source: AbilitySource
    /// False when the ability names a gear category that isn't equipped
    /// (Shield with no shield). UI renders these struck-through, not hidden.
    let isAvailable: Bool
    /// Use-boxes the row renders. 0 = untracked (passives and at-wills).
    /// Otherwise 1 + active extraUses hints from OTHER abilities naming this one.
    let totalUses: Int
}

struct SheetSpell: Hashable {
    let spell: SpellDefinition
    let readyUses: Int     // cast boxes
    let isReady: Bool
}

/// Derived flag + data for the summon box's Sacrifice button. Non-nil only while
/// Heart of the Grove (Druid L3) is active. Heal is honor-system copy (Druid rolls
/// and picks who) — no cross-character state.
struct SummonSacrifice: Hashable {
    let players: Int
    let dice: DiceExpr
    let addStat: Stat?
    var reminderLabel: String {
        var s = "Heal \(players) players \(diceString(dice))"
        if let addStat { s += " + \(addStat.rawValue.capitalized)" }
        return s
    }
}

struct CharacterSheet: Hashable {
    var name: String
    var raceName: String
    var className: String
    var pathName: String
    var level: Int

    var might: Int
    var mind: Int
    var speed: Int
    var maxHP: Int

    var gear: [GearDefinition]         // equipped, in the order the kid added it
    var abilities: [SheetAbility]

    var isCaster: Bool
    var spells: [SheetSpell]           // full spellbook; ready ones flagged
    var readySpellCap: Int

    var conditionImmunities: [ConditionKind]
    var theme: ThemeToken?
    /// Content-driven (PathDefinition.signatureBox — Wild only for now): render
    /// L3 signature powers in their OWN gold box. Appearing at level 3 is the point.
    var showsSignatureBox: Bool
    /// Non-nil while Heart of the Grove is active: enables the summon box's Sacrifice
    /// button and carries the heal reminder copy.
    var summonSacrifice: SummonSacrifice?

    var readySpells: [SheetSpell] { spells.filter(\.isReady) }
    var benchSpells: [SheetSpell] { spells.filter { !$0.isReady } }
    /// Equipped gear that can attack — the Gear box's weapon lines.
    var weapons: [GearDefinition] { gear.filter { $0.attack != nil } }
    /// Global rule: a second equipped light melee weapon grants a free-action second
    /// attack (its own roll). Counts the array, NOT a category set — duplicates matter.
    var hasDualWield: Bool {
        gear.filter { $0.category == .lightMelee && $0.attack != nil }.count >= 2
    }

    var signatureAbilities: [SheetAbility] { abilities.filter { $0.source == .signature } }
    var nonSignatureAbilities: [SheetAbility] { abilities.filter { $0.source != .signature } }

    /// A rolled 6 re-arms these ("every power marked (Recharge)")…
    var rechargeAbilityIDs: [String] {
        abilities.filter { $0.ability.reset == .recharge }.map(\.ability.id)
    }
    /// …and refills these. RULING: rechargeable = every non-tier-3 Ready spell
    /// ("all non tier 3 spells"). Derived from tier — no stored axis.
    var rechargeSpellIDs: [String] {
        readySpells.filter { $0.spell.tier != .t3 }.map(\.spell.id)
    }
}

/// Resting sheet for a character. Returns nil only if the choices reference missing content.
func deriveSheet(from c: CharacterChoices, using repo: ContentRepository) -> CharacterSheet? {
    guard let cls = repo.klass(c.classID),
          let path = repo.path(c.pathID),
          let race = repo.race(c.raceID) else { return nil }

    let level = max(1, min(c.level, cls.hpByLevel.count))
    func stat(_ s: Stat) -> Int { cls.baseStats[s] + (c.statBoosts[s.rawValue] ?? 0) }

    // Equipped gear — duplicates allowed ("Axe X 2" is two entries).
    let gear = c.equippedGearIDs.compactMap { repo.gear($0) }
    let equippedCategories = Set(gear.map(\.category))   // for gating only; loses counts

    func sheetAbility(_ a: AbilityDefinition, _ source: AbilitySource) -> SheetAbility {
        let available = a.requiresGearCategory.map { equippedCategories.contains($0) } ?? true
        return SheetAbility(ability: a, source: source, isAvailable: available, totalUses: 0)
    }

    // ---- Ability assembly. Order: class core, path core (L1), race, L2 powers, L3 powers.
    var abilities: [SheetAbility] = cls.coreAbilityIDs
        .compactMap { repo.ability($0) }
        .map { sheetAbility($0, .core) }
    abilities += path.coreAbilityIDs
        .compactMap { repo.ability($0) }
        .map { sheetAbility($0, .core) }
    abilities.append(sheetAbility(race.ability, .race))
    if level >= 2 {
        abilities += path.pathPowerIDs
            .compactMap { repo.ability($0) }
            .map { sheetAbility($0, .pathPower) }
    }
    if level >= 3 {
        abilities += path.signaturePowerIDs
            .compactMap { repo.ability($0) }
            .map { sheetAbility($0, .signature) }
    }

    // Passive EffectHints (the only hints that change resting numbers). Hints from a
    // gear-gated ability that isn't available do NOT apply. extraUses is collected
    // here too — it changes a resting number (how many boxes a row renders).
    var bonusHP = 0
    var immunities: [ConditionKind] = []
    var capFromHints = 0
    var bonusUses: [String: Int] = [:]
    var summonSacrifice: SummonSacrifice? = nil
    for hint in abilities.filter(\.isAvailable).flatMap({ $0.ability.effects }) {
        switch hint {
        case .maxHP(let d):                       bonusHP += d
        case .conditionImmunity(let k):           immunities.append(k)
        case .readySpellCap(let cap):             capFromHints = max(capFromHints, cap)
        case .extraUses(let abilityID, let n):    bonusUses[abilityID, default: 0] += n
        case let .summonSacrifice(players, dice, addStat):
            summonSacrifice = SummonSacrifice(players: players, dice: dice, addStat: addStat)
        default: break                            // runtime hints, not resting
        }
    }

    // Second pass: stamp use-box counts. Passives and at-wills stay untracked (0);
    // everything else defaults to 1 plus any extraUses granted to it.
    abilities = abilities.map { item in
        let a = item.ability
        let trackable = a.reset != .atWill && a.actionCost != .passive
        return SheetAbility(ability: a, source: item.source, isAvailable: item.isAvailable,
                            totalUses: trackable ? 1 + (bonusUses[a.id] ?? 0) : 0)
    }

    let maxHP = cls.hpByLevel[level - 1] + gear.equippedBonusHP + bonusHP

    // Spells. Cast counts come from starting grants (loot counts arrive with the
    // loot model; unknown -> 1).
    let grantUses = Dictionary(
        startingGrants(classID: c.classID, pathID: c.pathID, repo: repo).map { ($0.spellID, $0.readyUses) },
        uniquingKeysWith: { first, _ in first })
    let readySet = Set(c.readySpellIDs)
    let spells: [SheetSpell] = c.spellbookIDs.compactMap { id in
        guard let s = repo.spell(id) else { return nil }
        return SheetSpell(spell: s, readyUses: grantUses[id] ?? 1, isReady: readySet.contains(id))
    }

    return CharacterSheet(
        name: c.name, raceName: race.name, className: cls.name, pathName: path.name, level: level,
        might: stat(.might), mind: stat(.mind), speed: stat(.speed), maxHP: maxHP,
        gear: gear, abilities: abilities,
        isCaster: cls.spellListID != nil, spells: spells,
        readySpellCap: max(6, capFromHints),
        conditionImmunities: immunities,
        theme: path.themeOverride ?? cls.theme,
        showsSignatureBox: path.signatureBox ?? false,
        summonSacrifice: summonSacrifice)
}

// MARK: - Derived pet stats

/// What a pet box displays. Derived — never stored, never ID-checked in views.
struct PetStats: Hashable {
    let maxHP: Int
    let statline: String
    let trick: AbilityDefinition?
}

/// Pet numbers are DERIVED like everything else.
///  • Book companions (companionID set) are named characters: they keep their
///    printed statlines and are NOT touched by upgrades.
///  • Custom pets (companionID nil) base on the granted companion hint if one is
///    active (Wild's Bonded Companion: 5 HP + Pack Bite trick), else the standard
///    5 HP · +2 hit · d6.
///  • companionUpgrade hints (Pack Tactics: HP 8, bite 3) fold on top of custom
///    pets with max() semantics — an upgrade never makes a pet worse.
func derivePetStats(for pet: PetChoice, abilities: [SheetAbility],
                    repo: ContentRepository) -> PetStats {
    if let compID = pet.companionID, let comp = repo.companion(compID) {
        return PetStats(maxHP: comp.maxHP, statline: companionStatline(comp), trick: comp.trick)
    }

    let activeHints = abilities.filter(\.isAvailable).flatMap { $0.ability.effects }

    var granted: CompanionDefinition? = nil
    for hint in activeHints {
        if case let .companion(def) = hint { granted = def }
    }

    var maxHP = granted?.maxHP ?? 5
    var bite: Int? = nil
    for hint in activeHints {
        if case let .companionUpgrade(hp, damage) = hint {
            if let hp { maxHP = max(maxHP, hp) }
            if let damage { bite = max(bite ?? 0, damage) }
        }
    }

    var line = "HP \(maxHP)"
    if let bite {
        line += " · bite \(bite)"
    } else if let granted {
        if let hit = granted.hitBonus { line += " · +\(hit) hit" }
        if let atk = granted.attack { line += " · \(diceString(atk.damageDice))" }
    } else {
        line += " · +2 hit · d6"
    }
    return PetStats(maxHP: maxHP, statline: line, trick: granted?.trick)
}

// MARK: - Display helpers

func diceString(_ d: DiceExpr) -> String { d.count == 1 ? "d\(d.faces)" : "\(d.count)d\(d.faces)" }

func attackSummary(_ a: AttackProfile) -> String {
    let hit = a.toHitStat.map { "d20+\($0.rawValue.capitalized)" } ?? "auto-hit"
    var dmg = diceString(a.damageDice)
    if let ds = a.damageStat { dmg += "+\(ds.rawValue.capitalized)" }
    var line = "\(hit) · \(dmg)"
    switch a.targets {
    case .single:           break
    case .multiple(let n):  line += " · \(n) targets"
    case .cluster(let m):   line += " · up to \(m)"
    case .area:             line += " · all around"
    }
    return line
}

/// Companion statline: flat hitBonus, not stat-based ("d20 +2 · d6").
func companionStatline(_ comp: CompanionDefinition) -> String {
    var line = "HP \(comp.maxHP)"
    if let hit = comp.hitBonus { line += " · +\(hit) hit" }
    if let atk = comp.attack { line += " · \(diceString(atk.damageDice))" }
    return line
}

/// Kid-facing name for a roll target. Shared by the tracker's manual "+" popover
/// and the auto-chips abilities push (labels must match).
func rollTargetName(_ t: RollTarget) -> String {
    switch t {
    case .toHit:      "Attack roll"
    case .damage:     "Damage"
    case .mightCheck: "Might roll"
    case .mindCheck:  "Mind roll"
    case .speedCheck: "Speed roll"
    case .any:        "All rolls"
    }
}
