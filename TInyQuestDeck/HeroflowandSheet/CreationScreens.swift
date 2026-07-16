//  CreationScreens.swift
//  Screens 2–5 of the creation flow: Pick a Class (path cards inside themed class
//  sections), Path Detail (Build Info + tiered ability panels), Pick a Kind (card
//  grid), Kind Detail (tilted card + lore + lineup banner).
//
//  All art renders QuestArt at the locked ratios — real catalog asset if named, else
//  the dashed placeholder, so screens stay complete as art is drawn in. Keys:
//  path cards + path portrait -> path-<pathID>; kind tiles + tilted card ->
//  race-<raceID>; lineup banner -> race-<raceID>-lineup.
//  Depends on QuestStyle.swift, TapInfo.swift, and Color(hex:) from HeroTile.swift.
//
//  v2 changes: path cards are FIXED-WIDTH (a 2-path class renders identical cards
//  to a 3-path class, third slot just stays empty until content arrives), and
//  starting-kit spell names are TapInfo — tap for the full spell text.

import SwiftUI

// MARK: - Screen 2: Pick a Class (tap a PATH card — class+path commit together)

struct PickPathView: View {
    let repo: ContentRepository
    var draft: HeroDraft? = nil          // nil = browse mode (from the rulebook)
    var onSelect: (String) -> Void   // pathID

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let draft {
                    QuestChip(text: draft.name.isEmpty ? "Name goes here" : draft.name)
                    QuestChip(text: "Pick a Class", size: 17)
                } else {
                    QuestChip(text: "Classes", size: 17)
                }

                ForEach(repo.classes()) { cls in
                    classSection(cls)
                }
            }
            .padding(20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Color.white)
    }

    private func classSection(_ cls: ClassDefinition) -> some View {
        let paths = cls.pathIDs.compactMap { repo.path($0) }
        return VStack(alignment: .leading, spacing: 12) {
            Text(cls.name.uppercased()).font(questFont(24)).foregroundStyle(.black)
            Text(cls.role).font(questFontLight(15)).foregroundStyle(.black.opacity(0.7))

            HStack(alignment: .top, spacing: 14) {
                ForEach(paths) { p in
                    Button { onSelect(p.id) } label: {
                        VStack(spacing: 6) {
                            QuestArt(
                                name: QuestArtKey.path(p.id),
                                ratio: QuestRatio.tall,
                                colors: [Color(hex: (p.themeOverride ?? cls.theme).accent),
                                         Color(hex: (p.themeOverride ?? cls.theme).background)],
                                symbol: emblemSymbol((p.themeOverride ?? cls.theme).emblem),
                                caption: "1080×1920")
                            Text(p.name.uppercased())
                                .font(questFont(16))
                                .foregroundStyle(.black)
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(width: 220)   // fixed: 2 or 3 paths render identically
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)          // left-align when a slot is empty
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: cls.theme.background), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.black, lineWidth: 2))
    }
}

// MARK: - Screen 3: Path Detail (Build Info, Starting Kit, Path Power, Signature Powers)

struct PathDetailView: View {
    let repo: ContentRepository
    let pathID: String
    var onSelect: (() -> Void)? = nil    // nil = browse mode (no Select button)

    private var path: PathDefinition? { repo.path(pathID) }
    private var cls: ClassDefinition? { path.flatMap { repo.klass($0.classID) } }

    var body: some View {
        Group {
            if let path, let cls {
                content(path: path, cls: cls)
            } else {
                ContentUnavailableView("Missing content", systemImage: "exclamationmark.triangle")
            }
        }
        .background(Color.white)
    }

    private func content(path: PathDefinition, cls: ClassDefinition) -> some View {
        let theme = path.themeOverride ?? cls.theme
        let kit = path.startingGearIDs.compactMap { repo.gear($0) }
        let kitHP = cls.hpByLevel.first.map { $0 + kit.reduce(0) { $0 + $1.maxHP } } ?? 0
        let core = (cls.coreAbilityIDs + path.coreAbilityIDs).compactMap { repo.ability($0) }
        let powers = path.pathPowerIDs.compactMap { repo.ability($0) }
        let sigs = path.signaturePowerIDs.compactMap { repo.ability($0) }
        let spells: [(SpellDefinition, Int)] = startingGrants(classID: cls.id, pathID: path.id, repo: repo)
            .compactMap { g in repo.spell(g.spellID).map { ($0, g.readyUses) } }

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    QuestChip(text: path.name, fill: Color(hex: theme.background))
                    Spacer()
                    if let onSelect { SelectButton(action: onSelect) }
                }

                HStack(alignment: .top, spacing: 16) {
                    // Tall portrait — same asset as the class-select tile (1080×1920).
                    QuestArt(
                        name: QuestArtKey.path(path.id),
                        ratio: QuestRatio.tall,
                        colors: [Color(hex: theme.accent), Color(hex: theme.background)],
                        symbol: emblemSymbol(theme.emblem),
                        caption: "\(path.name) art")
                        .frame(maxWidth: 320)

                    VStack(spacing: 14) {
                        TierPanel(title: "Build Info") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(kit) { g in
                                    if let atk = g.attack {
                                        infoLine("\(g.name)  (\(attackSummary(atk)))")
                                    } else if g.maxHP != 0 {
                                        infoLine("\(g.name)  (+\(g.maxHP) HP)")
                                    } else {
                                        infoLine(g.name)
                                    }
                                }
                                infoLine("Total HP with kit: \(kitHP)").padding(.top, 2)
                            }
                        }

                        TierPanel(title: "Starting Kit", titleColor: TierColor.starting) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(core) { a in abilityLine(a, color: TierColor.starting) }
                                if !spells.isEmpty {
                                    infoLine("Starting spells (tap for details):").padding(.top, 2)
                                    ForEach(spells, id: \.0.id) { spell, uses in
                                        TapInfo(payload: .init(spell: spell, uses: uses,
                                                               tint: TierColor.starting)) {
                                            HStack(spacing: 4) {
                                                infoLine("• \(spell.name)\(uses > 1 ? "  ×\(uses)" : "")")
                                                Image(systemName: "info.circle")
                                                    .font(.caption2)
                                                    .foregroundStyle(TierColor.starting.opacity(0.7))
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        TierPanel(title: powers.count == 1 ? "Path Power" : "Path Powers",
                                  titleColor: TierColor.path, icon: "bolt.circle.fill") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(powers) { a in abilityLine(a, color: TierColor.path) }
                            }
                        }
                    }
                }

                TierPanel(title: "Signature Powers",
                          titleColor: TierColor.signature, icon: "sun.max.circle.fill") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(sigs) { a in abilityLine(a, color: TierColor.signature) }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }

    private func infoLine(_ s: String) -> some View {
        Text(s).font(questFontLight(15)).foregroundStyle(.black)
    }

    private func abilityLine(_ a: AbilityDefinition, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(a.name).font(questFont(16)).foregroundStyle(color)
                Text(usageLine(a)).font(questFontLight(12)).foregroundStyle(.black.opacity(0.55))
            }
            Text(a.text).font(questFontLight(14)).foregroundStyle(color.opacity(0.9))
        }
    }
}

// MARK: - Screen 4: Pick a Kind (the card grid)

struct PickKindView: View {
    let repo: ContentRepository
    var draft: HeroDraft? = nil          // nil = browse mode
    var onSelect: (String) -> Void   // raceID

    private let columns = [GridItem(.adaptive(minimum: 210, maximum: 280), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let draft {
                    HStack(spacing: 12) {
                        QuestChip(text: draft.name.isEmpty ? "Name goes here" : draft.name)
                        if let pathID = draft.pathID, let p = repo.path(pathID) {
                            QuestChip(text: p.name, size: 16)
                        }
                    }
                    QuestChip(text: "Pick a Kind", size: 17)
                } else {
                    QuestChip(text: "Kinds", size: 17)
                }

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(repo.races()) { race in
                        Button { onSelect(race.id) } label: { kindTile(race) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Color.white)
    }

    private func kindTile(_ race: RaceDefinition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(race.name.uppercased())
                .font(questFont(18)).foregroundStyle(.black)
                .lineLimit(1).minimumScaleFactor(0.6)
            QuestArt(
                name: QuestArtKey.race(race.id),
                ratio: QuestRatio.card,
                colors: [raceTint(race.id), raceTint(race.id).opacity(0.55)],
                symbol: "person.crop.square.badge.camera",
                caption: "card 1200×1680")
                .rotationEffect(.degrees(-3))
                .padding(6)
        }
        .padding(12)
        .background(raceTint(race.id).opacity(0.45), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.black, lineWidth: 2))
    }
}

// MARK: - Screen 5: Kind Detail (tilted card, lore panel, lineup banner)

struct KindDetailView: View {
    let repo: ContentRepository
    let raceID: String
    var onSelect: (() -> Void)? = nil    // nil = browse mode (no Select button)

    private var race: RaceDefinition? { repo.race(raceID) }

    var body: some View {
        Group {
            if let race {
                content(race)
            } else {
                ContentUnavailableView("Missing content", systemImage: "exclamationmark.triangle")
            }
        }
        .background(Color.white)
    }

    private func content(_ race: RaceDefinition) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    QuestChip(text: race.name, fill: raceTint(race.id))
                    Spacer()
                    if let onSelect { SelectButton(action: onSelect) }
                }

                HStack(alignment: .top, spacing: -30) {
                    // The tilted hero card — same 5:7 asset as the grid tile.
                    QuestArt(
                        name: QuestArtKey.race(race.id),
                        ratio: QuestRatio.card,
                        colors: [raceTint(race.id), raceTint(race.id).opacity(0.5)],
                        symbol: "person.crop.square.badge.camera",
                        caption: "\(race.name) card")
                        .frame(maxWidth: 330)
                        .rotationEffect(.degrees(-7))
                        .zIndex(1)

                    TierPanel(title: race.tagline) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(race.lore).font(questFontLight(15)).foregroundStyle(.black)

                            if !race.appearance.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(race.appearance, id: \.self) { line in
                                        Text("• \(line)").font(questFontLight(14))
                                            .foregroundStyle(.black.opacity(0.8))
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(race.ability.name)
                                        .font(questFont(16)).foregroundStyle(TierColor.starting)
                                    Text(usageLine(race.ability))
                                        .font(questFontLight(12)).foregroundStyle(.black.opacity(0.55))
                                }
                                Text(race.ability.text)
                                    .font(questFontLight(14))
                                    .foregroundStyle(TierColor.starting.opacity(0.9))
                            }

                            if !race.nameIdeas.isEmpty {
                                Text("Name ideas: \(race.nameIdeas.joined(separator: ", "))")
                                    .font(questFontLight(13)).foregroundStyle(.black.opacity(0.6))
                            }
                        }
                    }
                    .padding(.top, 40)
                }

                // Group lineup banner — different looks + class combos (3:2, 2048×1365).
                QuestArt(
                    name: QuestArtKey.raceLineup(race.id),
                    ratio: QuestRatio.banner,
                    colors: [raceTint(race.id).opacity(0.9), Color(hex: "5B4A8A")],
                    symbol: "person.3.fill",
                    caption: "\(race.name) lineup banner")
            }
            .padding(20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }
}
