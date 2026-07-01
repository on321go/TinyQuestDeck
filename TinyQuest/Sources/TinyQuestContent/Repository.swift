//  Repository.swift
//  TinyQuestContent — the seam the UI/VMs depend on (never touches JSON directly),
//  plus the load-time validator that turns a balance-edit typo into a loud, listed
//  failure instead of a crash at the table (§10).

import Foundation
import TinyQuestKit

public protocol ContentRepository {
    func classes() -> [ClassDefinition]
    func race(_ id: String) -> RaceDefinition?
    func races() -> [RaceDefinition]
    func path(_ id: String) -> PathDefinition?
    func ability(_ id: String) -> AbilityDefinition?
    func spell(_ id: String) -> SpellDefinition?
    func spellList(_ id: String) -> SpellListDefinition?
    func gear(_ id: String) -> GearDefinition?
}

public struct ContentIssue: Equatable, CustomStringConvertible {
    public let owner: String     // e.g. "path:champion"
    public let problem: String   // e.g. "startingGearID 'armorr' does not resolve"
    public var description: String { "[\(owner)] \(problem)" }
}

public struct ContentValidationError: Error, CustomStringConvertible {
    public let issues: [ContentIssue]
    public var description: String {
        "Content failed validation with \(issues.count) issue(s):\n" +
        issues.map { "  • \($0)" }.joined(separator: "\n")
    }
}

/// Decode-then-validate. Throws `ContentValidationError` listing every broken reference.
public final class ValidatingContentRepository: ContentRepository {
    private let bundle: ContentBundle
    private let classByID: [String: ClassDefinition]
    private let pathByID: [String: PathDefinition]
    private let abilityByID: [String: AbilityDefinition]
    private let spellByID: [String: SpellDefinition]
    private let spellListByID: [String: SpellListDefinition]
    private let gearByID: [String: GearDefinition]
    private let raceByID: [String: RaceDefinition]

    public init(bundle: ContentBundle) throws {
        self.bundle = bundle
        classByID = Dictionary(uniqueKeysWithValues: bundle.classes.map { ($0.id, $0) })
        pathByID = Dictionary(uniqueKeysWithValues: bundle.paths.map { ($0.id, $0) })
        abilityByID = Dictionary(uniqueKeysWithValues: bundle.abilities.map { ($0.id, $0) })
        spellByID = Dictionary(uniqueKeysWithValues: bundle.spells.map { ($0.id, $0) })
        spellListByID = Dictionary(uniqueKeysWithValues: bundle.spellLists.map { ($0.id, $0) })
        gearByID = Dictionary(uniqueKeysWithValues: bundle.gear.map { ($0.id, $0) })
        raceByID = Dictionary(uniqueKeysWithValues: bundle.races.map { ($0.id, $0) })

        let issues = Self.validate(bundle,
            classByID: classByID, pathByID: pathByID, abilityByID: abilityByID,
            spellByID: spellByID, spellListByID: spellListByID, gearByID: gearByID)
        if !issues.isEmpty { throw ContentValidationError(issues: issues) }
    }

    public func classes() -> [ClassDefinition] { bundle.classes }
    public func races() -> [RaceDefinition] { bundle.races }
    public func race(_ id: String) -> RaceDefinition? { raceByID[id] }
    public func path(_ id: String) -> PathDefinition? { pathByID[id] }
    public func ability(_ id: String) -> AbilityDefinition? { abilityByID[id] }
    public func spell(_ id: String) -> SpellDefinition? { spellByID[id] }
    public func spellList(_ id: String) -> SpellListDefinition? { spellListByID[id] }
    public func gear(_ id: String) -> GearDefinition? { gearByID[id] }

    // MARK: Validation

    static func validate(
        _ b: ContentBundle,
        classByID: [String: ClassDefinition],
        pathByID: [String: PathDefinition],
        abilityByID: [String: AbilityDefinition],
        spellByID: [String: SpellDefinition],
        spellListByID: [String: SpellListDefinition],
        gearByID: [String: GearDefinition]
    ) -> [ContentIssue] {
        var issues: [ContentIssue] = []
        func need(_ ok: Bool, _ owner: String, _ problem: @autoclosure () -> String) {
            if !ok { issues.append(ContentIssue(owner: owner, problem: problem())) }
        }

        for c in b.classes {
            let o = "class:\(c.id)"
            need(c.hpByLevel.count == 3, o, "hpByLevel must have 3 entries, has \(c.hpByLevel.count)")
            for a in c.coreAbilityIDs { need(abilityByID[a] != nil, o, "coreAbilityID '\(a)' does not resolve") }
            for p in c.pathIDs {
                need(pathByID[p] != nil, o, "pathID '\(p)' does not resolve")
                if let path = pathByID[p] { need(path.classID == c.id, o, "path '\(p)' has classID '\(path.classID)'") }
            }
            if let sl = c.spellListID { need(spellListByID[sl] != nil, o, "spellListID '\(sl)' does not resolve") }
            let catalog = c.spellListID.flatMap { spellListByID[$0] }.map { Set($0.spellIDs) }
            for g in c.baseSpells {
                need(spellByID[g.spellID] != nil, o, "baseSpell '\(g.spellID)' does not resolve")
                need(g.readyUses >= 1, o, "baseSpell '\(g.spellID)' readyUses must be >= 1")
                if let cat = catalog { need(cat.contains(g.spellID), o, "baseSpell '\(g.spellID)' not in catalog '\(c.spellListID!)'") }
            }
        }

        for p in b.paths {
            let o = "path:\(p.id)"
            need(classByID[p.classID] != nil, o, "classID '\(p.classID)' does not resolve")
            for g in p.startingGearIDs { need(gearByID[g] != nil, o, "startingGearID '\(g)' does not resolve") }
            need(!p.pathPowerOptionIDs.isEmpty, o, "pathPowerOptionIDs is empty")
            for a in p.pathPowerOptionIDs { need(abilityByID[a] != nil, o, "pathPower '\(a)' does not resolve") }
            for a in p.signatureOptionIDs { need(abilityByID[a] != nil, o, "signature '\(a)' does not resolve") }
            let catalog = classByID[p.classID]?.spellListID.flatMap { spellListByID[$0] }.map { Set($0.spellIDs) }
            for s in p.specialSpells {
                need(spellByID[s] != nil, o, "specialSpell '\(s)' does not resolve")
                if let cat = catalog { need(cat.contains(s), o, "specialSpell '\(s)' not in class catalog") }
            }
            for g in p.startingLoadoutOverride ?? [] {
                need(spellByID[g.spellID] != nil, o, "override spell '\(g.spellID)' does not resolve")
                if let cat = catalog { need(cat.contains(g.spellID), o, "override spell '\(g.spellID)' not in class catalog") }
            }
        }

        for l in b.spellLists {
            for s in l.spellIDs { need(spellByID[s] != nil, "spellList:\(l.id)", "spellID '\(s)' does not resolve") }
        }

        // Cross-check derived starting HP against the rulebook's stated path totals.
        for (pathID, expected) in Self.expectedStartingHP {
            guard let p = pathByID[pathID], let c = classByID[p.classID] else { continue }
            let total = (c.hpByLevel.first ?? 0) + p.startingGearIDs.compactMap { gearByID[$0]?.maxHP }.reduce(0, +)
            need(total == expected, "path:\(pathID)", "derived L1 HP \(total) != rulebook total \(expected)")
        }
        return issues
    }

    /// Rulebook "Total HP" at Level 1, per path — the number on the page.
    static let expectedStartingHP: [String: Int] = [
        "champion": 17, "guardian": 18, "warlord": 15,
        "dragon-guard": 13, "loremaster": 10,
    ]
}

public enum ContentLoader {
    public static func load(from url: URL) throws -> ValidatingContentRepository {
        let data = try Data(contentsOf: url)
        let bundle = try JSONDecoder().decode(ContentBundle.self, from: data)
        return try ValidatingContentRepository(bundle: bundle)
    }
}
