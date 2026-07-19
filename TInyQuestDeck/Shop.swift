//  Shop.swift
//  The buy vocabulary: a Purchasable (a gear entry OR a shop item) plus how a purchase
//  lands on a hero. Pure model — no SwiftUI, no persistence, no restock/stock logic yet
//  (StoredShop + restock arrive with the shop screen, once the UX is set). This is the
//  seam the shop grid/detail and the future Buy button will speak.
//
//  Buy is gold-gated ONLY: anyone can buy anything they can afford (a mage can own two
//  swords; a Knight can buy a scroll). What a purchase BECOMES can depend on the buyer —
//  a caster LEARNS a scroll (into their spellbook), a non-caster CARRIES it as a
//  one-shot item to use in a pinch or hand to the party's caster.
//
//  DEPENDS ON: `ownedGearIDs: [String]` on CharacterChoices (buy = own). This file will
//  not compile until that field exists — normalItems / magicItems / spellbookIDs / gold
//  are already present.

import Foundation

/// A single thing on a shop card. Cards group these by category for display; the unit
/// of purchase is one Purchasable.
public enum Purchasable: Identifiable, Hashable, Sendable {
    case gear(GearDefinition)
    case item(ItemDefinition)

    public var id: String {
        switch self {
        case .gear(let g): "gear:\(g.id)"
        case .item(let i): "item:\(i.id)"
        }
    }
    public var name: String {
        switch self { case .gear(let g): g.name; case .item(let i): i.name }
    }
    public var cost: Int {
        switch self {
        case .gear(let g): g.cost ?? Pricing.base(Pricing.group(for: g.category), g.rarity)
        case .item(let i): i.cost ?? Pricing.base(Pricing.group(for: i.kind), i.rarity)
        }
    }
    public var rarity: Rarity {
        switch self { case .gear(let g): g.rarity; case .item(let i): i.rarity }
    }
}

/// The concrete mutation a purchase makes to a hero. Resolved from a Purchasable + the
/// buyer (scrolls fork on caster-ness), then applied purely to CharacterChoices.
public enum PurchaseGrant: Hashable, Sendable {
    case gear(id: String)                        // → ownedGearIDs
    case consumable(name: String, magic: Bool)   // → normalItems / magicItems (free-text)
    case learnSpell(spellID: String)             
}

public enum ShopRules {
    /// A hero can hold spells in a book at all only if their class has a spell list.
        /// Computed off `classes()` so it doesn't depend on an optional by-id repo method.
        static func isCaster(_ hero: CharacterChoices, repo: ContentRepository) -> Bool {
            isCaster(classID: hero.classID, repo: repo)
        }

        /// The class-only form. The award composer needs this: for a hero on ANOTHER iPad
        /// there's no CharacterChoices to ask, but `GMPartyMember.classID` is the same
        /// value — so the "they'll learn it / they'll carry it" note reads identically for
        /// local and remote targets.
        ///
        /// It's only ever a PREDICTION. The actual scroll fork happens in
        /// `ShopRules.grant(for:buyer:)` on the device that redeems, against the real hero.
        /// That's precisely why a token carries the content id and not a resolved grant.
        static func isCaster(classID: String, repo: ContentRepository) -> Bool {
            repo.classes().first { $0.id == classID }?.spellListID != nil
        }

    /// Gold is the only gate. Returns the shortfall (> 0) when unaffordable, else nil.
    static func shortfall(buying p: Purchasable, hero: CharacterChoices) -> Int? {
        let short = p.cost - hero.gold
        return short > 0 ? short : nil
    }

    /// What this purchase becomes for THIS buyer. Scrolls: a caster learns the spell;
    /// a non-caster carries the scroll as a magic one-shot (honor-system use / giftable).
    static func grant(for p: Purchasable, buyer: CharacterChoices, repo: ContentRepository) -> PurchaseGrant {
        switch p {
        case .gear(let g):
            return .gear(id: g.id)
        case .item(let i):
            switch i.kind {
            case .consumable:
                return .consumable(name: i.name, magic: false)
            case .magicConsumable, .curio:
                return .consumable(name: i.name, magic: true)
            case .scroll:
                // SCROLLS ENTITLE, THE CASTER CLAIMS — the star rule, applied to objects.
                //
                // A scroll is ALWAYS an object. It used to fork right here: a caster's
                // scroll became a spellbook line at the moment of purchase, which meant
                // the kid never owned a scroll and never got asked. Nothing left to hand
                // a friend, nothing to save for later, no undo — the register decided.
                //
                // Now acquiring only ever ADDS the object (same invariant as awards:
                // "awards only ever add ownership"). `CharacterChoices.learn(scroll:)`
                // is the claim, and it's the kid's tap. `spellID` is still on the
                // definition; the sheet resolves it by the name-match rule when the
                // caster decides.
                return .consumable(name: i.name, magic: true)
            }
        }
    }
}

extension CharacterChoices {
    /// Apply a resolved grant. Pure "add what was bought" — deduct gold at the call site
    /// (the Buy handler) so this stays a single-purpose step:
    ///
    ///     guard ShopRules.shortfall(buying: p, hero: c) == nil else { return }
    ///     let grant = ShopRules.grant(for: p, buyer: c, repo: repo)
    ///     c.gold -= p.cost
    ///     c.receive(grant)
    ///     roster.update(c)
    ///
    /// Scroll-learn drops the spell into the spellbook (not auto-Ready) — the kid readies
    /// it via the sheet's existing spell menu, same as any found spell.
    mutating func receive(_ grant: PurchaseGrant) {
        switch grant {
        case .gear(let id):
            ownedGearIDs.append(id)
        case .consumable(let name, let magic):
            if magic { magicItems.append(name) } else { normalItems.append(name) }
        case .learnSpell(let spellID):
            if !spellbookIDs.contains(spellID) { spellbookIDs.append(spellID) }
        }
    }
    /// THE choke point — every acquisition (purchase, loot, GM token, adventure reward)
      /// goes through here. Gating later = an auth check in this one function; the ledger
      /// hangs here too.
      mutating func acquire(_ p: Purchasable, source: GrantSource, repo: ContentRepository) {
          receive(ShopRules.grant(for: p, buyer: self, repo: repo))
          // later: ledger.append(GrantEntry(item: p.id, source: source, at: .now))
      }
    
    /// THE CLAIM — the third hand-changing verb, beside `acquire` and `release`.
        /// A scroll the hero is holding becomes a spell they know.
        ///
        /// KID-INITIATED, ALWAYS. Nothing else in the app may call this: acquire adds the
        /// object, and this is the only thing that spends it. Same invariant the star track
        /// runs on — the entitlement arrives on its own, the build change never does.
        ///
        /// Routes through `receive(.learnSpell:)` rather than touching `spellbookIDs`
        /// directly, so the mechanism stays in one place. That case is no longer something
        /// the shop does TO a buyer; it's what a caster chooses.
        ///
        /// Matched by NAME — the same rule that auto-upgrades a homebrew item when it's
        /// promoted into content under the same name. Duplicates spend one copy, exactly
        /// like `release`. Returns false if the hero isn't holding it (a stale row).
        @discardableResult
        mutating func learn(scroll name: String, spellID: String) -> Bool {
            guard let i = magicItems.firstIndex(of: name) else { return false }
            magicItems.remove(at: i)
            receive(.learnSpell(spellID: spellID))   // not auto-Ready — the kid readies it
            return true
        }
}

/// Where an acquisition came from. The tag every future gate + audit log reads.
public enum GrantSource: Hashable, Sendable, Codable {
    case purchase, foundLoot, adventure
    /// The hero RECEIVED this — a token was redeemed on the device the hero lives on.
    case gmToken(String)
    /// The GM ISSUED a token addressed to this hero; whether it was ever scanned is
    /// unknowable from this device. Only ever written on the GM's iPad, and it's the
    /// honest tag for the ledger's remote and party rows. Adding a CASE is safe for
    /// stored blobs (no existing row contains it); mutating an existing one is not —
    /// GMStore.init decodes with `try?`, so a keyNotFound silently DROPS the row.
    case gmTokenIssued(String)
}

extension Purchasable {
    /// What the shop pays: half, rounded down. The loss is the point — a buy/sell loop
    /// is always net negative, so there's nothing to exploit.
    var sellPrice: Int { cost / 2 }
}

extension Purchasable {
    /// The inverse of `id`. "gear:long-sword" / "item:healing-potion" back to the thing.
    ///
    /// THE PREFIX IS THE DISCRIMINATOR, and it has been on the wire since the ledger's
    /// first row — `GMStore.award` records `.purchasable(id: p.id, ...)`, which is this
    /// namespaced form, not the raw content id. That's what lets a grant token carry a
    /// bare id and resolve unambiguously on the kid's device: gear ids and item ids live
    /// in different namespaces that could otherwise collide.
    ///
    /// nil = this device's content.json doesn't have it (a token from a newer build, or
    /// homebrew that was never promoted). Callers report it; nothing crashes.
    static func resolve(_ id: String, repo: ContentRepository) -> Purchasable? {
        guard let sep = id.firstIndex(of: ":") else { return nil }
        let rest = String(id[id.index(after: sep)...])
        switch id[id.startIndex ..< sep] {
        case "gear": return repo.gear(rest).map(Purchasable.gear)
        case "item": return repo.item(rest).map(Purchasable.item)
        default:     return nil
        }
    }
}

extension ShopRules {
    /// What a hero can sell: OWNED gear only. The starting kit isn't in ownedGearIDs
    /// (you can't sell your kit), and items are free-text names — homebrew/unofficial
    /// stuff a shop wouldn't buy. Duplicates list once per copy; each row sells one.
    static func sellable(for hero: CharacterChoices, repo: ContentRepository) -> [Purchasable] {
        hero.ownedGearIDs
            .compactMap { repo.gear($0) }
            .map(Purchasable.gear)
            .sorted { $0.name < $1.name }
    }
}

extension CharacterChoices {
    /// THE way things leave a hero — the mirror of `acquire`. Sweeps every array that can
    /// reference the gear, because equipped/showcase resolve from the repo (not from
    /// ownedGearIDs), so a sold sword would otherwise stay equipped and stay on the shelf.
    /// Only strips those if the hero no longer owns a copy AND it isn't kit gear — selling
    /// a spare long sword must never unequip the free one the path grants.
    mutating func release(_ p: Purchasable, source: GrantSource, repo: ContentRepository) {
        gold += p.sellPrice
        guard case .gear(let g) = p else { return }   // items aren't sellable
        if let i = ownedGearIDs.firstIndex(of: g.id) { ownedGearIDs.remove(at: i) }
        let kitIDs = Set(repo.path(pathID)?.startingGearIDs ?? [])
        if !ownedGearIDs.contains(g.id) && !kitIDs.contains(g.id) {
            equippedGearIDs.removeAll { $0 == g.id }
            showcaseGearIDs.removeAll { $0 == g.id }
        }
        // later: ledger.append(GrantEntry(item: p.id, source: source, at: .now))
    }
}
