//  AdventurePhoneView.swift  (iPhone / compact — the story reader)
//  The GM's war-room reader at phone width. PARALLEL VIEW, NOT A BRANCH:
//  AdventureView.swift is byte-identical; GMPhoneView presents this variant instead.
//
//  The iPad reader was already mostly vertical, so this keeps its structure — scene
//  chips, read-aloud block, options, GM callouts, fight card, rewards — and restacks
//  the three rows that overflow 390pt: the header (title + live-fight pill + close),
//  the encounter card (Start button drops to its own full-width row), and the
//  improvise card. "Start this battle" launches EncounterPhoneView, the phone board.
//
//  The current-scene position uses the SAME UserDefaults key as the iPad reader on
//  purpose: it's view position, not game data, and a GM who moves between devices
//  should land on the scene they left.
//
//  PhoneStory mirrors StoryStyle's dark-theme constants — the StoryStyle-mirrors-
//  BoardStyle precedent; fold into a shared QuestTheme when that decision lands.

import SwiftUI

private enum PhoneStory {
    static let background = Color(hex: "0F0F10")
    static let box        = Color(hex: "2A2A2E")
    static let field      = Color(hex: "323236")
    static let ink        = Color(hex: "F4F4F0")
    static let border     = Color(hex: "55555C")
    static let purple     = Color(hex: "B893E8")

    static let amber = Color(hex: "E8A020")
    static let peach = TierColor.selectPeach
    static let coral = Color(hex: "C94F3F")
    static let gold  = Color(hex: "E3B341")
}

struct AdventurePhoneView: View {
    let adventure: Adventure
    let repo: ContentRepository
    let encounters: EncounterStore
    let party: GMPartyStore
    let roster: RosterStore
    let gm: GMStore
    var onDismiss: () -> Void

    /// 0 = the Hook page; 1...scenes.count = scenes.
    @State private var page = 0
    @State private var showingBoard = false
    @State private var pendingPreset: EncounterPreset? = nil
    @State private var awarding: GMPartyMember? = nil
    @State private var goldPrefill: Int? = nil
    @State private var namingImprov = false
    @State private var improvTitle = ""
    @State private var awardingParty = false

    /// Same key as the iPad reader — one saved position per adventure, any device.
    private var pageKey: String { "gm.adventure.page.\(adventure.id)" }

    var body: some View {
        content
            .fullScreenCover(isPresented: $showingBoard) {
                EncounterPhoneView(repo: repo, store: encounters, party: party) { showingBoard = false }
            }
            .sheet(isPresented: $awardingParty) {
                AwardComposer(target: .party(party.members), repo: repo, roster: roster,
                              gm: gm, initialGold: goldPrefill)
            }
            .sheet(item: $awarding) { member in
                AwardComposer(target: .one(member), repo: repo, roster: roster, gm: gm,
                              initialGold: goldPrefill)
            }
            .confirmationDialog("A fight is already live", isPresented: pendingBinding,
                                titleVisibility: .visible, presenting: pendingPreset,
                                actions: { preset in
                Button("Continue the live fight") { showingBoard = true }
                Button("Start \(preset.title) instead", role: .destructive) {
                    encounters.start(preset: preset, repo: repo)
                    showingBoard = true
                }
                Button("Cancel", role: .cancel) {}
            }, message: { _ in
                Text("Starting a new battle replaces the one on the board.")
            })
            .alert("Name the fight!", isPresented: $namingImprov) {
                TextField("The Kitchen Ambush", text: $improvTitle)
                Button("Start") { startBattle(blankPreset(named: improvTitle)) }
                Button("Cancel", role: .cancel) {}
            }
    }

    private var pendingBinding: Binding<Bool> {
        Binding(get: { pendingPreset != nil }, set: { if !$0 { pendingPreset = nil } })
    }

    private var content: some View {
        VStack(spacing: 10) {
            header
            sceneChips
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if page == 0 { hookPage } else { scenePage(adventure.scenes[page - 1]) }
                }
                .padding(.bottom, 30)
            }
        }
        .padding(12)
        .background(PhoneStory.background.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .onAppear {
            let saved = UserDefaults.standard.integer(forKey: pageKey)
            page = min(max(0, saved), adventure.scenes.count)
        }
        .onChange(of: page) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: pageKey)
        }
    }

    // MARK: Header — title + close on row 1; tone line + the live-fight pill on row 2

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(adventure.title.uppercased())
                    .font(questFont(16)).foregroundStyle(.black)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color(hex: "C9C4EC"), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
                Spacer(minLength: 8)
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(PhoneStory.ink)
                        .frame(width: 40, height: 40)
                        .background(PhoneStory.box, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(PhoneStory.border, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Text("\(adventure.tone) · \(adventure.length)")
                    .font(questFontLight(11)).foregroundStyle(PhoneStory.ink.opacity(0.5))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                if let e = encounters.encounter {
                    Button { showingBoard = true } label: {
                        Label("Rd \(e.round)", systemImage: "flag.fill")
                            .font(questFont(12)).foregroundStyle(.black)
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(PhoneStory.peach, in: Capsule())
                            .overlay(Capsule().strokeBorder(.black, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var sceneChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pageChip(index: 0, label: "The Hook", symbol: "sparkles")
                ForEach(Array(adventure.scenes.enumerated()), id: \.element.id) { i, scene in
                    pageChip(index: i + 1, label: scene.title,
                             symbol: scene.encounter == nil ? "text.book.closed.fill" : "flag.fill")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func pageChip(index: Int, label: String, symbol: String) -> some View {
        let selected = page == index
        return Button { page = index } label: {
            Label(label, systemImage: symbol)
                .font(questFont(12))
                .foregroundStyle(selected ? .black : PhoneStory.ink.opacity(0.75))
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(selected ? PhoneStory.peach : PhoneStory.box, in: Capsule())
                .overlay(Capsule().strokeBorder(
                    selected ? .black : PhoneStory.border, lineWidth: selected ? 2 : 1.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: The Hook page

    private var hookPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            readAloudBlock(adventure.hook)
            if let secret = adventure.secret {
                gmCallout(title: "What's really going on", text: secret)
            }
            Button { page = 1 } label: {
                Label("Scene 1 — \(adventure.scenes.first?.title ?? "")", systemImage: "arrow.right")
                    .font(questFont(14)).foregroundStyle(.black)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(PhoneStory.peach, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
            }
            .buttonStyle(.plain)
            improviseLink(defaultTitle: adventure.title)
        }
    }

    // MARK: Scene pages

    @ViewBuilder
    private func scenePage(_ scene: AdventureScene) -> some View {
        Text(scene.title.uppercased())
            .font(questFont(20)).foregroundStyle(PhoneStory.ink)
            .lineLimit(2).minimumScaleFactor(0.7)

        readAloudBlock(scene.readAloud)

        if let options = scene.options, !options.isEmpty {
            optionsBlock(options)
        }

        if let notes = scene.gmNotes {
            gmCallout(title: "GM only", text: notes)
        }

        if let preset = scene.encounter {
            encounterCard(preset)
            improviseLink(defaultTitle: scene.title)
        } else {
            improviseCard(defaultTitle: scene.title)
        }

        if let rewards = scene.rewards, !rewards.isEmpty {
            rewardsCard(rewards)
        }

        sceneNav
    }

    /// The performance text — a touch smaller than the iPad's 19pt, still the
    /// biggest thing on the page. This is what the GM reads out loud.
    private func readAloudBlock(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(PhoneStory.peach)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 6) {
                Label("Read aloud", systemImage: "waveform")
                    .font(questFont(12)).foregroundStyle(PhoneStory.peach)
                Text(text)
                    .font(questFontLight(17)).foregroundStyle(PhoneStory.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PhoneStory.box, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(PhoneStory.border, lineWidth: 2))
    }

    /// Options restacked for the narrow column: label + check capsule share the top
    /// row, the outcome gets the full width underneath.
    private func optionsBlock(_ options: [AdventureOption]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                if i > 0 { Divider().overlay(PhoneStory.border.opacity(0.5)) }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(opt.label).font(questFont(14)).foregroundStyle(PhoneStory.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if let check = opt.check {
                            Text(check)
                                .font(questFont(11)).foregroundStyle(PhoneStory.ink)
                                .lineLimit(1).fixedSize()
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(PhoneStory.amber.opacity(0.28), in: Capsule())
                                .overlay(Capsule().strokeBorder(PhoneStory.amber, lineWidth: 1.5))
                        }
                    }
                    Text(opt.outcome)
                        .font(questFontLight(13)).foregroundStyle(PhoneStory.ink.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
            }
        }
        .background(PhoneStory.box, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(PhoneStory.border, lineWidth: 2))
    }

    private func gmCallout(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: "eye.slash.fill")
                .font(questFont(13)).foregroundStyle(PhoneStory.purple)
            Text(text)
                .font(questFontLight(13)).foregroundStyle(PhoneStory.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PhoneStory.purple.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(PhoneStory.purple, lineWidth: 2))
    }

    /// The fight card, restacked: identity row up top, "Start this battle" gets its
    /// own full-width row — the button a parent actually needs to hit mid-story.
    private func encounterCard(_ preset: EncounterPreset) -> some View {
        let monsterCount = preset.monsters.reduce(0) { $0 + max(1, $1.count ?? 1) }
        let locked = preset.places.filter { $0.lock != nil }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "flag.fill").font(.title3).foregroundStyle(PhoneStory.coral)
                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.title.uppercased())
                        .font(questFont(15)).foregroundStyle(PhoneStory.ink)
                        .lineLimit(2).minimumScaleFactor(0.7)
                    Text(monsterLine(preset))
                        .font(questFontLight(12)).foregroundStyle(PhoneStory.ink.opacity(0.6))
                        .lineLimit(2)
                    if let lock = locked.first?.lock {
                        Label(lock, systemImage: "lock.fill")
                            .font(questFontLight(11)).foregroundStyle(PhoneStory.amber)
                    }
                }
                Spacer(minLength: 6)
                Text("\(monsterCount)")
                    .font(questFont(20)).foregroundStyle(PhoneStory.coral)
            }
            Button { startBattle(preset) } label: {
                Label("Start this battle", systemImage: "play.fill")
                    .font(questFont(14)).foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(PhoneStory.peach, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(PhoneStory.box, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(PhoneStory.coral.opacity(0.8), lineWidth: 2))
    }

    /// One guard for every way a fight starts from the story — same rule as the iPad.
    private func startBattle(_ preset: EncounterPreset) {
        if encounters.encounter != nil {
            pendingPreset = preset
        } else {
            encounters.start(preset: preset, repo: repo)
            showingBoard = true
        }
    }

    private func blankPreset(named title: String) -> EncounterPreset {
        let t = title.trimmingCharacters(in: .whitespaces)
        return EncounterPreset(
            id: "improvised",
            title: t.isEmpty ? "The Fight" : t,
            places: [
                EncounterPreset.PresetPlace(name: "Here", lock: nil, parent: nil, side: nil),
                EncounterPreset.PresetPlace(name: "Over there", lock: nil, parent: nil, side: nil),
            ],
            monsters: [])
    }

    /// The dashed card for scenes with no written fight — button dropped to its own row.
    private func improviseCard(defaultTitle: String) -> some View {
        Button {
            improvTitle = defaultTitle
            namingImprov = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "wand.and.stars")
                        .font(.title3).foregroundStyle(PhoneStory.purple)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("NO FIGHT WRITTEN HERE")
                            .font(questFont(13)).foregroundStyle(PhoneStory.ink.opacity(0.85))
                        Text("Kids went sideways? Improvise one — name it, then build places and monsters right on the board.")
                            .font(questFontLight(12)).foregroundStyle(PhoneStory.ink.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Label("Improvise a battle", systemImage: "play.fill")
                    .font(questFont(13)).foregroundStyle(PhoneStory.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(PhoneStory.field, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(PhoneStory.border, lineWidth: 1.5))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PhoneStory.box.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(PhoneStory.border, style: StrokeStyle(lineWidth: 2, dash: [7, 5])))
        }
        .buttonStyle(.plain)
    }

    private func improviseLink(defaultTitle: String) -> some View {
        Button {
            improvTitle = defaultTitle
            namingImprov = true
        } label: {
            Label("Or improvise a different battle…", systemImage: "wand.and.stars")
                .font(questFontLight(13)).foregroundStyle(PhoneStory.ink.opacity(0.5))
        }
        .buttonStyle(.plain)
    }

    private func monsterLine(_ preset: EncounterPreset) -> String {
        preset.monsters.map { entry in
            let name = repo.monster(entry.monster)?.name ?? entry.monster
            let n = max(1, entry.count ?? 1)
            return n > 1 ? "\(n)× \(name)" : name
        }.joined(separator: " · ")
    }

    private func rewardsCard(_ rewards: [AdventureReward]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rewards.enumerated()), id: \.offset) { i, reward in
                if i > 0 { Divider().overlay(PhoneStory.border.opacity(0.5)) }
                HStack(spacing: 8) {
                    Image(systemName: "gift.fill").font(.caption).foregroundStyle(PhoneStory.gold)
                    Text(reward.label)
                        .font(questFontLight(13)).foregroundStyle(PhoneStory.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let gold = reward.gold {
                        giveMenu(gold: gold)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
            }
            Text("Items and homebrew rewards: pick the hero on the GM tab's party panel — the composer has the whole catalog.")
                .font(questFontLight(11)).foregroundStyle(PhoneStory.ink.opacity(0.4))
                .padding(.horizontal, 12).padding(.bottom, 10)
        }
        .background(PhoneStory.box, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(PhoneStory.gold.opacity(0.7), lineWidth: 2))
    }

    /// Gold reward → pick a hero (or everyone) → the composer opens prefilled.
    /// Same menu as the iPad; the composer handles local vs remote vs unlinked.
    private func giveMenu(gold: Int) -> some View {
        Menu {
            Button {
                goldPrefill = gold
                awardingParty = true
            } label: {
                Label("Everyone", systemImage: "person.3.fill")
            }
            Divider()
            ForEach(party.members) { member in
                Button(member.name) {
                    goldPrefill = gold
                    awarding = member
                }
            }
        } label: {
            Label("Give \(gold)g", systemImage: "person.fill.badge.plus")
                .font(questFont(12)).foregroundStyle(.black)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(PhoneStory.gold, in: Capsule())
                .overlay(Capsule().strokeBorder(.black, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(party.members.isEmpty)
    }

    private var sceneNav: some View {
        HStack {
            if page > 0 {
                Button { page -= 1 } label: {
                    Label(page == 1 ? "The Hook" : adventure.scenes[page - 2].title,
                          systemImage: "arrow.left")
                        .font(questFont(13)).foregroundStyle(PhoneStory.ink.opacity(0.7))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 12)
            if page < adventure.scenes.count {
                Button { page += 1 } label: {
                    Label(adventure.scenes[page].title, systemImage: "arrow.right")
                        .font(questFont(13)).foregroundStyle(PhoneStory.ink.opacity(0.7))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
    }
}
