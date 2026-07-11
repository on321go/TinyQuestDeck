//  Persistence.swift
//  The ONLY SwiftData-aware file in the app. CharacterChoices stays a pure Codable
//  value type everywhere; here it's stored as encoded Data inside a thin @Model
//  wrapper. Nothing else touches @Model, so the persistence framework never leaks
//  into the views, the derived sheet, or combat logic.
//
//  Because choices are the ONLY stored type (everything else is recomputed), the
//  migration surface is exactly CharacterChoices's stored fields — and nothing else.

import Foundation
import SwiftData

/// A saved hero: its id (for upserts), roster order, and the JSON-encoded choices.
@Model
final class StoredHero {
    @Attribute(.unique) var id: UUID
    var order: Int
    var data: Data          // JSONEncoder().encode(CharacterChoices)

    init(id: UUID, order: Int, data: Data) {
        self.id = id
        self.order = order
        self.data = data
    }
}

/// A saved combat snapshot (step 2 — persisted per hero so an interrupted fight
/// survives a quit). Keyed by the hero's id; the blob is the encoded CombatState.
@Model
final class StoredCombat {
    @Attribute(.unique) var heroID: UUID
    var data: Data          // JSONEncoder().encode(CombatState)

    init(heroID: UUID, data: Data) {
        self.heroID = heroID
        self.data = data
    }
}

enum PersistenceStore {
    /// One shared container for all saved data. If the on-disk store can't open
    /// (most often a schema change during development), fall back to an in-memory
    /// store so the app KEEPS RUNNING — this session just won't persist. The console
    /// warning is the cue to delete & relaunch to reset the on-disk store.
    static let container: ModelContainer = {
        let schema = Schema([StoredHero.self, StoredCombat.self])
        do {
            let container = try ModelContainer(for: schema)
            print("✅ Persistence: on-disk store ready")
            return container
        } catch {
            print("⚠️ Persistent store unavailable (\(error)). Using in-memory store — this session won't be saved. Delete & relaunch to reset.")
            let memory = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: memory)
        }
    }()
}
