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
//  Make RosterView() your root: WindowGroup { RosterView() }

import SwiftUI
import SwiftData

// MARK: - Persisted roster

@MainActor
@Observable
final class RosterStore {
    /// Observable source of truth for the UI. Mutating it (anywhere — including the
    /// update(_:)/remove(_:) extensions) writes through to SwiftData via didSet.
    var characters: [CharacterChoices] = [] {
        didSet { if ready { persist() } }
    }

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var ready = false     // gate: don't persist during initial load

    init() {
        context = ModelContext(PersistenceStore.container)
        load()
        ready = true
    }

    func add(_ c: CharacterChoices) { characters.append(c) }
    func remove(at offsets: IndexSet) { characters.remove(atOffsets: offsets) }

    // MARK: Persistence (private — the only SwiftData contact point)

    /// Load saved heroes in roster order. Decode failures are skipped, not fatal, so
    /// one corrupt blob can't take down the whole roster.
    private func load() {
        let descriptor = FetchDescriptor<StoredHero>(sortBy: [SortDescriptor(\.order)])
        let stored = (try? context.fetch(descriptor)) ?? []
        characters = stored.compactMap {
            try? JSONDecoder().decode(CharacterChoices.self, from: $0.data)
        }
    }

    /// Upsert by id + drop heroes no longer present. Upserting (rather than
    /// delete-all-then-reinsert) avoids a unique-id conflict within one save and
    /// keeps this cheap for a small roster.
    private func persist() {
        let stored = (try? context.fetch(FetchDescriptor<StoredHero>())) ?? []
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
        // Anything still in byID isn't in the roster anymore → delete it.
        byID.values.forEach { context.delete($0) }

        try? context.save()
    }
}

// MARK: - Root

struct RosterView: View {
    @State private var content = ContentStore()      // reused from ContentBrowser.swift
    @State private var roster = RosterStore()
    @State private var combat = CombatStore()
    @State private var building = false

    var body: some View {
        NavigationStack {
            Group {
                if let repo = content.repo {
                    rosterList(repo)
                } else if let error = content.error {
                    ScrollView {
                        Text(error).font(.callout.monospaced()).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading).padding()
                    }
                } else {
                    ProgressView("Loading content…")
                }
            }
            .navigationTitle("Heroes")
            .toolbar {
                if content.repo != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button { building = true } label: { Label("New Hero", systemImage: "plus") }
                    }
                }
            }
            .navigationDestination(for: CharacterChoices.self) { c in
                // TEMP: old play sheet deleted; new character sheet is next up
                Text(c.name).font(.largeTitle)
            }
            .fullScreenCover(isPresented: $building) {
                if let repo = content.repo {
                    CreationFlowView(repo: repo) { newHero in
                        roster.add(newHero)
                        building = false
                    }
                }
            }
        }
        .onAppear { if content.repo == nil && content.error == nil { content.load() } }
    }

    @ViewBuilder
    private func rosterList(_ repo: ContentRepository) -> some View {
        if roster.characters.isEmpty {
            ContentUnavailableView {
                Label("No heroes yet", systemImage: "person.crop.circle.badge.plus")
            } description: {
                Text("Tap + to make your first hero.")
            } actions: {
                Button("New Hero") { building = true }.buttonStyle(.borderedProminent)
            }
        } else {
            HeroGrid(characters: roster.characters, repo: repo) { roster.remove($0) }
        }
    }

    private func subtitle(for c: CharacterChoices, repo: ContentRepository) -> String {
        let race = repo.race(c.raceID)?.name ?? c.raceID
        let cls = repo.klass(c.classID)?.name ?? c.classID
        let path = repo.path(c.pathID)?.name ?? c.pathID
        return "\(race) · \(cls) — \(path)"
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

#Preview { RosterView() }
