//  CharacterSheetPhoneView.swift  (iPhone / compact — the character sheet)
//  Full parity with the iPad sheet as PAGED SHELVES (Joey's design): every row of
//  boxes becomes a viewAligned pager, one box per swipe with the next peeking —
//  the same gesture grammar as the phone battle board.
//
//    Shelf 0 — HEADER, two pages:
//        FIGHT: portrait+name · HP tile · the three stats · My Turn / Attack / Rest
//        HERO:  level badge · star track · gold · buffs · Hero Card · Rewards
//        (The action buttons live on the FIGHT page on purpose — they're every-turn
//        taps and a kid shouldn't swipe to find them. Easy to move.)
//    Shelf 1 — caster: Abilities [✦Signature] | Ready Spells | Spellbook…
//              non-caster: Abilities [✦Signature] | Gear | Show-off Gear | Show-off Items
//    Shelf 2 — Pets… | Spirit | +Pet | (caster: Gear) | Normal | Magic | (caster: show-offs)
//    Bottom  — the combat tracker, PAGED like the shelves: Next Attack big and
//              first, Until Next Turn peeking, This Fight one more swipe. Count
//              capsules flag chips waiting in off-screen scopes.
//
//  PARALLEL VIEW, NOT A BRANCH: CharacterSheetView.swift is byte-identical except
//  three access keywords (RechargeRollView / PortraitPicker / ArtPicker go internal
//  for reuse — the CombatantDetail precedent). MainTabView selects this at compact
//  width. LevelUpSheet and the tracker "+" popover are DUPLICATED in trimmed phone
//  metrics instead of reused: both carry fixed iPad widths (480 / 440) that clip at
//  390pt, and squeezing them would mean touching the iPad file's layout.
//
//  Every behavior rule carries over verbatim: the dice pillar (Recharge asks what
//  you rolled), stars entitle / the kid claims, single write path through
//  commitChoices, Beast Mode / Voice of the Wild spend-choice routing, scroll
//  learning, and the dev gold/star controls (they retire with the table run, on
//  both layouts at once).
//
//  NO LAZY CONTAINERS in the shelves. Swift 6 discipline: small named sub-pieces.

import SwiftUI

// Phone metrics — heights echo SheetMetrics; widths are container-relative.
private enum PhoneSheet {
    static let pageFraction: CGFloat = 0.94   // the peek that says "keep swiping"
    static let headerHeight: CGFloat = 332
    static let row1Height: CGFloat = 300
    static let row2Height: CGFloat = 240
    static let trackerHeight: CGFloat = 180
        /// Tracker cards: wider than half, narrower than a page, so the next scope
        /// always peeks. Next Attack gets the eye; the rest are one swipe away.
        static let trackerPageFraction: CGFloat = 0.62
    static let gearCap = 10
    static let gearMinSlots = 4
    static let bookBoxSize = 6
    static let showcaseCap = 3
}

struct CharacterSheetPhoneView: View {
    let repo: ContentRepository
    let roster: RosterStore
    let combat: CombatStore
    let gm: GMStore
    let characterID: UUID

    private var character: CharacterChoices? {
        roster.characters.first { $0.id == characterID }
    }

    var body: some View {
        Group {
            if let c = character, let sheet = deriveSheet(from: c, using: repo) {
                PhoneSheetBody(repo: repo, roster: roster, combat: combat, gm: gm,
                               character: c, sheet: sheet)
                    .onAppear {
                        combat.seed(c.id, maxHP: sheet.maxHP)
                        c.pets.forEach { pet in
                            let stats = derivePetStats(for: pet, abilities: sheet.abilities, repo: repo)
                            combat.seedPet(c.id, petID: pet.id, maxHP: stats.maxHP)
                        }
                    }
            } else {
                ContentUnavailableView("No hero selected",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Pick a hero from the Heroes tab or create a new one."))
            }
        }
    }
}

// MARK: - Body

private struct PhoneSheetBody: View {
    let repo: ContentRepository
    let roster: RosterStore
    let combat: CombatStore
    let gm: GMStore
    let character: CharacterChoices
    let sheet: CharacterSheet

    @State private var showRecharge = false
    @State private var showLevelUp = false
    @State private var addingMagicItem = false
    @State private var addingNormalItem = false
    @State private var namingPet = false
    @State private var petAlertTitle = "Name your pet!"
    @State private var pendingCompanionID: String? = nil
    @State private var newItemText = ""
    @State private var pendingTransform: PendingTransform? = nil
    @State private var pendingSummon: PendingSummon? = nil
    @State private var pickingPortrait = false
    @State private var pickingPetArtFor: PetChoice? = nil
    @State private var pickingSpiritArt = false
    @State private var showcaseInfoItem: ItemDefinition? = nil
    @State private var pendingLearn: PendingLearn? = nil
    @State private var showingHeroCard = false
    @State private var showingRedeem = false
    // Mirrors of the iPad sheet's temporary honor-system controls. They retire
    // together, on both layouts, after the clean table run — not before.
    private let showGearGrantDevControl = true
    private let showGoldDevControls = true
    private let showStarDevControls = true
    private let goldStep = 1

    private struct PendingTransform {
        let ability: AbilityDefinition
        let boxIndex: Int
        let total: Int
    }

    private struct PendingLearn {
        let itemName: String
        let spell: SpellDefinition
    }

    private struct PendingSummon {
        let ability: AbilityDefinition
        let boxIndex: Int
        let total: Int
    }

    private enum WildMode { case roots, bloom, spirit }

    private struct PetBadge { let text: String; let symbol: String }

    private var bg: Color { sheet.theme.map { Color(hex: $0.background) } ?? .blue }
    private var accent: Color { sheet.theme.map { Color(hex: $0.accent) } ?? .blue }
    private var state: CombatState { combat.states[character.id] ?? CombatState(currentHP: sheet.maxHP) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerPager
                sheetPanel
            }
            .padding(12)
        }
        .background(Color.white)
        .confirmationDialog(pendingLearn.map { "Learn \($0.spell.name)?" } ?? "",
                            isPresented: learnBinding, titleVisibility: .visible,
                            presenting: pendingLearn) { p in
            Button("Learn it — the scroll is used up") { learnScroll(p) }
            Button("Keep the scroll", role: .cancel) {}
        } message: { p in
            Text("\(p.spell.name) goes in your spellbook for good — ready it from your spell list when you want to cast it. The scroll is gone after this, so if you'd rather give it to someone else, keep it.")
        }
    }

    private var learnBinding: Binding<Bool> {
        Binding(get: { pendingLearn != nil }, set: { if !$0 { pendingLearn = nil } })
    }

    // MARK: Shelf 0 — the header pager (FIGHT page · HERO page)

    private var headerPager: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                fightPage
                    .containerRelativeFrame(.horizontal) { l, _ in l * PhoneSheet.pageFraction }
                heroPage
                    .containerRelativeFrame(.horizontal) { l, _ in l * PhoneSheet.pageFraction }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .frame(height: PhoneSheet.headerHeight)
    }

    /// Page 1 — everything a kid touches every turn.
    private var fightPage: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                portraitBlock.frame(width: 126)
                hpTile.frame(maxWidth: .infinity)
            }
            HStack(spacing: 8) {
                statTile("MIGHT", .might)
                statTile("SPEED", .speed)
                statTile("MIND", .mind)
            }
            actionButtons
        }
    }

    /// Page 2 — progress & treasure: level, stars, gold, and the QR corner.
    private var heroPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            levelBadge
            starBar
            HStack(spacing: 10) {
                goldBar
                Spacer(minLength: 0)
                buffSlot
            }
            HStack(spacing: 8) {
                heroCardButton
                redeemButton
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
    }

    private var portraitCombo: String {
        character.portraitID ?? QuestArtKey.portraitCombo(race: character.raceID, klass: character.classID)
    }

    private var portraitBlock: some View {
        VStack(spacing: -18) {
            Button { pickingPortrait = true } label: {
                QuestArt(name: QuestArtKey.portrait(combo: portraitCombo),
                         ratio: QuestRatio.card,
                         colors: [accent, bg],
                         symbol: emblemSymbol(sheet.theme?.emblem),
                         caption: "tap to choose")
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, accent)
                            .padding(6)
                    }
            }
            .buttonStyle(.plain)
            Text(sheet.name.uppercased())
                .font(questFont(13))
                .foregroundStyle(.black)
                .lineLimit(2).minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black, lineWidth: 2))
                .zIndex(1)
        }
        .sheet(isPresented: $pickingPortrait) {
            PortraitPicker(repo: repo, currentCombo: portraitCombo, bg: bg, accent: accent) { combo in
                var c = character
                c.portraitID = combo
                roster.update(c)
            }
        }
    }

    private var hpTile: some View {
        let hpColor: Color = state.currentHP <= 0 ? .red
            : (Double(state.currentHP) / Double(max(sheet.maxHP, 1)) <= 0.5 ? .orange : .green)
        return VStack(spacing: 2) {
            Text("Health Points").font(questFont(14)).foregroundStyle(.black)
            Text("\(sheet.maxHP) Max").font(questFontLight(12)).foregroundStyle(.black.opacity(0.6))
            Text("\(state.currentHP)")
                .font(.system(size: 42, weight: .heavy, design: .rounded))
                .foregroundStyle(hpColor)
                .contentTransition(.numericText())
            HStack(spacing: 6) {
                hpButton("-5") { combat.damage(character.id, 5) }
                hpButton("-1") { combat.damage(character.id, 1) }
                hpButton("+1") { combat.heal(character.id, 1, maxHP: sheet.maxHP) }
                hpButton("+5") { combat.heal(character.id, 5, maxHP: sheet.maxHP) }
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
    }

    private func hpButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(questFont(13))
                .foregroundStyle(label.hasPrefix("-") ? .red : .green)
                .frame(width: 38, height: 32)   // kid-thumb sized
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func statTile(_ label: String, _ stat: Stat) -> some View {
        let value: Int = switch stat {
            case .might: sheet.might; case .speed: sheet.speed; case .mind: sheet.mind
        }
        return VStack(spacing: 2) {
            Text(label).font(questFont(12)).foregroundStyle(.black)
            Text("+\(value)")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(hex: "4AA3DF"))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
    }

    // MARK: Action buttons (pinned to the FIGHT page — every-turn taps)

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button { showRecharge = true } label: {
                actionLabel("My Turn!", "die.face.6", fill: TierColor.panelCream)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showRecharge, arrowEdge: .bottom) {
                RechargeRollView { rolled in
                    combat.apply(character.id, event: .myTurnStarted)
                    combat.recharge(character.id, rolled: rolled,
                                    rechargeAbilityIDs: sheet.rechargeAbilityIDs,
                                    rechargeSpellIDs: sheet.rechargeSpellIDs)
                    showRecharge = false
                }
                .presentationCompactAdaptation(.popover)
            }

            Button { combat.apply(character.id, event: .attackResolved) } label: {
                actionLabel("Attack Done", "checkmark.seal", fill: TierColor.panelCream)
            }
            .buttonStyle(.plain)

            Button { combat.rest(character.id, maxHP: sheet.maxHP) } label: {
                actionLabel("Rest", "moon.zzz.fill", fill: TierColor.selectPeach)
            }
            .buttonStyle(.plain)
        }
    }

    private func actionLabel(_ text: String, _ symbol: String, fill: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(questFont(13)).foregroundStyle(.black)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(fill, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
    }

    // MARK: Level badge, stars, wallet, QR corner (the HERO page)

    private var levelBadge: some View {
        Button { showLevelUp = true } label: {
            HStack(spacing: 8) {
                Text(sheet.pathName.uppercased()).font(questFont(17))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 4)
                Text("Level \(sheet.level)").font(questFont(19))
                    .lineLimit(1).fixedSize()
                if character.canLevelUp {
                    Image(systemName: "sparkles")
                        .font(.body).foregroundStyle(TierColor.signature)
                }
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(bg, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(character.canLevelUp ? TierColor.signature : .black,
                              lineWidth: character.canLevelUp ? 3 : 2))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showLevelUp) {
            PhoneLevelUpSheet(
                targetLevel: min(character.level + 1, 3),
                pointsPool: 2,
                currentMight: sheet.might,
                currentSpeed: sheet.speed,
                currentMind: sheet.mind,
                atMaxLevel: character.level >= 3,
                starsToGo: character.canLevelUp ? nil : character.starsToNextLevel,
                bg: bg, accent: accent
            ) { alloc in
                levelUp(applying: alloc)
            }
            .presentationDetents([.large])
        }
    }

    private var starBar: some View {
        let add:    (() -> Void)? = showStarDevControls ? { adjustStars(by: 1) } : nil
        let remove: (() -> Void)? = showStarDevControls ? { adjustStars(by: -1) } : nil
        return StarTrack(stars: character.stars,
                         readyToLevel: character.canLevelUp,
                         onAdd: add, onRemove: remove)
    }

    private func adjustStars(by delta: Int) {
        var c = character
        c.stars = max(0, c.stars + delta)
        roster.update(c)
    }

    private var goldBar: some View {
        HStack(spacing: 10) {
            if showGoldDevControls {
                goldStepButton("minus.circle.fill", tint: .red.opacity(0.8)) { adjustGold(by: -goldStep) }
            }
            HStack(spacing: 6) {
                coinIcon
                Text("\(character.gold)")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(hex: "C79008"))
                    .contentTransition(.numericText())
            }
            if showGoldDevControls {
                goldStepButton("plus.circle.fill", tint: .green.opacity(0.85)) { adjustGold(by: goldStep) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
        .fixedSize()
    }

    private var heroCardButton: some View {
        Button { showingHeroCard = true } label: {
            Label("Hero Card", systemImage: "qrcode")
                .font(questFont(13)).foregroundStyle(.black)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingHeroCard) {
            HeroCardSheet(hero: character, repo: repo, bg: bg, accent: accent)
                .presentationDetents([.medium, .large])
        }
    }

    private var redeemButton: some View {
        Button { showingRedeem = true } label: {
            Label("Rewards", systemImage: "qrcode.viewfinder")
                .font(questFont(13)).foregroundStyle(.black)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingRedeem) {
            RedeemSheet(hero: character, repo: repo, roster: roster, gm: gm,
                        bg: bg, accent: accent)
        }
    }

    private func goldStepButton(_ symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title2).foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }

    private var coinIcon: some View {
        ZStack {
            Circle().fill(Color(hex: "E8B923"))
            Circle().strokeBorder(Color(hex: "B5860B"), lineWidth: 2).padding(2)
        }
        .frame(width: 20, height: 20)
    }

    private func adjustGold(by delta: Int) {
        var c = character
        c.gold = max(0, c.gold + delta)
        roster.update(c)
    }

    private var buffSlot: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile").foregroundStyle(.red.opacity(0.3))
            Image(systemName: "shield.lefthalf.filled").foregroundStyle(.blue.opacity(0.3))
        }
        .font(.title3)
        .padding(.trailing, 2)
    }

    /// Same rules as the iPad: level bump + point spend + HP recompute + granted
    /// companions. One write path.
    private func levelUp(applying alloc: [Stat: Int]) {
        var c = character
        c.level += 1
        for (stat, n) in alloc where n != 0 {
            c.statBoosts[stat.rawValue, default: 0] += n
        }
        commitChoices(c)
        promptForGrantedCompanion(atNewLevel: c.level)
    }

    private func promptForGrantedCompanion(atNewLevel level: Int) {
        guard let path = repo.path(character.pathID) else { return }
        let newIDs: [String] = switch level {
            case 2: path.pathPowerIDs
            case 3: path.signaturePowerIDs
            default: []
        }
        let grantsPet = newIDs.compactMap { repo.ability($0) }
            .flatMap(\.effects)
            .contains { if case .companion = $0 { return true } else { return false } }
        if grantsPet {
            pendingCompanionID = nil
            newItemText = ""
            petAlertTitle = "A new best friend joins you! What's their name?"
            namingPet = true
        }
    }

    // MARK: The themed panel — two paged shelves + the tracker

    private var sheetPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            shelf(height: PhoneSheet.row1Height) {
                abilitiesBox
                if showsSignatureBox { signatureBox }
                if sheet.isCaster {
                    readySpellsBox
                    ForEach(Array(benchChunks.enumerated()), id: \.offset) { i, chunk in
                        spellbookBox(chunk, index: i)
                    }
                    if benchChunks.isEmpty { spellbookBox([], index: 0) }
                } else {
                    gearBox
                    showcaseGearBox
                    showcaseItemsBox
                }
            }
            // Voice of the Wild rides on shelf 1 (where its box lives) — kept apart
            // from the transform dialog below: two confirmationDialogs on one view
            // is the known bad shape.
            .confirmationDialog("Wild gift?",
                                isPresented: Binding(get: { pendingSummon != nil },
                                                     set: { if !$0 { pendingSummon = nil } }),
                                titleVisibility: .visible,
                                presenting: pendingSummon) { pending in
                Button("Roots — 2 foes Stuck") { spendVoice(pending, mode: .roots) }
                Button("Bloom — 2 foes Hurt")  { spendVoice(pending, mode: .bloom) }
                Button("Call a Spirit Animal!") { spendVoice(pending, mode: .spirit) }
                    .disabled(state.summon != nil)
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text(state.summon != nil
                     ? "Your spirit animal is already here — pick Roots or Bloom."
                     : "What does the wild answer with?")
            }

            shelf(height: PhoneSheet.row2Height) {
                ForEach(Array(character.pets.enumerated()), id: \.element.id) { i, pet in
                    petBox(pet, isLast: i == character.pets.count - 1)
                }
                if let summon = state.summon { summonBox(summon) }
                if character.pets.isEmpty { addPetBox }
                if sheet.isCaster { gearBox }

                itemsBox(title: "Normal Items", items: character.normalItems,
                         adding: $addingNormalItem) { commitItems(normal: $0) }
                itemsBox(title: "Magic Items", items: character.magicItems,
                         adding: $addingMagicItem,
                         learnable: learnableSpell) { commitItems(magic: $0) }
                if sheet.isCaster {
                    showcaseGearBox
                    showcaseItemsBox
                }
            }

            trackerPanel
        }
        .padding(10)
        .background(bg.opacity(0.85), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.black, lineWidth: 2))
        .alert(petAlertTitle, isPresented: $namingPet) {
            TextField("Pet name", text: $newItemText)
            Button("Add") {
                defer { newItemText = ""; pendingCompanionID = nil; petAlertTitle = "Name your pet!" }
                guard !newItemText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                var c = character
                let pet = PetChoice(name: newItemText, companionID: pendingCompanionID)
                c.pets.append(pet)
                roster.update(c)
                let stats = derivePetStats(for: pet, abilities: sheet.abilities, repo: repo)
                combat.seedPet(c.id, petID: pet.id, maxHP: stats.maxHP)
            }
            Button("Cancel", role: .cancel) {
                newItemText = ""; pendingCompanionID = nil; petAlertTitle = "Name your pet!"
            }
        }
        .confirmationDialog("Who grows?!",
                            isPresented: Binding(get: { pendingTransform != nil },
                                                 set: { if !$0 { pendingTransform = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingTransform) { pending in
            ForEach(character.pets) { pet in
                Button(pet.name) {
                    spendWithTransform(pending.ability, boxIndex: pending.boxIndex,
                                       total: pending.total, pet: pet)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $pickingPetArtFor) { pet in
            ArtPicker(title: "\(pet.name)'s Look",
                      currentImageID: pet.imageID,
                      defaultArtName: petFallbackArt(pet),
                      slotCount: QuestArtKey.petArtSlotCount,
                      key: QuestArtKey.pet,
                      symbol: "pawprint.fill",
                      bg: bg, accent: accent) { newImageID in
                var c = character
                if let idx = c.pets.firstIndex(where: { $0.id == pet.id }) {
                    c.pets[idx].imageID = newImageID
                    roster.update(c)
                }
            }
        }
        .popover(item: $showcaseInfoItem) { item in
            VStack(alignment: .leading, spacing: 8) {
                Text(item.name).font(questFont(20)).foregroundStyle(.black)
                Text(item.text).font(questFontLight(15)).foregroundStyle(.black.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18).frame(maxWidth: 320)
            .presentationCompactAdaptation(.popover)
        }
    }

    /// A paged shelf of uniform boxes — the phone's boxRow. One box per swipe,
    /// the next peeking; NOT lazy.
    private func shelf<Content: View>(height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) { content() }
                .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .frame(height: height)
    }

    /// The uniform box, container-relative instead of 370pt fixed. Same chrome.
    private func sheetBox<Content: View>(_ title: String, height: CGFloat,
                                         titleColor: Color = .black,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(questFont(16)).foregroundStyle(titleColor)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                .lineLimit(1).minimumScaleFactor(0.7)
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(height: height - 34)
                .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
        }
        .containerRelativeFrame(.horizontal) { l, _ in l * PhoneSheet.pageFraction }
    }

    private func emptySlot(_ hint: String = "empty") -> some View {
        Text(hint)
            .font(questFontLight(12)).foregroundStyle(.black.opacity(0.3))
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.black.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }

    // MARK: Abilities

    private var showsSignatureBox: Bool {
        sheet.showsSignatureBox && !sheet.signatureAbilities.isEmpty
    }

    private var abilitiesBox: some View {
        abilityListBox("Abilities",
                       items: showsSignatureBox ? sheet.nonSignatureAbilities : sheet.abilities,
                       titleColor: .black)
    }

    private var signatureBox: some View {
        abilityListBox("✦ Signature Powers", items: sheet.signatureAbilities,
                       titleColor: TierColor.signature)
    }

    private func abilityListBox(_ title: String, items: [SheetAbility], titleColor: Color) -> some View {
        sheetBox(title, height: PhoneSheet.row1Height, titleColor: titleColor) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items, id: \.ability.id) { item in abilityRow(item) }
                }
            }
        }
    }

    private func tierColor(_ s: AbilitySource) -> Color {
        switch s {
        case .core, .race:  TierColor.starting
        case .pathPower:    TierColor.path
        case .signature:    TierColor.signature
        }
    }

    private func tierIcon(_ s: AbilitySource) -> String? {
        switch s {
        case .pathPower: "bolt.circle.fill"
        case .signature: "sun.max.circle.fill"
        default: nil
        }
    }

    private func abilityRow(_ item: SheetAbility) -> some View {
        let a = item.ability
        let color = tierColor(item.source)
        let spent = state.spentUses(a.id)
        let fullySpent = state.isFullySpent(a.id, of: item.totalUses)

        return HStack(spacing: 8) {
            TapInfo(payload: .init(ability: a, tint: color)) {
                Text(a.name)
                    .font(questFont(14))
                    .foregroundStyle(item.isAvailable ? color : color.opacity(0.5))
                    .strikethrough(!item.isAvailable || fullySpent)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            if let icon = tierIcon(item.source) {
                Image(systemName: icon).font(.caption).foregroundStyle(color)
            }
            if !item.isAvailable {
                Text("Not Equipped").font(questFontLight(11)).foregroundStyle(.red)
            }
            Spacer(minLength: 4)
            if item.totalUses > 0 && item.isAvailable {
                HStack(spacing: 4) {
                    ForEach(0..<item.totalUses, id: \.self) { i in
                        Button {
                            tapAbilityBox(a, boxIndex: i, total: item.totalUses)
                        } label: {
                            Image(systemName: i < spent ? "checkmark.square.fill" : "square")
                                .font(.title3)
                                .foregroundStyle(i < spent ? .black.opacity(0.45) : color)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Same spend-choice routing as the iPad: summon → mode picker; transform →
    /// pet picker (or the only pet); everything else plain.
    private func tapAbilityBox(_ a: AbilityDefinition, boxIndex i: Int, total: Int) {
        let spending = i >= state.spentUses(a.id)
        let transforms = a.effects.contains {
            if case .petTransform = $0 { return true } else { return false }
        }
        let summons = a.effects.contains {
            if case .summon = $0 { return true } else { return false }
        }

        if spending && summons {
            pendingSummon = PendingSummon(ability: a, boxIndex: i, total: total)
        } else if spending && transforms && character.pets.count > 1 {
            pendingTransform = PendingTransform(ability: a, boxIndex: i, total: total)
        } else if spending && transforms, let pet = character.pets.first {
            spendWithTransform(a, boxIndex: i, total: total, pet: pet)
        } else {
            combat.setAbilitySpent(character.id, ability: a, toBoxIndex: i, total: total,
                                   rechargeSpellIDs: sheet.rechargeSpellIDs)
        }
    }

    private func spendWithTransform(_ a: AbilityDefinition, boxIndex: Int, total: Int, pet: PetChoice) {
        let stats = derivePetStats(for: pet, abilities: sheet.abilities, repo: repo)
        combat.setAbilitySpent(character.id, ability: a, toBoxIndex: boxIndex, total: total,
                               rechargeSpellIDs: sheet.rechargeSpellIDs,
                               transformPet: TransformTarget(petID: pet.id, petName: pet.name,
                                                             normalMaxHP: stats.maxHP))
    }

    private func spendVoice(_ pending: PendingSummon, mode: WildMode) {
        let a = pending.ability
        func spendBox(summonSpec: SummonSpec? = nil) {
            combat.setAbilitySpent(character.id, ability: a, toBoxIndex: pending.boxIndex,
                                   total: pending.total, rechargeSpellIDs: sheet.rechargeSpellIDs,
                                   summonSpec: summonSpec)
        }
        func note(_ label: String) {
            combat.addModifier(character.id, Modifier(label: label, value: 0, target: .any,
                                                      scope: .thisFight, source: .manual))
        }
        switch mode {
        case .roots:
            spendBox(); note("Roots: 2 foes Stuck")
        case .bloom:
            spendBox(); note("Bloom: 2 foes Hurt")
        case .spirit:
            guard state.summon == nil else { return }
            spendBox(summonSpec: SummonSpec(name: "Spirit Animal"))
        }
    }

    // MARK: Showcase boxes

    private var showcaseGearBox: some View {
        let picks = character.showcaseGearIDs.compactMap { repo.gear($0) }.map(Purchasable.gear)
        let have = Set(character.equippedGearIDs + character.ownedGearIDs)
        let candidates = have.compactMap { repo.gear($0) }
            .filter { !character.showcaseGearIDs.contains($0.id) }
            .sorted { $0.name < $1.name }.map(Purchasable.gear)
        return showcaseBox(title: "Show-off Gear", picks: picks, candidates: candidates,
            onAdd:    { if case .gear(let g) = $0 { mutate { $0.showcaseGearIDs.append(g.id) } } },
            onRemove: { if case .gear(let g) = $0 { mutate { $0.showcaseGearIDs.removeAll { $0 == g.id } } } })
    }

    private var showcaseItemsBox: some View {
        let picks = character.showcaseItemIDs.compactMap { repo.item($0) }.map(Purchasable.item)
        let ownedNames = Set(character.normalItems + character.magicItems)
        let candidates = repo.items()
            .filter { ownedNames.contains($0.name) && !character.showcaseItemIDs.contains($0.id) }
            .sorted { $0.name < $1.name }.map(Purchasable.item)
        return showcaseBox(title: "Show-off Items", picks: picks, candidates: candidates,
            onAdd:    { if case .item(let i) = $0 { mutate { $0.showcaseItemIDs.append(i.id) } } },
            onRemove: { if case .item(let i) = $0 { mutate { $0.showcaseItemIDs.removeAll { $0 == i.id } } } })
    }

    /// Both shelves are the same height on the phone, so the caster/non-caster
    /// height fork disappears; the art shrinks a notch to fit three-up.
    private func showcaseBox(title: String, picks: [Purchasable], candidates: [Purchasable],
                             onAdd: @escaping (Purchasable) -> Void,
                             onRemove: @escaping (Purchasable) -> Void) -> some View {
        sheetBox(title, height: sheet.isCaster ? PhoneSheet.row2Height : PhoneSheet.row1Height) {
            VStack {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(picks) { p in showcaseArt(p, onRemove: onRemove) }
                    if picks.count < PhoneSheet.showcaseCap {
                        showcaseAddSlot(candidates: candidates, onAdd: onAdd)
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private func showcaseArt(_ p: Purchasable, onRemove: @escaping (Purchasable) -> Void) -> some View {
        let art = QuestArt(name: questArtName(for: p), ratio: 0.52, colors: [accent, bg],
                           symbol: categorySymbol(ShopCategory.category(of: p)), caption: nil, framed: false)
            .frame(width: 82, height: 156)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black, lineWidth: 2))

        Group {
            switch p {
            case .gear(let g): TapInfo(payload: .init(gear: g, tint: accent)) { art }
            case .item:        Button { if case .item(let i) = p { showcaseInfoItem = i } } label: { art }
                                   .buttonStyle(.plain)
            }
        }
        .contextMenu { Button("Remove", role: .destructive) { onRemove(p) } }
    }

    private func showcaseAddSlot(candidates: [Purchasable], onAdd: @escaping (Purchasable) -> Void) -> some View {
        Menu {
            if candidates.isEmpty {
                Text("Buy or equip something to show off!")
            } else {
                ForEach(candidates) { p in Button(p.name) { onAdd(p) } }
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus.circle.fill").font(.title).foregroundStyle(accent.opacity(0.6))
                Text("Add").font(questFontLight(12)).foregroundStyle(.black.opacity(0.4))
            }
            .frame(width: 92, height: 156)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.black.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
        .buttonStyle(.plain)
    }

    private func mutate(_ f: (inout CharacterChoices) -> Void) {
        var c = character; f(&c); roster.update(c)
    }

    // MARK: Gear box

    private var gearBox: some View {
        sheetBox("Gear", height: sheet.isCaster ? PhoneSheet.row2Height : PhoneSheet.row1Height) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(sheet.gear.enumerated()), id: \.offset) { index, g in
                        gearRow(g, index: index)
                    }
                    gearAddMenu
                    let shown = sheet.gear.count + 1
                    if shown < PhoneSheet.gearMinSlots {
                        ForEach(0..<(PhoneSheet.gearMinSlots - shown), id: \.self) { _ in
                            emptySlot()
                        }
                    }
                }
            }
        }
    }

    private func gearRow(_ g: GearDefinition, index: Int) -> some View {
        HStack {
            TapInfo(payload: .init(gear: g, tint: accent)) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(g.name).font(questFont(13)).foregroundStyle(.black)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        if sheet.hasDualWield && g.category == .lightMelee && isSecondLightMelee(at: index) {
                            Text("FREE ACTION").font(questFontLight(10)).foregroundStyle(TierColor.path)
                        }
                    }
                    if let atk = g.attack {
                        Text(attackSummary(atk))
                            .font(.caption2.monospaced()).foregroundStyle(.black.opacity(0.55))
                    } else if g.maxHP != 0 {
                        Text("+\(g.maxHP) Max HP").font(questFontLight(12)).foregroundStyle(accent)
                    }
                }
            }
            Spacer()
            Button { removeGear(at: index) } label: {
                Image(systemName: "minus.circle").foregroundStyle(.red.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
    }

    private func isSecondLightMelee(at index: Int) -> Bool {
        let lightIndexes = sheet.gear.enumerated()
            .filter { $0.element.category == .lightMelee && $0.element.attack != nil }
            .map(\.offset)
        return lightIndexes.count >= 2 && index != lightIndexes.first
    }

    // MARK: Gear "Add" menu (same grouping + ★ nudge as the iPad)

    private struct GearGroup: Identifiable {
        let id: Int
        let title: String
        let items: [GearDefinition]
    }

    private var bestStats: Set<Stat> {
        let top = max(sheet.might, max(sheet.speed, sheet.mind))
        var out: Set<Stat> = []
        if sheet.might == top { out.insert(.might) }
        if sheet.speed == top { out.insert(.speed) }
        if sheet.mind  == top { out.insert(.mind) }
        return out
    }

    private func statWord(_ s: Stat) -> String {
        switch s { case .might: "Might"; case .speed: "Speed"; case .mind: "Mind" }
    }

    private func gearFamily(_ g: GearDefinition) -> (order: Int, base: String, stat: Stat?) {
        switch g.category {
        case .heavyMelee:  return (0, "Heavy Weapons", .might)
        case .lightMelee:
            return g.attack?.toHitStat == .might
                ? (1, "Heavy One-Handers", .might)
                : (2, "Finesse Weapons",   .speed)
        case .rangedPhysical:
            return g.attack?.damageStat == nil
                ? (3, "Small Ranged", .speed)
                : (2, "Ranged Weapons", .speed)
        case .magicMental: return (4, "Magic Weapons", .mind)
        case .armor:       return (5, "Armor", nil)
        case .shield:      return (6, "Shields", nil)
        case .advClothes:  return (7, "Clothes", nil)
        }
    }

    private func gearGroups(_ items: [GearDefinition]) -> [GearGroup] {
        var buckets: [Int: (title: String, items: [GearDefinition])] = [:]
        for g in items {
            let fam = gearFamily(g)
            let title: String = {
                guard let stat = fam.stat else { return fam.base }
                let star = bestStats.contains(stat) ? "★ " : ""
                return "\(star)\(fam.base)  ·  \(statWord(stat))"
            }()
            buckets[fam.order, default: (title, [])].items.append(g)
        }
        return buckets.keys.sorted().map {
            GearGroup(id: $0, title: buckets[$0]!.title, items: buckets[$0]!.items)
        }
    }

    private func gearMenuButton(_ g: GearDefinition) -> some View {
        Button { addGear(g.id) } label: { Text(g.name) }
    }

    private var gearAddMenu: some View {
        let kitIDs = repo.path(character.pathID)?.startingGearIDs ?? []
        let kit = kitIDs.compactMap { repo.gear($0) }
        let owned = Set(character.ownedGearIDs)
            .compactMap { repo.gear($0) }
            .filter { !kitIDs.contains($0.id) }
            .sorted { $0.name < $1.name }

        return Menu {
            Section("Starting Kit") {
                ForEach(kit) { g in gearMenuButton(g) }
            }
            if !owned.isEmpty {
                Section("Owned") {
                    ForEach(owned) { g in gearMenuButton(g) }
                }
            }
            if showGearGrantDevControl {
                Section("Found on an Adventure") {
                    Menu("Add treasure…") {
                        ForEach(gearGroups(repo.allGear().filter { !character.ownedGearIDs.contains($0.id) })) { group in
                            Section(group.title) {
                                ForEach(group.items) { g in
                                    Button(g.name) { mutate { $0.acquire(.gear(g), source: .foundLoot, repo: repo) } }
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Add", systemImage: "plus.circle.fill")
                .font(questFont(13)).foregroundStyle(accent)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
    }

    private func addGear(_ id: String) {
        guard character.equippedGearIDs.count < PhoneSheet.gearCap else { return }
        var c = character
        c.equippedGearIDs.append(id)
        commitChoices(c)
    }

    private func removeGear(at index: Int) {
        var c = character
        guard c.equippedGearIDs.indices.contains(index) else { return }
        c.equippedGearIDs.remove(at: index)
        commitChoices(c)
    }

    /// Single write path — identical to the iPad sheet's.
    private func commitChoices(_ c: CharacterChoices) {
        let oldMax = sheet.maxHP
        roster.update(c)
        if let newSheet = deriveSheet(from: c, using: repo) {
            combat.adjustMaxHP(c.id, delta: newSheet.maxHP - oldMax, newMaxHP: newSheet.maxHP)
        }
    }

    // MARK: Spells

    private var benchChunks: [[SheetSpell]] {
        stride(from: 0, to: sheet.benchSpells.count, by: PhoneSheet.bookBoxSize).map {
            Array(sheet.benchSpells[$0..<min($0 + PhoneSheet.bookBoxSize, sheet.benchSpells.count)])
        }
    }

    private var readySpellsBox: some View {
        sheetBox("Spells ✦  (\(sheet.readySpells.count)/\(sheet.readySpellCap))",
                 height: PhoneSheet.row1Height) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(sheet.readySpells, id: \.spell.id) { s in spellRow(s, ready: true) }
                        ForEach(0..<max(0, sheet.readySpellCap - sheet.readySpells.count), id: \.self) { _ in
                            emptySlot("spell slot")
                        }
                    }
                }
                spellAddMenu
            }
        }
    }

    private func spellbookBox(_ chunk: [SheetSpell], index: Int) -> some View {
        sheetBox(index == 0 ? "Spellbook" : "Spellbook \(index + 1)",
                 height: PhoneSheet.row1Height) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(chunk, id: \.spell.id) { s in spellRow(s, ready: false) }
                ForEach(0..<max(0, PhoneSheet.bookBoxSize - chunk.count), id: \.self) { _ in
                    emptySlot("found spells go here")
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func spellRow(_ s: SheetSpell, ready: Bool) -> some View {
        let spent = state.spellUsesSpent[s.spell.id] ?? 0
        return HStack(spacing: 8) {
            TapInfo(payload: .init(spell: s.spell, uses: s.readyUses, tint: TierColor.starting)) {
                Text(s.spell.name).font(questFont(13))
                    .foregroundStyle(ready ? TierColor.starting : .black.opacity(0.65))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            if ready {
                HStack(spacing: 4) {
                    ForEach(0..<max(s.readyUses, 1), id: \.self) { i in
                        Button {
                            combat.setSpent(character.id, s.spell.id, toBoxIndex: i, total: s.readyUses)
                        } label: {
                            Image(systemName: i < spent ? "checkmark.square.fill" : "square")
                                .font(.body)
                                .foregroundStyle(i < spent ? .black.opacity(0.4) : TierColor.starting)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Menu {
                if ready {
                    Button("Move to Spellbook") { moveSpell(s.spell.id, toReady: false) }
                } else if sheet.readySpells.count < sheet.readySpellCap {
                    Button("Make Ready") { moveSpell(s.spell.id, toReady: true) }
                }
                Button("Remove", role: .destructive) { removeSpell(s.spell.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body).foregroundStyle(.black.opacity(0.35))
            }
        }
    }

    private var spellAddMenu: some View {
        let catalog = repo.klass(character.classID)?.spellListID
            .flatMap { repo.spellList($0) }?.spellIDs ?? []
        let known = Set(character.spellbookIDs)
        let addable = catalog.filter { !known.contains($0) }.compactMap { repo.spell($0) }
        return Menu {
            ForEach(addable) { s in
                Button("\(s.name)  (\(s.tier.rawValue))") { addSpell(s.id) }
            }
        } label: {
            Label("Add spell", systemImage: "plus.circle.fill")
                .font(questFont(13)).foregroundStyle(accent)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
        .disabled(addable.isEmpty)
    }

    private func addSpell(_ id: String) {
        var c = character
        c.spellbookIDs.append(id)
        if c.readySpellIDs.count < sheet.readySpellCap { c.readySpellIDs.append(id) }
        roster.update(c)
    }

    private func moveSpell(_ id: String, toReady: Bool) {
        var c = character
        if toReady {
            if !c.readySpellIDs.contains(id) { c.readySpellIDs.append(id) }
        } else {
            c.readySpellIDs.removeAll { $0 == id }
        }
        roster.update(c)
    }

    private func learnableSpell(_ itemName: String) -> SpellDefinition? {
        guard sheet.isCaster else { return nil }
        guard let def = repo.items().first(where: { $0.name == itemName && $0.kind == .scroll }),
              let spellID = def.spellID,
              !character.spellbookIDs.contains(spellID) else { return nil }
        return repo.spell(spellID)
    }

    private func learnScroll(_ p: PendingLearn) {
        var c = character
        guard c.learn(scroll: p.itemName, spellID: p.spell.id) else { return }
        roster.update(c)
    }

    private func removeSpell(_ id: String) {
        var c = character
        c.spellbookIDs.removeAll { $0 == id }
        c.readySpellIDs.removeAll { $0 == id }
        roster.update(c)
    }

    // MARK: Pets & the Spirit Animal (shared petLikeBox — art floats over the border)

    private func petLikeBox<Footer: View>(
        title: String,
        badge: PetBadge?,
        statline: String,
        hp: Int, maxHP: Int,
        hpTint: Color,
        artName: String,
        artSymbol: String,
        artCaption: String,
        trick: AbilityDefinition?,
        onMinus: @escaping () -> Void,
        onPlus: @escaping () -> Void,
        onTapArt: (() -> Void)? = nil,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        let artWidth: CGFloat = 124      // a notch under the iPad's 155
        let artPeek: CGFloat  = 20
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(questFont(16)).foregroundStyle(.black)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                .lineLimit(1).minimumScaleFactor(0.7)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let badge {
                            Label(badge.text, systemImage: badge.symbol)
                                .font(questFont(12)).foregroundStyle(TierColor.signature)
                        }
                        Text(statline)
                            .font(questFontLight(13)).foregroundStyle(.black.opacity(0.75))
                            .lineLimit(2).minimumScaleFactor(0.8)
                        HStack(spacing: 8) {
                            Text("HP \(hp)/\(maxHP)")
                                .font(questFont(15))
                                .foregroundStyle(hp == 0 ? .red : hpTint)
                            Button(action: onMinus) {
                                Image(systemName: "minus.circle").foregroundStyle(.red.opacity(0.7))
                            }
                            Button(action: onPlus) {
                                Image(systemName: "plus.circle").foregroundStyle(.green.opacity(0.8))
                            }
                        }
                        .buttonStyle(.plain)
                        if let trick {
                            TapInfo(payload: .init(ability: trick, tint: TierColor.path)) {
                                HStack(spacing: 5) {
                                    Image(systemName: "star.circle.fill").font(.caption)
                                    Text(trick.name).font(questFont(13))
                                        .lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .foregroundStyle(TierColor.path)
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    Color.clear.frame(width: artWidth)
                }
                Spacer(minLength: 0)
                footer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: PhoneSheet.row2Height - 34)
            .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                petArt(artName: artName, artSymbol: artSymbol, artCaption: artCaption,
                       onTapArt: onTapArt)
                    .frame(width: artWidth)
                    .offset(x: -6, y: -artPeek)
                    .allowsHitTesting(onTapArt != nil)
            }
        }
        .containerRelativeFrame(.horizontal) { l, _ in l * PhoneSheet.pageFraction }
    }

    @ViewBuilder
    private func petArt(artName: String, artSymbol: String, artCaption: String,
                        onTapArt: (() -> Void)?) -> some View {
        if let onTapArt {
            Button(action: onTapArt) {
                QuestArt(name: artName, ratio: 0.78, colors: [bg, accent],
                         symbol: artSymbol, caption: artCaption, framed: false)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.white, accent)
                            .padding(4)
                    }
            }
            .buttonStyle(.plain)
        } else {
            QuestArt(name: artName, ratio: 0.78, colors: [bg, accent],
                     symbol: artSymbol, caption: artCaption, framed: false)
        }
    }

    private func petFallbackArt(_ pet: PetChoice) -> String {
        pet.companionID.map(QuestArtKey.pet) ?? QuestArtKey.customPet
    }

    private func petArtName(_ pet: PetChoice) -> String {
        pet.imageID.map(QuestArtKey.pet) ?? petFallbackArt(pet)
    }

    private func petBox(_ pet: PetChoice, isLast: Bool) -> some View {
        let stats = derivePetStats(for: pet, abilities: sheet.abilities, repo: repo)
        let transform = state.petTransforms[pet.id]
        let maxHP = transform?.maxHP ?? stats.maxHP
        let statline = transform.map { "HP \($0.maxHP) · bite \($0.damage)" } ?? stats.statline
        let hp = state.petHP[pet.id] ?? maxHP
        return petLikeBox(
            title: "Pet: \(pet.name)",
            badge: transform != nil ? PetBadge(text: "BEAST MODE!", symbol: "flame.fill") : nil,
            statline: statline,
            hp: hp, maxHP: maxHP,
            hpTint: TierColor.starting,
            artName: petArtName(pet),
            artSymbol: transform != nil ? "flame.fill" : "pawprint.fill",
            artCaption: pet.companionID.flatMap { repo.companion($0)?.name } ?? "custom pet",
            trick: stats.trick,
            onMinus: { combat.adjustPetHP(character.id, petID: pet.id, by: -1, maxHP: maxHP) },
            onPlus:  { combat.adjustPetHP(character.id, petID: pet.id, by: 1, maxHP: maxHP) },
            onTapArt: { pickingPetArtFor = pet }
        ) {
            if isLast { addPetMenu(label: "Add another pet", size: 12) }
        }
        .contextMenu {
            Button("Remove \(pet.name)", role: .destructive) {
                var c = character
                c.pets.removeAll { $0.id == pet.id }
                roster.update(c)
            }
        }
    }

    private func summonBox(_ summon: Summon) -> some View {
        petLikeBox(
            title: summon.name,
            badge: PetBadge(text: "SPIRIT ANIMAL", symbol: "sparkles"),
            statline: "Bites \(summon.damage) · end of round",
            hp: summon.currentHP, maxHP: summon.maxHP,
            hpTint: TierColor.path,
            artName: character.spiritImageID.map(QuestArtKey.spirit) ?? QuestArtKey.spirit("1"),
            artSymbol: "sparkles",
            artCaption: "animal spirit",
            trick: nil,
            onMinus: { combat.adjustSummonHP(character.id, by: -1) },
            onPlus:  { combat.adjustSummonHP(character.id, by: 1) },
            onTapArt: { pickingSpiritArt = true }
        ) {
            if let sac = sheet.summonSacrifice {
                Button { sacrificeSummon(sac) } label: {
                    Label("Sacrifice", systemImage: "leaf.fill")
                        .font(questFont(12)).foregroundStyle(TierColor.signature)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $pickingSpiritArt) {
            ArtPicker(title: "Spirit Animal's Look",
                      currentImageID: character.spiritImageID,
                      defaultArtName: nil,
                      slotCount: QuestArtKey.spiritArtSlotCount,
                      key: QuestArtKey.spirit,
                      symbol: "sparkles",
                      bg: bg, accent: accent) { newImageID in
                var c = character
                c.spiritImageID = newImageID
                roster.update(c)
            }
        }
    }

    private func sacrificeSummon(_ sac: SummonSacrifice) {
        combat.addModifier(character.id, Modifier(label: sac.reminderLabel, value: 0,
                                                  target: .any, scope: .thisFight, source: .manual))
        combat.clearSummon(character.id)
    }

    private func addPetMenu(label: String, size: CGFloat) -> some View {
        Menu {
            Section("From the book") {
                ForEach(repo.companions()) { comp in
                    Button(comp.name) {
                        pendingCompanionID = comp.id
                        newItemText = comp.name
                        petAlertTitle = "Name your pet!"
                        namingPet = true
                    }
                }
            }
            Button("Custom pet…") {
                pendingCompanionID = nil
                newItemText = ""
                petAlertTitle = "Name your pet!"
                namingPet = true
            }
        } label: {
            Label(label, systemImage: "plus.circle.fill")
                .font(questFont(size)).foregroundStyle(accent)
        }
    }

    private var addPetBox: some View {
        sheetBox("Pets", height: PhoneSheet.row2Height) {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "pawprint.circle").font(.system(size: 36))
                    .foregroundStyle(accent.opacity(0.5))
                addPetMenu(label: "Add pet", size: 14)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Items boxes

    private func itemsBox(title: String, items: [String],
                          adding: Binding<Bool>,
                          learnable: @escaping (String) -> SpellDefinition? = { _ in nil },
                          commit: @escaping ([String]) -> Void) -> some View {
        sheetBox(title, height: PhoneSheet.row2Height) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack {
                            Text(item).font(questFont(13)).foregroundStyle(.black)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Spacer()
                            if let spell = learnable(item) {
                                Button { pendingLearn = PendingLearn(itemName: item, spell: spell) } label: {
                                    Label("Learn", systemImage: "sparkles")
                                        .font(questFont(10)).foregroundStyle(accent)
                                        .lineLimit(1).fixedSize()
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .overlay(Capsule().strokeBorder(accent.opacity(0.5), lineWidth: 1.5))
                                }
                                .buttonStyle(.plain)
                            }
                            Button {
                                var list = items; list.remove(at: index); commit(list)
                            } label: {
                                Image(systemName: "minus.circle").foregroundStyle(.red.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button { adding.wrappedValue = true } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                            .font(questFont(13)).foregroundStyle(accent)
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .alert("Add to \(title)", isPresented: adding) {
            TextField("Item name", text: $newItemText)
            Button("Add") {
                var list = items
                if !newItemText.trimmingCharacters(in: .whitespaces).isEmpty { list.append(newItemText) }
                commit(list); newItemText = ""
            }
            Button("Cancel", role: .cancel) { newItemText = "" }
        }
    }

    private func commitItems(magic: [String]? = nil, normal: [String]? = nil) {
        var c = character
        if let magic { c.magicItems = magic }
        if let normal { c.normalItems = normal }
        roster.update(c)
    }

    // MARK: Combat tracker (paged — Next Attack big and first, swipe for the rest)
        //
        // Order is intent: Next Attack is the scope a kid reads mid-roll, so it owns
        // the resting view. NOT lazy — three cards.

        private var trackerPanel: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    trackerCard("Next Attack", scope: .nextAttack)
                    trackerCard("Until Next Turn", scope: .untilNextTurn)
                    trackerCard("This Fight", scope: .thisFight)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .frame(height: PhoneSheet.trackerHeight)
        }

    private var trackerDivider: some View {
        Rectangle().fill(.black.opacity(0.2)).frame(width: 1).padding(.vertical, 4)
    }

    private func trackerCard(_ title: String, scope: ModifierScope) -> some View {
            let chips = state.modifiers.filter { $0.scope == scope }
            return VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text(title.uppercased()).font(questFont(13)).foregroundStyle(.black)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if !chips.isEmpty {
                        // Chips waiting in an off-screen scope announce themselves here.
                        Text("\(chips.count)")
                            .font(questFont(11)).foregroundStyle(.black.opacity(0.6))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.white, in: Capsule())
                            .overlay(Capsule().strokeBorder(.black.opacity(0.25), lineWidth: 1))
                    }
                    Spacer(minLength: 0)
                    PhoneTrackerAddButton(accent: accent,
                        onAddNumber: { value, target in
                            let sign = value >= 0 ? "+" : ""
                            combat.addModifier(character.id, Modifier(
                                label: "\(sign)\(value) \(rollTargetName(target))",
                                value: value, target: target, scope: scope, source: .manual))
                        },
                        onAddNote: { text in
                            combat.addModifier(character.id, Modifier(
                                label: text, value: 0, target: .any, scope: scope, source: .manual))
                        })
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(chips) { m in
                            Button { combat.removeModifier(character.id, modifierID: m.id) } label: {
                                Text(m.label)
                                    .font(questFont(15))
                                    .foregroundStyle(m.value >= 0 ? Color(hex: "4AA3DF") : .red)
                                    .lineLimit(2).minimumScaleFactor(0.8)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                        if chips.isEmpty {
                            Text("nothing yet — tap +")
                                .font(questFontLight(12)).foregroundStyle(.black.opacity(0.25))
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .top)
            .containerRelativeFrame(.horizontal) { l, _ in l * PhoneSheet.trackerPageFraction }
            .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
        }
}

// MARK: - Tracker "+" popover, phone metrics
//
// DUPLICATED, not reused: the iPad TrackerAddButton fixes its popover at 440pt,
// which clips at phone width, and its 6-segment target picker turns to confetti at
// ~110pt columns. Same behavior, menu-style target picker, flexible width.

private struct PhoneTrackerAddButton: View {
    let accent: Color
    var onAddNumber: (Int, RollTarget) -> Void
    var onAddNote: (String) -> Void

    @State private var showing = false
    @State private var mode: Mode = .number
    @State private var value = 2
    @State private var target: RollTarget = .toHit
    @State private var noteText = ""

    private enum Mode: String, CaseIterable, Identifiable {
        case number = "Number", note = "Note"
        var id: String { rawValue }
    }

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "plus.circle.fill").font(.body).foregroundStyle(accent)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing,
                 attachmentAnchor: .point(.top),
                 arrowEdge: .bottom) {
            VStack(spacing: 12) {
                Picker("Kind", selection: $mode) {
                    ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
                }
                .pickerStyle(.segmented)

                if mode == .number {
                    HStack {
                        Text("Applies to").font(questFontLight(14)).foregroundStyle(.black.opacity(0.6))
                        Spacer()
                        Picker("Applies to", selection: $target) {
                            Text("Attack").tag(RollTarget.toHit)
                            Text("Damage").tag(RollTarget.damage)
                            Text("Might").tag(RollTarget.mightCheck)
                            Text("Mind").tag(RollTarget.mindCheck)
                            Text("Speed").tag(RollTarget.speedCheck)
                            Text("All").tag(RollTarget.any)
                        }
                        .pickerStyle(.menu)
                    }
                    Stepper(value: $value, in: -5...5) {
                        Text(value >= 0 ? "+\(value)" : "\(value)")
                            .font(questFont(20))
                            .foregroundStyle(value >= 0 ? Color(hex: "4AA3DF") : .red)
                    }
                } else {
                    TextField("Type anything… (e.g. +2 heals · 3 turns)", text: $noteText)
                        .textFieldStyle(.roundedBorder)
                        .font(questFont(15))
                }

                Button("Add") {
                    if mode == .number {
                        onAddNumber(value, target)
                    } else {
                        let t = noteText.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty { onAddNote(t) }
                    }
                    showing = false
                    value = 2; target = .toHit; noteText = ""; mode = .number
                }
                .font(questFont(15)).foregroundStyle(.black)
                .padding(.horizontal, 22).padding(.vertical, 8)
                .background(TierColor.selectPeach, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black, lineWidth: 2))
                .buttonStyle(.plain)
            }
            .padding(14)
            .frame(width: 320)
            .background(TierColor.panelCream)
            .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Level-up, phone metrics
//
// DUPLICATED, not reused: the iPad LevelUpSheet's stat rows carry fixed 46pt step
// buttons + a 92pt value column inside 480pt — that's ~330pt of fixed content and
// it clips at phone width. Same rules verbatim (2 points, all-spent gate, maxed /
// not-yet states); only the metrics shrink.

private struct PhoneLevelUpSheet: View {
    let targetLevel: Int
    let pointsPool: Int
    let currentMight: Int
    let currentSpeed: Int
    let currentMind: Int
    let atMaxLevel: Bool
    let starsToGo: Int?
    let bg: Color
    let accent: Color
    var onConfirm: ([Stat: Int]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var alloc: [Stat: Int] = [.might: 0, .speed: 0, .mind: 0]

    private var spent: Int { alloc.values.reduce(0, +) }
    private var left: Int { pointsPool - spent }

    var body: some View {
        ScrollView {
            VStack {
                if atMaxLevel { maxedContent }
                else if let n = starsToGo, n > 0 { notYetContent(n) }
                else { spendContent }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bg.opacity(0.85))
    }

    private var maxedContent: some View {
        VStack(spacing: 14) {
            Image(systemName: "crown.fill").font(.system(size: 44))
                .foregroundStyle(TierColor.signature)
            Text("Level 3 is the top — for now!")
                .font(questFont(20)).foregroundStyle(.black)
                .multilineTextAlignment(.center)
            Text("You're as strong as heroes get on this quest. New adventures might raise the ceiling later!")
                .font(questFontLight(14)).foregroundStyle(.black.opacity(0.7))
                .multilineTextAlignment(.center)
            closeButton("Okay!")
        }
        .padding(18)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.black, lineWidth: 2))
    }

    private func notYetContent(_ starsToGo: Int) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "star.circle.fill").font(.system(size: 44))
                .foregroundStyle(TierColor.signature)
            Text(starsToGo == 1 ? "One more star!" : "\(starsToGo) more stars!")
                .font(questFont(20)).foregroundStyle(.black)
                .multilineTextAlignment(.center)
            Text("Finish a quest, take down a boss, or do something so clever it skips the fight — then come back and level up!")
                .font(questFontLight(14)).foregroundStyle(.black.opacity(0.7))
                .multilineTextAlignment(.center)
            closeButton("Okay!")
        }
        .padding(18)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.black, lineWidth: 2))
    }

    private var spendContent: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("LEVEL UP!").font(questFont(26)).foregroundStyle(.black)
                Text("You reached Level \(targetLevel)!")
                    .font(questFont(16)).foregroundStyle(.black.opacity(0.75))
            }

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(0..<pointsPool, id: \.self) { i in
                        Image(systemName: "sparkle")
                            .font(.system(size: 24))
                            .foregroundStyle(i < left ? TierColor.signature : .black.opacity(0.15))
                            .scaleEffect(i < left ? 1 : 0.8)
                            .animation(.snappy, value: left)
                    }
                }
                Text("Points left: \(left)")
                    .font(questFont(15))
                    .foregroundStyle(left == 0 ? .green : .black)
                    .contentTransition(.numericText())
            }
            .padding(.vertical, 9).frame(maxWidth: .infinity)
            .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))

            Text("Spend your points — all on one stat, or split them!")
                .font(questFontLight(13)).foregroundStyle(.black.opacity(0.7))
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                statRow("MIGHT", .might, current: currentMight)
                statRow("SPEED", .speed, current: currentSpeed)
                statRow("MIND",  .mind,  current: currentMind)
            }

            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Text("Cancel").font(questFont(15)).foregroundStyle(.black)
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
                }
                .buttonStyle(.plain)

                Button { onConfirm(alloc); dismiss() } label: {
                    Label("Level Up!", systemImage: "arrow.up.circle.fill")
                        .font(questFont(16)).foregroundStyle(.black)
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(left == 0 ? TierColor.selectPeach : Color.gray.opacity(0.25),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.black.opacity(left == 0 ? 1 : 0.25), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .disabled(left != 0)
            }
        }
        .padding(16)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.black, lineWidth: 2))
    }

    private func statRow(_ label: String, _ stat: Stat, current: Int) -> some View {
        let added = alloc[stat] ?? 0
        let newVal = current + added
        return HStack(spacing: 8) {
            Text(label).font(questFont(15)).foregroundStyle(.black)
                .frame(width: 58, alignment: .leading)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            stepButton("minus", enabled: added > 0) { alloc[stat] = max(0, added - 1) }
            VStack(spacing: 0) {
                Text("+\(newVal)")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(added > 0 ? .green : Color(hex: "4AA3DF"))
                    .contentTransition(.numericText())
                Text(added > 0 ? "+\(added) this level" : "was +\(current)")
                    .font(questFontLight(10))
                    .foregroundStyle(added > 0 ? .green : .black.opacity(0.4))
            }
            .frame(width: 76)
            stepButton("plus", enabled: left > 0) { alloc[stat] = added + 1 }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black.opacity(0.15), lineWidth: 1.5))
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(enabled ? .black : .black.opacity(0.2))
                .frame(width: 42, height: 42)   // still kid-thumb sized
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.black.opacity(enabled ? 1 : 0.2), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private func closeButton(_ title: String) -> some View {
        Button { dismiss() } label: {
            Text(title).font(questFont(16)).foregroundStyle(.black)
                .padding(.horizontal, 24).padding(.vertical, 11)
                .background(TierColor.selectPeach, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}
