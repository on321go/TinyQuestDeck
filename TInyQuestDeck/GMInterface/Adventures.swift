//  Adventures.swift
//  Story content — the GM's adventure modules as data. An Adventure is a hook,
//  a GM-only secret, and a list of scenes; a scene is read-aloud text the GM
//  performs, option lines with stat checks (display only — kids roll real dice),
//  GM notes, an optional fight, and reward lines.
//
//  THE KEY REUSE: a scene's fight is an `EncounterPreset` — the exact struct
//  encounters.json uses — so "Start this battle" hydrates through the same
//  hydrate(repo:) path as the Battle panel presets. One format, zero new
//  hydration code, and unknown monster/place refs degrade with the same
//  console warnings instead of crashes.
//
//  Rewards carry an optional gold amount that prefills the award composer;
//  item rewards are labels the GM grants through the composer's Item/Homebrew
//  tabs (keeps the schema thin — the composer already knows the catalog).

import Foundation

struct AdventureOption: Codable, Hashable {
    let label: String          // "Force the door"
    let check: String?         // "Might 13+" — display only, honor system
    let outcome: String        // what happens; read or paraphrase
}

struct AdventureReward: Codable, Hashable {
    let label: String          // "20 gold from the mayor"
    let gold: Int?             // prefills the composer's gold stepper when set
}

struct AdventureScene: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let readAloud: String      // performed to the kids
    let gmNotes: String?       // secrets & mechanics — GM eyes only
    let options: [AdventureOption]?
    let encounter: EncounterPreset?
    let rewards: [AdventureReward]?
}

struct Adventure: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let tone: String           // "Mystery — gentle, with funny moments"
    let length: String         // "30–45 minutes"
    let hook: String           // read-aloud opener
    let secret: String?        // "What's really going on" — GM only
    let scenes: [AdventureScene]
}

private struct AdventureFile: Codable { let adventures: [Adventure] }

@MainActor
@Observable
final class AdventureStore {
    private(set) var adventures: [Adventure] = []

    init() {
        guard let url = Bundle.main.url(forResource: "adventures", withExtension: "json") else {
            print("⚠️ AdventureStore: adventures.json not found in bundle")
            return
        }
        do {
            adventures = try JSONDecoder().decode(AdventureFile.self,
                                                  from: Data(contentsOf: url)).adventures
            print("📂 AdventureStore: loaded \(adventures.count) adventure(s)")
        } catch {
            print("❌ AdventureStore: failed to parse adventures.json — \(error)")
        }
    }
}
