//  CharacterSheet.swift
//  The derived sheet: choices + content -> the numbers read at the table. Pure, no
//  SwiftUI, fully testable. Nothing here is stored; it's recomputed from CharacterChoices.
//  This is the STATIC (resting) sheet — current HP / conditions / live chips come later.

import Foundation

enum AbilitySource: String, Hashable { case core, race, pathPower, signature }

struct SheetAbility: Hashable {
    let ability: AbilityDefinition
    let source: AbilitySource
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

    var gear: [GearDefinition]
    var abilities: [SheetAbility]

    var isCaster: Bool
    var spells: [SheetSpell]          // full spellbook; ready ones flagged
    var readySpellCap: Int

    var conditionImmunities: [ConditionKind]
    var theme: ThemeToken?

    var readySpells: [SheetSpell] { spells.filter(\.isReady) }
}

/// Resting sheet for a character. Returns nil only if the choices reference missing content.
func deriveSheet(from c: CharacterChoices, using repo: ContentRepository) -> CharacterSheet? {
    guard let cls = repo.klass(c.classID),
          let path = repo.path(c.pathID),
          let race = repo.race(c.raceID) else { return nil }

    let level = max(1, min(c.level, cls.hpByLevel.count))
    func stat(_ s: Stat) -> Int { cls.baseStats[s] + (c.statBoosts[s.rawValue] ?? 0) }

    let gear = path.startingGearIDs.compactMap { repo.gear($0) }

    // Abilities the character actually has AT THIS LEVEL.
    var abilities: [SheetAbility] = cls.coreAbilityIDs
        .compactMap { repo.ability($0) }
        .map { SheetAbility(ability: $0, source: .core) }
    abilities.append(SheetAbility(ability: race.ability, source: .race))
    if level >= 2,
       let powerID = c.chosenPathPowerID ?? path.autoSelectedPathPowerID,
       let power = repo.ability(powerID) {
        abilities.append(SheetAbility(ability: power, source: .pathPower))
    }
    if level >= 3, let sigID = c.chosenSignatureID, let sig = repo.ability(sigID) {
        abilities.append(SheetAbility(ability: sig, source: .signature))
    }

    // Passive EffectHints from those abilities (the only hints that change resting numbers).
    var bonusHP = 0
    var immunities: [ConditionKind] = []
    var capFromHints = 0
    for hint in abilities.flatMap({ $0.ability.effects }) {
        switch hint {
        case .maxHP(let d):            bonusHP += d
        case .conditionImmunity(let k): immunities.append(k)
        case .readySpellCap(let cap):  capFromHints = max(capFromHints, cap)
        default: break                 // modifier/maxDamage/applyCondition/etc. are runtime, not resting
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
