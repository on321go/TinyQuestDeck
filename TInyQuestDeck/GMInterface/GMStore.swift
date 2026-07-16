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
enum GrantKind: Codable, Hashable, Sendable {
    case gold(Int)
    case purchasable(id: String, name: String)
    case homebrew(name: String, magic: Bool)
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
