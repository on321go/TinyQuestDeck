//  CreationFlowPhone.swift  (iPhone / compact — the whole creation flow)
//  The portal at phone width: shell + all five screens in one file, because they
//  travel together (the QuestQR one-file lesson). PARALLEL VIEWS, NOT BRANCHES:
//  CreationFlow.swift and CreationScreens.swift are byte-identical; MainTabView
//  presents this shell at compact width.
//
//  Reused straight from the iPad flow (all already internal — zero access hunks):
//  HeroDraft, CreationRoute, TierPanel, SelectButton's peach language, QuestChip,
//  QuestArt + the locked ratios, TapInfo, usageLine, attackSummary, raceTint,
//  startingGrants. `makeHero()` is DUPLICATED verbatim (it's private in
//  CreationFlowView) — it stays the one place a draft becomes a real character,
//  and the gear-starts-BLANK ruling rides with it.
//
//  Phone reshapes:
//    • Pick a Class — each class section's fixed-width card row becomes a
//      horizontal scroll (one card + a peek), the app's established grammar.
//    • Path Detail / Kind Detail — the two-column compositions restack vertically:
//      art on top, panels full-width below. SELECT moves to a bottom-pinned bar
//      (safeAreaInset) so the commit button is always under a thumb — a kid reads
//      the whole path scrolling DOWN and never has to scroll back up to say yes.
//    • Pick a Kind — the adaptive grid gets a phone minimum so kinds sit two-up
//      (the card-spread feel) instead of one giant column.
//    • Kind Detail keeps the tilts — the card leans at -7° above the lore panel
//      with a slight overlap, so the collectible-card charm survives the restack.
//
//  Browse mode survives: like the iPad screens, draft/onSelect are optional, so
//  the rulebook's Browse Classes / Browse Kinds covers can adopt these phone
//  variants later with a size-class branch of their own (out of scope today).
//
//  NO LAZY CONTAINERS except PickKindPhoneView's grid — the same top-level
//  LazyVGrid shape the iPad picker already ships (the culling gotcha was GM
//  surfaces and nested laziness).

import SwiftUI

// MARK: - Shared phone chrome

/// QuestChip's look with phone manners: one line, scales down instead of pushing
/// the row wider than the screen.
private func phoneChip(_ text: String,
                       fill: Color = Color(hex: "A8CBE4"),
                       size: CGFloat = 15) -> some View {
    Text(text.uppercased())
        .font(questFont(size)).foregroundStyle(.black)
        .lineLimit(1).minimumScaleFactor(0.6)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
}

/// The bottom-pinned SELECT bar for the detail screens. Full width, thumb-height,
/// the same peach as the iPad's SelectButton. Renders nothing in browse mode.
@ViewBuilder
private func selectBar(_ onSelect: (() -> Void)?) -> some View {
    if let onSelect {
        VStack(spacing: 0) {
            Rectangle().fill(.black.opacity(0.12)).frame(height: 1)
            Button(action: onSelect) {
                Text("SELECT")
                    .font(questFont(19)).foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(TierColor.selectPeach, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .background(Color.white.opacity(0.97))
    }
}

// MARK: - Shell

struct CreationFlowPhoneView: View {
    let repo: ContentRepository
    var onCreate: (CharacterChoices) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = HeroDraft()
    @State private var route: [CreationRoute] = []

    var body: some View {
        NavigationStack(path: $route) {
            NewHeroPhoneView(
                draft: draft,
                onCancel: { dismiss() },
                onBegin: { route.append(.pickPath) })
            .navigationDestination(for: CreationRoute.self) { r in
                destination(for: r)
                    .navigationBarBackButtonHidden(false)
            }
        }
    }

    @ViewBuilder
    private func destination(for r: CreationRoute) -> some View {
        switch r {
        case .pickPath:
            PickPathPhoneView(repo: repo, draft: draft) { pathID in
                route.append(.pathDetail(pathID))
            }
        case .pathDetail(let pathID):
            PathDetailPhoneView(repo: repo, pathID: pathID) {
                draft.pathID = pathID
                draft.classID = repo.path(pathID)?.classID
                route.append(.pickKind)
            }
        case .pickKind:
            PickKindPhoneView(repo: repo, draft: draft) { raceID in
                route.append(.kindDetail(raceID))
            }
        case .kindDetail(let raceID):
            KindDetailPhoneView(repo: repo, raceID: raceID) {
                draft.raceID = raceID
                if let hero = makeHero() {
                    onCreate(hero)
                }
                dismiss()
            }
        }
    }

    /// The one place a draft becomes a real character (duplicated from the iPad
    /// shell — same rules exactly). Seeds the spell loadout; gear starts BLANK per
    /// the design ruling (the sheet's Add picker offers the kit).
    private func makeHero() -> CharacterChoices? {
        guard let classID = draft.classID,
              let pathID = draft.pathID,
              let raceID = draft.raceID,
              !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }

        var c = CharacterChoices(name: draft.name, raceID: raceID, classID: classID, pathID: pathID)
        let ids = startingGrants(classID: classID, pathID: pathID, repo: repo).map(\.spellID)
        c.spellbookIDs = ids
        c.readySpellIDs = ids
        return c
    }
}

// MARK: - Screen 1: New Hero (the portal, portrait-sized)

struct NewHeroPhoneView: View {
    @Bindable var draft: HeroDraft
    var onCancel: () -> Void
    var onBegin: () -> Void

    private var nameReady: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("TINY QUEST DECK")
                    .font(questFont(21))
                    .foregroundStyle(Color(hex: "8A7BB8"))
                    .padding(.top, 6)

                // Name card — same composition, phone-tightened header row.
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Button("CANCEL", action: onCancel)
                            .font(questFont(13)).foregroundStyle(.black)
                            .padding(.horizontal, 11).padding(.vertical, 8)
                            .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
                        Spacer(minLength: 4)
                        Text("NEW HERO").font(questFont(17)).foregroundStyle(.black)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 4)
                        Button("CREATE", action: onBegin)
                            .font(questFont(13)).foregroundStyle(.black)
                            .padding(.horizontal, 11).padding(.vertical, 8)
                            .background(nameReady ? TierColor.selectPeach : TierColor.panelCream,
                                        in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
                            .disabled(!nameReady)
                            .opacity(nameReady ? 1 : 0.5)
                    }

                    Text("NAME").font(questFont(16)).foregroundStyle(.black)
                    TextField("", text: $draft.name)
                        .font(questFontLight(20))
                        .textInputAutocapitalization(.words)
                        .padding(.horizontal, 12).padding(.vertical, 11)
                        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
                        .submitLabel(.go)
                        .onSubmit { if nameReady { onBegin() } }
                }
                .padding(14)
                .background(Color(hex: "A8CBE4"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.black, lineWidth: 2))

                // The portal fills the phone — that's the moment, not a bug.
                QuestArt(
                    name: QuestArtKey.portal,
                    ratio: QuestRatio.portal,
                    colors: [Color(hex: "58C7E8"), Color(hex: "2E7FD0"), Color(hex: "7B5FC0")],
                    symbol: "sparkles.rectangle.stack",
                    caption: "portal art · 1536×2048",
                    framed: false)
            }
            .padding(14)
        }
        .background(Color.white)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Screen 2: Pick a Class (card rows scroll — one card + a peek)

struct PickPathPhoneView: View {
    let repo: ContentRepository
    var draft: HeroDraft? = nil          // nil = browse mode
    var onSelect: (String) -> Void       // pathID

    private let cardWidth: CGFloat = 168   // 9:16 → ~299 tall; one full + a peek

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let draft {
                    HStack(spacing: 8) {
                        phoneChip(draft.name.isEmpty ? "Name goes here" : draft.name)
                        Spacer(minLength: 0)
                    }
                    phoneChip("Pick a Class", size: 14)
                } else {
                    phoneChip("Classes", size: 14)
                }

                ForEach(repo.classes()) { cls in
                    classSection(cls)
                }
            }
            .padding(14)
        }
        .background(Color.white)
    }

    private func classSection(_ cls: ClassDefinition) -> some View {
        let paths = cls.pathIDs.compactMap { repo.path($0) }
        return VStack(alignment: .leading, spacing: 10) {
            Text(cls.name.uppercased()).font(questFont(20)).foregroundStyle(.black)
            Text(cls.role).font(questFontLight(13)).foregroundStyle(.black.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            // The iPad lays these flat at fixed width; at 390pt that clips. Here
            // the row scrolls — same cards, same fixed width, the peek says "more".
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
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
                                    .font(questFont(14))
                                    .foregroundStyle(.black)
                                    .lineLimit(1).minimumScaleFactor(0.6)
                            }
                            .frame(width: cardWidth)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: cls.theme.background), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.black, lineWidth: 2))
    }
}

// MARK: - Screen 3: Path Detail (restacked; SELECT pinned at the bottom)

struct PathDetailPhoneView: View {
    let repo: ContentRepository
    let pathID: String
    var onSelect: (() -> Void)? = nil    // nil = browse mode (no Select bar)

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
        .safeAreaInset(edge: .bottom) { selectBar(onSelect) }
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
            VStack(alignment: .leading, spacing: 14) {
                phoneChip(path.name, fill: Color(hex: theme.background), size: 16)

                // Portrait on top, centered — the panels get the full width below.
                QuestArt(
                    name: QuestArtKey.path(path.id),
                    ratio: QuestRatio.tall,
                    colors: [Color(hex: theme.accent), Color(hex: theme.background)],
                    symbol: emblemSymbol(theme.emblem),
                    caption: "\(path.name) art")
                    .frame(maxWidth: 210)
                    .frame(maxWidth: .infinity)

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

                TierPanel(title: "Signature Powers",
                          titleColor: TierColor.signature, icon: "sun.max.circle.fill") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(sigs) { a in abilityLine(a, color: TierColor.signature) }
                    }
                }
            }
            .padding(14)
        }
    }

    private func infoLine(_ s: String) -> some View {
        Text(s).font(questFontLight(14)).foregroundStyle(.black)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func abilityLine(_ a: AbilityDefinition, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(a.name).font(questFont(15)).foregroundStyle(color)
                Text(usageLine(a)).font(questFontLight(11)).foregroundStyle(.black.opacity(0.55))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(a.text).font(questFontLight(13)).foregroundStyle(color.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Screen 4: Pick a Kind (two-up card spread)

struct PickKindPhoneView: View {
    let repo: ContentRepository
    var draft: HeroDraft? = nil          // nil = browse mode
    var onSelect: (String) -> Void       // raceID

    // Two columns at phone width — the card-spread feel instead of one giant column.
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let draft {
                    HStack(spacing: 8) {
                        phoneChip(draft.name.isEmpty ? "Name goes here" : draft.name)
                        if let pathID = draft.pathID, let p = repo.path(pathID) {
                            phoneChip(p.name, size: 13)
                        }
                        Spacer(minLength: 0)
                    }
                    phoneChip("Pick a Kind", size: 14)
                } else {
                    phoneChip("Kinds", size: 14)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(repo.races()) { race in
                        Button { onSelect(race.id) } label: { kindTile(race) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
        }
        .background(Color.white)
    }

    private func kindTile(_ race: RaceDefinition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(race.name.uppercased())
                .font(questFont(15)).foregroundStyle(.black)
                .lineLimit(1).minimumScaleFactor(0.6)
            QuestArt(
                name: QuestArtKey.race(race.id),
                ratio: QuestRatio.card,
                colors: [raceTint(race.id), raceTint(race.id).opacity(0.55)],
                symbol: "person.crop.square.badge.camera",
                caption: "card 1200×1680")
                .rotationEffect(.degrees(-3))
                .padding(5)
        }
        .padding(10)
        .background(raceTint(race.id).opacity(0.45), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.black, lineWidth: 2))
    }
}

// MARK: - Screen 5: Kind Detail (tilted card above the lore; SELECT pinned)

struct KindDetailPhoneView: View {
    let repo: ContentRepository
    let raceID: String
    var onSelect: (() -> Void)? = nil    // nil = browse mode (no Select bar)

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
        .safeAreaInset(edge: .bottom) { selectBar(onSelect) }
    }

    private func content(_ race: RaceDefinition) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                phoneChip(race.name, fill: raceTint(race.id), size: 16)

                // The tilted hero card, centered, leaning over the lore panel below —
                // the iPad's side-by-side overlap turned vertical, charm intact.
                QuestArt(
                    name: QuestArtKey.race(race.id),
                    ratio: QuestRatio.card,
                    colors: [raceTint(race.id), raceTint(race.id).opacity(0.5)],
                    symbol: "person.crop.square.badge.camera",
                    caption: "\(race.name) card")
                    .frame(maxWidth: 215)
                    .frame(maxWidth: .infinity)
                    .rotationEffect(.degrees(-7))
                    .zIndex(1)

                TierPanel(title: race.tagline) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(race.lore).font(questFontLight(14)).foregroundStyle(.black)
                            .fixedSize(horizontal: false, vertical: true)

                        if !race.appearance.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(race.appearance, id: \.self) { line in
                                    Text("• \(line)").font(questFontLight(13))
                                        .foregroundStyle(.black.opacity(0.8))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(race.ability.name)
                                    .font(questFont(15)).foregroundStyle(TierColor.starting)
                                Text(usageLine(race.ability))
                                    .font(questFontLight(11)).foregroundStyle(.black.opacity(0.55))
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            Text(race.ability.text)
                                .font(questFontLight(13))
                                .foregroundStyle(TierColor.starting.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !race.nameIdeas.isEmpty {
                            Text("Name ideas: \(race.nameIdeas.joined(separator: ", "))")
                                .font(questFontLight(12)).foregroundStyle(.black.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, -26)   // tuck the panel under the leaning card
                .zIndex(0)

                // Group lineup banner — full width, 3:2 fits a phone naturally.
                QuestArt(
                    name: QuestArtKey.raceLineup(race.id),
                    ratio: QuestRatio.banner,
                    colors: [raceTint(race.id).opacity(0.9), Color(hex: "5B4A8A")],
                    symbol: "person.3.fill",
                    caption: "\(race.name) lineup banner")
            }
            .padding(14)
        }
    }
}
