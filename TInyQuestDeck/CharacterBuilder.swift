//  CharacterBuilder.swift
//  The MVP loop: roster -> "+" -> pick race/class/path/name -> create -> back to roster.
//  In-memory only this pass (RosterStore). SwiftData persistence is step 4.
//
//  Make RosterView() your root: WindowGroup { RosterView() }

import SwiftUI

// MARK: - In-memory roster

@MainActor
@Observable
final class RosterStore {
    var characters: [CharacterChoices] = []
    func add(_ c: CharacterChoices) { characters.append(c) }
    func remove(at offsets: IndexSet) { characters.remove(atOffsets: offsets) }
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
