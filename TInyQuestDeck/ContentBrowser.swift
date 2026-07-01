//  ContentBrowser.swift
//  First light: loads content.json from the app bundle, runs it through
//  ValidatingContentRepository, and shows what decoded. Throwaway diagnostic that
//  doubles as the seed for the character builder.
//
//  To see it: make ContentBrowserView() your root view temporarily, e.g.
//      WindowGroup { ContentBrowserView() }
//  in your App file. Swap back when you're done eyeballing it.

import SwiftUI

// MARK: - Store: load once, hold the repo or a readable error.

@MainActor
@Observable
final class ContentStore {
    var repo: ValidatingContentRepository?
    var error: String?

    func load() {
        guard let url = Bundle.main.url(forResource: "content", withExtension: "json") else {
            error = """
            content.json not found in the app bundle.
            Select it in the Project navigator, open the File inspector (right panel),
            and check your app under "Target Membership".
            """
            return
        }
        do {
            repo = try ContentLoader.load(from: url)
            error = nil
        } catch let e as ContentValidationError {
            error = e.description          // lists every broken reference / HP mismatch
        } catch {
            //error = "Failed to decode content.json:\n\(error)" as! any Error
        }
    }
}

// MARK: - Root

struct ContentBrowserView: View {
    @State private var store = ContentStore()

    var body: some View {
        NavigationStack {
            Group {
                if let repo = store.repo {
                    loaded(repo)
                } else if let error = store.error {
                    ScrollView {
                        Text(error)
                            .font(.callout.monospaced())
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                } else {
                    ProgressView("Loading content…")
                }
            }
            .navigationTitle("Content")
            .navigationDestination(for: ClassDefinition.self) { ClassDetailView(klass: $0, repo: store.repo!) }
            .navigationDestination(for: PathDefinition.self)  { PathDetailView(path: $0, repo: store.repo!) }
        }
        .onAppear { if store.repo == nil && store.error == nil { store.load() } }
    }

    @ViewBuilder
    private func loaded(_ repo: ValidatingContentRepository) -> some View {
        List {
            Section("Classes") {
                ForEach(repo.classes()) { klass in
                    NavigationLink(value: klass) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(klass.name).font(.headline)
                            Text(klass.role).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Races") {
                ForEach(repo.races()) { race in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(race.name).font(.headline)
                        Text(race.ability.name).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Class detail

struct ClassDetailView: View {
    let klass: ClassDefinition
    let repo: ValidatingContentRepository

    var body: some View {
        List {
            Section("Stats") {
                statRow("Might", klass.baseStats[.might])
                statRow("Mind",  klass.baseStats[.mind])
                statRow("Speed", klass.baseStats[.speed])
                LabeledContent("HP by level", value: klass.hpByLevel.map(String.init).joined(separator: " / "))
            }

            let core = klass.coreAbilityIDs.compactMap { repo.ability($0) }
            if !core.isEmpty {
                Section("Core abilities") { ForEach(core) { AbilityRow(ability: $0) } }
            }

            if !klass.baseSpells.isEmpty {
                Section("Starting spells") {
                    ForEach(klass.baseSpells, id: \.spellID) { grant in
                        if let spell = repo.spell(grant.spellID) {
                            LabeledContent {
                                Text("×\(grant.readyUses)").foregroundStyle(.secondary)
                            } label: {
                                Text(spell.name)
                            }
                        }
                    }
                }
            }

            Section("Paths") {
                ForEach(klass.pathIDs.compactMap { repo.path($0) }) { path in
                    NavigationLink(value: path) { Text(path.name) }
                }
            }
        }
        .navigationTitle(klass.name)
    }

    private func statRow(_ name: String, _ value: Int) -> some View {
        LabeledContent(name, value: "+\(value)")
    }
}

// MARK: - Path detail

struct PathDetailView: View {
    let path: PathDefinition
    let repo: ValidatingContentRepository

    var body: some View {
        List {
            Section { Text(path.blurb).font(.subheadline) }

            Section("Starting gear") {
                ForEach(path.startingGearIDs.compactMap { repo.gear($0) }) { gear in
                    LabeledContent(gear.name, value: gear.maxHP > 0 ? "+\(gear.maxHP) HP" : gear.category.rawValue)
                }
            }

            Section(path.pathPowerOptionIDs.count > 1 ? "Level 2 — choose one" : "Level 2 power") {
                ForEach(path.pathPowerOptionIDs.compactMap { repo.ability($0) }) { AbilityRow(ability: $0) }
            }

            Section("Level 3 — choose one") {
                ForEach(path.signatureOptionIDs.compactMap { repo.ability($0) }) { AbilityRow(ability: $0) }
            }

            if !path.specialSpells.isEmpty {
                Section("Themed spell pool") {
                    ForEach(path.specialSpells.compactMap { repo.spell($0) }) { Text($0.name) }
                }
            }
        }
        .navigationTitle(path.name)
    }
}

// MARK: - Shared

struct AbilityRow: View {
    let ability: AbilityDefinition
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(ability.name).font(.headline)
                Spacer()
                Text("\(ability.actionCost.rawValue) • \(ability.reset.rawValue)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(ability.text).font(.callout).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview { ContentBrowserView() }
