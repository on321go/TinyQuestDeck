//  GMView.swift  (v2 — battle + party rework)
//  The Game Master tab — the cockpit a GM navigates a game from. Top to bottom:
//
//    • GM rulebook shortcuts (§7.1.5) — difficulty / stat-call / Legendary tables.
//      ("Monsters" shortcut REMOVED: the bench below is the live bestiary; the
//      rulebook table is the printable copy.)
//    • Battle (§7.1.1) — the live encounter card (resume) or the preset picker /
//      ad-hoc start. The board itself is EncounterView, full-screen.
//    • The Party — GMPartyStore members (NOT the local roster: on a dedicated GM
//      iPad the kids' heroes live on THEIR iPad). Members are added from a local
//      hero (the GM's own) or by hand; the QR hero-card scan lands here next and
//      fills the same records with real hero ids.
//    • Monster bench (§7.1.2) — browse; the improviser lives on the board's
//      "+ Fighter" menu, where its output has somewhere to land.
//    • Award ledger (§7.1.3).
//
//  Awards: direct grant when the member's hero exists in the LOCAL roster (the
//  GM's own hero, or a shared-iPad family); otherwise the composer explains that
//  QR delivery is the next layer. Story scenes (adventures.json) slot in above
//  Battle when they land.

import SwiftUI

// MARK: - Tunable palette (GM purple family — matches the rulebook's GM half)

private enum GMStyle {
    static let accent   = Color(hex: "8A4FD0")
    static let ink      = Color(hex: "5B3390")
    static let page     = Color(hex: "C9C4EC")
    static let pageTint = 0.45
    static let gold     = Color(hex: "C79008")
}

// MARK: - Root

struct GMView: View {
    let repo: ContentRepository
    let roster: RosterStore
    let gm: GMStore
    let party: GMPartyStore
    let encounters: EncounterStore
    let adventures: AdventureStore
    let rulebook: RulebookStore

    @State private var awarding: GMPartyMember? = nil
    @State private var shortcut: RuleSection? = nil
    @State private var showingBoard = false
    @State private var addingMember = false
    @State private var namingAdHoc = false
    @State private var adHocTitle = ""
    @State private var openAdventure: Adventure? = nil
    @State private var scanningHero = false
    @State private var awardingParty = false


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    QuestChip(text: "Game Master", fill: GMStyle.page, size: 22)
                    shortcutsRow
                    storyPanel
                    battlePanel
                    partyPanel
                    benchPanel
                    ledgerPanel
                }
                .padding(20)
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
            }
            .background(Color.white)
        }
        .onAppear { if rulebook.rulebook == nil && rulebook.error == nil { rulebook.load() } }
        .sheet(item: $awarding) { member in
                    AwardComposer(target: .one(member), repo: repo, roster: roster, gm: gm)
                }
                .sheet(isPresented: $awardingParty) {
                    AwardComposer(target: .party(party.members), repo: repo, roster: roster, gm: gm)
                }
        .sheet(item: $shortcut) { section in
            NavigationStack { RuleSectionDetail(section: section, store: rulebook) }
        }
        .sheet(isPresented: $addingMember) {
            AddPartyMemberSheet(repo: repo) { party.add($0) }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $scanningHero) {
            ScanHeroCardSheet(repo: repo,
                              existingIDs: Set(party.members.map(\.id))) { card in
                // update(), not add(): same id = same hero, so a re-scan after a
                // level-up refreshes the snapshot in place. add() would no-op.
                party.update(GMPartyMember(card: card))
            }
        }
        .fullScreenCover(isPresented: $showingBoard) {
            EncounterView(repo: repo, store: encounters, party: party) { showingBoard = false }
        }
        .fullScreenCover(item: $openAdventure) { adv in
            AdventureView(adventure: adv, repo: repo, encounters: encounters,
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
//        .alert(item: $remoteNoteFor) { member in
//            Alert(title: Text("\(member.name) lives on another iPad"),
//                  message: Text("Their hero isn't on this device, so awards can't land here directly. QR delivery — you show a code, they scan it — is the next layer. For now, use the sheet's gold stepper and Found-on-an-Adventure menu on their iPad."),
//                  dismissButton: .default(Text("Got it")))
//        }
    }

    // MARK: Rulebook shortcuts (gm-monsters removed — the bench IS the live version)

    private static let shortcutIDs = [
        "gm-difficulty", "gm-stat-call", "gm-legendary", "gm-treasure",
    ]

    private func section(_ id: String) -> RuleSection? {
        rulebook.rulebook?.sections.first { $0.id == id }
    }

    private var shortcutsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Self.shortcutIDs, id: \.self) { id in
                    if let s = section(id) {
                        Button { shortcut = s } label: {
                            Label(s.title, systemImage: s.icon)
                                .font(questFont(14)).foregroundStyle(.black)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(GMStyle.accent, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Story — the adventure modules (adventures.json). The top of the
    // cockpit: pick a module, read scenes, launch its fights onto the board.

    private var storyPanel: some View {
        panel("Story") {
            if adventures.adventures.isEmpty {
                Text("Adventure modules load from adventures.json — read-aloud scenes, checks, fights, and rewards, all launchable from one screen.")
                    .font(questFontLight(14)).foregroundStyle(.black.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
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
                .font(questFont(15)).foregroundStyle(.black)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(a.tone)
                .font(questFontLight(12)).foregroundStyle(.black.opacity(0.55))
                .lineLimit(2)
            Text("\(a.scenes.count) scenes · \(a.length)")
                .font(questFontLight(11)).foregroundStyle(.black.opacity(0.45))
        }
        .padding(12)
        .frame(width: 235, height: 96, alignment: .topLeading)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(GMStyle.accent, lineWidth: 2))
    }

    // MARK: Battle (§7.1.1 — the centerpiece)

    private var battlePanel: some View {
        panel("Battle") {
            if let e = encounters.encounter {
                Button { showingBoard = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "flag.fill")
                            .font(.title2).foregroundStyle(TierColor.signature)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(e.title.uppercased())
                                .font(questFont(18)).foregroundStyle(.black)
                            Text("Round \(e.round) · \(e.standingMonsters) monster\(e.standingMonsters == 1 ? "" : "s") standing · \(e.places.count) places")
                                .font(questFontLight(13)).foregroundStyle(.black.opacity(0.6))
                        }
                        Spacer()
                        Text("CONTINUE →").font(questFont(15)).foregroundStyle(.black)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(TierColor.selectPeach, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black, lineWidth: 2))
                    }
                    .padding(14)
                    .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.black, lineWidth: 2))
                }
                .buttonStyle(.plain)
            } else {
                // A plain horizontal row, NOT a LazyVGrid — lazy containers were
                // culling preset cards on scroll and never bringing them back
                // (same family as the old portrait-gallery bug). Seven small
                // cards need no laziness; deterministic wins.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
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
                                    .font(.title2).foregroundStyle(GMStyle.accent)
                                Text("Build your own").font(questFont(14)).foregroundStyle(.black)
                                Text("Name it, add places as you go")
                                    .font(questFontLight(11)).foregroundStyle(.black.opacity(0.5))
                            }
                            .frame(width: 210, height: 96)
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
            Text(preset.title).font(questFont(15)).foregroundStyle(.black)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text("\(preset.places.count - locked) places\(locked > 0 ? " + \(locked) locked" : "") · \(monsterCount) monster\(monsterCount == 1 ? "" : "s")")
                .font(questFontLight(12)).foregroundStyle(.black.opacity(0.55))
            if locked > 0, let lock = preset.places.first(where: { $0.lock != nil })?.lock {
                Label(lock, systemImage: "lock.fill")
                    .font(questFontLight(11)).foregroundStyle(Color(hex: "B57B10"))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(12)
        .frame(width: 235, height: 96, alignment: .topLeading)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
    }

    // MARK: The Party (GMPartyStore — the QR hero-card import target)

    private var partyPanel: some View {
        panel("The Party") {
            if party.members.isEmpty {
                Text("Who's playing this game? Scan the hero card on each player's Character Sheet, add the GM's own hero from this iPad, or add a player by hand.")
                    .font(questFontLight(14)).foregroundStyle(.black.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Plain VStack, not a LazyVGrid — same disappearing-card
                // protection as the preset row. A party is a handful of rows.
                VStack(spacing: 14) {
                    ForEach(party.members) { memberCard($0) }
                }
            }
            addMemberMenu
            partyAwardButton
        }
    }

    /// A member whose hero lives in the LOCAL roster (GM's own hero / shared iPad).
    private func localHero(for member: GMPartyMember) -> CharacterChoices? {
        roster.characters.first { $0.id == member.id }
    }

    private func memberCard(_ member: GMPartyMember) -> some View {
        let local = localHero(for: member)
        // Live values when local (level-ups show immediately); snapshot otherwise.
        let level = local?.level ?? member.level
        let combo = local?.portraitID ?? member.portraitCombo
            ?? QuestArtKey.portraitCombo(race: member.raceID ?? "", klass: member.classID)
        let className = repo.klass(member.classID)?.name ?? member.classID
        let sheet = local.flatMap { deriveSheet(from: $0, using: repo) }
        let bg = sheet?.theme.map { Color(hex: $0.background) } ?? GMStyle.page
        let accent = sheet?.theme.map { Color(hex: $0.accent) } ?? GMStyle.accent
        // Bound explicitly, and passed as `action:` rather than as a trailing closure:
        // two trailing closures on Button is the shape that reports "extra trailing
        // closure" when anything inside the first one fails to infer. Same family as
        // starBar's note in CharacterSheetView — don't make the type checker guess in
        // a body this size.
        //
        // No branch anymore: the COMPOSER is what knows local from remote, and it
        // handles both. This card just says who was tapped.
        let isLocal = local != nil
        let awardable = isLocal || member.isLinked
        let tap: () -> Void = { awarding = member }
        
        return Button(action: tap) {
            HStack(spacing: 12) {
                QuestArt(name: QuestArtKey.portrait(combo: combo), ratio: QuestRatio.card,
                         colors: [accent, bg], symbol: "person.fill",
                         caption: nil, framed: true)
                    .frame(width: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(member.name.uppercased())
                        .font(questFont(16)).foregroundStyle(.black)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("Lv \(level) · \(className)")
                        .font(questFontLight(13)).foregroundStyle(.black.opacity(0.65))
                    if let local {
                        HStack(spacing: 5) {
                            Circle().fill(GMStyle.gold).frame(width: 10, height: 10)
                            Text("\(local.gold)").font(questFont(14)).foregroundStyle(GMStyle.gold)
                        }
                    } else {
                        Label("On their iPad", systemImage: "ipad")
                            .font(questFontLight(11)).foregroundStyle(GMStyle.ink.opacity(0.7))
                    }
                }
                Spacer(minLength: 8)
                Label(chipTitle(local: isLocal, awardable: awardable),
                      systemImage: chipSymbol(local: isLocal, awardable: awardable))
                .font(questFont(13)).foregroundStyle(.black)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(awardable ? TierColor.selectPeach : Color(hex: "E8A020"),
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black, lineWidth: 2))
            }
            .padding(12)
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
    
    /// Award (here) · Send (their iPad) · Not linked (nobody's — typed in by hand).
    /// Amber isn't a wall: the tap still opens the composer, which is where the
    /// explanation and the remedy live.
    private func chipTitle(local: Bool, awardable: Bool) -> String {
        if !awardable { return "Not linked" }
        return local ? "Award" : "Send"
    }
    
    private func chipSymbol(local: Bool, awardable: Bool) -> String {
        if !awardable { return "exclamationmark.triangle.fill" }
        return local ? "gift.fill" : "qrcode"
    }
    
    private var addMemberMenu: some View {
        // Local heroes not yet in the party (the GM's own hero, design-test heroes).
        let memberIDs = Set(party.members.map(\.id))
        let localCandidates = roster.characters.filter { !memberIDs.contains($0.id) }
        return Menu {
            if !localCandidates.isEmpty {
                Section("From this iPad") {
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
                .font(questFont(14)).foregroundStyle(GMStyle.accent)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(GMStyle.accent.opacity(0.5),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
        .buttonStyle(.plain)
    }
    
    /// The party token's front door. Quest and boss stars are party-wide ALWAYS, and
        /// "everyone gets 25 gold" turns out to be just as common — one code beats N.
        private var partyAwardButton: some View {
            Button { awardingParty = true } label: {
                Label("Award the whole party…", systemImage: "person.3.fill")
                    .font(questFont(14)).foregroundStyle(.black)
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(TierColor.selectPeach, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .disabled(party.members.isEmpty)
        }

    // MARK: Monster bench (§7.1.2 — the live bestiary; improviser is on the board)

    private var benchPanel: some View {
        panel("Monster Bench") {
            let byThreat = Dictionary(grouping: repo.monsters(), by: \.threat)
            ForEach(MonsterThreat.allCases, id: \.self) { threat in
                if let group = byThreat[threat], !group.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(threat.benchLabel.uppercased())
                            .font(questFont(13)).foregroundStyle(GMStyle.ink.opacity(0.8))
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
        HStack(alignment: .center, spacing: 10) {
            TapInfo(payload: InfoPayload(
                title: m.name,
                subtitle: "HP \(m.hp) · +\(m.toHit) to hit · \(m.damageLine)",
                text: m.quirk, attack: nil, tint: GMStyle.accent)
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name).font(questFont(15)).foregroundStyle(GMStyle.ink)
                    Text(m.quirk).font(questFontLight(12))
                        .foregroundStyle(.black.opacity(0.6)).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            statPill("HP \(m.hp)")
            statPill("+\(m.toHit)")
            Text(m.damageLine)
                .font(.caption.monospaced()).foregroundStyle(.black.opacity(0.7))
                .frame(minWidth: 72, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func statPill(_ text: String) -> some View {
        Text(text).font(questFont(12)).foregroundStyle(.black)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.white, in: Capsule())
            .overlay(Capsule().strokeBorder(.black.opacity(0.25), lineWidth: 1))
    }

    // MARK: Ledger (§7.1.3 back half)

    private var ledgerPanel: some View {
        panel("Award Ledger") {
            if gm.ledger.isEmpty {
                Text("Every gold, star, and item award lands here, with a timestamp.")
                    .font(questFontLight(15)).foregroundStyle(.black.opacity(0.5))
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
                        .font(questFontLight(12)).foregroundStyle(.black.opacity(0.4))
                }
            }
        }
    }

    private func ledgerRow(_ e: GrantEntry) -> some View {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(e.heroName) — \(e.kind.summary)")
                        .font(questFont(14)).foregroundStyle(.black)
                    Text(e.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(questFontLight(11)).foregroundStyle(.black.opacity(0.5))
                }
                Spacer()
                if case .gmTokenIssued = e.source {
                    // "sent" ≠ "received". This iPad cannot know if they scanned it.
                    Label("code sent", systemImage: "qrcode")
                        .font(questFontLight(11)).foregroundStyle(.black.opacity(0.5))
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .overlay(Capsule().strokeBorder(.black.opacity(0.2), lineWidth: 1))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }

    // MARK: Shared panel chrome

    private func panel<Content: View>(_ title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(questFont(18)).foregroundStyle(.black.opacity(0.8))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GMStyle.page.opacity(GMStyle.pageTint),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.black.opacity(0.12), lineWidth: 1.5))
    }
}

// MARK: - Add a party member by hand (fallback until the QR hero-card import)
// Internal (not private): EncounterView reuses this sheet for late arrivals
// ("Add Fighter -> New player just showed up...") without leaving the board.

struct AddPartyMemberSheet: View {
    let repo: ContentRepository
    var onAdd: (GMPartyMember) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var classID = ""
    @State private var raceID = ""
    @State private var level = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ADD A PLAYER").font(questFont(22)).foregroundStyle(.black)
            Text("Their hero isn't on this device, so awards can't land here directly. QR delivery — you show a code, they scan it — is the next layer. For now, use the sheet's gold stepper, star track, and Found-on-an-Adventure menu on their iPad.")
                .font(questFontLight(13)).foregroundStyle(.black.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            TextField("Hero name", text: $name)
                .font(questFont(17))
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black.opacity(0.3), lineWidth: 1.5))

            HStack(spacing: 16) {
                Picker("Class", selection: $classID) {
                    Text("Class…").tag("")
                    ForEach(repo.classes()) { Text($0.name).tag($0.id) }
                }
                Picker("Kind", selection: $raceID) {
                    Text("Kind…").tag("")
                    ForEach(repo.races()) { Text($0.name).tag($0.id) }
                }
            }
            .pickerStyle(.menu)
            .font(questFont(15))

            Stepper(value: $level, in: 1...3) {
                Text("Level \(level)").font(questFont(16)).foregroundStyle(.black)
            }

            Spacer(minLength: 0)

            Button {
                onAdd(GMPartyMember(name: name.trimmingCharacters(in: .whitespaces),
                                    classID: classID,
                                    raceID: raceID.isEmpty ? nil : raceID,
                                    level: level,
                                    portraitCombo: raceID.isEmpty ? nil
                                        : QuestArtKey.portraitCombo(race: raceID, klass: classID)))
                dismiss()
            } label: {
                Text("Add to the party")
                    .font(questFont(16)).foregroundStyle(.black)
                    .padding(.horizontal, 24).padding(.vertical, 11)
                    .background(TierColor.selectPeach, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || classID.isEmpty)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TierColor.panelCream)
    }
}

/// WHO an award is for. `.one` addresses a hero by id; `.party` addresses nobody, which
/// is exactly what a party token is — one code, redeemed once per kid.
enum AwardTarget {
    case one(GMPartyMember)
    case party([GMPartyMember])
}

// MARK: - Award composer
//
// THE TARGET IS A GMPartyMember, NOT A HERO — identity, never sheet state, which is
// the same single-owner rule the party panel runs on. `localHero` is the ONE branch:
// non-nil means the hero lives on this iPad and the token redeems in-process; nil
// means it lives on another one and the token has to travel (step 6, Show QR).
//
// EVERY AWARD IS A GrantToken. Give doesn't mutate a hero — it builds a token and
// calls `gm.redeem`, exactly what a scanned code will do on the kid's device. One
// redeem path, two transports; the QR is transport, not the award.
//
// Internal, not private: AdventureView deep-links scene rewards here with the gold
// prefilled.

struct AwardComposer: View {
    let target: AwardTarget
    let repo: ContentRepository
    let roster: RosterStore
    let gm: GMStore
    var initialGold: Int? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .gold
    @State private var goldAmount = 10
    @State private var starAmount = 1
    @State private var query = ""
    @State private var confirming: Purchasable? = nil
    @State private var homebrewName = ""
    @State private var homebrewMagic = false
    @State private var toast: String? = nil
    @State private var emitted: GrantToken? = nil

    private enum Mode: String, CaseIterable, Identifiable {
        case gold = "Gold", star = "Star", item = "Item", homebrew = "Homebrew"
        var id: String { rawValue }
    }

    /// The single member, when there is one. nil for a party award.
        private var single: GMPartyMember? {
            if case .one(let m) = target { return m }
            return nil
        }

        /// Everyone this award touches.
        private var members: [GMPartyMember] {
            switch target {
            case .one(let m):   return [m]
            case .party(let m): return m
            }
        }

        private var displayName: String {
            switch target {
            case .one(let m): return m.name
            case .party:      return "the whole party"
            }
        }

        /// nil = nothing to redeem in-process. True for every party award (a party token
        /// has no single hero) and for any remote member.
        private var localHero: CharacterChoices? {
            single.flatMap { m in roster.characters.first { $0.id == m.id } }
        }
        private var isLocal: Bool { localHero != nil }

        private func isHere(_ m: GMPartyMember) -> Bool {
            roster.characters.contains { $0.id == m.id }
        }

        private var isAwardable: Bool {
            switch target {
            case .one(let m):    return isLocal || m.isLinked
            case .party(let ms): return ms.contains { $0.isLinked || isHere($0) }
            }
        }

    /// Live from the roster when local; unknowable when remote — their sheet is the
    /// only place those numbers exist, and this iPad has no business guessing.
    private var liveGold: Int? { localHero?.gold }
    private var liveStars: Int? { localHero?.stars }

    // MARK: The one award path

    /// Build the token, then pick a transport per target. Local hero: redeem here — no
        /// code, no camera. Remote hero: issue and show the code. PARTY: one code, and every
        /// local member redeems in-process on the way out, because they can't scan this
        /// screen either.
        private func give(_ kind: GrantKind, flashing line: String) {
            switch target {
            case .one(let m):
                guard let hero = localHero else {
                    emitted = gm.issue(kind, to: m)   // nothing lands here — not this iPad's hero
                    return
                }
                let token = GrantToken.single(kind, hero: hero.id, name: m.name)
                let result = gm.redeem(token, on: hero.id, roster: roster, repo: repo)
                if case .applied = result {
                    flash(line)
                } else {
                    print("⚠️ AwardComposer: redeem returned \(result) for \(m.name)")
                    flash("That didn't land — check the console.")
                }

            case .party(let ms):
                if let token = gm.issueToParty(kind, members: ms, roster: roster, repo: repo) {
                    emitted = token
                } else if ms.contains(where: { isHere($0) }) {
                    // Everyone was local. It already landed; there's nothing to scan.
                    flash(line)
                } else {
                    // Nobody was addressable. isAwardable should have caught this at the
                    // door — if this fires, the gate above isn't applied.
                    flash("Nobody in the party is linked to a hero yet.")
                }
            }
        }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heroHeader
                    if isAwardable {
                        Picker("Mode", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        switch mode {
                        case .gold:     goldSection
                        case .star:     starSection
                        case .item:     itemSection
                        case .homebrew: homebrewSection
                        }
                    } else {
                        unlinkedPanel
                    }
                }
                .padding(20)
            }
            .background(Color(hex: "C9C4EC").opacity(0.35).ignoresSafeArea())
            .navigationTitle("Award")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(questFont(16))
                }
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(questFont(15)).foregroundStyle(.black)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(TierColor.selectPeach, in: Capsule())
                        .overlay(Capsule().strokeBorder(.black, lineWidth: 2))
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            if let g = initialGold { goldAmount = max(-500, min(500, g)) }
        }
        .confirmationDialog(confirming?.name ?? "", isPresented: confirmingBinding,
                            titleVisibility: .visible, presenting: confirming) { p in
            Button(isLocal ? "Give to \(displayName)" : "Show a code for \(displayName)") {
                            // The dialog is still dismissing; a .sheet presented in this same tick
                            // gets swallowed — and `issue` would still have minted the token and
                            // written the ledger row, so you'd get a "code sent" row for a code
                            // nobody ever saw. Hop one runloop and let the dialog finish.
                            let kind = GrantKind.purchasable(id: p.id, name: p.name)
                            let line = "\(p.name) → \(displayName)!"
                            Task { @MainActor in give(kind, flashing: line) }
                        }
            Button("Cancel", role: .cancel) {}
        } message: { p in
            Text(awardNote(p))
        }
        .sheet(item: $emitted) { token in
            GrantTokenSheet(token: token, memberName: single?.name, repo: repo)
        }
    }

    private var confirmingBinding: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
    }

    private var heroHeader: some View {
        HStack(spacing: 10) {
            Text(displayName.uppercased()).font(questFont(20)).foregroundStyle(.black)
            if let stars = liveStars {
                HStack(spacing: 5) {
                    Image(systemName: "star.fill").font(.caption).foregroundStyle(TierColor.signature)
                    Text("\(stars)")
                        .font(questFont(18)).foregroundStyle(TierColor.signature)
                        .contentTransition(.numericText())
                }
            }
            Spacer()
            if let gold = liveGold {
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: "C79008")).frame(width: 12, height: 12)
                    Text("\(gold)")
                        .font(questFont(18)).foregroundStyle(Color(hex: "C79008"))
                        .contentTransition(.numericText())
                }
            } else if single == nil {
                Label("Everyone", systemImage: "person.3.fill")
                    .font(questFontLight(12)).foregroundStyle(.black.opacity(0.55))
            } else {
                Label("On their iPad", systemImage: "ipad")
                    .font(questFontLight(12)).foregroundStyle(.black.opacity(0.55))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
                .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
            }

            /// The dead end, named. A member's `id` is the award address; a hand-typed member's
            /// id is a fresh UUID that addresses no hero anywhere, so there is nothing to give
            /// and no code worth showing. Not a scold — the remedy is two taps, and it's the one
            /// GMParty.swift already documents ("remove + rescan").
            private var unlinkedPanel: some View {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Not linked to a hero", systemImage: "exclamationmark.triangle.fill")
                        .font(questFont(17)).foregroundStyle(Color(hex: "C79008"))
                    Text(single == nil
                         ? "Nobody in the party is linked to a hero yet. Awards are addressed to a hero, and a typed name isn't one."
                         : "\(displayName) was typed in by hand, so this iPad knows their name and class but not WHICH hero they are. A code sent to them would land nowhere and tell the player it wasn't theirs.")
                        .font(questFontLight(14)).foregroundStyle(.black.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Fix it: remove them from the party (long-press their card), then add them again with Scan a Hero Card. Their card carries their real id and awards will find them from then on.")
                        .font(questFontLight(14)).foregroundStyle(.black.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    Divider().overlay(.black.opacity(0.15))
                    Text("Typed members are still fine on the battle board — they just can't be paid.")
                        .font(questFontLight(12)).foregroundStyle(.black.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "E8A020").opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color(hex: "E8A020"), lineWidth: 2))
            }

            // Stars — the progression currency. Milestone-sized and mostly party-wide, so this
    // stays deliberately blunt: one star, one hero, one tap. A quest or boss star means
    // repeating that for each kid (or one scanned code, once the party token lands) —
    // that repetition IS the sibling-proofing, and at three heroes it's cheap.
    //
    // THE INVARIANT: this awards stars and nothing else. `redeem` routes .star through
    // `awardStar`, which never touches `level` — it only makes `canLevelUp` true, and
    // the kid still spends the points. Stars entitle; the kid claims.
    private var starSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Stars for what they achieved, gold for how they played. A star is milestone-sized: quest done, boss down — or anything that would have BEEN one of those, however they pulled it off. A great moment that isn't a milestone is worth gold.")
                .font(questFontLight(13)).foregroundStyle(.black.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            // Split out: the track was the fattest expression in this body, and giant
            // view expressions time out the Swift 6 type checker.
            if let live = localHero {
                starTrackPreview(live)
            } else {
                Text(single == nil ? "Each kid's track lives on their own iPad."
                     : "Their star track lives on their iPad.")
                .font(questFontLight(12)).foregroundStyle(.black.opacity(0.5))
            }
            
            Stepper(value: $starAmount, in: -3...3) {
                Text(starLabel(starAmount))
                    .font(questFont(20))
                    .foregroundStyle(starAmount >= 0 ? TierColor.signature : .red)
                    .contentTransition(.numericText())
            }
            
            awardButton(awardTitle(starAmount >= 0 ? "Award \(starLabel(starAmount))"
                                   : "Take back \(starLabel(-starAmount))"),
                        symbol: awardSymbol,
                        enabled: starAmount != 0) {
                give(.star(starAmount),
                     flashing: starAmount >= 0 ? "★ → \(displayName)!" : "\(starAmount) star — oof!")
            }
        }
        .padding(16)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.black, lineWidth: 2))
    }

    private func starTrackPreview(_ hero: CharacterChoices) -> some View {
        let slots = CharacterChoices.starTrackLength
        let filled = min(max(0, hero.stars), slots)
        return HStack(spacing: 6) {
            ForEach(0 ..< slots, id: \.self) { i in
                Image(systemName: i < filled ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(i < filled ? TierColor.signature : .black.opacity(0.25))
            }
            if hero.stars > slots {
                Text("+\(hero.stars - slots)")
                    .font(questFont(14)).foregroundStyle(.black.opacity(0.5))
            }
            Spacer()
            Text(starStatus(hero))
                .font(questFontLight(12))
                .foregroundStyle(hero.canLevelUp ? TierColor.signature : .black.opacity(0.55))
        }
    }

    private func starLabel(_ n: Int) -> String {
        "\(n >= 0 ? "+" : "")\(n) star\(abs(n) == 1 ? "" : "s")"
    }

    private func starStatus(_ hero: CharacterChoices) -> String {
        if hero.canLevelUp { return "Ready for Level \(hero.earnedLevel)!" }
        if let togo = hero.starsToNextLevel { return "\(togo) to go" }
        return "Track full"
    }

    private var goldSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach([5, 10, 25, 50, 100], id: \.self) { n in
                    Button { goldAmount = n } label: {
                        Text("+\(n)")
                            .font(questFont(15))
                            .foregroundStyle(.black.opacity(goldAmount == n ? 1 : 0.6))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(goldAmount == n ? TierColor.selectPeach : .white,
                                        in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(.black, lineWidth: goldAmount == n ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            Stepper(value: $goldAmount, in: -500...500, step: 5) {
                Text(goldAmount >= 0 ? "+\(goldAmount) gold" : "\(goldAmount) gold")
                    .font(questFont(20))
                    .foregroundStyle(goldAmount >= 0 ? Color(hex: "C79008") : .red)
                    .contentTransition(.numericText())
            }
            awardButton(awardTitle(goldAmount >= 0 ? "Award \(goldAmount) gold" : "Take \(-goldAmount) gold"),
                        symbol: awardSymbol,
                        enabled: goldAmount != 0) {
                give(.gold(goldAmount),
                     flashing: goldAmount >= 0 ? "+\(goldAmount) gold → \(displayName)!"
                     : "\(goldAmount) gold — ouch!")
            }
        }
        .padding(16)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.black, lineWidth: 2))
    }

    private var catalog: [(title: String, items: [Purchasable])] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        func match(_ name: String) -> Bool { q.isEmpty || name.lowercased().contains(q) }
        let gear = repo.allGear().filter { match($0.name) }.map(Purchasable.gear)
        let items = repo.items().filter { match($0.name) }
        func bucket(_ k: ItemKind) -> [Purchasable] {
            items.filter { $0.kind == k }.sorted { $0.name < $1.name }.map(Purchasable.item)
        }
        return [
            ("Weapons, Armor & Gear", gear),
            ("Potions & Supplies", bucket(.consumable)),
            ("Magic Items", bucket(.magicConsumable)),
            ("Scrolls", bucket(.scroll)),
            ("Curiosities", bucket(.curio)),
        ].filter { !$0.items.isEmpty }
    }

    private var itemSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color(hex: "5B3390"))
                TextField("Search treasure…", text: $query)
                    .font(questFontLight(16)).autocorrectionDisabled()
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black.opacity(0.3), lineWidth: 1.5))

            ForEach(catalog, id: \.title) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title.uppercased())
                        .font(questFont(13)).foregroundStyle(Color(hex: "5B3390").opacity(0.8))
                    VStack(spacing: 0) {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { i, p in
                            if i > 0 { Divider().overlay(.black.opacity(0.1)) }
                            Button { confirming = p } label: {
                                HStack {
                                    Text(p.name).font(questFont(14)).foregroundStyle(.black)
                                    Spacer()
                                    Text(String(describing: p.rarity).capitalized)
                                        .font(questFontLight(12)).foregroundStyle(.black.opacity(0.45))
                                    Image(systemName: "gift.fill")
                                        .font(.caption).foregroundStyle(Color(hex: "8A4FD0"))
                                }
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
                }
            }
        }
    }
    
    /// Local heroes get the verb; remote heroes get a code. Same token behind both.
        private func awardTitle(_ localTitle: String) -> String {
            isLocal ? localTitle : "Show the code"
        }
        private var awardSymbol: String { isLocal ? "gift.fill" : "qrcode" }

    /// A PREDICTION, read off the member's class — the same value local or remote. The
    /// real fork happens in ShopRules.grant on the device that redeems, against the
    /// real hero, which is why the token carries an id and not a resolved grant.
    private func awardNote(_ p: Purchasable) -> String {
        switch p {
        case .gear:
            return "Lands in \(displayName)'s owned gear — they equip it from the sheet's Add menu."
        case .item(let i):
            switch i.kind {
            case .scroll:
                return "Lands in Magic Items as a scroll. A caster can learn it from their own sheet — or hold it and hand it to someone who can."
            case .consumable:       return "Lands in Normal Items."
            case .magicConsumable, .curio: return "Lands in Magic Items."
            }
        }
    }
    
    private var homebrewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Something you invented at the table. It lands on the sheet as a free-text item — if it earns a spot in the official game later, add it to the content under the same name and every copy upgrades itself.")
                .font(questFontLight(13)).foregroundStyle(.black.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            TextField("Item name — e.g. The Slightly Cursed Spoon", text: $homebrewName)
                .font(questFont(16))
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black.opacity(0.3), lineWidth: 1.5))
            Toggle(isOn: $homebrewMagic) {
                Text("Magic item").font(questFont(15)).foregroundStyle(.black)
            }
            .tint(Color(hex: "8A4FD0"))
            awardButton(awardTitle("Award it"), symbol: awardSymbol,
                                    enabled: !homebrewName.trimmingCharacters(in: .whitespaces).isEmpty) {
                let trimmed = homebrewName.trimmingCharacters(in: .whitespaces)
                give(.homebrew(name: trimmed, magic: homebrewMagic),
                     flashing: "\(trimmed) → \(displayName)!")
                homebrewName = ""
            }
        }
        .padding(16)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.black, lineWidth: 2))
    }

    private func awardButton(_ title: String, symbol: String = "gift.fill",
                              enabled: Bool, action: @escaping () -> Void) -> some View {
         Button(action: action) {
             Label(title, systemImage: symbol)
                .font(questFont(16)).foregroundStyle(.black)
                .padding(.horizontal, 20).padding(.vertical, 11)
                .background(enabled ? TierColor.selectPeach : Color.gray.opacity(0.25),
                            in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.black.opacity(enabled ? 1 : 0.25), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func flash(_ msg: String) {
        withAnimation(.snappy) { toast = msg }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeOut) { toast = nil }
        }
    }
}
