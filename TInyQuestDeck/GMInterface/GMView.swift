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

    @State private var awarding: CharacterChoices? = nil
    @State private var shortcut: RuleSection? = nil
    @State private var showingBoard = false
    @State private var addingMember = false
    @State private var namingAdHoc = false
    @State private var adHocTitle = ""
    @State private var remoteNoteFor: GMPartyMember? = nil
    @State private var openAdventure: Adventure? = nil
    @State private var scanningHero = false


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
        .sheet(item: $awarding) { hero in
            AwardComposer(hero: hero, repo: repo, roster: roster, gm: gm)
        }
        .sheet(item: $shortcut) { section in
            NavigationStack { RuleSectionDetail(section: section) }
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
        .alert(item: $remoteNoteFor) { member in
            Alert(title: Text("\(member.name) lives on another iPad"),
                  message: Text("Their hero isn't on this device, so awards can't land here directly. QR delivery — you show a code, they scan it — is the next layer. For now, use the sheet's gold stepper and Found-on-an-Adventure menu on their iPad."),
                  dismissButton: .default(Text("Got it")))
        }
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

        return Button {
            if let local { awarding = local } else { remoteNoteFor = member }
        } label: {
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
                Label("Award", systemImage: "gift.fill")
                    .font(questFont(13)).foregroundStyle(.black.opacity(local != nil ? 1 : 0.4))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(local != nil ? TierColor.selectPeach : Color.gray.opacity(0.2),
                                in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.black.opacity(local != nil ? 1 : 0.3), lineWidth: 2))
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
                Text("Every gold and item award lands here, with a timestamp.")
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
                Text("\(e.heroName) — \(grantLabel(e.kind))")
                    .font(questFont(14)).foregroundStyle(.black)
                Text(e.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(questFontLight(11)).foregroundStyle(.black.opacity(0.5))
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func grantLabel(_ kind: GrantKind) -> String {
        switch kind {
        case .gold(let n):                  n >= 0 ? "+\(n) gold" : "\(n) gold"
        case .purchasable(_, let name):     name
        case .homebrew(let name, let magic): "\(name)\(magic ? " ✦" : "") · homebrew"
        }
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
            Text("Their hero lives on their own iPad — this is just the name tag on the GM's map. Re-add them via QR scan later to link the real hero.")
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

// MARK: - Award composer (direct grants for LOCAL heroes; the QR emit replaces
// the Give button for remote members when that layer lands). Internal, not
// private: AdventureView deep-links scene rewards here with the gold prefilled.

struct AwardComposer: View {
    let hero: CharacterChoices        // identity snapshot; live gold reads from roster
    let repo: ContentRepository
    let roster: RosterStore
    let gm: GMStore
    var initialGold: Int? = nil       // scene-reward deep-link prefill

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .gold
    @State private var goldAmount = 10
    @State private var query = ""
    @State private var confirming: Purchasable? = nil
    @State private var homebrewName = ""
    @State private var homebrewMagic = false
    @State private var toast: String? = nil

    private enum Mode: String, CaseIterable, Identifiable {
        case gold = "Gold", item = "Item", homebrew = "Homebrew"
        var id: String { rawValue }
    }

    private var liveGold: Int {
        roster.characters.first { $0.id == hero.id }?.gold ?? hero.gold
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heroHeader
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .gold:     goldSection
                    case .item:     itemSection
                    case .homebrew: homebrewSection
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
            Button("Give to \(hero.name)") {
                gm.award(p, to: hero.id, roster: roster, repo: repo)
                flash("\(p.name) → \(hero.name)!")
            }
            Button("Cancel", role: .cancel) {}
        } message: { p in
            Text(awardNote(p))
        }
    }

    private var confirmingBinding: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
    }

    private var heroHeader: some View {
        HStack(spacing: 10) {
            Text(hero.name.uppercased()).font(questFont(20)).foregroundStyle(.black)
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(Color(hex: "C79008")).frame(width: 12, height: 12)
                Text("\(liveGold)")
                    .font(questFont(18)).foregroundStyle(Color(hex: "C79008"))
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
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
            awardButton(goldAmount >= 0 ? "Award \(goldAmount) gold" : "Take \(-goldAmount) gold",
                        enabled: goldAmount != 0) {
                gm.awardGold(goldAmount, to: hero.id, roster: roster)
                flash(goldAmount >= 0 ? "+\(goldAmount) gold → \(hero.name)!"
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

    private func awardNote(_ p: Purchasable) -> String {
        switch p {
        case .gear:
            return "Lands in \(hero.name)'s owned gear — they equip it from the sheet's Add menu."
        case .item(let i):
            switch i.kind {
            case .scroll:
                return ShopRules.isCaster(hero, repo: repo)
                    ? "\(hero.name) is a caster — they'll learn this spell into their spellbook."
                    : "\(hero.name) isn't a caster — they'll carry the scroll as a one-shot magic item."
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
            awardButton("Award it",
                        enabled: !homebrewName.trimmingCharacters(in: .whitespaces).isEmpty) {
                gm.awardHomebrew(homebrewName, magic: homebrewMagic, to: hero.id, roster: roster)
                flash("\(homebrewName) → \(hero.name)!")
                homebrewName = ""
            }
        }
        .padding(16)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.black, lineWidth: 2))
    }

    private func awardButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "gift.fill")
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
