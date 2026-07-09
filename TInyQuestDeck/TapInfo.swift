//  TapInfo.swift
//  The app-wide "tap a name, get the rules" component. Wraps any compact label;
//  tapping shows a quest-styled popover with the full text, usage line, and attack
//  summary. Used on the path detail (spells), and heavily on the character sheet
//  (abilities, powers, spells, gear) where compact rows replace inline descriptions.
//
//  Depends on QuestStyle.swift (fonts, TierColor) and CharacterSheet.swift's
//  attackSummary(_:). On iPad this is a true popover; on compact widths it stays
//  a popover too (presentationCompactAdaptation) so it never becomes a full sheet.

import SwiftUI

// MARK: - What a popover shows (build from ability / spell / gear)

struct InfoPayload {
    let title: String
    let subtitle: String?       // usage line, cast count, +HP…
    let text: String
    let attack: AttackProfile?
    let tint: Color
}

extension InfoPayload {
    init(ability a: AbilityDefinition, tint: Color) {
        self.init(title: a.name, subtitle: usageLine(a), text: a.text, attack: a.attack, tint: tint)
    }

    init(spell s: SpellDefinition, uses: Int? = nil, tint: Color = TierColor.starting) {
        let sub = (uses ?? 1) > 1 ? "Ready casts: \(uses!)" : nil
        self.init(title: s.name, subtitle: sub, text: s.text, attack: s.attack, tint: tint)
    }

    init(gear g: GearDefinition, tint: Color = .black) {
        self.init(title: g.name,
                  subtitle: g.maxHP != 0 ? "+\(g.maxHP) Max HP" : nil,
                  text: "", attack: g.attack, tint: tint)
    }
}

// MARK: - The tappable wrapper

struct TapInfo<Label: View>: View {
    let payload: InfoPayload
    @ViewBuilder var label: () -> Label

    @State private var showing = false

    var body: some View {
        Button { showing = true } label: { label() }
            .buttonStyle(.plain)
            .popover(isPresented: $showing, arrowEdge: .top) {
                InfoCard(payload: payload)
                    .presentationCompactAdaptation(.popover)
            }
    }
}

// MARK: - The card inside the popover

struct InfoCard: View {
    let payload: InfoPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(payload.title)
                .font(questFont(20))
                .foregroundStyle(payload.tint)

            if let subtitle = payload.subtitle {
                Text(subtitle)
                    .font(questFontLight(13))
                    .foregroundStyle(.black.opacity(0.55))
            }

            if !payload.text.isEmpty {
                Text(payload.text)
                    .font(questFontLight(16))
                    .foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let atk = payload.attack {
                Text(attackSummary(atk))
                    .font(.caption.monospaced())
                    .foregroundStyle(payload.tint)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .background(TierColor.panelCream)
    }
}
