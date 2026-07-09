//  CharacterSheetView.swift
//  The new digital-native character sheet (mockup: character_sheet_champion/mystic).
//  Reads the derived sheet, layers CombatStore on top, and writes choice changes
//  (gear, level, pets, items) back through RosterStore so the sheet re-derives live.
//
//  DICE PILLAR: Recharge asks "what did you roll?" — the app never rolls.
//  Depends on QuestStyle.swift, TapInfo.swift, Color(hex:)/emblemSymbol (HeroTile.swift).

import SwiftUI

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
                        c.pets.forEach { combat.seedPet(c.id, petID: $0.id) }
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
    @State private var addingPet = false
    @State private var newItemText = ""

    private var bg: Color { sheet.theme.map { Color(hex: $0.background) } ?? .blue }
    private var accent: Color { sheet.theme.map { Color(hex: $0.accent) } ?? .blue }
    private var state: CombatState { combat.states[character.id] ?? CombatState(currentHP: sheet.maxHP) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerRow
                mainPanel
            }
            .padding(16)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .background(Color.white)
    }

    // MARK: Header: portrait+name | HP + class/level + buff slot | stats

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 16) {
            portraitBlock.frame(width: 280)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    hpTile
                    VStack(alignment: .leading, spacing: 10) {
                        levelBadge
                        buffSlot   // phase 2: buff/debuff indicators live here
                    }
                }
                HStack(spacing: 12) {
                    statTile("MIGHT", .might)
                    statTile("SPEED", .speed)
                    statTile("MIND", .mind)
                }
            }
        }
    }

    private var portraitBlock: some View {
        VStack(spacing: -26) {
            // Tap-to-change portrait gallery is a later feature; placeholder for now.
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

    /// Phase 2: buff/debuff indicator area (the brain/skull icons). Space reserved.
    private var buffSlot: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile").foregroundStyle(.red.opacity(0.35))
            Image(systemName: "shield.lefthalf.filled").foregroundStyle(.blue.opacity(0.35))
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

    // MARK: Main themed panel: abilities/pets left, gear/spells/items right, tracker bottom

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    abilitiesPanel
                    petsPanel
                }
                VStack(alignment: .leading, spacing: 14) {
                    gearPanel
                    if sheet.isCaster { spellsPanel }
                    itemsPanel(title: "Magic Items", items: character.magicItems,
                               adding: $addingMagicItem) { commitItems(magic: $0) }
                    itemsPanel(title: "Normal Items", items: character.normalItems,
                               adding: $addingNormalItem) { commitItems(normal: $0) }
                }
            }
            trackerPanel
            restBar
        }
        .padding(14)
        .background(bg.opacity(0.85), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.black, lineWidth: 2))
    }

    private func panelTitle(_ s: String) -> some View {
        Text(s).font(questFont(18)).foregroundStyle(.white)
            .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
    }

    // MARK: Abilities (compact rows: tap name for TapInfo, checkbox for use-tracking)

    private var abilitiesPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            panelTitle("Abilities")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(sheet.abilities, id: \.ability.id) { item in
                    abilityRow(item)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
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

    // MARK: Gear (blank start; Add menu seeded with the book kit; HP delta live)

    private var gearPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            panelTitle("Gear")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(sheet.gear.enumerated()), id: \.offset) { index, g in
                    HStack {
                        TapInfo(payload: .init(gear: g, tint: accent)) {
                            HStack(spacing: 6) {
                                Text(g.name).font(questFont(14)).foregroundStyle(.black)
                                if let atk = g.attack {
                                    Text(attackSummary(atk))
                                        .font(.caption2.monospaced()).foregroundStyle(.black.opacity(0.6))
                                } else if g.maxHP != 0 {
                                    Text("+\(g.maxHP) HP")
                                        .font(questFontLight(12)).foregroundStyle(accent)
                                }
                                if sheet.hasDualWield && g.category == .lightMelee && isSecondLightMelee(at: index) {
                                    Text("FREE ACTION").font(questFontLight(11)).foregroundStyle(TierColor.path)
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
                gearAddMenu
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
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
        }
    }

    private func addGear(_ id: String) {
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

    /// Single write path: update the roster, re-derive, and shift current HP by
    /// the Max-HP delta (gear/level changes feel immediate, never silently wound).
    private func commitChoices(_ c: CharacterChoices) {
        let oldMax = sheet.maxHP
        roster.update(c)
        if let newSheet = deriveSheet(from: c, using: repo) {
            combat.adjustMaxHP(c.id, delta: newSheet.maxHP - oldMax, newMaxHP: newSheet.maxHP)
        }
    }

    // MARK: Spells (cast boxes; tap name for full text)

    private var spellsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                panelTitle("Spells")
                Image(systemName: "sparkle").foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(sheet.readySpells, id: \.spell.id) { s in spellRow(s) }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
        }
    }

    private func spellRow(_ s: SheetSpell) -> some View {
        let spent = state.spellUsesSpent[s.spell.id] ?? 0
        return HStack(spacing: 8) {
            TapInfo(payload: .init(spell: s.spell, uses: s.readyUses, tint: TierColor.starting)) {
                Text(s.spell.name).font(questFont(14)).foregroundStyle(TierColor.starting)
            }
            Spacer()
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
    }

    // MARK: Pets

    private var petsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            panelTitle("Pets")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(character.pets) { pet in petRow(pet) }
                Button { addingPet = true } label: {
                    Label("Add pet", systemImage: "plus.circle.fill")
                        .font(questFont(14)).foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
        }
        .alert("Name your pet!", isPresented: $addingPet) {
            TextField("Pet name", text: $newItemText)
            Button("Add") {
                var c = character
                let pet = PetChoice(name: newItemText)
                c.pets.append(pet)
                roster.update(c)
                combat.seedPet(c.id, petID: pet.id)
                newItemText = ""
            }
            Button("Cancel", role: .cancel) { newItemText = "" }
        }
    }

    private func petRow(_ pet: PetChoice) -> some View {
        let hp = state.petHP[pet.id] ?? 5
        return HStack(spacing: 10) {
            PlaceholderArt(ratio: 1, colors: [bg, accent], symbol: "pawprint.fill")
                .frame(width: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(pet.name).font(questFont(15)).foregroundStyle(TierColor.starting)
                Text("HP \(hp)/5 · +2 hit / d6").font(questFontLight(13)).foregroundStyle(.black.opacity(0.7))
            }
            Spacer()
            HStack(spacing: 6) {
                Button { combat.adjustPetHP(character.id, petID: pet.id, by: -1) } label: {
                    Image(systemName: "minus.circle").foregroundStyle(.red.opacity(0.7))
                }
                Button { combat.adjustPetHP(character.id, petID: pet.id, by: 1) } label: {
                    Image(systemName: "plus.circle").foregroundStyle(.green.opacity(0.8))
                }
            }
            .buttonStyle(.plain)
        }
        .contextMenu {
            Button("Remove \(pet.name)", role: .destructive) {
                var c = character
                c.pets.removeAll { $0.id == pet.id }
                roster.update(c)
            }
        }
    }

    // MARK: Magic / Normal items (free-form)

    private func itemsPanel(title: String, items: [String],
                            adding: Binding<Bool>, commit: @escaping ([String]) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            panelTitle(title)
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
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
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

    // MARK: Combat tracker (the three buckets; chips expire via TurnEvent)

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
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
    }

    private var trackerDivider: some View {
        Rectangle().fill(.black.opacity(0.2)).frame(width: 1).padding(.vertical, 4)
    }

    private func trackerColumn(_ title: String, scope: ModifierScope) -> some View {
        let chips = state.modifiers.filter { $0.scope == scope }
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(title.uppercased()).font(questFont(13)).foregroundStyle(.black)
                TrackerAddButton(accent: accent) { value, target in
                    let sign = value >= 0 ? "+" : ""
                    combat.addModifier(character.id, Modifier(
                        label: "\(sign)\(value) \(trackerTargetName(target))",
                        value: value, target: target, scope: scope, source: .manual))
                }
            }
            ForEach(chips) { m in
                Button { combat.removeModifier(character.id, modifierID: m.id) } label: {
                    Text(m.label)
                        .font(questFont(14))
                        .foregroundStyle(m.value >= 0 ? Color(hex: "4AA3DF") : .red)
                }
                .buttonStyle(.plain)
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

    // MARK: Rest / Recharge / turn events

    private var restBar: some View {
        HStack(spacing: 10) {
            Button {
                combat.apply(character.id, event: .myTurnStarted)
                showRecharge = true
            } label: {
                Label("My Turn — Recharge!", systemImage: "die.face.6")
                    .font(questFont(15)).foregroundStyle(.black)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showRecharge, arrowEdge: .top) {
                RechargeRollView { rolled in
                    combat.recharge(character.id, rolled: rolled,
                        rechargeAbilityIDs: sheet.abilities
                            .filter { $0.ability.reset == .recharge }.map(\.ability.id))
                    showRecharge = false
                }
                .presentationCompactAdaptation(.popover)
            }

            Button { combat.apply(character.id, event: .attackResolved) } label: {
                Label("Attack Done", systemImage: "checkmark.seal")
                    .font(questFont(15)).foregroundStyle(.black)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
            }
            .buttonStyle(.plain)

            Spacer()

            Button { combat.rest(character.id, maxHP: sheet.maxHP) } label: {
                Label("Rest", systemImage: "moon.zzz.fill")
                    .font(questFont(15)).foregroundStyle(.black)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(TierColor.selectPeach, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
            }
            .buttonStyle(.plain)
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
            Image(systemName: "plus.circle.fill").font(.caption).foregroundStyle(accent)
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
