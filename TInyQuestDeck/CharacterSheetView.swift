//  CharacterSheetView.swift  (v2 — fixed-frame full-sheet layout)
//  The sheet always LOOKS complete: fixed-size themed background, uniform boxes in
//  two horizontally-swiping rows, empty slots rendered as dashed placeholders, and
//  the combat tracker permanently full-size at the bottom.
//
//  Row 1 — caster: Abilities | Ready Spells | Spellbook…    non-caster: Abilities | Gear
//  Row 2 — caster: Pets… | +Pet | Gear | Normal | Magic     non-caster: Pets… | +Pet | Normal | Magic
//  Bottom — full combat tracker (fixed height, never minimized).
//  My Turn / Attack Done / Rest live under the stat tiles.
//
//  DICE PILLAR: Recharge asks "what did you roll?" — the app never rolls.
//  Depends on QuestStyle.swift, TapInfo.swift, Color(hex:)/emblemSymbol.

import SwiftUI

// Fixed metrics — the "full sheet" frame the boxes live in.
private enum SheetMetrics {
    static let boxWidth: CGFloat = 330
    static let row1Height: CGFloat = 300
    static let row2Height: CGFloat = 240
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
                            let maxHP = pet.companionID.flatMap { repo.companion($0)?.maxHP } ?? 5
                            combat.seedPet(c.id, petID: pet.id, maxHP: maxHP)
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
    @State private var pendingCompanionID: String? = nil
    @State private var newItemText = ""

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
            }
        }
    }

    private var portraitBlock: some View {
        VStack(spacing: -26) {
            PlaceholderArt(ratio: QuestRatio.card,
                           colors: [accent, bg],
                           symbol: emblemSymbol(sheet.theme?.emblem),
                           caption: "portrait 1200×1680")
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
    }

    private var hpTile: some View {
        let hpColor: Color = state.currentHP <= 0 ? .red
            : (Double(state.currentHP) / Double(max(sheet.maxHP, 1)) <= 0.5 ? .orange : .green)
        return VStack(spacing: 2) {
            Text("HP").font(questFont(16)).foregroundStyle(.black)
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
                Text("\(sheet.level)").font(questFont(24))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(bg, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .confirmationDialog(levelDialogTitle, isPresented: $showLevelUp, titleVisibility: .visible) {
            if character.level < 3 {
                Button("Boost Might +2") { levelUp(boosting: .might) }
                Button("Boost Speed +2") { levelUp(boosting: .speed) }
                Button("Boost Mind +2")  { levelUp(boosting: .mind) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var levelDialogTitle: String {
        character.level < 3
            ? "Level up to \(character.level + 1)! Boost one stat by +2 — new powers appear automatically."
            : "Level 3 is the top (for now!)"
    }

    private func levelUp(boosting stat: Stat) {
        var c = character
        c.level += 1
        c.statBoosts[stat.rawValue, default: 0] += 2
        commitChoices(c)
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
        .frame(width: 96).padding(.vertical, 10)
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
                        rechargeAbilityIDs: sheet.abilities
                            .filter { $0.ability.reset == .recharge }.map(\.ability.id))
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

            boxRow(height: SheetMetrics.row2Height) {
                ForEach(Array(character.pets.enumerated()), id: \.element.id) { i, pet in
                    petBox(pet, isLast: i == character.pets.count - 1)
                }
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
        .alert("Name your pet!", isPresented: $namingPet) {
            TextField("Pet name", text: $newItemText)
            Button("Add") {
                guard !newItemText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                var c = character
                let pet = PetChoice(name: newItemText, companionID: pendingCompanionID)
                c.pets.append(pet)
                roster.update(c)
                let maxHP = pendingCompanionID.flatMap { repo.companion($0)?.maxHP } ?? 5
                combat.seedPet(c.id, petID: pet.id, maxHP: maxHP)
                newItemText = ""; pendingCompanionID = nil
            }
            Button("Cancel", role: .cancel) { newItemText = ""; pendingCompanionID = nil }
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

    /// The uniform box: white title above a fixed-size cream panel.
    private func sheetBox<Content: View>(_ title: String, height: CGFloat,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(questFont(18)).foregroundStyle(.white)
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

    private var abilitiesBox: some View {
        sheetBox("Abilities", height: SheetMetrics.row1Height) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(sheet.abilities, id: \.ability.id) { item in abilityRow(item) }
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
        let trackable = a.reset != .atWill && a.actionCost != .passive
        let used = state.usedAbilityIDs.contains(a.id)

        return HStack(spacing: 8) {
            TapInfo(payload: .init(ability: a, tint: color)) {
                Text(a.name)
                    .font(questFont(15))
                    .foregroundStyle(item.isAvailable ? color : color.opacity(0.5))
                    .strikethrough(!item.isAvailable || used)
            }
            if let icon = tierIcon(item.source) {
                Image(systemName: icon).font(.caption).foregroundStyle(color)
            }
            if !item.isAvailable {
                Text("Not Equipped").font(questFontLight(12)).foregroundStyle(.red)
            }
            Spacer()
            if trackable && item.isAvailable {
                Button { combat.toggleUsed(character.id, a.id) } label: {
                    Image(systemName: used ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(used ? .black.opacity(0.45) : color)
                }
                .buttonStyle(.plain)
            }
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

    private var gearAddMenu: some View {
        let kitIDs = repo.path(character.pathID)?.startingGearIDs ?? []
        let kit = kitIDs.compactMap { repo.gear($0) }
        let others = repo.allGear().filter { !kitIDs.contains($0.id) }
        return Menu {
            Section("Starting kit") {
                ForEach(kit) { g in Button(g.name) { addGear(g.id) } }
            }
            if !others.isEmpty {
                Section("More gear") {
                    ForEach(others) { g in Button(g.name) { addGear(g.id) } }
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

    // MARK: Pets (each pet is its OWN box; big image; book companions or custom)

    private func petBox(_ pet: PetChoice, isLast: Bool) -> some View {
        let comp = pet.companionID.flatMap { repo.companion($0) }
        let maxHP = comp?.maxHP ?? 5
        let hp = state.petHP[pet.id] ?? maxHP
        return sheetBox("Pet: \(pet.name)", height: SheetMetrics.row2Height) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    PlaceholderArt(ratio: 1, colors: [bg, accent], symbol: "pawprint.fill",
                                   caption: comp?.name ?? "custom pet")
                        .frame(width: 116)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(comp.map(companionStatline) ?? "HP 5 · +2 hit · d6")
                            .font(questFontLight(14)).foregroundStyle(.black.opacity(0.75))
                        HStack(spacing: 8) {
                            Text("HP \(hp)/\(maxHP)")
                                .font(questFont(16))
                                .foregroundStyle(hp == 0 ? .red : TierColor.starting)
                            Button { combat.adjustPetHP(character.id, petID: pet.id, by: -1, maxHP: maxHP) } label: {
                                Image(systemName: "minus.circle").foregroundStyle(.red.opacity(0.7))
                            }
                            Button { combat.adjustPetHP(character.id, petID: pet.id, by: 1, maxHP: maxHP) } label: {
                                Image(systemName: "plus.circle").foregroundStyle(.green.opacity(0.8))
                            }
                        }
                        .buttonStyle(.plain)
                        if let trick = comp?.trick {
                            TapInfo(payload: .init(ability: trick, tint: TierColor.path)) {
                                HStack(spacing: 5) {
                                    Image(systemName: "star.circle.fill").font(.caption)
                                    Text(trick.name).font(questFont(14))
                                }
                                .foregroundStyle(TierColor.path)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                if isLast { addPetMenu(label: "Add another pet", size: 13) }
            }
        }
        .contextMenu {
            Button("Remove \(pet.name)", role: .destructive) {
                var c = character
                c.pets.removeAll { $0.id == pet.id }
                roster.update(c)
            }
        }
    }

    /// Shared companion/custom pet picker (used by the empty-state box and pet boxes).
    private func addPetMenu(label: String, size: CGFloat) -> some View {
        Menu {
            Section("From the book") {
                ForEach(repo.companions()) { comp in
                    Button(comp.name) {
                        pendingCompanionID = comp.id
                        newItemText = comp.name
                        namingPet = true
                    }
                }
            }
            Button("Custom pet…") {
                pendingCompanionID = nil
                newItemText = ""
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
                TrackerAddButton(accent: accent) { value, target in
                    let sign = value >= 0 ? "+" : ""
                    combat.addModifier(character.id, Modifier(
                        label: "\(sign)\(value) \(trackerTargetName(target))",
                        value: value, target: target, scope: scope, source: .manual))
                }
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

    private func trackerTargetName(_ t: RollTarget) -> String {
        switch t {
        case .toHit: "Attack roll"
        case .damage: "Damage"
        case .mightCheck: "Might roll"
        case .mindCheck: "Mind roll"
        case .speedCheck: "Speed roll"
        case .any: "All rolls"
        }
    }
}

// MARK: - "What did you roll?" — the physical-dice Recharge prompt

private struct RechargeRollView: View {
    var onRolled: (Int) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Roll a d6!").font(questFont(20)).foregroundStyle(.black)
            Text("On a 6, all your Recharge powers come back.")
                .font(questFontLight(14)).foregroundStyle(.black.opacity(0.7))
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

// MARK: - Tracker "+" popover

private struct TrackerAddButton: View {
    let accent: Color
    var onAdd: (Int, RollTarget) -> Void

    @State private var showing = false
    @State private var value = 2
    @State private var target: RollTarget = .toHit

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "plus.circle.fill").font(.body).foregroundStyle(accent)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing, arrowEdge: .top) {
            VStack(spacing: 12) {
                Picker("Applies to", selection: $target) {
                    Text("Attack roll").tag(RollTarget.toHit)
                    Text("Damage").tag(RollTarget.damage)
                    Text("Mind roll").tag(RollTarget.mindCheck)
                    Text("All rolls").tag(RollTarget.any)
                }
                .pickerStyle(.segmented)
                Stepper(value: $value, in: -5...5) {
                    Text(value >= 0 ? "+\(value)" : "\(value)")
                        .font(questFont(20))
                        .foregroundStyle(value >= 0 ? Color(hex: "4AA3DF") : .red)
                }
                Button("Add") {
                    onAdd(value, target)
                    showing = false
                    value = 2; target = .toHit
                }
                .font(questFont(16)).foregroundStyle(.black)
                .padding(.horizontal, 22).padding(.vertical, 8)
                .background(TierColor.selectPeach, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black, lineWidth: 2))
                .buttonStyle(.plain)
            }
            .padding(16)
            .frame(width: 340)
            .background(TierColor.panelCream)
            .presentationCompactAdaptation(.popover)
        }
    }
}
