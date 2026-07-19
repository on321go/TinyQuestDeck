//  GMParty.swift
//  The GM-side party — WHO is playing this game, as lightweight records, because on
//  a dedicated GM iPad the kids' heroes don't exist in the local RosterStore (they
//  live on the players' iPad). A GMPartyMember is identity + display, never sheet
//  state (single-owner rule: HP, spells, and gear stay kid-side).
//
//  THE CRUCIAL FIELD is `id`: when a member is imported from a hero — locally today,
//  via the QR hero-card scan next — it carries the hero's CharacterChoices.id, so
//  award attribution and the future QR reward tokens address the right hero exactly.
//  Manually-entered members get a fresh UUID; they can be re-linked by a QR import
//  later (remove + rescan).
//
//  Persistence: a StoredParty singleton blob (StoredShop-shaped). The party is a
//  handful of records that change together — one row, not row-per-member.

import Foundation
import SwiftData

struct GMPartyMember: Codable, Identifiable, Hashable {
    var id: UUID = UUID()          // == the hero's CharacterChoices.id when imported
    var name: String
    var classID: String
    var raceID: String? = nil
    var pathID: String? = nil
    var level: Int = 1
    var portraitCombo: String? = nil   // QuestArt portrait key ("forest-elf-knight")
    var linked: Bool? = nil     // Bool?, NOT Bool = false — see the patch's note
    }

    extension GMPartyMember {
        var isLinked: Bool { linked == true }
    }

extension GMPartyMember {
    /// Snapshot a hero that exists on THIS iPad (the GM's own hero, or a shared-iPad
    /// family). The QR hero-card import will build the exact same record from a
    /// scanned payload instead of a local lookup.
    init(hero: CharacterChoices) {
        self.init(id: hero.id,
                  name: hero.name,
                  classID: hero.classID,
                  raceID: hero.raceID,
                  pathID: hero.pathID,
                  level: hero.level,
                  portraitCombo: hero.portraitID
                      ?? QuestArtKey.portraitCombo(race: hero.raceID, klass: hero.classID),
                  linked: true)      // the id IS a hero's
    }
}



@MainActor
@Observable
final class GMPartyStore {
    var members: [GMPartyMember] = []

    @ObservationIgnored private let context: ModelContext
    static let singletonKey = "gm-party"

    init() {
        context = ModelContext(PersistenceStore.container)
        let key = Self.singletonKey
        if let data = (try? context.fetch(
                FetchDescriptor<StoredParty>(predicate: #Predicate { $0.key == key })))?.first?.data,
           let loaded = try? JSONDecoder().decode([GMPartyMember].self, from: data) {
            members = loaded
        }
        print("📂 GMPartyStore: loaded \(members.count) party member(s)")
    }

    func add(_ member: GMPartyMember) {
        guard !members.contains(where: { $0.id == member.id }) else { return }
        members.append(member)
        save()
    }

    /// Refresh a member from a newer snapshot (re-import after a level-up). Same id
    /// = same hero; display fields update in place.
    func update(_ member: GMPartyMember) {
        if let i = members.firstIndex(where: { $0.id == member.id }) { members[i] = member }
        else { members.append(member) }
        save()
    }

    func remove(_ member: GMPartyMember) {
        members.removeAll { $0.id == member.id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(members) else { return }
        let key = Self.singletonKey
        let existing = try? context.fetch(
            FetchDescriptor<StoredParty>(predicate: #Predicate { $0.key == key })).first
        if let row = existing {
            row.data = data
        } else {
            context.insert(StoredParty(key: key, data: data))
        }
        do {
            try context.save()
            print("💾 GMPartyStore: saved \(members.count) member(s)")
        } catch {
            print("❌ GMPartyStore: save failed — \(error)")
        }
    }
}
