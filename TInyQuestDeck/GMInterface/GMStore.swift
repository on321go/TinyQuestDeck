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
///
/// Adding a case is safe for the stored ledger: old StoredGrant blobs never contain
/// it, and Swift's synthesized enum Codable keys on the case name, so nothing already
/// written re-reads differently.
enum GrantKind: Codable, Hashable, Sendable {
    case gold(Int)
    case purchasable(id: String, name: String)
    case homebrew(name: String, magic: Bool)
    /// Progression. Almost always 1 — quest, boss, or a rare individual bonus.
    /// Party-wide awards write ONE row per hero (see `awardStar(_:to:roster:)`), so
    /// the ledger reads as "who has what," not "what did I announce."
    case star(Int)
}

extension GrantKind {
    /// One line, GM voice. The ledger row and the token sheet both say this — there is
    /// exactly one GM-facing description of a kind. (RedeemSheet's `describe` is the
    /// KID's voice for the same enum: "A star!" vs "+1 star". Same data, different
    /// room — don't merge those.)
    var summary: String {
        switch self {
        case .gold(let n):                   n >= 0 ? "+\(n) gold" : "\(n) gold"
        case .purchasable(_, let name):      name
        case .homebrew(let name, let magic): "\(name)\(magic ? " ✦" : "") · homebrew"
        case .star(let n):                   "\(n >= 0 ? "+" : "")\(n) star\(abs(n) == 1 ? "" : "s")"
        }
    }
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

/// What a redeem did, in terms the kid-facing sheet can render directly.
enum RedeemResult: Equatable {
    case applied(String)            // the award, kid-readable ("+25 gold", "Rope of Climbing")
    case alreadyRedeemed            // this (nonce, hero) pair — not this nonce
    case wrongHero(String?)         // the name on the token, when it carried one
    case unknownContent(String)     // an id this device's content.json doesn't have
    case noHero                     // the hero vanished between scan and tap
}

// MARK: - Store

@MainActor
@Observable
final class GMStore {
    /// Newest first. Append-only — nothing in the app edits or deletes a ledger row.
    private(set) var ledger: [GrantEntry] = []
    
    @ObservationIgnored private let context: ModelContext
    /// The one-shot guard. Device-local, UserDefaults-backed — see SeenTokens.swift.
    @ObservationIgnored private let seen = SeenTokens()
    
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
    func awardGold(_ amount: Int, to heroID: UUID, roster: RosterStore,
                   source: GrantSource = .adventure) {
        guard amount != 0, var hero = roster.characters.first(where: { $0.id == heroID }) else { return }
        hero.gold = max(0, hero.gold + amount)
        roster.update(hero)
        record(GrantEntry(heroID: heroID, heroName: hero.name,
                          kind: .gold(amount), source: source, timestamp: .now))
    }

    /// Award (or take back) stars. Clamped at 0, uncapped upward — the track only
    /// draws 6, but extras bank quietly for thresholds that don't exist yet.
    ///
    /// Deliberately does NOT touch `level`: stars entitle, the kid claims. The sheet's
    /// level badge lights from `hero.canLevelUp` and the existing point-spend flow does
    /// the rest, so a star award can never silently change a hero's build.
    func awardStar(_ amount: Int = 1, to heroID: UUID, roster: RosterStore,
                   source: GrantSource = .adventure) {
        guard amount != 0, var hero = roster.characters.first(where: { $0.id == heroID }) else { return }
        hero.stars = max(0, hero.stars + amount)
        roster.update(hero)
        record(GrantEntry(heroID: heroID, heroName: hero.name,
                          kind: .star(amount), source: source, timestamp: .now))
    }
    
    /// The party-wide case — quest and boss stars, which are party-wide ALWAYS
    /// (the sibling-proofing rule). One call, one row per hero, so the ledger can
    /// still answer "does this hero have their star?" for each kid independently.
    /// Heroes that no longer exist are skipped by the single-hero writer.
    func awardStar(_ amount: Int = 1, toParty heroIDs: [UUID], roster: RosterStore,
                   source: GrantSource = .adventure) {
        for heroID in heroIDs { awardStar(amount, to: heroID, roster: roster, source: source) }
    }

    /// Award official content — the same acquire() the shop's Buy uses, tagged
    /// .adventure. Scrolls fork on caster-ness exactly like a purchase (a caster
    /// learns it, a non-caster carries it); gear lands in ownedGearIDs, never
    /// auto-equipped — the kid equips from the sheet's Owned section, same as a buy.
    func award(_ p: Purchasable, to heroID: UUID, roster: RosterStore,
               repo: ContentRepository, source: GrantSource = .adventure) {
        guard var hero = roster.characters.first(where: { $0.id == heroID }) else { return }
        hero.acquire(p, source: source, repo: repo)
        roster.update(hero)
        record(GrantEntry(heroID: heroID, heroName: hero.name,
                          kind: .purchasable(id: p.id, name: p.name),
                          source: source, timestamp: .now))
    }
    
    /// Award a homebrew (free-text) item. Lands in Normal/Magic Items by name —
    /// exactly like typing it on the sheet, but with provenance. If the item is later
    /// promoted into content.json under the same exact name, it auto-upgrades on
    /// every hero carrying it (the name-match rule) with no ledger rewrite needed.
    func awardHomebrew(_ name: String, magic: Bool, to heroID: UUID, roster: RosterStore,
                       source: GrantSource = .adventure) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              var hero = roster.characters.first(where: { $0.id == heroID }) else { return }
        if magic { hero.magicItems.append(trimmed) } else { hero.normalItems.append(trimmed) }
        roster.update(hero)
        record(GrantEntry(heroID: heroID, heroName: hero.name,
                          kind: .homebrew(name: trimmed, magic: magic),
                          source: source, timestamp: .now))
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
    
    // MARK: Tokens (the ONE apply path — two transports)

        /// Apply a token to a hero on THIS device. Every award in the app lands here:
        /// the composer's Give builds a token and redeems it in-process (no code, no
        /// camera — an iPad can't scan its own screen), and a scanned code redeems the
        /// identical struct. The QR is transport, not the award.
        ///
        /// A dispatcher, deliberately — NOT a reimplementation. The four writers above own
        /// the roster lookup, the clamp, the ledger row, and the never-touch-`level`
        /// invariant; they're proven, so redeem's job is only dedup + source + validation.
        ///
        /// THE INVARIANT SURVIVES: `.star` routes through `awardStar`, which touches `stars`
        /// and nothing else. Redeeming a star can only make `canLevelUp` true. A token can
        /// never silently change a hero's build.
        @discardableResult
        func redeem(_ token: GrantToken, on heroID: UUID,
                    roster: RosterStore, repo: ContentRepository) -> RedeemResult {
            // Validate EVERYTHING before burning the nonce — after this, apply can't fail.
            guard token.addresses(heroID) else { return .wrongHero(token.heroName) }
            guard let hero = roster.characters.first(where: { $0.id == heroID }) else { return .noHero }
            guard !seen.contains(nonce: token.nonce, heroID: heroID) else { return .alreadyRedeemed }

            let source = GrantSource.gmToken(token.nonce)
            let line: String

            switch token.kind {
            case .gold(let n):
                awardGold(n, to: heroID, roster: roster, source: source)
                line = "\(n >= 0 ? "+" : "")\(n) gold"
            case .star(let n):
                awardStar(n, to: heroID, roster: roster, source: source)
                line = "\(n >= 0 ? "+" : "")\(n) star\(abs(n) == 1 ? "" : "s")"
            case .purchasable(let id, let name):
                // Resolved from THIS device's content — the token carried an id, not a thing.
                guard let p = Purchasable.resolve(id, repo: repo) else { return .unknownContent(name) }
                award(p, to: heroID, roster: roster, repo: repo, source: source)
                line = p.name
            case .homebrew(let name, let magic):
                awardHomebrew(name, magic: magic, to: heroID, roster: roster, source: source)
                line = name
            }

            seen.mark(nonce: token.nonce, heroID: heroID)
            print("💾 GMStore: redeemed \(token.nonce.prefix(8)) → \(hero.name) (\(line))")
            return .applied(line)
        }

        /// The GM's side of a REMOTE award: build the token and record it as ISSUED. Nothing
        /// lands on a hero here — the hero isn't on this iPad. The caller renders the token
        /// as a QR; the kid's device is where `redeem` (and the truth) happens.
        ///
        /// The row is `.gmTokenIssued`, not `.gmToken`, on purpose: the GM's ledger can
        /// honestly say "I gave this out," never "they got it." The ledger is transparency,
        /// not a cheat-cop.
        func issue(_ kind: GrantKind, to member: GMPartyMember) -> GrantToken {
            let token = GrantToken.single(kind, hero: member.id, name: member.name)
            record(GrantEntry(heroID: member.id, heroName: member.name, kind: kind,
                              source: .gmTokenIssued(token.nonce), timestamp: .now))
            print("💾 GMStore: issued \(token.nonce.prefix(8)) → \(member.name)")
            return token
        }
    
    /// ONE token, addressed to nobody. Every kid scans it in turn and `(nonce, heroID)`
        /// makes it land exactly once each — which is the whole reason the dedup key is a
        /// pair. Keying on nonce alone would tell the second kid it was already used.
        ///
        /// LOCAL MEMBERS REDEEM RIGHT HERE. Not a shortcut: they physically cannot scan this
        /// iPad's own screen, so there is no transport for them and none is needed. Same
        /// token, in-process — the two-transports rule, applied per member instead of per
        /// award.
        ///
        /// Unlinked members are skipped silently. There's no hero id to address and no row
        /// worth writing; the party panel already flags them in amber.
        ///
        /// Returns nil when nobody needs the code — every member was local, it already
        /// landed, and there is nothing to hold up.
        @discardableResult
        func issueToParty(_ kind: GrantKind, members: [GMPartyMember],
                          roster: RosterStore, repo: ContentRepository) -> GrantToken? {
            let token = GrantToken.party(kind)
            var needsCode = false
            var landed = 0

            for m in members {
                if roster.characters.contains(where: { $0.id == m.id }) {
                    redeem(token, on: m.id, roster: roster, repo: repo)
                    landed += 1
                } else if m.isLinked {
                    // "Sent," not "received" — same honesty as `issue`. One row per member
                    // so the ledger keeps answering "does THIS kid have their star."
                    record(GrantEntry(heroID: m.id, heroName: m.name, kind: kind,
                                      source: .gmTokenIssued(token.nonce), timestamp: .now))
                    needsCode = true
                }
            }

            print("💾 GMStore: party \(kind.summary) — \(landed) here, code needed: \(needsCode)")
            return needsCode ? token : nil
        }
}
