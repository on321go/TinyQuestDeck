//  CharacterSheet.swift
//  The derived sheet: choices + content -> the numbers read at the table. Pure, no
//  SwiftUI, fully testable. Nothing here is stored; it's recomputed from CharacterChoices.
//  This is the STATIC (resting) sheet — current HP / conditions / live chips come later.
//
//  Gear is the character's EQUIPPED gear (a stored choice), not the path's book kit.
//  Consequences:
//   • maxHP = hpByLevel[level] + Σ equipped maxHP + passive maxHP hints — so adding
//     Armor on the sheet immediately raises Max HP, matching the mockup behavior.
//   • Abilities can be gear-gated: Shield requires an equipped shield. Gated
//     abilities stay ON the sheet with isAvailable == false so the UI can render
//     the mockup's strikethrough "Not Equipped" state instead of hiding them.
//   • Path Powers and Signature Powers are grant-all: every listed power appears
//     once the level threshold is met. No selection state exists anywhere.
//   • Dual wield is a GLOBAL derived rule: two equipped lightMelee weapons = the
//     second attack is a free action (hasDualWield). Two rolls, two attacks.

import Foundation

enum AbilitySource: String, Hashable { case core, race, pathPower, signature }

struct SheetAbility: Hashable {
    let ability: AbilityDefinition
    let source: AbilitySource
    /// False when the ability names a gear category that isn't currently equipped
    /// (Shield with no shield). UI renders these struck-through, not hidden.
    let isAvailable: Bool
}

struct SheetSpell: Hashable {
    let spell: SpellDefinition
    let readyUses: Int     // cast boxes
    let isReady: Bool
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

    var readySpells: [SheetSpell] { spells.filter(\.isReady) }
    /// Equipped gear that can attack — the Gear section's weapon lines.
    var weapons: [GearDefinition] { gear.filter { $0.attack != nil } }
    /// Global rule: a second equipped light melee weapon grants a free-action second
    /// attack (its own roll). Counts the array, NOT a category set — duplicates matter.
    var hasDualWield: Bool {
        gear.filter { $0.category == .lightMelee && $0.attack != nil }.count >= 2
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
        return SheetAbility(ability: a, source: source, isAvailable: available)
    }

    // Abilities the character actually has AT THIS LEVEL. Grant-all: no choice fields.
    var abilities: [SheetAbility] = cls.coreAbilityIDs
        .compactMap { repo.ability($0) }
        .map { sheetAbility($0, .core) }
    
    abilities.append(sheetAbility(race.ability, .race))
    if level >= 2 {
        abilities += path.coreAbilityIDs
            .compactMap { repo.ability($0) }
            .map { sheetAbility($0, .core) }
    }
    if level >= 3 {
        abilities += path.signaturePowerIDs
            .compactMap { repo.ability($0) }
            .map { sheetAbility($0, .signature) }
    }

    // Passive EffectHints (the only hints that change resting numbers). Hints from a
    // gear-gated ability that isn't available do NOT apply.
    var bonusHP = 0
    var immunities: [ConditionKind] = []
    var capFromHints = 0
    for hint in abilities.filter(\.isAvailable).flatMap({ $0.ability.effects }) {
        switch hint {
        case .maxHP(let d):             bonusHP += d
        case .conditionImmunity(let k): immunities.append(k)
        case .readySpellCap(let cap):   capFromHints = max(capFromHints, cap)
        default: break                  // modifier/maxDamage/applyCondition/etc. are runtime, not resting
        }
    }

    let maxHP = cls.hpByLevel[level - 1] + gear.reduce(0) { $0 + $1.maxHP } + bonusHP

    // Spells. Cast counts come from the starting grants (loot-granted counts arrive with a
    // loot model later; unknown -> 1). At L1 every ready spell is a starting spell, so exact.
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
        theme: path.themeOverride ?? cls.theme)
}

// MARK: - Display helpers (used by the play sheet; pure string formatting)

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
