//  CharacterSheetView.swift  (v2 — fixed-frame full-sheet layout)
//  The sheet always LOOKS complete: fixed-size themed background, uniform boxes in
//  two horizontally-swiping rows, empty slots rendered as dashed placeholders, and
//  the combat tracker permanently full-size at the bottom.
//
//  Row 1 — caster: Abilities | Ready Spells | Spellbook…    non-caster: Abilities | Gear
//  Row 2 — caster: Pets… | Spirit | +Pet | Gear | Normal | Magic
//          non-caster: Pets… | Spirit | +Pet | Normal | Magic
//  Bottom — full combat tracker (fixed height, never minimized).
//  My Turn / Attack Done / Rest live under the stat tiles.
//
//  DICE PILLAR: Recharge asks "what did you roll?" — the app never rolls.
//  Depends on QuestStyle.swift, TapInfo.swift, Color(hex:)/emblemSymbol.
//
//  Powers-audit pass:
//   • Ability rows render totalUses checkboxes (spell-row style): Unbreakable makes
//     Shield show two, with zero ability IDs in this file.
//   • Checking a box fires the ability's hints via CombatStore.setAbilitySpent —
//     Perfect Shot / Battle Cry push their chips into the tracker automatically;
//     the "+" stays for monster effects and buffs from other players' heroes.
//   • The rolled 6 now also refills non-t3 Ready spell casts (sheet.rechargeSpellIDs)
//     and the popover reminds the kid of the free spell swap (honor system — the
//     ⋯ menu is always open).
//   • Pet boxes read derivePetStats: Pack Tactics shows HP 8 · bite 3 with no
//     hardcoding. Leveling into a power that grants a companion (Wild L2) pops
//     the naming flow automatically — grant-all applies to best friends too.
//   • SIGNATURE BOX (content-gated via PathDefinition.signatureBox — Wild only
//     for now): at L3 signature powers get their OWN gold box, so leveling up
//     makes a whole new box appear. Other classes keep one Abilities box.
//   • BEAST MODE (petTransform hint): checking the box asks "Who grows?!" when
//     the hero has several pets, flips the chosen pet box to beast stats with a
//     badge, and drops a "This Fight" chip — tap the chip when the fight ends to
//     shrink back (the use stays spent). Un-checking retracts everything.
//
//  Visual pass:
//   • Pet box FLIPPED — stats/HP/trick on the LEFT, art on the RIGHT, and the art
//     is a touch taller so it peeks above the top edge of the box.
//   • Box TITLES are now BLACK everywhere EXCEPT the Scout/Wild "✦ Signature Powers"
//     box, which keeps its orange (TierColor.signature).
//   • Tracker "+" offers Might / Mind / Speed roll targets plus a free-text Note.
//   • Level-up is a POINT-SPEND sheet: 2 points split any way across Might/Speed/Mind.
//
//  Druid "Voice of the Wild" pass:
//   • Voice of the Wild is a MODE ability: tapping a use-box opens a "Wild gift?"
//     picker (mirrors Beast Mode's "Who grows?!"). Roots / Bloom push a manual
//     honor-system note chip into THIS FIGHT; Spirit Animal SUMMONS a creature.
//     The mode copy lives here (view-level) exactly like Beast Mode's labels —
//     declaring Roots/Bloom as noteChips on the ability would fire all three modes
//     at once. The `.summon` hint carries only the Spirit branch's data.
//   • SPIRIT ANIMAL: a live, app-summoned creature (CombatState.summon — NOT a
//     PetChoice). Its own box slots in row 2 right after the pets, appearing when
//     summoned and vanishing at 0 HP / Sacrifice / Rest. One at a time — the Spirit
//     option greys out while one's already live.
//   • The pet box's inner layout is now a shared `petLikeBox`; `petBox` and
//     `summonBox` both call it. `summonBox` passes no trick and adds a SACRIFICE
//     button, gated on `sheet.summonSacrifice` (Heart of the Grove, Druid L3),
//     which drops the honor-system heal reminder chip and clears the spirit.

import SwiftUI

// Fixed metrics — the "full sheet" frame the boxes live in.
private enum SheetMetrics {
    static let boxWidth: CGFloat = 370
    static let row1Height: CGFloat = 290
    static let row2Height: CGFloat = 230
    static let trackerHeight: CGFloat = 140
    static let gearCap = 5
    static let bookBoxSize = 6      // spells per Spellbook box
}

struct CharacterSheetView: View {
    let repo: ContentRepository
    let roster: RosterStore
    let combat: CombatStore
    let characterID: UUID

    private var character: CharacterChoices? {
        roster.characters.first { $0.id == characterID }
    }

    var body: some View {
        Group {
            if let c = character, let sheet = deriveSheet(from: c, using: repo) {
                SheetBody(repo: repo, roster: roster, combat: combat, character: c, sheet: sheet)
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

private struct SheetBody: View {
    let repo: ContentRepository
    let roster: RosterStore
    let combat: CombatStore
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

    private struct PendingTransform {
        let ability: AbilityDefinition
        let boxIndex: Int
        let total: Int
    }

    /// Voice of the Wild spend awaiting a mode pick (Roots / Bloom / Spirit).
    private struct PendingSummon {
        let ability: AbilityDefinition
        let boxIndex: Int
        let total: Int
    }

    /// The three Voice of the Wild modes. Roots/Bloom are honor-system reminders;
    /// Spirit summons the animal spirit.
    private enum WildMode { case roots, bloom, spirit }

    /// Badge shown top-left of a pet-like box (Beast Mode flame). nil for a plain box.
    private struct PetBadge { let text: String; let symbol: String }

    private var bg: Color { sheet.theme.map { Color(hex: $0.background) } ?? .blue }
    private var accent: Color { sheet.theme.map { Color(hex: $0.accent) } ?? .blue }
    private var state: CombatState { combat.states[character.id] ?? CombatState(currentHP: sheet.maxHP) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerRow
                sheetPanel
            }
            .padding(16)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .background(Color.white)
    }

    // MARK: Header (portrait+name | HP · level · buff slot | stats | action buttons)

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 16) {
            portraitBlock.frame(width: 260)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    hpTile
                    VStack(alignment: .leading, spacing: 10) {
                        levelBadge
                        buffSlot
                    }
                }
                HStack(spacing: 12) {
                    statTile("MIGHT", .might)
                    statTile("SPEED", .speed)
                    statTile("MIND", .mind)
                }
                actionButtons
                goldBar
            }
        }
    }

    /// The portrait the sheet shows: the kid's chosen race×class combo, or their own
    /// race×class as the default. Stored as an opaque combo string in portraitID.
    private var portraitCombo: String {
        character.portraitID ?? QuestArtKey.portraitCombo(race: character.raceID, klass: character.classID)
    }

    private var portraitBlock: some View {
        VStack(spacing: -26) {
            // Tap the portrait to open the gallery (non-destructive — just a look, so
            // no confirm); the pencil badge makes it discoverable.
            Button { pickingPortrait = true } label: {
                QuestArt(name: QuestArtKey.portrait(combo: portraitCombo),
                         ratio: QuestRatio.card,
                         colors: [accent, bg],
                         symbol: emblemSymbol(sheet.theme?.emblem),
                         caption: "tap to choose")
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white, accent)
                            .padding(8)
                    }
            }
            .buttonStyle(.plain)
            Text(sheet.name.uppercased())
                .font(questFont(18))
                .foregroundStyle(.black)
                .lineLimit(2).minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
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
            Text("Health Points").font(questFont(16)).foregroundStyle(.black)
            Text("\(sheet.maxHP) Max").font(questFontLight(13)).foregroundStyle(.black.opacity(0.6))
            Text("\(state.currentHP)")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(hpColor)
                .contentTransition(.numericText())
            HStack(spacing: 6) {
                hpButton("-5") { combat.damage(character.id, 5) }
                hpButton("-1") { combat.damage(character.id, 1) }
                hpButton("+1") { combat.heal(character.id, 1, maxHP: sheet.maxHP) }
                hpButton("+5") { combat.heal(character.id, 5, maxHP: sheet.maxHP) }
            }
        }
        .padding(12)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
    }

    private func hpButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(questFont(13))
                .foregroundStyle(label.hasPrefix("-") ? .red : .green)
                .frame(width: 34, height: 28)
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private var levelBadge: some View {
        Button { showLevelUp = true } label: {
            HStack(spacing: 10) {
                Text(sheet.pathName.uppercased()).font(questFont(22))
                Text("Level \(sheet.level)").font(questFont(24))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(bg, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showLevelUp) {
            LevelUpSheet(
                targetLevel: min(character.level + 1, 3),
                pointsPool: 2,
                currentMight: sheet.might,
                currentSpeed: sheet.speed,
                currentMind: sheet.mind,
                atMaxLevel: character.level >= 3,
                bg: bg, accent: accent
            ) { alloc in
                levelUp(applying: alloc)
            }
            .presentationDetents([.medium, .large])
        }
    }
    
    // MARK: Gold wallet (header)
  
    private let showGoldDevControls = true
    // MARK: Gold wallet (compact bar, under the action buttons)
    //
    // The coin + total is permanent. The − / + steppers flanking it are a TEMPORARY test
    // affordance standing in for the real earning path (GM award / solo-adventure loot) —
    // gated on `showGoldDevControls` so they lift out in one edit. Each tap moves `goldStep`.
    // goldStep = 5 hits the example prices (15/20/60); set it to 1 to test exact
    // affordability edges, or bump it for faster top-ups.
    private let goldStep = 1

    private var goldBar: some View {
        HStack(spacing: 10) {
            if showGoldDevControls {
                goldStepButton("minus.circle.fill", tint: .red.opacity(0.8)) { adjustGold(by: -goldStep) }
            }
            HStack(spacing: 6) {
                coinIcon
                Text("\(character.gold)")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
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
        .fixedSize()      // hug content — a compact pill under the recharge button, not full width
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
        .frame(width: 22, height: 22)
    }

    private func adjustGold(by delta: Int) {
        var c = character
        c.gold = max(0, c.gold + delta)
        roster.update(c)
    }


    /// Apply a point allocation across stats. The rulebook's "+2 to one stat" is
    /// just {stat: 2}; splits like {might: 1, speed: 1} keep the same +2 total.
    /// Level increment, HP recompute, and companion-naming all stay unchanged.
    private func levelUp(applying alloc: [Stat: Int]) {
        var c = character
        c.level += 1
        for (stat, n) in alloc where n != 0 {
            c.statBoosts[stat.rawValue, default: 0] += n
        }
        commitChoices(c)
        promptForGrantedCompanion(atNewLevel: c.level)
    }

    /// Grant-all applies to best friends too: if the powers that just arrived carry
    /// a companion hint (Wild's Bonded Companion at L2), pop the naming flow now.
    /// Data-driven — no ability IDs here.
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

    /// Phase 2: buff/debuff indicator area (brain/skull). Space reserved.
    private var buffSlot: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile").foregroundStyle(.red.opacity(0.3))
            Image(systemName: "shield.lefthalf.filled").foregroundStyle(.blue.opacity(0.3))
        }
        .font(.title2)
        .padding(.leading, 4)
    }

    private func statTile(_ label: String, _ stat: Stat) -> some View {
        let value: Int = switch stat {
            case .might: sheet.might; case .speed: sheet.speed; case .mind: sheet.mind
        }
        return VStack(spacing: 2) {
            Text(label).font(questFont(14)).foregroundStyle(.black)
            Text("+\(value)")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(hex: "4AA3DF"))
        }
        .frame(width: 116).padding(.vertical, 10)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
    }

    // MARK: Action buttons (moved under the stats per playtest)

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button { showRecharge = true } label: {
                actionLabel("My Turn — Recharge!", "die.face.6", fill: TierColor.panelCream)
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
            .font(questFont(14)).foregroundStyle(.black)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(fill, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
    }

    // MARK: The fixed-frame themed panel

    private var sheetPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            boxRow(height: SheetMetrics.row1Height) {
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
                }
            }
            // Voice of the Wild's mode picker rides on row 1 (where its ability box
            // lives) — kept separate from the transform dialog below to avoid two
            // confirmationDialogs on one view.
            .confirmationDialog("Wild gift?",
                                isPresented: Binding(get: { pendingSummon != nil },
                                                     set: { if !$0 { pendingSummon = nil } }),
                                titleVisibility: .visible,
                                presenting: pendingSummon) { pending in
                Button("Roots — 2 foes Stuck") { spendVoice(pending, mode: .roots) }
                Button("Bloom — 2 foes Hurt")  { spendVoice(pending, mode: .bloom) }
                Button("Call a Spirit Animal!") { spendVoice(pending, mode: .spirit) }
                    .disabled(state.summon != nil)   // one spirit at a time
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text(state.summon != nil
                     ? "Your spirit animal is already here — pick Roots or Bloom."
                     : "What does the wild answer with?")
            }

            boxRow(height: SheetMetrics.row2Height) {
                ForEach(Array(character.pets.enumerated()), id: \.element.id) { i, pet in
                    petBox(pet, isLast: i == character.pets.count - 1)
                }
                if let summon = state.summon { summonBox(summon) }
                if character.pets.isEmpty { addPetBox }
                if sheet.isCaster { gearBox }
                itemsBox(title: "Normal Items", items: character.normalItems,
                         adding: $addingNormalItem) { commitItems(normal: $0) }
                itemsBox(title: "Magic Items", items: character.magicItems,
                         adding: $addingMagicItem) { commitItems(magic: $0) }
            }

            trackerPanel
        }
        .padding(14)
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
    }

    /// A fixed-height horizontal band of uniform boxes; extra boxes swipe in.
    private func boxRow<Content: View>(height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) { content() }
        }
        .frame(height: height)
        .scrollClipDisabled(false)
    }

    /// The uniform box: title above a fixed-size cream panel.
    /// Titles default to BLACK now; the only override in the app is the Scout/Wild
    /// signature box's orange.
    private func sheetBox<Content: View>(_ title: String, height: CGFloat,
                                         titleColor: Color = .black,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(questFont(18)).foregroundStyle(titleColor)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(12)
                .frame(width: SheetMetrics.boxWidth, height: height - 36, alignment: .top)
                .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
        }
    }

    private func emptySlot(_ hint: String = "empty") -> some View {
        Text(hint)
            .font(questFontLight(12)).foregroundStyle(.black.opacity(0.3))
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.black.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }

    // MARK: Abilities box

    /// Signature powers split into their own gold box only when the path opts in
    /// (content flag) AND the hero has any — i.e. the box APPEARS at level 3.
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
        sheetBox(title, height: SheetMetrics.row1Height, titleColor: titleColor) {
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

    /// One ability row: tap-name-for-rules, then totalUses checkboxes (spell-row
    /// style — Unbreakable's Shield ×2 is just two boxes). Checking a box routes
    /// through CombatStore.setAbilitySpent so the ability's hints fire (auto-chips,
    /// resetAbility, rechargeSpells).
    private func abilityRow(_ item: SheetAbility) -> some View {
        let a = item.ability
        let color = tierColor(item.source)
        let spent = state.spentUses(a.id)
        let fullySpent = state.isFullySpent(a.id, of: item.totalUses)

        return HStack(spacing: 8) {
            TapInfo(payload: .init(ability: a, tint: color)) {
                Text(a.name)
                    .font(questFont(15))
                    .foregroundStyle(item.isAvailable ? color : color.opacity(0.5))
                    .strikethrough(!item.isAvailable || fullySpent)
            }
            if let icon = tierIcon(item.source) {
                Image(systemName: icon).font(.caption).foregroundStyle(color)
            }
            if !item.isAvailable {
                Text("Not Equipped").font(questFontLight(12)).foregroundStyle(.red)
            }
            Spacer()
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

    /// Box-tap routing. Two abilities need the kid to make a choice on SPEND:
    ///   • petTransform (Beast Mode) — pick which pet grows ("Who grows?!").
    ///   • summon (Voice of the Wild) — pick the mode ("Wild gift?": Roots/Bloom/Spirit).
    /// Everything else (and every UN-spend, including mis-tapping a summon box back
    /// off) falls through to the plain path. Data-driven; the only special cases are
    /// the hints' presence.
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

    /// Resolve a Voice of the Wild mode pick. Roots/Bloom spend the box and drop a
    /// manual (kid-dismissable) reminder chip into THIS FIGHT — they're honor-system,
    /// so they're view-pushed, not ability hints. Spirit spends the box with a
    /// SummonSpec so the store creates the spirit animal (guarded: one at a time).
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
            guard state.summon == nil else { return }   // belt-and-suspenders vs. disabled
            spendBox(summonSpec: SummonSpec(name: "Spirit Animal"))
        }
    }

    // MARK: Gear box (5 fixed slots)

    private var gearBox: some View {
        sheetBox("Gear", height: sheet.isCaster ? SheetMetrics.row2Height : SheetMetrics.row1Height) {
            ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<SheetMetrics.gearCap, id: \.self) { slot in
                    if slot < sheet.gear.count {
                        gearRow(sheet.gear[slot], index: slot)
                    } else if slot == sheet.gear.count {
                        gearAddMenu
                    } else {
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
                        Text(g.name).font(questFont(14)).foregroundStyle(.black)
                        if sheet.hasDualWield && g.category == .lightMelee && isSecondLightMelee(at: index) {
                            Text("FREE ACTION").font(questFontLight(11)).foregroundStyle(TierColor.path)
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

    // MARK: Gear "Add" menu — grouped by weapon family, labelled with the stat it uses,
    // and ★-marked when it matches the hero's best stat (a nudge, not a restriction —
    // a mage CAN still grab two swords). Starting kit stays pinned at the top.

    private struct GearGroup: Identifiable {
        let id: Int          // sort order doubles as identity
        let title: String
        let items: [GearDefinition]
    }

    /// The hero's strongest stat(s) — used to ★ the weapon families that fit them best.
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

    /// (sort order, base title, the stat this family rolls to hit with — nil for armor).
    /// rangedPhysical splits by damage so Bows (d6+Speed) and small ranged (d6) separate,
    /// even though they share a category. Reorder by changing the leading ints.
    private func gearFamily(_ g: GearDefinition) -> (order: Int, base: String, stat: Stat?) {
        switch g.category {
        case .heavyMelee:  return (0, "Heavy Weapons", .might)
        case .lightMelee:
            return g.attack?.toHitStat == .might
                ? (1, "Heavy One-Handers", .might)   // Long Sword, Mace, Battle Axe…
                : (2, "Finesse Weapons",   .speed)   // Short Sword, Rapier, Dagger
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

        // Free to equip: the BASIC (common) catalog only — rulebook's "any character can use
        // any gear." Special gear (uncommon+) is shop-only; it must be owned to equip.
        let basics = repo.allGear().filter { $0.rarity == .common && !kitIDs.contains($0.id) }

        // Bought / earned specials: only what THIS hero owns (deduped; basics already free above).
        let owned = Set(character.ownedGearIDs)
            .compactMap { repo.gear($0) }
            .filter { $0.rarity != .common }
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
            ForEach(gearGroups(basics)) { group in
                Section(group.title) {
                    ForEach(group.items) { g in gearMenuButton(g) }
                }
            }
        } label: {
            Label("Add", systemImage: "plus.circle.fill")
                .font(questFont(14)).foregroundStyle(accent)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
    }

    private func addGear(_ id: String) {
        guard character.equippedGearIDs.count < SheetMetrics.gearCap else { return }
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

    /// Single write path: update roster, re-derive, shift current HP by the Max-HP delta.
    private func commitChoices(_ c: CharacterChoices) {
        let oldMax = sheet.maxHP
        roster.update(c)
        if let newSheet = deriveSheet(from: c, using: repo) {
            combat.adjustMaxHP(c.id, delta: newSheet.maxHP - oldMax, newMaxHP: newSheet.maxHP)
        }
    }

    // MARK: Spells (Ready box capped at readySpellCap; Spellbook boxes of 6, swipeable)

    private var benchChunks: [[SheetSpell]] {
        stride(from: 0, to: sheet.benchSpells.count, by: SheetMetrics.bookBoxSize).map {
            Array(sheet.benchSpells[$0..<min($0 + SheetMetrics.bookBoxSize, sheet.benchSpells.count)])
        }
    }

    private var readySpellsBox: some View {
        sheetBox("Spells ✦  (\(sheet.readySpells.count)/\(sheet.readySpellCap))",
                 height: SheetMetrics.row1Height) {
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
                 height: SheetMetrics.row1Height) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(chunk, id: \.spell.id) { s in spellRow(s, ready: false) }
                ForEach(0..<max(0, SheetMetrics.bookBoxSize - chunk.count), id: \.self) { _ in
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
                Text(s.spell.name).font(questFont(14))
                    .foregroundStyle(ready ? TierColor.starting : .black.opacity(0.65))
            }
            Spacer()
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
            // Visible menu — long-press context menus get swallowed by the tappable name.
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
                .font(questFont(14)).foregroundStyle(accent)
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

    private func removeSpell(_ id: String) {
        var c = character
        c.spellbookIDs.removeAll { $0 == id }
        c.readySpellIDs.removeAll { $0 == id }
        roster.update(c)
    }

    // MARK: Pets & the Spirit Animal (shared petLikeBox: stats/HP/trick LEFT, art RIGHT)
    //  The art is a touch taller than square so it peeks above the top edge of the box.
    //  petBox passes the pet's derived trick + an "add another pet" footer; summonBox
    //  passes no trick + a Sacrifice footer (gated on Heart of the Grove).

    /// Shared inner layout for a pet OR the summoned spirit. Values-only so neither
    /// type leaks into the other — the summon is live CombatState, not a PetChoice.
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
        let artWidth: CGFloat = 155      // was 116 (~⅓ bigger)
        let artPeek: CGFloat  = 24       // was 20 (~20% more lift above the box line)
        // Inlined box (not sheetBox) so the art can be overlaid AFTER the border —
        // that's what makes the pet sit OVER the outline instead of the outline
        // cutting across it.
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(questFont(18)).foregroundStyle(.black)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    // LEFT: badge / stats / HP steppers / trick
                    VStack(alignment: .leading, spacing: 6) {
                        if let badge {
                            Label(badge.text, systemImage: badge.symbol)
                                .font(questFont(13)).foregroundStyle(TierColor.signature)
                        }
                        Text(statline)
                            .font(questFontLight(14)).foregroundStyle(.black.opacity(0.75))
                        HStack(spacing: 8) {
                            Text("HP \(hp)/\(maxHP)")
                                .font(questFont(16))
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
                                    Text(trick.name).font(questFont(14))
                                }
                                .foregroundStyle(TierColor.path)
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    // Reserve the art's footprint so stats never run under it; the real
                    // art is overlaid on the whole panel (below).
                    Color.clear.frame(width: artWidth)
                }
                Spacer(minLength: 0)
                footer()
            }
            .padding(12)
            .frame(width: SheetMetrics.boxWidth, height: SheetMetrics.row2Height - 36, alignment: .top)
            .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
            // ART ON TOP — added AFTER the border overlay, so the pet draws OVER the
            // outline and above neighboring content, floating prominently.
            .overlay(alignment: .topTrailing) {
                petArt(artName: artName, artSymbol: artSymbol, artCaption: artCaption,
                       onTapArt: onTapArt)
                    .frame(width: artWidth)
                    .offset(x: -8, y: -artPeek)
                    .allowsHitTesting(onTapArt != nil)
            }
        }
    }

    /// The pet/summon art (borderless, floating). Tappable with a pencil badge when
    /// onTapArt is set (pets open the image gallery); plain otherwise (the summon).
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

    /// A pet's fallback art (no gallery pick): bespoke companion art if drawn, else
    /// the generic custom-pet image.
    private func petFallbackArt(_ pet: PetChoice) -> String {
        pet.companionID.map(QuestArtKey.pet) ?? QuestArtKey.customPet
    }
    /// A pet's displayed art: the kid's gallery pick (imageID) wins, else the fallback.
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
            if isLast { addPetMenu(label: "Add another pet", size: 13) }
        }
        .contextMenu {
            Button("Remove \(pet.name)", role: .destructive) {
                var c = character
                c.pets.removeAll { $0.id == pet.id }
                roster.update(c)
            }
        }
    }

    /// The summoned spirit animal (Voice of the Wild). Live state, not a PetChoice:
    /// steppers hit adjustSummonHP (0 HP dissipates it), and the SACRIFICE button
    /// appears only with Heart of the Grove — it drops the honor-system heal reminder
    /// and clears the spirit.
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
                        .font(questFont(13)).foregroundStyle(TierColor.signature)
                }
                .buttonStyle(.plain)
            }
        }
        // Spirit look persists on the character (a trait, not per-summon). The picker
        // rides on the summon box, which only exists while a spirit is out.
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

    /// Heart of the Grove: push the honor-system heal reminder (Druid rolls & picks
    /// who — no cross-character state), then remove the spirit.
    private func sacrificeSummon(_ sac: SummonSacrifice) {
        combat.addModifier(character.id, Modifier(label: sac.reminderLabel, value: 0,
                                                  target: .any, scope: .thisFight, source: .manual))
        combat.clearSummon(character.id)
    }

    /// Shared companion/custom pet picker (used by the empty-state box and pet boxes).
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
        sheetBox("Pets", height: SheetMetrics.row2Height) {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "pawprint.circle").font(.system(size: 40))
                    .foregroundStyle(accent.opacity(0.5))
                addPetMenu(label: "Add pet", size: 15)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Items boxes

    private func itemsBox(title: String, items: [String],
                          adding: Binding<Bool>, commit: @escaping ([String]) -> Void) -> some View {
        sheetBox(title, height: SheetMetrics.row2Height) {
            ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack {
                        Text(item).font(questFont(14)).foregroundStyle(.black)
                        Spacer()
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
                        .font(questFont(14)).foregroundStyle(accent)
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

    // MARK: Combat tracker (fixed size, always fully visible)

    private var trackerPanel: some View {
        HStack(alignment: .top, spacing: 0) {
            trackerColumn("Next Attack", scope: .nextAttack)
            trackerDivider
            trackerColumn("Until Next Turn", scope: .untilNextTurn)
            trackerDivider
            trackerColumn("This Fight", scope: .thisFight)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: SheetMetrics.trackerHeight)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
    }

    private var trackerDivider: some View {
        Rectangle().fill(.black.opacity(0.2)).frame(width: 1).padding(.vertical, 4)
    }

    private func trackerColumn(_ title: String, scope: ModifierScope) -> some View {
        let chips = state.modifiers.filter { $0.scope == scope }
        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(title.uppercased()).font(questFont(14)).foregroundStyle(.black)
                TrackerAddButton(accent: accent,
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
                VStack(spacing: 6) {
                    ForEach(chips) { m in
                        Button { combat.removeModifier(character.id, modifierID: m.id) } label: {
                            Text(m.label)
                                .font(questFont(16))
                                .foregroundStyle(m.value >= 0 ? Color(hex: "4AA3DF") : .red)
                        }
                        .buttonStyle(.plain)
                    }
                    if chips.isEmpty {
                        Text("—").font(questFontLight(14)).foregroundStyle(.black.opacity(0.2))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - "What did you roll?" — the physical-dice Recharge prompt

private struct RechargeRollView: View {
    var onRolled: (Int) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Roll a d6!").font(questFont(20)).foregroundStyle(.black)
            Text("On a 6, your Recharge powers AND spells come back —\nand you may swap one Ready Spell for free!")
                .font(questFontLight(14)).foregroundStyle(.black.opacity(0.7))
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                ForEach(1...6, id: \.self) { n in
                    Button { onRolled(n) } label: {
                        Image(systemName: "die.face.\(n).fill")
                            .font(.system(size: 34))
                            .foregroundStyle(n == 6 ? TierColor.starting : .black.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Tap what you rolled").font(questFontLight(12)).foregroundStyle(.black.opacity(0.5))
        }
        .padding(18)
        .background(TierColor.panelCream)
    }
}

// MARK: - Tracker "+" popover  (opens ABOVE the button; Number chip OR free-text Note)

private struct TrackerAddButton: View {
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
        // Anchor to the TOP of the "+" with the arrow on the popover's BOTTOM edge,
        // so the whole menu opens UPWARD — clear of the screen's bottom edge.
        .popover(isPresented: $showing,
                 attachmentAnchor: .point(.top),
                 arrowEdge: .bottom) {
            VStack(spacing: 12) {
                Picker("Kind", selection: $mode) {
                    ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
                }
                .pickerStyle(.segmented)

                if mode == .number {
                    Picker("Applies to", selection: $target) {
                        Text("Attack").tag(RollTarget.toHit)
                        Text("Damage").tag(RollTarget.damage)
                        Text("Might").tag(RollTarget.mightCheck)
                        Text("Mind").tag(RollTarget.mindCheck)
                        Text("Speed").tag(RollTarget.speedCheck)
                        Text("All").tag(RollTarget.any)
                    }
                    .pickerStyle(.segmented)
                    Stepper(value: $value, in: -5...5) {
                        Text(value >= 0 ? "+\(value)" : "\(value)")
                            .font(questFont(20))
                            .foregroundStyle(value >= 0 ? Color(hex: "4AA3DF") : .red)
                    }
                } else {
                    // Free-text catch-all: heal-over-time, a buff from another player,
                    // anything not modeled. Lands in THIS column's scope, value 0.
                    TextField("Type anything… (e.g. +2 heals · 3 turns)", text: $noteText)
                        .textFieldStyle(.roundedBorder)
                        .font(questFont(16))
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
                .font(questFont(16)).foregroundStyle(.black)
                .padding(.horizontal, 22).padding(.vertical, 8)
                .background(TierColor.selectPeach, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black, lineWidth: 2))
                .buttonStyle(.plain)
            }
            .padding(16)
            .frame(width: 440)
            .background(TierColor.panelCream)
            .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Level-up: spend your points

/// Level-up is a point-spend, not a preset. Each level grants `pointsPool` points
/// (2 today) the kid distributes across Might / Speed / Mind — the rulebook's
/// "+2 to one stat" is just "put both points in one row." Every point must be spent
/// before Level Up! enables. At max level it shows a friendly "top of the ladder"
/// message instead of the spend UI.
private struct LevelUpSheet: View {
    let targetLevel: Int
    let pointsPool: Int
    let currentMight: Int
    let currentSpeed: Int
    let currentMind: Int
    let atMaxLevel: Bool
    let bg: Color
    let accent: Color
    var onConfirm: ([Stat: Int]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var alloc: [Stat: Int] = [.might: 0, .speed: 0, .mind: 0]

    private var spent: Int { alloc.values.reduce(0, +) }
    private var left: Int { pointsPool - spent }

    var body: some View {
        VStack {
            if atMaxLevel { maxedContent } else { spendContent }
        }
        .padding(24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bg.opacity(0.85))
    }

    // MARK: Maxed

    private var maxedContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "crown.fill").font(.system(size: 48))
                .foregroundStyle(TierColor.signature)
            Text("Level 3 is the top — for now!")
                .font(questFont(22)).foregroundStyle(.black)
                .multilineTextAlignment(.center)
            Text("You're as strong as heroes get on this quest. New adventures might raise the ceiling later!")
                .font(questFontLight(15)).foregroundStyle(.black.opacity(0.7))
                .multilineTextAlignment(.center)
            closeButton("Okay!")
        }
        .padding(22)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.black, lineWidth: 2))
    }

    // MARK: Spend

    private var spendContent: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text("LEVEL UP!").font(questFont(30)).foregroundStyle(.black)
                Text("You reached Level \(targetLevel)!")
                    .font(questFont(18)).foregroundStyle(.black.opacity(0.75))
            }

            // Sparkle meter — bright sparkles = points still to spend.
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(0..<pointsPool, id: \.self) { i in
                        Image(systemName: "sparkle")
                            .font(.system(size: 28))
                            .foregroundStyle(i < left ? TierColor.signature : .black.opacity(0.15))
                            .scaleEffect(i < left ? 1 : 0.8)
                            .animation(.snappy, value: left)
                    }
                }
                Text("Points left: \(left)")
                    .font(questFont(16))
                    .foregroundStyle(left == 0 ? .green : .black)
                    .contentTransition(.numericText())
            }
            .padding(.vertical, 10).frame(maxWidth: .infinity)
            .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))

            Text("Spend your points — all on one stat, or split them!")
                .font(questFontLight(14)).foregroundStyle(.black.opacity(0.7))
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                statRow("MIGHT", .might, current: currentMight)
                statRow("SPEED", .speed, current: currentSpeed)
                statRow("MIND",  .mind,  current: currentMind)
            }

            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Text("Cancel").font(questFont(16)).foregroundStyle(.black)
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
                }
                .buttonStyle(.plain)

                Button { onConfirm(alloc); dismiss() } label: {
                    Label("Level Up!", systemImage: "arrow.up.circle.fill")
                        .font(questFont(18)).foregroundStyle(.black)
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(left == 0 ? TierColor.selectPeach : Color.gray.opacity(0.25),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.black.opacity(left == 0 ? 1 : 0.25), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .disabled(left != 0)
            }
        }
        .padding(20)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.black, lineWidth: 2))
    }

    /// One stat row: a stepper on the resulting value. "−" bottoms out at the current
    /// stat (can't spend below 0 added); "+" is capped by points left.
    private func statRow(_ label: String, _ stat: Stat, current: Int) -> some View {
        let added = alloc[stat] ?? 0
        let newVal = current + added
        return HStack(spacing: 14) {
            Text(label).font(questFont(18)).foregroundStyle(.black)
                .frame(width: 78, alignment: .leading)
            Spacer()
            stepButton("minus", enabled: added > 0) { alloc[stat] = max(0, added - 1) }
            VStack(spacing: 0) {
                Text("+\(newVal)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(added > 0 ? .green : Color(hex: "4AA3DF"))
                    .contentTransition(.numericText())
                Text(added > 0 ? "+\(added) this level" : "was +\(current)")
                    .font(questFontLight(11))
                    .foregroundStyle(added > 0 ? .green : .black.opacity(0.4))
            }
            .frame(width: 92)
            stepButton("plus", enabled: left > 0) { alloc[stat] = added + 1 }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black.opacity(0.15), lineWidth: 1.5))
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2.weight(.bold))
                .foregroundStyle(enabled ? .black : .black.opacity(0.2))
                .frame(width: 46, height: 46)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.black.opacity(enabled ? 1 : 0.2), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func closeButton(_ title: String) -> some View {
        Button { dismiss() } label: {
            Text(title).font(questFont(18)).foregroundStyle(.black)
                .padding(.horizontal, 28).padding(.vertical, 12)
                .background(TierColor.selectPeach, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Portrait gallery (pick ANY race×class combo's art)

/// A free gallery of every race×class portrait combo. Each cell renders QuestArt of
/// that combo's key — present art shows, undrawn combos stay dashed placeholders — so
/// new portrait assets appear here automatically as they're drawn (drop them in the
/// catalog named "portrait-<raceID>-<classID>"; nothing to wire). Tapping a cell
/// stores its opaque combo string on the character; reachable from the sheet, so the
/// look is changeable any time.
private struct PortraitPicker: View {
    let repo: ContentRepository
    let currentCombo: String
    let bg: Color
    let accent: Color
    var onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 14)]

    /// One gallery cell. `key` is the opaque string stored in portraitID; the asset
    /// name is portrait-<key>. `label` is what the cell shows.
    private struct Combo: Identifiable {
        let key: String
        let label: String
        var id: String { key }
    }

    /// Race×class portraits, race-major. Per combo: the base image plus any -2…N
    /// variants that exist. A combo with NO art yet still gets one placeholder cell,
    /// so the full race×class grid stays visible.
    private var combos: [Combo] {
        repo.races().flatMap { race -> [Combo] in
            repo.classes().flatMap { cls -> [Combo] in
                let base = QuestArtKey.portraitCombo(race: race.id, klass: cls.id)
                let rc = "\(race.name) · \(cls.name)"
                var found: [Combo] = []
                if questAssetExists(QuestArtKey.portrait(combo: base)) {
                    found.append(Combo(key: base, label: rc))
                }
                for n in 2...QuestArtKey.portraitVariantSlots {
                    let vk = "\(base)-\(n)"
                    if questAssetExists(QuestArtKey.portrait(combo: vk)) {
                        found.append(Combo(key: vk, label: "\(rc) \(n)"))
                    }
                }
                if found.isEmpty { found.append(Combo(key: base, label: rc)) }
                return found
            }
        }
    }

    /// Generic portraits (portrait-any-N) that fit anyone — only those that exist.
    private var miscCombos: [Combo] {
        (1...QuestArtKey.portraitMiscSlots).map(String.init).compactMap { n in
            let key = QuestArtKey.portraitMisc(n)
            return questAssetExists(QuestArtKey.portrait(combo: key))
                ? Combo(key: key, label: "Anyone \(n)") : nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    Section { ForEach(combos) { cell($0) } }
                    if !miscCombos.isEmpty {
                        Section(header: sectionHeader("Something Different")) {
                            ForEach(miscCombos) { cell($0) }
                        }
                    }
                }
                .padding(16)
            }
            .background(bg.opacity(0.85))
            .navigationTitle("Pick a Look")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(questFont(16))
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased()).font(questFont(15)).foregroundStyle(.black)
            Spacer()
        }
        .padding(.horizontal, 4).padding(.top, 10).padding(.bottom, 2)
    }

    private func cell(_ combo: Combo) -> some View {
        let selected = combo.key == currentCombo
        return Button {
            onPick(combo.key)
            dismiss()
        } label: {
            VStack(spacing: 5) {
                QuestArt(name: QuestArtKey.portrait(combo: combo.key),
                         ratio: QuestRatio.card,
                         colors: [accent, bg],
                         symbol: "person.fill",
                         caption: combo.label)
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white, TierColor.starting)
                                .padding(6)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(selected ? TierColor.starting : .clear, lineWidth: 3))
                Text(combo.label)
                    .font(questFontLight(11)).foregroundStyle(.black)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Art gallery (shared by pets and the Druid's spirit animal)

/// Pick a look from a generic image pool (e.g. pet-1 … pet-N, spirit-1 … spirit-N).
/// Only slots whose asset exists are shown, so undrawn numbers never appear as empty
/// cells. When `defaultArtName` is set, the first cell is "Default" (clears the stored
/// imageID → bespoke/fallback art); pass nil to omit it. The pick is handed back via
/// onPick (a slot string, or nil for Default).
private struct ArtPicker: View {
    let title: String
    let currentImageID: String?
    let defaultArtName: String?      // nil = no "Default" cell
    let slotCount: Int
    let key: (String) -> String      // slot -> asset name (QuestArtKey.pet / .spirit)
    var symbol: String = "pawprint.fill"   // placeholder glyph for undrawn slots
    let bg: Color
    let accent: Color
    var onPick: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    /// Only the pool slots that actually have art drawn.
    private var slots: [String] {
        (1...slotCount).map(String.init).filter { questAssetExists(key($0)) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    if let defaultArtName { defaultCell(defaultArtName) }
                    ForEach(slots, id: \.self) { slot in cell(slot) }
                }
                .padding(16)
            }
            .background(bg.opacity(0.85))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(questFont(16))
                }
            }
        }
    }

    private func defaultCell(_ name: String) -> some View {
        let selected = currentImageID == nil
        return Button {
            onPick(nil); dismiss()
        } label: {
            artCell(name: name, label: "Default", selected: selected)
        }
        .buttonStyle(.plain)
    }

    private func cell(_ slot: String) -> some View {
        let selected = currentImageID == slot
        return Button {
            onPick(slot); dismiss()
        } label: {
            artCell(name: key(slot), label: "#\(slot)", selected: selected)
        }
        .buttonStyle(.plain)
    }

    private func artCell(name: String, label: String, selected: Bool) -> some View {
        VStack(spacing: 5) {
            QuestArt(name: name, ratio: 0.78, colors: [accent, bg],
                     symbol: symbol, caption: label, framed: false)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, TierColor.starting)
                            .padding(5)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selected ? TierColor.starting : .clear, lineWidth: 3))
            Text(label).font(questFontLight(11)).foregroundStyle(.black).lineLimit(1)
        }
    }
}
