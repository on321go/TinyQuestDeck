//  GMStore.swift
//  The GM tab's state: the award pipeline plus the loaded grant ledger.
//
//  ONE WRITER RULE: every award goes through this store, which both mutates the hero
//  (via RosterStore — the existing persistence path) AND appends the ledger row, so
//  attribution is never optional. The handoff's plan was "ledger.append inside
//  acquire()" — but CharacterChoices is a pure value type with no reach into
//  SwiftData, so the ledger records HERE, at the same call sites that invoke
//  acquire(). Same choke point, one layer up.
//
//  The ledger is a GM transparency/audit log, NOT a cheat-cop (honor system holds).
//  Rows are append-only and denormalize the hero's name, so the log stays readable
//  after a hero is deleted. This composer + ledger is the front half of the planned
//  QR token system — the QR emit is a go-live layer on top; nothing here is throwaway.
//
//  Awards only ever ADD ownership (never auto-equip), so Max HP can't change through
//  this store and no CombatStore is needed — unlike SellView, which strips worn gear.

import Foundation
import SwiftData

// MARK: - Ledger vocabulary (pure Codable — persisted as the StoredGrant blob)

/// What was awarded. Purchasables are OFFICIAL content (resolvable ids — priced,
/// sellable, showcase-eligible); homebrew is the free-text lane (GM-invented items,
/// unsellable by design — see the official-vs-homebrew ruling in the shop handoff).
///
/// Adding a case is safe for the stored ledger: old StoredGrant blobs never contain
/// it, and Swift's synthesized enum Codable keys on the case name, so nothing already
/// written re-reads differently.
enum GrantKind: Codable, Hashable, Sendable {
    case gold(Int)
    case purchasable(id: String, name: String)
    case homebrew(name: String, magic: Bool)
    /// Progression. Almost always 1 — quest, boss, or a rare individual bonus.
    /// Party-wide awards write ONE row per hero (see `awardStar(_:to:roster:)`), so
    /// the ledger reads as "who has what," not "what did I announce."
    case star(Int)
}

/// One ledger line.
struct GrantEntry: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    let heroID: UUID
    let heroName: String        // denormalized — survives hero deletion
    let kind: GrantKind
    let source: GrantSource     // .adventure today; .gmToken when QR lands
    let timestamp: Date
}

// MARK: - Store

@MainActor
@Observable
final class GMStore {
    /// Newest first. Append-only — nothing in the app edits or deletes a ledger row.
    private(set) var ledger: [GrantEntry] = []

    @ObservationIgnored private let context: ModelContext

    init() {
        context = ModelContext(PersistenceStore.container)
        let descriptor = FetchDescriptor<StoredGrant>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        let stored = (try? context.fetch(descriptor)) ?? []
        ledger = stored.compactMap { try? JSONDecoder().decode(GrantEntry.self, from: $0.data) }
        print("📂 GMStore: loaded \(ledger.count) ledger entr\(ledger.count == 1 ? "y" : "ies")")
    }

    // MARK: Awards (the single writer)

    /// Award (or deduct — the GM taketh away) gold. Clamped at 0 like the sheet's
    /// stepper so a big deduction can't go negative.
    func awardGold(_ amount: Int, to heroID: UUID, roster: RosterStore) {
        guard amount != 0, var hero = roster.characters.first(where: { $0.id == heroID }) else { return }
        hero.gold = max(0, hero.gold + amount)
        roster.update(hero)
        record(GrantEntry(heroID: heroID, heroName: hero.name,
                          kind: .gold(amount), source: .adventure, timestamp: .now))
    }

    /// Award (or take back) stars. Clamped at 0, uncapped upward — the track only
    /// draws 6, but extras bank quietly for thresholds that don't exist yet.
    ///
    /// Deliberately does NOT touch `level`: stars entitle, the kid claims. The sheet's
    /// level badge lights from `hero.canLevelUp` and the existing point-spend flow does
    /// the rest, so a star award can never silently change a hero's build.
    func awardStar(_ amount: Int = 1, to heroID: UUID, roster: RosterStore) {
        guard amount != 0, var hero = roster.characters.first(where: { $0.id == heroID }) else { return }
        hero.stars = max(0, hero.stars + amount)
        roster.update(hero)
        record(GrantEntry(heroID: heroID, heroName: hero.name,
                          kind: .star(amount), source: .adventure, timestamp: .now))
    }

    /// The party-wide case — quest and boss stars, which are party-wide ALWAYS
    /// (the sibling-proofing rule). One call, one row per hero, so the ledger can
    /// still answer "does this hero have their star?" for each kid independently.
    /// Heroes that no longer exist are skipped by the single-hero writer.
    func awardStar(_ amount: Int = 1, toParty heroIDs: [UUID], roster: RosterStore) {
        for heroID in heroIDs { awardStar(amount, to: heroID, roster: roster) }
    }

    /// Award official content — the same acquire() the shop's Buy uses, tagged
    /// .adventure. Scrolls fork on caster-ness exactly like a purchase (a caster
    /// learns it, a non-caster carries it); gear lands in ownedGearIDs, never
    /// auto-equipped — the kid equips from the sheet's Owned section, same as a buy.
    func award(_ p: Purchasable, to heroID: UUID, roster: RosterStore, repo: ContentRepository) {
        guard var hero = roster.characters.first(where: { $0.id == heroID }) else { return }
        hero.acquire(p, source: .adventure, repo: repo)
        roster.update(hero)
        record(GrantEntry(heroID: heroID, heroName: hero.name,
                          kind: .purchasable(id: p.id, name: p.name),
                          source: .adventure, timestamp: .now))
    }

    /// Award a homebrew (free-text) item. Lands in Normal/Magic Items by name —
    /// exactly like typing it on the sheet, but with provenance. If the item is later
    /// promoted into content.json under the same exact name, it auto-upgrades on
    /// every hero carrying it (the name-match rule) with no ledger rewrite needed.
    func awardHomebrew(_ name: String, magic: Bool, to heroID: UUID, roster: RosterStore) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              var hero = roster.characters.first(where: { $0.id == heroID }) else { return }
        if magic { hero.magicItems.append(trimmed) } else { hero.normalItems.append(trimmed) }
        roster.update(hero)
        record(GrantEntry(heroID: heroID, heroName: hero.name,
                          kind: .homebrew(name: trimmed, magic: magic),
                          source: .adventure, timestamp: .now))
    }

    // MARK: Ledger persistence (append-only)

    private func record(_ entry: GrantEntry) {
        ledger.insert(entry, at: 0)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        context.insert(StoredGrant(heroID: entry.heroID, timestamp: entry.timestamp, data: data))
        do {
            try context.save()
            print("💾 GMStore: recorded grant for \(entry.heroName)")
        } catch {
            print("❌ GMStore: ledger save failed — \(error)")
        }
    }
}
