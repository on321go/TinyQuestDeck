//  PlaySheetView.swift
//  Read-only themed play sheet. Renders the derived CharacterSheet — no live state yet
//  (current HP, checking off spell boxes, conditions come with the combat tracker).
//  Reuses Color(hex:) and emblemSymbol from HeroTile.swift.

import SwiftUI

struct PlaySheetView: View {
    let character: CharacterChoices
    let repo: ContentRepository

    var body: some View {
        Group {
            if let sheet = deriveSheet(from: character, using: repo) {
                SheetBody(sheet: sheet)
            } else {
                ContentUnavailableView("Couldn’t build this sheet",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This hero references content that didn’t load."))
            }
        }
        .navigationTitle(character.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SheetBody: View {
    let sheet: CharacterSheet

    private var bg: Color { sheet.theme.map { Color(hex: $0.background) } ?? .gray }
    private var panel: Color { sheet.theme.map { Color(hex: $0.panel) } ?? .white }
    private var accent: Color { sheet.theme.map { Color(hex: $0.accent) } ?? .blue }
    private var ink: Color { sheet.theme.map { Color(hex: $0.ink) } ?? .primary }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                statRow
                if !sheet.conditionImmunities.isEmpty { immunities }
                abilitiesSection
                gearSection
                if sheet.isCaster { spellsSection }
            }
            .padding()
        }
        .background(bg.opacity(0.15))
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [bg, bg.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: emblemSymbol(sheet.theme?.emblem))
                        .font(.system(size: 96)).foregroundStyle(ink.opacity(0.12))
                        .offset(x: 14, y: -4)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(sheet.name).font(.largeTitle.weight(.heavy)).foregroundStyle(ink)
                Text("Level \(sheet.level) · \(sheet.raceName) · \(sheet.className) — \(sheet.pathName)")
                    .font(.subheadline).foregroundStyle(ink.opacity(0.75))
            }
            .padding(18)
        }
    }

    // MARK: Stats (oversized)

    private var statRow: some View {
        HStack(spacing: 12) {
            statTile("MIGHT", "+\(sheet.might)")
            statTile("MIND",  "+\(sheet.mind)")
            statTile("SPEED", "+\(sheet.speed)")
            statTile("HP",    "\(sheet.maxHP)", emphasized: true)
        }
    }

    private func statTile(_ label: String, _ value: String, emphasized: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(ink.opacity(0.6))
            Text(value)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(emphasized ? accent : ink)
                .minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(0.25)))
    }

    private var immunities: some View {
        let names = sheet.conditionImmunities.map { $0.rawValue.capitalized }.joined(separator: ", ")
        return Label("Immune to \(names)", systemImage: "checkmark.shield.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(panel.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Abilities

    private var abilitiesSection: some View {
        section("Abilities") {
            ForEach(sheet.abilities, id: \.ability.id) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.ability.name).font(.headline).foregroundStyle(ink)
                        sourceTag(item.source)
                        Spacer()
                        Text("\(item.ability.actionCost.rawValue) • \(item.ability.reset.rawValue)")
                            .font(.caption2).foregroundStyle(ink.opacity(0.55))
                    }
                    Text(item.ability.text).font(.callout).foregroundStyle(ink.opacity(0.85))
                    if let atk = item.ability.attack {
                        Text(attackSummary(atk)).font(.caption.monospaced()).foregroundStyle(accent)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(panel, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func sourceTag(_ s: AbilitySource) -> some View {
        let label: String = switch s {
            case .core: "Core"; case .race: "Race"
            case .pathPower: "Path"; case .signature: "Signature"
        }
        return Text(label.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(accent.opacity(0.18), in: Capsule())
            .foregroundStyle(accent)
    }

    // MARK: Gear

    private var gearSection: some View {
        section("Gear") {
            ForEach(sheet.gear) { g in
                HStack {
                    Text(g.name).font(.subheadline.weight(.medium)).foregroundStyle(ink)
                    Spacer()
                    if let atk = g.attack {
                        Text(attackSummary(atk)).font(.caption.monospaced()).foregroundStyle(ink.opacity(0.7))
                    } else if g.maxHP > 0 {
                        Text("+\(g.maxHP) HP").font(.caption.weight(.semibold)).foregroundStyle(accent)
                    }
                }
                .padding(.vertical, 8).padding(.horizontal, 12)
                .background(panel, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: Spells

    private var spellsSection: some View {
        section("Ready Spells  (cap \(sheet.readySpellCap))") {
            ForEach(sheet.readySpells, id: \.spell.id) { s in spellRow(s) }

            let bench = sheet.spells.filter { !$0.isReady }
            if !bench.isEmpty {
                Text("Spellbook").font(.caption.weight(.bold)).foregroundStyle(ink.opacity(0.55))
                    .padding(.top, 6)
                ForEach(bench, id: \.spell.id) { s in
                    Text(s.spell.name).font(.subheadline).foregroundStyle(ink.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4).padding(.horizontal, 12)
                }
            }
        }
    }

    private func spellRow(_ s: SheetSpell) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(s.spell.name).font(.headline).foregroundStyle(ink)
                Spacer()
                HStack(spacing: 3) {
                    ForEach(0..<max(s.readyUses, 0), id: \.self) { _ in
                        Image(systemName: "square").font(.caption2).foregroundStyle(accent)
                    }
                }
            }
            Text(s.spell.text).font(.callout).foregroundStyle(ink.opacity(0.85))
            if let atk = s.spell.attack {
                Text(attackSummary(atk)).font(.caption.monospaced()).foregroundStyle(accent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panel, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Section scaffold

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.subheadline.weight(.bold)).foregroundStyle(ink.opacity(0.6))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
