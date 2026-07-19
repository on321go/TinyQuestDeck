//  SeenTokens.swift
//  The one-shot guard for grant tokens: which (nonce, hero) pairs this iPad has
//  already redeemed.
//
//  WHY USERDEFAULTS AND NOT SWIFTDATA. This is guard state, not game data — the same
//  category as AdventureView's scene position (view state, UserDefaults, no schema
//  change). It isn't part of a hero, it doesn't travel on a hero card, and losing it
//  costs exactly one re-scannable code. StoredShop/StoredParty earn their @Model
//  because they hold real content; a Set<String> doesn't. And a @Model means touching
//  Persistence.swift's Schema array — the one place in this app that can fail to open
//  the on-disk store (that's why the in-memory fallback exists). Putting migration
//  risk on the dedup guard of an honor-system feature is a bad trade.
//
//  THE KEY IS THE PAIR, NEVER THE NONCE ALONE. A party token (hero == nil) is ONE code
//  that every kid scans in turn. Keying on nonce alone tells the second hero on a
//  shared iPad that the code was already used — which is the exact bug this key shape
//  exists to prevent.
//
//  Not a cheat-cop: the threat model is a kid double-tapping, not forgery. No signing.

import Foundation

@MainActor
final class SeenTokens {
    /// Insertion-ordered so the cap can evict the oldest. Nonces carry no timestamp,
    /// so age is the only prunable axis we have.
    private var order: [String]
    private var seen: Set<String>

    private let defaults: UserDefaults
    private let key: String
    private let cap: Int

    /// Injectable for tests and for a throwaway store in previews.
    init(defaults: UserDefaults = .standard,
         key: String = "quest.seenGrantTokens",
         cap: Int = 500) {
        self.defaults = defaults
        self.key = key
        self.cap = cap
        order = defaults.stringArray(forKey: key) ?? []
        seen = Set(order)
        print("📂 SeenTokens: \(order.count) redeemed token(s) on file")
    }

    private static func pair(_ nonce: String, _ heroID: UUID) -> String {
        "\(nonce)|\(heroID.uuidString)"
    }

    func contains(nonce: String, heroID: UUID) -> Bool {
        seen.contains(Self.pair(nonce, heroID))
    }

    /// Test-and-set. Returns false if the pair was ALREADY marked — but callers should
    /// still gate on `contains` first, because a redeem has to validate the whole token
    /// (hero exists, content resolves) BEFORE burning the nonce.
    @discardableResult
    func mark(nonce: String, heroID: UUID) -> Bool {
        let k = Self.pair(nonce, heroID)
        guard seen.insert(k).inserted else { return false }
        order.append(k)
        if order.count > cap {
            let excess = order.count - cap
            for old in order.prefix(excess) { seen.remove(old) }
            order.removeFirst(excess)
        }
        defaults.set(order, forKey: key)
        print("💾 SeenTokens: marked \(k) (\(order.count) on file)")
        return true
    }

    #if DEBUG
    /// Re-scan the same code during a desk test without regenerating it.
    func reset() {
        order = []
        seen = []
        defaults.removeObject(forKey: key)
        print("⚠️ SeenTokens: cleared")
    }
    #endif
}
