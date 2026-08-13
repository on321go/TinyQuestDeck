//  GMPhoneView.swift  (iPhone / compact — the Game Master cockpit)
//  The GM tab at phone width. PARALLEL VIEW, NOT A BRANCH: GMView.swift is
//  byte-identical; MainTabView selects this variant when horizontalSizeClass is
//  compact (iPhone, and an iPad in Split View / Slide Over).
//
//  Same cockpit, same order — rulebook shortcuts / Story / Battle / Party / Bench /
//  Ledger — with the rows that overflow 390pt restacked: the live-encounter card
//  puts CONTINUE on its own row, member cards shrink the portrait and chip, and
//  bench rows drop the damage line under the name. Story and Battle open the PHONE
//  full-screen covers (AdventurePhoneView / EncounterPhoneView).
//
//  Everything below the view layer is shared: the same stores, the same
//  AwardComposer / AddPartyMemberSheet / ScanHeroCardSheet / RuleSectionDetail.
//  PhoneGM mirrors GMStyle's constants (the StoryStyle-mirrors-BoardStyle call).
//
//  NO LAZY CONTAINERS on GM surfaces — the culling gotcha. Plain stacks throughout.

import SwiftUI

private enum PhoneGM {
    static let accent   = Color(hex: "8A4FD0")
    static let ink      = Color(hex: "5B3390")
    static let page     = Color(hex: "C9C4EC")
    static let pageTint = 0.45
    static let gold     = Color(hex: "C79008")

    static let cardWidth: CGFloat = 220   // story/preset cards — one full + a peek at 390pt
}

struct GMPhoneView: View {
    let repo: ContentRepository
    let roster: RosterStore
    let gm: GMStore
    let party: GMPartyStore
    let encounters: EncounterStore
    let adventures: AdventureStore
    let library: LibraryStore

    @State private var awarding: GMPartyMember? = nil
    @State private var shortcut: RuleSection? = nil
    @State private var showingBoard = false
    @State private var addingMember = false
    @State private var namingAdHoc = false
    @State private var adHocTitle = ""
    @State private var openAdventure: Adventure? = nil
    @State private var scanningHero = false
    @State private var awardingParty = false
    @State private var ledgerExpanded = false
    @State private var benchExpanded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    QuestChip(text: "Game Master", fill: PhoneGM.page, size: 18)
                    shortcutsRow
                    storyPanel
                    battlePanel
                    partyPanel
                    benchPanel
                    ledgerPanel
                }
                .padding(14)
            }
            .background(Color.white)
        }
        .onAppear { if library.books.isEmpty && library.error == nil { library.load() } }
        .sheet(item: $awarding) { member in
            AwardComposer(target: .one(member), repo: repo, roster: roster, gm: gm)
        }
        .sheet(isPresented: $awardingParty) {
            AwardComposer(target: .party(party.members), repo: repo, roster: roster, gm: gm)
        }
        .sheet(item: $shortcut) { section in
            NavigationStack { RuleSectionDetail(section: section, store: library) }
        }
        .sheet(isPresented: $addingMember) {
            AddPartyMemberSheet(repo: repo) { party.add($0) }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $scanningHero) {
            ScanHeroCardSheet(repo: repo,
                              existingIDs: Set(party.members.map(\.id))) { card in
                // update(), not add() — a re-scan after a level-up refreshes in place.
                party.update(GMPartyMember(card: card))
            }
        }
        .fullScreenCover(isPresented: $showingBoard) {
            EncounterPhoneView(repo: repo, store: encounters, party: party) { showingBoard = false }
        }
        .fullScreenCover(item: $openAdventure) { adv in
            AdventurePhoneView(adventure: adv, repo: repo, encounters: encounters,
                               party: party, roster: roster, gm: gm) { openAdventure = nil }
        }
        .alert("Name the fight!", isPresented: $namingAdHoc) {
            TextField("The Kitchen Ambush", text: $adHocTitle)
            Button("Start") {
                encounters.startAdHoc(title: adHocTitle)
                adHocTitle = ""
                showingBoard = true
            }
            Button("Cancel", role: .cancel) { adHocTitle = "" }
        }
    }

    // MARK: Rulebook shortcuts (same ids as the iPad cockpit)

    private static let shortcutIDs = [
        "gm-difficulty", "gm-stat-call", "gm-legendary", "gm-treasure",
    ]

    private func section(_ id: String) -> RuleSection? {
        library.section(id)
    }

    private var shortcutsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.shortcutIDs, id: \.self) { id in
                    if let s = section(id) {
                        Button { shortcut = s } label: {
                            Label(s.title, systemImage: s.icon)
                                .font(questFont(13)).foregroundStyle(.black)
                                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(PhoneGM.accent, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Story

    private var storyPanel: some View {
        panel("Story") {
            if adventures.adventures.isEmpty {
                Text("Adventure modules load from adventures.json — read-aloud scenes, checks, fights, and rewards, all launchable from one screen.")
                    .font(questFontLight(13)).foregroundStyle(.black.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(adventures.adventures) { adv in
                            Button { openAdventure = adv } label: { adventureCard(adv) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func adventureCard(_ a: Adventure) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(a.title, systemImage: "book.fill")
                .font(questFont(14)).foregroundStyle(.black)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(a.tone)
                .font(questFontLight(11)).foregroundStyle(.black.opacity(0.55))
                .lineLimit(2)
            Text("\(a.scenes.count) scenes · \(a.length)")
                .font(questFontLight(10)).foregroundStyle(.black.opacity(0.45))
        }
        .padding(11)
        .frame(width: PhoneGM.cardWidth, height: 92, alignment: .topLeading)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(PhoneGM.accent, lineWidth: 2))
    }

    // MARK: Battle

    private var battlePanel: some View {
        panel("Battle") {
            if let e = encounters.encounter {
                Button { showingBoard = true } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "flag.fill")
                                .font(.title3).foregroundStyle(TierColor.signature)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(e.title.uppercased())
                                    .font(questFont(16)).foregroundStyle(.black)
                                    .lineLimit(1).minimumScaleFactor(0.6)
                                Text("Round \(e.round) · \(e.standingMonsters) monster\(e.standingMonsters == 1 ? "" : "s") standing · \(e.places.count) places")
                                    .font(questFontLight(12)).foregroundStyle(.black.opacity(0.6))
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        Text("CONTINUE →")
                            .font(questFont(14)).foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(TierColor.selectPeach, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black, lineWidth: 2))
                    }
                    .padding(12)
                    .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.black, lineWidth: 2))
                }
                .buttonStyle(.plain)
            } else {
                // Plain horizontal row, NOT lazy — same disappearing-card protection
                // as the iPad cockpit.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(encounters.presets) { preset in
                            Button {
                                encounters.start(preset: preset, repo: repo)
                                showingBoard = true
                            } label: {
                                presetCard(preset)
                            }
                            .buttonStyle(.plain)
                        }
                        Button { namingAdHoc = true } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3).foregroundStyle(PhoneGM.accent)
                                Text("Build your own").font(questFont(13)).foregroundStyle(.black)
                                Text("Name it, add places as you go")
                                    .font(questFontLight(10)).foregroundStyle(.black.opacity(0.5))
                            }
                            .frame(width: 180, height: 92)
                            .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(.black.opacity(0.25),
                                              style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func presetCard(_ preset: EncounterPreset) -> some View {
        let locked = preset.places.filter { $0.parent != nil }.count
        let monsterCount = preset.monsters.reduce(0) { $0 + max(1, $1.count ?? 1) }
        return VStack(alignment: .leading, spacing: 5) {
            Text(preset.title).font(questFont(14)).foregroundStyle(.black)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text("\(preset.places.count - locked) places\(locked > 0 ? " + \(locked) locked" : "") · \(monsterCount) monster\(monsterCount == 1 ? "" : "s")")
                .font(questFontLight(11)).foregroundStyle(.black.opacity(0.55))
                .lineLimit(2)
            if locked > 0, let lock = preset.places.first(where: { $0.lock != nil })?.lock {
                Label(lock, systemImage: "lock.fill")
                    .font(questFontLight(10)).foregroundStyle(Color(hex: "B57B10"))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(11)
        .frame(width: PhoneGM.cardWidth, height: 92, alignment: .topLeading)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
    }

    // MARK: The Party

    private var partyPanel: some View {
        panel("The Party") {
            if party.members.isEmpty {
                Text("Who's playing this game? Scan the hero card on each player's Character Sheet, add the GM's own hero from this device, or add a player by hand.")
                    .font(questFontLight(13)).foregroundStyle(.black.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 12) {
                    ForEach(party.members) { memberCard($0) }
                }
            }
            addMemberMenu
            partyAwardButton
        }
    }

    private func localHero(for member: GMPartyMember) -> CharacterChoices? {
        roster.characters.first { $0.id == member.id }
    }

    /// The iPad card, shrunk: 48pt portrait, tighter type, a smaller chip. Same
    /// routing — the COMPOSER knows local from remote from unlinked; this card
    /// just says who was tapped.
    private func memberCard(_ member: GMPartyMember) -> some View {
        let local = localHero(for: member)
        let level = local?.level ?? member.level
        let combo = local?.portraitID ?? member.portraitCombo
            ?? QuestArtKey.portraitCombo(race: member.raceID ?? "", klass: member.classID)
        let className = repo.klass(member.classID)?.name ?? member.classID
        let isLocal = local != nil
        let awardable = isLocal || member.isLinked
        let tap: () -> Void = { awarding = member }

        return Button(action: tap) {
            HStack(spacing: 10) {
                QuestArt(name: QuestArtKey.portrait(combo: combo), ratio: QuestRatio.card,
                         colors: [PhoneGM.accent, PhoneGM.page], symbol: "person.fill",
                         caption: nil, framed: true)
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(member.name.uppercased())
                        .font(questFont(14)).foregroundStyle(.black)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("Lv \(level) · \(className)")
                        .font(questFontLight(12)).foregroundStyle(.black.opacity(0.65))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let local {
                        HStack(spacing: 4) {
                            Circle().fill(PhoneGM.gold).frame(width: 9, height: 9)
                            Text("\(local.gold)").font(questFont(12)).foregroundStyle(PhoneGM.gold)
                        }
                    } else {
                        Label("On their iPad", systemImage: "ipad")
                            .font(questFontLight(10)).foregroundStyle(PhoneGM.ink.opacity(0.7))
                    }
                }
                Spacer(minLength: 6)
                Label(chipTitle(local: isLocal, awardable: awardable),
                      systemImage: chipSymbol(local: isLocal, awardable: awardable))
                .font(questFont(12)).foregroundStyle(.black)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(awardable ? TierColor.selectPeach : Color(hex: "E8A020"),
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black, lineWidth: 2))
            }
            .padding(10)
            .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.black, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove \(member.name) from the party", role: .destructive) {
                party.remove(member)
            }
        }
    }

    private func chipTitle(local: Bool, awardable: Bool) -> String {
        if !awardable { return "Not linked" }
        return local ? "Award" : "Send"
    }

    private func chipSymbol(local: Bool, awardable: Bool) -> String {
        if !awardable { return "exclamationmark.triangle.fill" }
        return local ? "gift.fill" : "qrcode"
    }

    private var addMemberMenu: some View {
        let memberIDs = Set(party.members.map(\.id))
        let localCandidates = roster.characters.filter { !memberIDs.contains($0.id) }
        return Menu {
            if !localCandidates.isEmpty {
                Section("From this device") {
                    ForEach(localCandidates) { hero in
                        Button(hero.name) { party.add(GMPartyMember(hero: hero)) }
                    }
                }
            }
            Button("Scan a hero card…", systemImage: "qrcode.viewfinder") {
                scanningHero = true
            }
            Button("Add by hand…") { addingMember = true }
        } label: {
            Label("Add to the party", systemImage: "plus.circle.fill")
                .font(questFont(13)).foregroundStyle(PhoneGM.accent)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(PhoneGM.accent.opacity(0.5),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
        .buttonStyle(.plain)
    }

    private var partyAwardButton: some View {
        Button { awardingParty = true } label: {
            Label("Award the whole party…", systemImage: "person.3.fill")
                .font(questFont(13)).foregroundStyle(.black)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(TierColor.selectPeach, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(party.members.isEmpty)
    }

    // MARK: Monster bench — the damage line drops under the name at this width

    private var benchPanel: some View {
        collapsiblePanel("Monster Bench", isExpanded: $benchExpanded) {
            let byThreat = Dictionary(grouping: repo.monsters(), by: \.threat)
            ForEach(MonsterThreat.allCases, id: \.self) { threat in
                if let group = byThreat[threat], !group.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(threat.benchLabel.uppercased())
                            .font(questFont(12)).foregroundStyle(PhoneGM.ink.opacity(0.8))
                        VStack(spacing: 0) {
                            ForEach(Array(group.sorted { $0.hp < $1.hp }.enumerated()),
                                    id: \.element.id) { i, m in
                                if i > 0 { Divider().overlay(.black.opacity(0.12)) }
                                monsterRow(m)
                            }
                        }
                        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
                    }
                }
            }
        }
    }

    private func monsterRow(_ m: MonsterDefinition) -> some View {
        HStack(alignment: .center, spacing: 8) {
            TapInfo(payload: InfoPayload(
                title: m.name,
                subtitle: "HP \(m.hp) · +\(m.toHit) to hit · \(m.damageLine)",
                text: m.quirk, attack: nil, tint: PhoneGM.accent)
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name).font(questFont(14)).foregroundStyle(PhoneGM.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(m.damageLine)
                        .font(.caption2.monospaced()).foregroundStyle(.black.opacity(0.6))
                }
            }
            Spacer(minLength: 6)
            statPill("HP \(m.hp)")
            statPill("+\(m.toHit)")
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
    }

    private func statPill(_ text: String) -> some View {
        Text(text).font(questFont(11)).foregroundStyle(.black)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(.white, in: Capsule())
            .overlay(Capsule().strokeBorder(.black.opacity(0.25), lineWidth: 1))
    }

    // MARK: Ledger

    private var ledgerPanel: some View {
        collapsiblePanel("Award Ledger", count: gm.ledger.count, isExpanded: $ledgerExpanded) {
            if gm.ledger.isEmpty {
                Text("Every gold, star, and item award lands here, with a timestamp.")
                    .font(questFontLight(14)).foregroundStyle(.black.opacity(0.5))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(gm.ledger.prefix(25).enumerated()), id: \.element.id) { i, e in
                        if i > 0 { Divider().overlay(.black.opacity(0.12)) }
                        ledgerRow(e)
                    }
                }
                .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
                if gm.ledger.count > 25 {
                    Text("Showing the latest 25 of \(gm.ledger.count).")
                        .font(questFontLight(11)).foregroundStyle(.black.opacity(0.4))
                }
            }
        }
    }

    private func ledgerRow(_ e: GrantEntry) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(e.heroName) — \(e.kind.summary)")
                    .font(questFont(13)).foregroundStyle(.black)
                    .lineLimit(2).minimumScaleFactor(0.8)
                Text(e.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(questFontLight(10)).foregroundStyle(.black.opacity(0.5))
            }
            Spacer(minLength: 6)
            if case .gmTokenIssued = e.source {
                Label("code sent", systemImage: "qrcode")
                    .font(questFontLight(10)).foregroundStyle(.black.opacity(0.5))
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(.black.opacity(0.2), lineWidth: 1))
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
    }

    // MARK: Shared panel chrome (mirrors the iPad cockpit's)

    private func collapsiblePanel<Content: View>(_ title: String,
                                                 count: Int? = nil,
                                                 isExpanded: Binding<Bool>,
                                                 @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { isExpanded.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(title.uppercased()).font(questFont(16)).foregroundStyle(.black.opacity(0.8))
                    if let count {
                        Text("· \(count)").font(questFont(16)).foregroundStyle(.black.opacity(0.4))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black.opacity(0.4))
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                content()
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PhoneGM.page.opacity(PhoneGM.pageTint),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.black.opacity(0.12), lineWidth: 1.5))
    }

    private func panel<Content: View>(_ title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(questFont(16)).foregroundStyle(.black.opacity(0.8))
            content()
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PhoneGM.page.opacity(PhoneGM.pageTint),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.black.opacity(0.12), lineWidth: 1.5))
    }
}
