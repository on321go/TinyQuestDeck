//  Encounter.swift
//  The Places battle system — GM-side live encounter state plus preset content.
//  Implements BATTLE_SYSTEM_SPEC §2 (data model) and the store the board renders.
//
//  SINGLE-OWNER RULE: position is GM-side ONLY. Character sheets never know their
//  place; hero HP stays on the kids' sheets (their iPad). A hero Combatant here is
//  a chip with a name and conditions — no HP mirroring, ever.
//
//  NO LEGALITY ENFORCEMENT: the store never validates melee range, lock rolls, or
//  move distance. Illegal states are VISIBLE (wrong column), which is all the
//  enforcement this game needs — the app is a shared map, not a referee.
//
//  DICE PILLAR: nothing here rolls. Lock text ("Speed 12 to climb") is display only.
//
//  Persistence: ONE live encounter (StoredEncounter singleton row, same shape as
//  StoredShop). Resume-on-launch; starting a new fight replaces it; ending deletes it.

import Foundation
import SwiftData

// MARK: - Model (spec §2)

/// A zone. Adjacency is LINEAR for v1: places with parentID == nil form the strip
/// in array order; a locked place hangs off exactly one parent (adjacent to it only).
/// Which side of its parent a locked place hangs on. Optional so encounters saved
/// before this field existed keep decoding (nil = above, the original behavior).
enum LockedSide: String, Codable, Hashable { case above, below }

struct Place: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String                  // "The old bridge"
    var lock: String? = nil           // "Speed 12 to climb" — display only, honor system
    var parentID: UUID? = nil         // nil = main strip; set = hangs off that parent
    var side: LockedSide? = nil       // above (default) or below the parent
}

extension Place {
    var resolvedSide: LockedSide { side ?? .above }
}

struct Combatant: Codable, Identifiable, Hashable {
    /// Heroes reference a GMPartyMember (whose id matches the kid's hero id when
    /// QR-imported). Monsters carry an optional content id — nil = improvised at
    /// the table via Quick Monster Math.
    enum Kind: Codable, Hashable {
        case hero(memberID: UUID)
        case monster(monsterID: String?)
    }

    var id: UUID = UUID()
    var name: String                  // "Goblin A", "Mittens"
    var kind: Kind
    var placeID: UUID
    var hp: Int = 0                   // monsters only; heroes track HP on their sheet
    var maxHP: Int = 0
    var toHit: Int? = nil             // monsters — snapshotted at add time
    var damageLine: String? = nil     // monsters — "d6+2 fire"
    var conditions: Set<ConditionKind> = []

    var isMonster: Bool { if case .monster = kind { return true }; return false }
    var isDown: Bool { isMonster && hp <= 0 }
}

struct Encounter: Codable, Hashable {
    var title: String
    var places: [Place] = []
    var combatants: [Combatant] = []
    var activeCombatantID: UUID? = nil     // turn highlight (optional; table owns order)
    var round: Int = 1

    /// The linear strip, in authored order. Locked places render off their parents.
    var strip: [Place] { places.filter { $0.parentID == nil } }
    func lockedPlaces(off parentID: UUID) -> [Place] { places.filter { $0.parentID == parentID } }
    func combatants(in placeID: UUID) -> [Combatant] { combatants.filter { $0.placeID == placeID } }
    func place(_ id: UUID) -> Place? { places.first { $0.id == id } }
    var standingMonsters: Int { combatants.filter { $0.isMonster && $0.hp > 0 }.count }
}

// MARK: - Quick Monster Math (the improviser's table — rulebook gm-monsters)

extension MonsterThreat {
    /// Suggested defaults when the GM improvises: pick a tier → numbers filled →
    /// GM names it. (HP is the mid of the rulebook band; steppable in the sheet.)
    var suggestedHP: Int {
        switch self { case .wimpy: 3; case .normal: 7; case .tough: 14; case .boss: 24 }
    }
    var suggestedToHit: Int {
        switch self { case .wimpy: 2; case .normal: 2; case .tough: 4; case .boss: 5 }
    }
    var suggestedDamageLine: String {
        switch self { case .wimpy: "d4"; case .normal: "d6"; case .tough: "d6+2"; case .boss: "d6+3" }
    }
}

// MARK: - Presets (encounters.json — content, hydrated to UUIDs on start)

struct EncounterPreset: Codable, Identifiable, Hashable {
    struct PresetPlace: Codable, Hashable {
        let name: String
        let lock: String?
        let parent: String?           // strip place name; presence = child place
        let side: LockedSide?         // "above" (default) or "below" the parent
    }
    struct PresetMonster: Codable, Hashable {
        let monster: String           // MonsterDefinition id
        let place: String             // place name within this preset
        let count: Int?               // default 1; >1 auto-labels A/B/C…
    }

    let id: String
    let title: String
    let places: [PresetPlace]
    let monsters: [PresetMonster]

    /// Names → UUIDs, monster ids → snapshotted Combatants. Unknown monster ids or
    /// place names are skipped with a console warning (content typo, not a crash —
    /// the fight still starts).
    func hydrate(repo: ContentRepository) -> Encounter {
        // Pass 1: create every place (strip order preserved — strip = parentless in
        // array order, so authored order IS the map).
        var made: [Place] = places.map { Place(name: $0.name, lock: $0.lock) }
        // Pass 2: resolve parents by name.
        for (i, p) in places.enumerated() where p.parent != nil {
            if let parent = made.first(where: { $0.name == p.parent }) {
                made[i].parentID = parent.id
                made[i].side = p.side
            } else {
                print("⚠️ Encounter preset '\(id)': parent '\(p.parent!)' not found for '\(p.name)'")
            }
        }

        var fighters: [Combatant] = []
        var labelCounts: [String: Int] = [:]
        for entry in monsters {
            guard let def = repo.monster(entry.monster) else {
                print("⚠️ Encounter preset '\(id)': monster '\(entry.monster)' does not resolve")
                continue
            }
            guard let place = made.first(where: { $0.name == entry.place }) else {
                print("⚠️ Encounter preset '\(id)': place '\(entry.place)' not found for '\(entry.monster)'")
                continue
            }
            for _ in 0..<max(1, entry.count ?? 1) {
                labelCounts[def.name, default: 0] += 1
                fighters.append(Combatant.monster(def, label: labelCounts[def.name]!, in: place.id))
            }
        }
        // Suffix A/B/C only when a monster appears more than once.
        for (name, total) in labelCounts where total == 1 {
            if let i = fighters.firstIndex(where: { $0.name.hasPrefix(name + " ") }) {
                fighters[i].name = name
            }
        }
        return Encounter(title: title, places: made, combatants: fighters)
    }
}

private struct EncounterPresetFile: Codable { let presets: [EncounterPreset] }

extension Combatant {
    /// A bestiary monster, stats snapshotted at add time (content edits mid-fight
    /// never shift a live fight). `label` numbers duplicates: 1 → "Goblin A".
    static func monster(_ def: MonsterDefinition, label: Int, in placeID: UUID) -> Combatant {
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]
        let suffix = label <= letters.count ? letters[label - 1] : "\(label)"
        return Combatant(name: "\(def.name) \(suffix)",
                         kind: .monster(monsterID: def.id),
                         placeID: placeID,
                         hp: def.hp, maxHP: def.hp,
                         toHit: def.toHit, damageLine: def.damageLine)
    }
}

// MARK: - Store

@MainActor
@Observable
final class EncounterStore {
    /// The one live encounter (nil = no fight running). Resume-on-launch.
    var encounter: Encounter? = nil
    private(set) var presets: [EncounterPreset] = []

    @ObservationIgnored private let context: ModelContext
    static let singletonKey = "live-encounter"

    init() {
        context = ModelContext(PersistenceStore.container)
        restore()
        loadPresets()
    }

    // MARK: Lifecycle

    func start(preset: EncounterPreset, repo: ContentRepository) {
        commit(preset.hydrate(repo: repo))
    }

    /// Ad hoc: a named fight with two starter places the GM renames/extends.
    func startAdHoc(title: String) {
        let t = title.trimmingCharacters(in: .whitespaces)
        commit(Encounter(title: t.isEmpty ? "The Fight" : t,
                         places: [Place(name: "Here"), Place(name: "Over there")]))
    }

    /// End of fight: clear live state and delete the stored row. (Rewards flow
    /// through the award composer — the board just gets out of the way.)
    func end() {
        encounter = nil
        if let row = fetchRow() { context.delete(row) }
        try? context.save()
        print("💾 EncounterStore: encounter ended and cleared")
    }

    // MARK: Places

    /// One-tap "+ place" — REQUIRED mid-fight (kids invent places: "can I hide in
    /// the giant pot?"). GM names it, optional lock, optional parent. (spec §1.1)
    func addPlace(name: String, lock: String?, parentID: UUID?, side: LockedSide? = nil) {
        guard var e = encounter else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let cleanLock = lock?.trimmingCharacters(in: .whitespaces)
        e.places.append(Place(name: trimmed,
                              lock: (cleanLock?.isEmpty ?? true) ? nil : cleanLock,
                              parentID: parentID,
                              side: parentID == nil ? nil : side))
        commit(e)
    }

    func removePlace(_ placeID: UUID) {
        guard var e = encounter else { return }
        // Never strand a combatant or a locked child: refuse unless empty and childless.
        guard e.combatants(in: placeID).isEmpty, e.lockedPlaces(off: placeID).isEmpty else { return }
        e.places.removeAll { $0.id == placeID }
        commit(e)
    }

    // MARK: Combatants

    func move(_ combatantID: UUID, to placeID: UUID) {
        guard var e = encounter,
              let i = e.combatants.firstIndex(where: { $0.id == combatantID }) else { return }
        e.combatants[i].placeID = placeID
        commit(e)
    }

    func addHero(_ member: GMPartyMember, to placeID: UUID) {
        guard var e = encounter else { return }
        guard !e.combatants.contains(where: {
            if case .hero(let m) = $0.kind { return m == member.id }; return false
        }) else { return }
        e.combatants.append(Combatant(name: member.name,
                                      kind: .hero(memberID: member.id),
                                      placeID: placeID))
        commit(e)
    }

    func addMonster(_ def: MonsterDefinition, to placeID: UUID) {
        guard var e = encounter else { return }
        let existing = e.combatants.filter {
            if case .monster(let id) = $0.kind { return id == def.id }; return false
        }.count
        var c = Combatant.monster(def, label: existing + 1, in: placeID)
        if existing == 0 { c.name = def.name }   // solo copies drop the suffix
        else if existing == 1, let i = e.combatants.firstIndex(where: { $0.name == def.name }) {
            e.combatants[i].name = "\(def.name) A"   // retro-label the first when a second lands
        }
        commit({ var e2 = e; e2.combatants.append(c); return e2 }())
    }

    /// Quick Monster Math: threat picked → numbers filled → GM names it → chip
    /// lands in a place. (spec §7.1.2)
    func addImprovised(name: String, threat: MonsterThreat, to placeID: UUID) {
        guard var e = encounter else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        e.combatants.append(Combatant(name: trimmed,
                                      kind: .monster(monsterID: nil),
                                      placeID: placeID,
                                      hp: threat.suggestedHP, maxHP: threat.suggestedHP,
                                      toHit: threat.suggestedToHit,
                                      damageLine: threat.suggestedDamageLine))
        commit(e)
    }

    func remove(_ combatantID: UUID) {
        guard var e = encounter else { return }
        e.combatants.removeAll { $0.id == combatantID }
        if e.activeCombatantID == combatantID { e.activeCombatantID = nil }
        commit(e)
    }

    func damage(_ combatantID: UUID, _ amount: Int) {
        guard var e = encounter,
              let i = e.combatants.firstIndex(where: { $0.id == combatantID }),
              e.combatants[i].isMonster else { return }
        let c = e.combatants[i]
        e.combatants[i].hp = max(0, min(c.maxHP, c.hp - amount))
        commit(e)
    }

    func toggleCondition(_ combatantID: UUID, _ k: ConditionKind) {
        guard var e = encounter,
              let i = e.combatants.firstIndex(where: { $0.id == combatantID }) else { return }
        if e.combatants[i].conditions.contains(k) { e.combatants[i].conditions.remove(k) }
        else { e.combatants[i].conditions.insert(k) }
        commit(e)
    }

    // MARK: Round & turn (nice-to-have v1 — the table owns the real order)

    func setRound(_ n: Int) {
        guard var e = encounter else { return }
        e.round = max(1, n)
        commit(e)
    }

    /// Cycle the highlight through combatants in array order; wrapping bumps the
    /// round. Purely a shared-map affordance — turns still go around the table.
    func nextTurn() {
        guard var e = encounter, !e.combatants.isEmpty else { return }
        if let current = e.activeCombatantID,
           let i = e.combatants.firstIndex(where: { $0.id == current }) {
            let next = (i + 1) % e.combatants.count
            if next == 0 { e.round += 1 }
            e.activeCombatantID = e.combatants[next].id
        } else {
            e.activeCombatantID = e.combatants.first?.id
        }
        commit(e)
    }

    func clearTurnHighlight() {
        guard var e = encounter else { return }
        e.activeCombatantID = nil
        commit(e)
    }

    // MARK: Persistence (singleton row, StoredShop-shaped)

    private func commit(_ e: Encounter) {
        encounter = e
        guard let data = try? JSONEncoder().encode(e) else { return }
        if let row = fetchRow() {
            row.data = data
        } else {
            context.insert(StoredEncounter(key: Self.singletonKey, data: data))
        }
        do {
            try context.save()
        } catch {
            print("❌ EncounterStore: save failed — \(error)")
        }
    }

    private func fetchRow() -> StoredEncounter? {
        let key = Self.singletonKey
        return try? context.fetch(
            FetchDescriptor<StoredEncounter>(predicate: #Predicate { $0.key == key })).first
    }

    private func restore() {
        guard let data = fetchRow()?.data,
              let e = try? JSONDecoder().decode(Encounter.self, from: data) else { return }
        encounter = e
        print("📂 EncounterStore: restored '\(e.title)' (round \(e.round))")
    }

    private func loadPresets() {
        guard let url = Bundle.main.url(forResource: "encounters", withExtension: "json") else {
            print("⚠️ EncounterStore: encounters.json not found in bundle")
            return
        }
        do {
            presets = try JSONDecoder().decode(EncounterPresetFile.self,
                                               from: Data(contentsOf: url)).presets
        } catch {
            print("❌ EncounterStore: failed to parse encounters.json — \(error)")
        }
    }
}
