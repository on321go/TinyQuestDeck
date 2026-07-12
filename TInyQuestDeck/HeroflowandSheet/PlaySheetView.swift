////  PlaySheetView.swift
////  Themed play sheet — now LIVE. Reads the static derived sheet and layers per-session
////  combat state (CombatStore) on top: HP, conditions, ability use, spell casts, Rest/Recharge.
////  Reuses Color(hex:) and emblemSymbol from HeroTile.swift.
//
//import SwiftUI
//
//struct PlaySheetView: View {
//    let character: CharacterChoices
//    let repo: ContentRepository
//    let combat: CombatStore
//
//    var body: some View {
//        Group {
//            if let sheet = deriveSheet(from: character, using: repo) {
//                SheetBody(sheet: sheet, id: character.id, combat: combat)
//                    .onAppear { combat.seed(character.id, maxHP: sheet.maxHP) }
//            } else {
//                ContentUnavailableView("Couldn’t build this sheet",
//                    systemImage: "exclamationmark.triangle",
//                    description: Text("This hero references content that didn’t load."))
//            }
//        }
//        .navigationTitle(character.name)
//        .navigationBarTitleDisplayMode(.inline)
//    }
//}
//
//private struct SheetBody: View {
//    let sheet: CharacterSheet
//    let id: UUID
//    let combat: CombatStore
//
//    @State private var rechargeResult: Int?
//
//    private var bg: Color { sheet.theme.map { Color(hex: $0.background) } ?? .gray }
//    private var panel: Color { sheet.theme.map { Color(hex: $0.panel) } ?? .white }
//    private var accent: Color { sheet.theme.map { Color(hex: $0.accent) } ?? .blue }
//    private var ink: Color { sheet.theme.map { Color(hex: $0.ink) } ?? .primary }
//
//    private var state: CombatState { combat.states[id] ?? CombatState(currentHP: sheet.maxHP) }
//
//    var body: some View {
//        ScrollView {
//            VStack(spacing: 18) {
//                header
//                hpControl
//                statRow
//                conditionsRow
//                abilitiesSection
//                gearSection
//                if sheet.isCaster { spellsSection }
//                restBar
//            }
//            .padding()
//        }
//        .background(bg.opacity(0.15))
//    }
//
//    // MARK: Header
//
//    private var header: some View {
//        ZStack(alignment: .leading) {
//            RoundedRectangle(cornerRadius: 18, style: .continuous)
//                .fill(LinearGradient(colors: [bg, bg.opacity(0.7)], startPoint: .top, endPoint: .bottom))
//                .overlay(alignment: .topTrailing) {
//                    Image(systemName: emblemSymbol(sheet.theme?.emblem))
//                        .font(.system(size: 96)).foregroundStyle(ink.opacity(0.12)).offset(x: 14, y: -4)
//                }
//            VStack(alignment: .leading, spacing: 4) {
//                Text(sheet.name).font(.largeTitle.weight(.heavy)).foregroundStyle(ink)
//                Text("Level \(sheet.level) · \(sheet.raceName) · \(sheet.className) — \(sheet.pathName)")
//                    .font(.subheadline).foregroundStyle(ink.opacity(0.75))
//            }
//            .padding(18)
//        }
//    }
//
//    // MARK: HP (live)
//
//    private var hpColor: Color {
//        let f = Double(state.currentHP) / Double(max(sheet.maxHP, 1))
//        if state.currentHP <= 0 { return .red }
//        return f <= 0.5 ? .orange : .green
//    }
//
//    private var hpControl: some View {
//        VStack(spacing: 10) {
//            HStack(alignment: .firstTextBaseline, spacing: 6) {
//                Text("\(state.currentHP)")
//                    .font(.system(size: 56, weight: .heavy, design: .rounded))
//                    .foregroundStyle(hpColor).contentTransition(.numericText())
//                Text("/ \(sheet.maxHP) HP").font(.title3.weight(.semibold)).foregroundStyle(ink.opacity(0.6))
//                if state.currentHP <= 0 {
//                    Text("DOWN").font(.caption.weight(.black)).foregroundStyle(.white)
//                        .padding(.horizontal, 8).padding(.vertical, 3)
//                        .background(.red, in: Capsule())
//                }
//            }
//            HStack(spacing: 10) {
//                hpButton("-5") { combat.damage(id, 5) }
//                hpButton("-1") { combat.damage(id, 1) }
//                hpButton("+1") { combat.heal(id, 1, maxHP: sheet.maxHP) }
//                hpButton("+5") { combat.heal(id, 5, maxHP: sheet.maxHP) }
//            }
//        }
//        .frame(maxWidth: .infinity)
//        .padding(16)
//        .background(panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
//        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(0.25)))
//    }
//
//    private func hpButton(_ label: String, action: @escaping () -> Void) -> some View {
//        Button(action: action) {
//            Text(label).font(.title3.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 10)
//        }
//        .buttonStyle(.bordered).tint(label.hasPrefix("-") ? .red : .green)
//    }
//
//    // MARK: Stats
//
//    private var statRow: some View {
//        HStack(spacing: 12) {
//            statTile("MIGHT", sheet.might)
//            statTile("MIND",  sheet.mind)
//            statTile("SPEED", sheet.speed)
//        }
//    }
//
//    private func statTile(_ label: String, _ value: Int) -> some View {
//        VStack(spacing: 2) {
//            Text(label).font(.caption2.weight(.bold)).foregroundStyle(ink.opacity(0.6))
//            Text("+\(value)").font(.system(size: 38, weight: .heavy, design: .rounded)).foregroundStyle(ink)
//        }
//        .frame(maxWidth: .infinity).padding(.vertical, 12)
//        .background(panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
//        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(0.25)))
//    }
//
//    // MARK: Conditions (immunity-aware)
//
//    private var conditionsRow: some View {
//        section("Conditions") {
//            HStack(spacing: 8) {
//                ForEach(ConditionKind.allCases, id: \.self) { cond in
//                    let immune = sheet.conditionImmunities.contains(cond)
//                    let active = state.conditions.contains(cond)
//                    Button { combat.toggleCondition(id, cond) } label: {
//                        HStack(spacing: 4) {
//                            if immune { Image(systemName: "shield.fill").font(.caption2) }
//                            Text(cond.rawValue.capitalized).font(.caption.weight(.semibold))
//                        }
//                        .padding(.horizontal, 10).padding(.vertical, 8)
//                        .frame(maxWidth: .infinity)
//                        .background(active ? accent : panel, in: RoundedRectangle(cornerRadius: 10))
//                        .foregroundStyle(immune ? ink.opacity(0.35) : (active ? .white : ink))
//                        .strikethrough(immune)
//                    }
//                    .buttonStyle(.plain)
//                    .disabled(immune)
//                }
//            }
//        }
//    }
//
//    // MARK: Abilities (use-tracking)
//
//    private var abilitiesSection: some View {
//        section("Abilities") {
//            ForEach(sheet.abilities, id: \.ability.id) { item in
//                let a = item.ability
//                let trackable = a.reset != .atWill && a.actionCost != .passive
//                let used = state.usedAbilityIDs.contains(a.id)
//                VStack(alignment: .leading, spacing: 4) {
//                    HStack {
//                        Text(a.name).font(.headline).foregroundStyle(ink).strikethrough(used)
//                        sourceTag(item.source)
//                        Spacer()
//                        if trackable {
//                            Button { combat.toggleUsed(id, a.id) } label: {
//                                Image(systemName: used ? "arrow.counterclockwise.circle.fill" : "circle")
//                                    .font(.title3).foregroundStyle(used ? accent : ink.opacity(0.4))
//                            }.buttonStyle(.plain)
//                        } else {
//                            Text("always").font(.caption2).foregroundStyle(ink.opacity(0.4))
//                        }
//                    }
//                    HStack(spacing: 6) {
//                        Text("\(a.actionCost.rawValue) • \(a.reset.rawValue)")
//                            .font(.caption2).foregroundStyle(ink.opacity(0.55))
//                        if used { Text("USED").font(.caption2.weight(.bold)).foregroundStyle(.red) }
//                    }
//                    Text(a.text).font(.callout).foregroundStyle(ink.opacity(used ? 0.4 : 0.85))
//                    if let atk = a.attack {
//                        Text(attackSummary(atk)).font(.caption.monospaced()).foregroundStyle(accent)
//                    }
//                }
//                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
//                .background(panel, in: RoundedRectangle(cornerRadius: 12))
//                .opacity(used ? 0.7 : 1)
//            }
//        }
//    }
//
//    private func sourceTag(_ s: AbilitySource) -> some View {
//        let label: String = switch s {
//            case .core: "Core"; case .race: "Race"; case .pathPower: "Path"; case .signature: "Signature"
//        }
//        return Text(label.uppercased()).font(.caption2.weight(.bold))
//            .padding(.horizontal, 6).padding(.vertical, 2)
//            .background(accent.opacity(0.18), in: Capsule()).foregroundStyle(accent)
//    }
//
//    // MARK: Gear
//
//    private var gearSection: some View {
//        section("Gear") {
//            ForEach(sheet.gear) { g in
//                HStack {
//                    Text(g.name).font(.subheadline.weight(.medium)).foregroundStyle(ink)
//                    Spacer()
//                    if let atk = g.attack {
//                        Text(attackSummary(atk)).font(.caption.monospaced()).foregroundStyle(ink.opacity(0.7))
//                    } else if g.maxHP > 0 {
//                        Text("+\(g.maxHP) HP").font(.caption.weight(.semibold)).foregroundStyle(accent)
//                    }
//                }
//                .padding(.vertical, 8).padding(.horizontal, 12)
//                .background(panel, in: RoundedRectangle(cornerRadius: 10))
//            }
//        }
//    }
//
//    // MARK: Spells (spendable casts)
//
//    private var spellsSection: some View {
//        section("Ready Spells  (cap \(sheet.readySpellCap))") {
//            ForEach(sheet.readySpells, id: \.spell.id) { s in spellRow(s) }
//            let bench = sheet.spells.filter { !$0.isReady }
//            if !bench.isEmpty {
//                Text("Spellbook").font(.caption.weight(.bold)).foregroundStyle(ink.opacity(0.55)).padding(.top, 6)
//                ForEach(bench, id: \.spell.id) { s in
//                    Text(s.spell.name).font(.subheadline).foregroundStyle(ink.opacity(0.8))
//                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4).padding(.horizontal, 12)
//                }
//            }
//        }
//    }
//
//    private func spellRow(_ s: SheetSpell) -> some View {
//        let spent = state.spellUsesSpent[s.spell.id] ?? 0
//        return VStack(alignment: .leading, spacing: 4) {
//            HStack {
//                Text(s.spell.name).font(.headline).foregroundStyle(ink)
//                Spacer()
//                HStack(spacing: 4) {
//                    ForEach(0..<max(s.readyUses, 0), id: \.self) { i in
//                        Button {
//                            combat.setSpent(id, s.spell.id, toBoxIndex: i, total: s.readyUses)
//                        } label: {
//                            Image(systemName: i < spent ? "checkmark.square.fill" : "square")
//                                .font(.body).foregroundStyle(i < spent ? ink.opacity(0.45) : accent)
//                        }.buttonStyle(.plain)
//                    }
//                }
//            }
//            Text(s.spell.text).font(.callout).foregroundStyle(ink.opacity(0.85))
//            if let atk = s.spell.attack {
//                Text(attackSummary(atk)).font(.caption.monospaced()).foregroundStyle(accent)
//            }
//        }
//        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
//        .background(panel, in: RoundedRectangle(cornerRadius: 12))
//    }
//
//    // MARK: Rest / Recharge
//
//    private var restBar: some View {
//        VStack(spacing: 8) {
//            if let roll = rechargeResult {
//                Text(roll == 6 ? "Recharge: rolled a 6 — powers re-armed!" : "Recharge: rolled \(roll) — not yet.")
//                    .font(.caption.weight(.semibold))
//                    .foregroundStyle(roll == 6 ? .green : ink.opacity(0.6))
//            }
//            HStack(spacing: 12) {
//                Button {
//                    let ids = sheet.abilities.filter { $0.ability.reset == .recharge }.map(\.ability.id)
//                    rechargeResult = combat.recharge(id, rechargeAbilityIDs: ids)
//                } label: {
//                    Label("Recharge (d6)", systemImage: "die.face.6").frame(maxWidth: .infinity).padding(.vertical, 8)
//                }.buttonStyle(.bordered)
//
//                Button {
//                    combat.rest(id, maxHP: sheet.maxHP); rechargeResult = nil
//                } label: {
//                    Label("Rest", systemImage: "moon.zzz.fill").frame(maxWidth: .infinity).padding(.vertical, 8)
//                }.buttonStyle(.borderedProminent).tint(accent)
//            }
//        }
//        .padding(.top, 4)
//    }
//
//    // MARK: Section scaffold
//
//    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
//        VStack(alignment: .leading, spacing: 8) {
//            Text(title.uppercased()).font(.subheadline.weight(.bold)).foregroundStyle(ink.opacity(0.6))
//            content()
//        }
//        .frame(maxWidth: .infinity, alignment: .leading)
//    }
//}
