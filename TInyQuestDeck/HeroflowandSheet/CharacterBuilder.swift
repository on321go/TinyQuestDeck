//  CharacterBuilder.swift
//  The MVP loop: roster -> "+" -> pick race/class/path/name -> create -> back to roster.
//  Roster now PERSISTS via SwiftData (step 4): heroes survive quit. CharacterChoices
//  stays a pure Codable struct — see Persistence.swift for the thin @Model wrapper.
//
//  Persistence rides on the `characters` didSet: EVERY mutation path (add, remove,
//  and the update(_:)/remove(_:) extensions elsewhere) saves automatically, because
//  they all mutate `characters`. Nothing outside this class and Persistence.swift is
//  SwiftData-aware.
//
//  App root is MainTabView, which owns the single shared RosterStore + CombatStore.

import SwiftUI
import SwiftData

// MARK: - Persisted roster

@MainActor
@Observable
final class RosterStore {
    /// Observable source of truth for the UI. Every mutation persists EXPLICITLY via
    /// save() — no reliance on property observers (didSet does not fire reliably under
    /// @Observable, which is why an earlier version silently didn't save).
    var characters: [CharacterChoices] = []

    @ObservationIgnored private let context: ModelContext

    init() {
        context = ModelContext(PersistenceStore.container)
        let descriptor = FetchDescriptor<StoredHero>(sortBy: [SortDescriptor(\.order)])
        let stored = (try? context.fetch(descriptor)) ?? []
        characters = stored.compactMap {
            try? JSONDecoder().decode(CharacterChoices.self, from: $0.data)
        }
        print("📂 RosterStore: loaded \(characters.count) hero(es) from disk")
    }

    // All four mutation paths live here now and save explicitly. If your project has
    // update(_:)/remove(_:) defined in an extension elsewhere (e.g. HeroTile.swift),
    // DELETE those — the compiler will flag them as duplicate declarations and point
    // you right at them.
    func add(_ c: CharacterChoices) { characters.append(c); save() }
    func remove(at offsets: IndexSet) { characters.remove(atOffsets: offsets); save(intentionalDeletion: true) }
    func remove(_ c: CharacterChoices) { characters.removeAll { $0.id == c.id }; save(intentionalDeletion: true) }
    func update(_ c: CharacterChoices) {
        if let i = characters.firstIndex(where: { $0.id == c.id }) { characters[i] = c }
        else { characters.append(c) }
        save()
    }

    // MARK: Persistence

    /// Upsert by id + drop heroes no longer present. `intentionalDeletion` is set only
    /// by remove(); it's what makes an empty roster allowed to clear the store. Any
    /// OTHER save() with an empty roster (a stray/duplicate instance, an add/update
    /// that somehow ran on an empty list) refuses to wipe a non-empty store — so a
    /// second instance can never nuke your heroes.
    func save(intentionalDeletion: Bool = false) {
        let stored = (try? context.fetch(FetchDescriptor<StoredHero>())) ?? []

        if characters.isEmpty && !stored.isEmpty && !intentionalDeletion {
            print("⚠️ RosterStore: refused to wipe \(stored.count) stored hero(es) from an empty roster")
            return
        }

        var byID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for (i, c) in characters.enumerated() {
            guard let data = try? JSONEncoder().encode(c) else { continue }
            if let hero = byID.removeValue(forKey: c.id) {
                hero.data = data
                hero.order = i
            } else {
                context.insert(StoredHero(id: c.id, order: i, data: data))
            }
        }
        byID.values.forEach { context.delete($0) }

        do {
            try context.save()
            print("💾 RosterStore: saved \(characters.count) hero(es)")
        } catch {
            print("❌ RosterStore: save failed — \(error)")
        }
    }
}

// MARK: - Builder

struct CharacterBuilderView: View {
    let repo: ContentRepository
    var onCreate: (CharacterChoices) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var raceID = ""
    @State private var classID = ""
    @State private var pathID = ""

    private var paths: [PathDefinition] {
        (repo.klass(classID)?.pathIDs ?? []).compactMap { repo.path($0) }
    }
    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !raceID.isEmpty && !classID.isEmpty && !pathID.isEmpty
    }
    private var draft: CharacterChoices {
        CharacterChoices(name: name, raceID: raceID, classID: classID, pathID: pathID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Hero name", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section("Kind") {
                    Picker("Race", selection: $raceID) {
                        Text("Choose…").tag("")
                        ForEach(repo.races()) { Text($0.name).tag($0.id) }
                    }
                    if let race = repo.race(raceID) {
                        Text(race.tagline).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Class") {
                    Picker("Class", selection: $classID) {
                        Text("Choose…").tag("")
                        ForEach(repo.classes()) { Text($0.name).tag($0.id) }
                    }
                    .onChange(of: classID) { _, _ in pathID = "" }   // class drives paths; reset on change
                    if let cls = repo.klass(classID) {
                        Text(cls.role).font(.caption).foregroundStyle(.secondary)
                    }
                }

                if !classID.isEmpty {
                    Section("Path") {
                        Picker("Path", selection: $pathID) {
                            Text("Choose…").tag("")
                            ForEach(paths) { Text($0.name).tag($0.id) }
                        }
                        if let p = repo.path(pathID) {
                            Text(p.blurb).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if canCreate, let summary = startingSummary(for: draft, using: repo) {
                    Section("Starting out") { StartingSummaryRows(summary: summary) }
                }
            }
            .navigationTitle("New Hero")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { onCreate(makeHero()) }.disabled(!canCreate)
                }
            }
        }
    }

    private func makeHero() -> CharacterChoices {
        var c = draft
        let ids = startingGrants(classID: classID, pathID: pathID, repo: repo).map(\.spellID)
        c.spellbookIDs = ids
        c.readySpellIDs = ids        // L1: every starting spell is Ready (<= cap of 6)
        return c
    }
}


// MARK: - Shared summary rows (used in builder preview + hero summary)

struct StartingSummaryRows: View {
    let summary: StartingSummary

    var body: some View {
        LabeledContent("Might", value: "+\(summary.might)")
        LabeledContent("Mind",  value: "+\(summary.mind)")
        LabeledContent("Speed", value: "+\(summary.speed)")
        LabeledContent("HP",    value: "\(summary.hp)")
        if !summary.gearNames.isEmpty {
            LabeledContent("Gear", value: summary.gearNames.joined(separator: ", "))
        }
        if !summary.spells.isEmpty {
            ForEach(summary.spells, id: \.name) { spell in
                LabeledContent("Spell") {
                    Text("\(spell.name)  ×\(spell.uses)").foregroundStyle(.secondary)
                }
            }
        }
    }
}

// (RosterView removed — MainTabView is the app root and owns the single RosterStore.)
