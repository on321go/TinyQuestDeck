//  AdventureView.swift
//  The story reader — the GM's war-room view of an adventure module. Full-screen,
//  dark themed (same test look as the battle board): scene chips across the top,
//  then the selected page — big read-aloud text the GM performs, option lines with
//  their stat checks (display only; kids roll real dice), GM-only notes, the
//  scene's fight with "Start this battle" (loads the preset straight onto the
//  Places board), and reward lines that deep-link into the award composer with
//  the gold prefilled.
//
//  The current scene per adventure persists in UserDefaults (view position, not
//  game data — no schema change). The live fight persists via EncounterStore as
//  ever, so quitting mid-battle and reopening the adventure resumes both.

import SwiftUI

private enum StoryStyle {
    /// Mirrors the board's dark test theme. Promote both into a shared QuestTheme
    /// if dark becomes the GM's permanent look.
    static let darkMode = true

    static var background: Color { darkMode ? Color(hex: "0F0F10") : .white }
    static var box:        Color { darkMode ? Color(hex: "2A2A2E") : TierColor.panelCream }
    static var field:      Color { darkMode ? Color(hex: "323236") : .white }
    static var ink:        Color { darkMode ? Color(hex: "F4F4F0") : .black }
    static var border:     Color { darkMode ? Color(hex: "55555C") : .black }
    static var purple:     Color { darkMode ? Color(hex: "B893E8") : Color(hex: "8A4FD0") }

    static let amber   = Color(hex: "E8A020")
    static let peach   = TierColor.selectPeach
    static let coral   = Color(hex: "C94F3F")
    static let gold    = Color(hex: "E3B341")
}

struct AdventureView: View {
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
    @State private var awarding: CharacterChoices? = nil
    @State private var goldPrefill: Int? = nil
    @State private var remoteNote: RemoteRef? = nil

    private struct RemoteRef: Identifiable { let id = UUID(); let name: String }
    private var pageKey: String { "gm.adventure.page.\(adventure.id)" }

    var body: some View {
        content
            .fullScreenCover(isPresented: $showingBoard) {
                EncounterView(repo: repo, store: encounters, party: party) { showingBoard = false }
            }
            .sheet(item: $awarding) { hero in
                AwardComposer(hero: hero, repo: repo, roster: roster, gm: gm,
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
            .alert(item: $remoteNote) { ref in
                Alert(title: Text("\(ref.name) lives on another iPad"),
                      message: Text("Awards can't land here directly — QR delivery is the next layer. For now, they use their sheet's gold stepper."),
                      dismissButton: .default(Text("Got it")))
            }
    }

    private var pendingBinding: Binding<Bool> {
        Binding(get: { pendingPreset != nil }, set: { if !$0 { pendingPreset = nil } })
    }

    private var content: some View {
        VStack(spacing: 12) {
            header
            sceneChips
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if page == 0 { hookPage } else { scenePage(adventure.scenes[page - 1]) }
                }
                .padding(.bottom, 30)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(StoryStyle.background.ignoresSafeArea())
        .environment(\.colorScheme, StoryStyle.darkMode ? .dark : .light)
        .onAppear {
            let saved = UserDefaults.standard.integer(forKey: pageKey)
            page = min(max(0, saved), adventure.scenes.count)
        }
        .onChange(of: page) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: pageKey)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                QuestChip(text: adventure.title, fill: Color(hex: "C9C4EC"), size: 20)
                Text("\(adventure.tone) · \(adventure.length)")
                    .font(questFontLight(12)).foregroundStyle(StoryStyle.ink.opacity(0.5))
            }
            Spacer()
            // The live fight is reachable from anywhere in the story.
            if let e = encounters.encounter {
                Button { showingBoard = true } label: {
                    Label("\(e.title) · Rd \(e.round)", systemImage: "flag.fill")
                        .font(questFont(13)).foregroundStyle(.black)
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(StoryStyle.peach, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
            Button { onDismiss() } label: {
                Label("Close", systemImage: "xmark")
                    .font(questFont(14)).foregroundStyle(StoryStyle.ink)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(StoryStyle.box, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(StoryStyle.border, lineWidth: 2))
            }
            .buttonStyle(.plain)
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
                .font(questFont(13))
                .foregroundStyle(selected ? .black : StoryStyle.ink.opacity(0.75))
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(selected ? StoryStyle.peach : StoryStyle.box,
                            in: Capsule())
                .overlay(Capsule().strokeBorder(
                    selected ? .black : StoryStyle.border, lineWidth: selected ? 2 : 1.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: The Hook page

    private var hookPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            readAloudBlock(adventure.hook)
            if let secret = adventure.secret {
                gmCallout(title: "What's really going on", text: secret)
            }
            Button { page = 1 } label: {
                Label("Scene 1 — \(adventure.scenes.first?.title ?? "")", systemImage: "arrow.right")
                    .font(questFont(15)).foregroundStyle(.black)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(StoryStyle.peach, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Scene pages

    @ViewBuilder
    private func scenePage(_ scene: AdventureScene) -> some View {
        Text(scene.title.uppercased())
            .font(questFont(24)).foregroundStyle(StoryStyle.ink)

        readAloudBlock(scene.readAloud)

        if let options = scene.options, !options.isEmpty {
            optionsBlock(options)
        }

        if let notes = scene.gmNotes {
            gmCallout(title: "GM only", text: notes)
        }

        if let preset = scene.encounter {
            encounterCard(preset)
        }

        if let rewards = scene.rewards, !rewards.isEmpty {
            rewardsCard(rewards)
        }

        sceneNav
    }

    /// The performance text — big, light, with a peach accent bar. This is the
    /// thing the GM reads out loud.
    private func readAloudBlock(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(StoryStyle.peach)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 6) {
                Label("Read aloud", systemImage: "waveform")
                    .font(questFont(12)).foregroundStyle(StoryStyle.peach)
                Text(text)
                    .font(questFontLight(19)).foregroundStyle(StoryStyle.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StoryStyle.box, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(StoryStyle.border, lineWidth: 2))
    }

    private func optionsBlock(_ options: [AdventureOption]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                if i > 0 { Divider().overlay(StoryStyle.border.opacity(0.5)) }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(opt.label).font(questFont(15)).foregroundStyle(StoryStyle.ink)
                        Text(opt.outcome)
                            .font(questFontLight(14)).foregroundStyle(StoryStyle.ink.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if let check = opt.check {
                        Text(check)
                            .font(questFont(12)).foregroundStyle(StoryStyle.ink)
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(StoryStyle.amber.opacity(0.28), in: Capsule())
                            .overlay(Capsule().strokeBorder(StoryStyle.amber, lineWidth: 1.5))
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
        .background(StoryStyle.box, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(StoryStyle.border, lineWidth: 2))
    }

    private func gmCallout(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: "eye.slash.fill")
                .font(questFont(13)).foregroundStyle(StoryStyle.purple)
            Text(text)
                .font(questFontLight(14)).foregroundStyle(StoryStyle.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StoryStyle.purple.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(StoryStyle.purple, lineWidth: 2))
    }

    private func encounterCard(_ preset: EncounterPreset) -> some View {
        let monsterCount = preset.monsters.reduce(0) { $0 + max(1, $1.count ?? 1) }
        let locked = preset.places.filter { $0.lock != nil }
        return HStack(spacing: 12) {
            Image(systemName: "flag.fill").font(.title3).foregroundStyle(StoryStyle.coral)
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.title.uppercased()).font(questFont(16)).foregroundStyle(StoryStyle.ink)
                Text(monsterLine(preset))
                    .font(questFontLight(12)).foregroundStyle(StoryStyle.ink.opacity(0.6))
                    .lineLimit(2)
                if let lock = locked.first?.lock {
                    Label(lock, systemImage: "lock.fill")
                        .font(questFontLight(11)).foregroundStyle(StoryStyle.amber)
                }
            }
            Spacer()
            Button {
                if encounters.encounter != nil { pendingPreset = preset }
                else {
                    encounters.start(preset: preset, repo: repo)
                    showingBoard = true
                }
            } label: {
                Label("Start this battle", systemImage: "play.fill")
                    .font(questFont(14)).foregroundStyle(.black)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(StoryStyle.peach, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
            }
            .buttonStyle(.plain)
            Text("\(monsterCount)")
                .font(questFont(20)).foregroundStyle(StoryStyle.coral)
        }
        .padding(14)
        .background(StoryStyle.box, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(StoryStyle.coral.opacity(0.8), lineWidth: 2))
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
                if i > 0 { Divider().overlay(StoryStyle.border.opacity(0.5)) }
                HStack(spacing: 10) {
                    Image(systemName: "gift.fill").font(.caption).foregroundStyle(StoryStyle.gold)
                    Text(reward.label)
                        .font(questFontLight(14)).foregroundStyle(StoryStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let gold = reward.gold {
                        giveMenu(gold: gold)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
            Text("Items and homebrew rewards: pick the hero on the GM tab's party panel — the composer has the whole catalog.")
                .font(questFontLight(11)).foregroundStyle(StoryStyle.ink.opacity(0.4))
                .padding(.horizontal, 14).padding(.bottom, 10)
        }
        .background(StoryStyle.box, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(StoryStyle.gold.opacity(0.7), lineWidth: 2))
    }

    /// Gold reward → pick a hero → the award composer opens prefilled. Local
    /// heroes grant directly; remote members get the QR explainer (next layer).
    private func giveMenu(gold: Int) -> some View {
        Menu {
            ForEach(party.members) { member in
                Button(member.name) {
                    if let hero = roster.characters.first(where: { $0.id == member.id }) {
                        goldPrefill = gold
                        awarding = hero
                    } else {
                        remoteNote = RemoteRef(name: member.name)
                    }
                }
            }
        } label: {
            Label("Give \(gold)g", systemImage: "person.fill.badge.plus")
                .font(questFont(12)).foregroundStyle(.black)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(StoryStyle.gold, in: Capsule())
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
                        .font(questFont(13)).foregroundStyle(StoryStyle.ink.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if page < adventure.scenes.count {
                Button { page += 1 } label: {
                    Label(adventure.scenes[page].title, systemImage: "arrow.right")
                        .font(questFont(13)).foregroundStyle(StoryStyle.ink.opacity(0.7))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
    }
}
