//  EncounterView.swift  (v3 — dark board theme, single control row, late arrivals)
//  The Places board — the GM battle tracker (BATTLE_SYSTEM_SPEC §3). Presented
//  full-screen from the GM tab so the map gets the whole iPad at the table.
//
//  THEME: BoardStyle.darkMode routes every surface through theme constants —
//  near-black board, dark grey boxes, warm-white ink — while the game's visual
//  language (hero green / monster coral / lock amber / blue place headers /
//  purple quirk) is untouched. Flip the Bool to return to cream & white.
//
//  LAYOUT: a horizontal strip of place columns in strip order. A child place hangs
//  ABOVE or BELOW its parent (Place.side) as a floating sub-card with an amber
//  dashed border; hanging cards are overlays into reserved padding, so the main
//  columns always sit in one straight row. A locked place NEXT TO rooms is just a
//  strip place WITH a lock — strip columns render their lock capsule.
//
//  MOVEMENT: tap-chip-then-tap-place. Tap the SELECTED chip again → detail sheet.
//  NO LEGALITY ENFORCEMENT and DICE PILLAR: nothing rolls; illegal states are
//  visible — that's the referee.

import SwiftUI

// MARK: - Board palette

private enum BoardStyle {
    /// THEME TEST (Joey's dark-table look): black board + dark grey boxes.
    /// Every surface routes through the vars below, so the experiment is one Bool.
    static let darkMode = true

    static var background: Color { darkMode ? Color(hex: "0F0F10") : .white }
    static var box:        Color { darkMode ? Color(hex: "2A2A2E") : TierColor.panelCream }
    static var boxDeep:    Color { darkMode ? Color(hex: "1C1C1E") : TierColor.panelCream }
    static var field:      Color { darkMode ? Color(hex: "323236") : .white }
    static var ink:        Color { darkMode ? Color(hex: "F4F4F0") : .black }
    static var border:     Color { darkMode ? Color(hex: "55555C") : .black }
    static var quirkPurple: Color { darkMode ? Color(hex: "B893E8") : Color(hex: "8A4FD0") }
    static var select:      Color { darkMode ? Color(hex: "7EB3E0") : Color(hex: "3E6E96") }
    static var lockFill:    Color { darkMode ? Color(hex: "3A3226") : Color(hex: "FFF3D6") }

    // Kept colors — the visual language survives the theme swap.
    static let heroFill      = Color(hex: "CDE3BE")
    static let heroBorder    = Color(hex: "17A34A")
    static let monsterFill   = Color(hex: "F8D3CB")
    static let monsterBorder = Color(hex: "C94F3F")
    static let lockAmber     = Color(hex: "E8A020")
    static let headerBlue    = Color(hex: "A8CBE4")

    static let columnWidth: CGFloat = 250
    static let columnHeight: CGFloat = 440
    static let lockedHeight: CGFloat = 170
    static let buttonHeight: CGFloat = 42
    static let hangGap: CGFloat = 12
}

// MARK: - Board

struct EncounterView: View {
    let repo: ContentRepository
    let store: EncounterStore
    let party: GMPartyStore
    var onDismiss: () -> Void

    @State private var selectedID: UUID? = nil
    @State private var detail: DetailRef? = nil
    @State private var addingPlace = false
    @State private var scanningHero = false
    @State private var addingPlayer = false
    @State private var improvising: MonsterThreat? = nil
    @State private var improvName = ""
    @State private var endingFight = false

    private struct DetailRef: Identifiable { let id: UUID }

    // The body is deliberately split into named sub-pieces — one giant
    // expression sent the Swift 6 type checker into "unable to type-check
    // in reasonable time" territory.
    var body: some View {
        boardContent
            .sheet(item: $detail) { detailSheet($0) }
            .sheet(isPresented: $addingPlace) { placeSheet }
            .sheet(isPresented: $addingPlayer) { newPlayerSheet }
            .sheet(isPresented: $scanningHero) { scanHeroSheet }
            .alert("Name it!", isPresented: improvBinding, presenting: improvising,
                   actions: { improvActions($0) },
                   message: { improvMessage($0) })
            .confirmationDialog("End the fight?", isPresented: $endingFight,
                                titleVisibility: .visible,
                                actions: { endFightActions },
                                message: { Text("The board clears. Hand out the loot from the party panel.") })
    }

    private var boardContent: some View {
        VStack(spacing: 10) {
            if let e = store.encounter {
                header(e)
                selectionHint(e)
                board(e)
            } else {
                // The fight ended from under the cover — just close.
                Color.clear.onAppear { onDismiss() }
            }
        }
        .padding(16)
        .background(BoardStyle.background.ignoresSafeArea())
        .environment(\.colorScheme, BoardStyle.darkMode ? .dark : .light)
    }

    /// Resolve live from the store each render, so damage/condition edits
    /// inside the sheet stay in sync with the board behind it.
    @ViewBuilder
    private func detailSheet(_ ref: DetailRef) -> some View {
        if let c = store.encounter?.combatants.first(where: { $0.id == ref.id }) {
            CombatantDetail(combatant: c, repo: repo, store: store) { detail = nil }
                .presentationDetents([.medium])
                .environment(\.colorScheme, BoardStyle.darkMode ? .dark : .light)
        }
    }

    @ViewBuilder
    private var placeSheet: some View {
        if let e = store.encounter {
            AddPlaceSheet(strip: e.strip) { name, lock, parentID, side in
                store.addPlace(name: name, lock: lock, parentID: parentID, side: side)
            }
            .presentationDetents([.large])
            .environment(\.colorScheme, BoardStyle.darkMode ? .dark : .light)
        }
    }

    /// Late arrival: a brand-new player joins mid-fight — added to the party AND
    /// dropped onto the board in one motion, without leaving the battle. (Reuses
    /// the GM tab's AddPartyMemberSheet; a hero already in the party is the
    /// simpler case, one tap away under Add Fighter → Heroes.)
    private var newPlayerSheet: some View {
        AddPartyMemberSheet(repo: repo) { member in
            party.add(member)
            store.addHero(member, to: defaultPlaceID)
        }
        .presentationDetents([.medium, .large])
    }
    
    /// Late arrival, QR flavor: scan the newcomer's hero card → a party record
        /// carrying their REAL CharacterChoices.id → chip on the board, in one motion.
        /// Same two-step as newPlayerSheet; the identity is imported instead of typed,
        /// which is the whole point — a hand-typed member can never be awarded to.
        private var scanHeroSheet: some View {
            ScanHeroCardSheet(repo: repo,
                              existingIDs: Set(party.members.map(\.id))) { card in
                let member = GMPartyMember(card: card)
                party.update(member)
                // A re-scan of someone ALREADY fighting refreshes their party card but
                // must not drop a second chip. addFighterMenu prevents duplicates by
                // filtering the menu (`benched`); a scan bypasses that filter, and
                // store.addHero doesn't guard.
                if !isOnBoard(member.id) { store.addHero(member, to: defaultPlaceID) }
            }
        }

        private func isOnBoard(_ memberID: UUID) -> Bool {
            store.encounter?.combatants.contains { c in
                if case .hero(let m) = c.kind { return m == memberID }
                return false
            } ?? false
        }

    /// The improviser's one text field: "GM names it" is the whole rule.
    @ViewBuilder
    private func improvActions(_ threat: MonsterThreat) -> some View {
        TextField("The Grumpy Thing", text: $improvName)
        Button("Add") {
            store.addImprovised(name: improvName, threat: threat, to: defaultPlaceID)
            improvName = ""
        }
        Button("Cancel", role: .cancel) { improvName = "" }
    }

    private func improvMessage(_ threat: MonsterThreat) -> some View {
        Text("\(threat.rawValue.capitalized): HP \(threat.suggestedHP) · +\(threat.suggestedToHit) to hit · \(threat.suggestedDamageLine). Tweak HP on its chip after.")
    }

    @ViewBuilder
    private var endFightActions: some View {
        Button("End it — time for rewards!", role: .destructive) {
            store.end()
            onDismiss()
        }
        Button("Keep fighting", role: .cancel) {}
    }

    private var improvBinding: Binding<Bool> {
        Binding(get: { improvising != nil }, set: { if !$0 { improvising = nil } })
    }

    /// New fighters land in the first strip place; the GM taps them into position.
    private var defaultPlaceID: UUID {
        store.encounter?.strip.first?.id ?? UUID()
    }

    // MARK: Header — row 1 is identity (title · close); row 2 is the game console
    // (round · turn · add · end), all on one line at one height.

    private func header(_ e: Encounter) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                QuestChip(text: e.title, fill: Color(hex: "C9C4EC"), size: 20)
                Spacer()
                Button { onDismiss() } label: { headerButton("Close", "xmark") }
                    .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                roundChip(e)

                Button { store.nextTurn() } label: {
                    headerButton("Next Turn", "arrow.right.circle.fill")
                }
                .buttonStyle(.plain)

                addFighterMenu(e)

                Button { addingPlace = true } label: { headerButton("Add Place", "plus.square.on.square") }
                    .buttonStyle(.plain)

                Spacer()

                Button { endingFight = true } label: {
                    headerButton("End Fight", "flag.checkered",
                                 fill: TierColor.selectPeach, ink: .black)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func roundChip(_ e: Encounter) -> some View {
        HStack(spacing: 8) {
            Button { store.setRound(e.round - 1) } label: {
                Image(systemName: "minus.circle").foregroundStyle(BoardStyle.ink.opacity(0.5))
            }
            Text("Round \(e.round)").font(questFont(16)).foregroundStyle(BoardStyle.ink)
                .lineLimit(1).fixedSize()   // NEVER wraps — the "Ro-un-d-3" totem pole
                .contentTransition(.numericText())
            Button { store.setRound(e.round + 1) } label: {
                Image(systemName: "plus.circle").foregroundStyle(BoardStyle.ink.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .frame(height: BoardStyle.buttonHeight)
        .background(BoardStyle.box, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BoardStyle.border, lineWidth: 2))
    }

    private func headerButton(_ text: String, _ symbol: String,
                              fill: Color = BoardStyle.box,
                              ink: Color = BoardStyle.ink) -> some View {
        Label(text, systemImage: symbol)
            .font(questFont(14)).foregroundStyle(ink)
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14)
            .frame(height: BoardStyle.buttonHeight)
            .background(fill, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BoardStyle.border, lineWidth: 2))
    }

    private func addFighterMenu(_ e: Encounter) -> some View {
        // Party members not already on the board.
        let onBoard = Set(e.combatants.compactMap { c -> UUID? in
            if case .hero(let m) = c.kind { return m }; return nil
        })
        let benched = party.members.filter { !onBoard.contains($0.id) }

        return Menu {
            if !benched.isEmpty {
                Section("Heroes") {
                    ForEach(benched) { m in
                        Button(m.name) { store.addHero(m, to: defaultPlaceID) }
                    }
                }
            }
            Section("Monsters") {
                ForEach(repo.monsters()) { def in
                    Button("\(def.name)  (HP \(def.hp))") { store.addMonster(def, to: defaultPlaceID) }
                }
            }
            Section("Improvise — Quick Monster Math") {
                ForEach(MonsterThreat.allCases, id: \.self) { t in
                    Button("\(t.rawValue.capitalized) — HP \(t.suggestedHP) · \(t.suggestedDamageLine)") {
                        improvName = ""
                        improvising = t
                    }
                }
            }
            Section("Late arrival?") {
                Button { scanningHero = true } label: {
                    Label("Scan a hero card…", systemImage: "qrcode.viewfinder")
                }
                Button { addingPlayer = true } label: {
                    Label("New player just showed up…", systemImage: "figure.wave")
                }
            }
        } label: {
            headerButton("Add Fighter", "plus.circle.fill")
        }
    }
    
    // MARK: Selection hint

    @ViewBuilder
    private func selectionHint(_ e: Encounter) -> some View {
        if let sel = selectedID, let c = e.combatants.first(where: { $0.id == sel }) {
            HStack(spacing: 8) {
                Image(systemName: "hand.tap.fill").foregroundStyle(BoardStyle.select)
                Text("Tap a place to move \(c.name) — or tap \(c.name) again for details.")
                    .font(questFontLight(14)).foregroundStyle(BoardStyle.ink.opacity(0.75))
                Spacer()
                Button { selectedID = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(BoardStyle.ink.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(BoardStyle.select.opacity(0.15), in: Capsule())
        } else {
            Text("Tap a fighter, then tap where they go. Nothing is enforced — the map just shows the truth.")
                .font(questFontLight(13)).foregroundStyle(BoardStyle.ink.opacity(0.4))
        }
    }

    // MARK: The strip
    //
    // Main columns are the ONLY row content (so they always align); hanging cards
    // render as overlays offset above/below into padding reserved for the deepest
    // stack on each side.

    private func board(_ e: Encounter) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(e.strip) { place in
                    placeColumn(place, in: e)
                        .overlay(alignment: .top) { hangingStack(LockedSide.above, off: place, in: e) }
                        .overlay(alignment: .bottom) { hangingStack(LockedSide.below, off: place, in: e) }
                }
            }
            .padding(.top, reserve(LockedSide.above, in: e))
            .padding(.bottom, reserve(LockedSide.below, in: e))
            .padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func hangers(_ side: LockedSide, off place: Place, in e: Encounter) -> [Place] {
        e.lockedPlaces(off: place.id).filter { $0.resolvedSide == side }
    }

    /// Vertical space to reserve so the deepest hanging stack fits inside the
    /// scroll content (overlays don't take layout space on their own).
    private func reserve(_ side: LockedSide, in e: Encounter) -> CGFloat {
        let deepest = e.strip.map { hangers(side, off: $0, in: e).count }.max() ?? 0
        guard deepest > 0 else { return 0 }
        return CGFloat(deepest) * BoardStyle.lockedHeight
             + CGFloat(deepest - 1) * 10
             + BoardStyle.hangGap
    }

    @ViewBuilder
    private func hangingStack(_ side: LockedSide, off place: Place, in e: Encounter) -> some View {
        let cards = hangers(side, off: place, in: e)
        if !cards.isEmpty {
            let stackHeight = CGFloat(cards.count) * BoardStyle.lockedHeight
                            + CGFloat(cards.count - 1) * 10
            VStack(spacing: 10) {
                ForEach(cards) { hangingCard($0, in: e) }
            }
            .offset(y: side == .above ? -(stackHeight + BoardStyle.hangGap)
                                      :  (stackHeight + BoardStyle.hangGap))
        }
    }

    private func placeColumn(_ place: Place, in e: Encounter) -> some View {
        VStack(spacing: 8) {
            Text(place.name.uppercased())
                .font(questFont(15)).foregroundStyle(.black)
                .lineLimit(2).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(BoardStyle.headerBlue, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BoardStyle.border, lineWidth: 2))

            // A locked place IN the row ("next to" the others) — the golden rule
            // still applies, the lock just guards a ground-level door.
            if let lock = place.lock { lockCapsule(lock) }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(e.combatants(in: place.id)) { chip($0, in: e) }
                }
                .padding(.vertical, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: BoardStyle.columnWidth, height: BoardStyle.columnHeight)
        .background(BoardStyle.box, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(BoardStyle.border, lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { placeTapped(place.id) }
        .contextMenu {
            if e.combatants(in: place.id).isEmpty && e.lockedPlaces(off: place.id).isEmpty {
                Button("Remove \(place.name)", role: .destructive) { store.removePlace(place.id) }
            }
        }
    }

    private func lockCapsule(_ lock: String) -> some View {
        Label(lock, systemImage: "lock.fill")
            .font(questFontLight(11)).foregroundStyle(BoardStyle.ink)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(BoardStyle.lockAmber.opacity(0.28), in: Capsule())
            .overlay(Capsule().strokeBorder(BoardStyle.lockAmber, lineWidth: 1.5))
            .lineLimit(1).minimumScaleFactor(0.6)
    }

    private func hangingCard(_ place: Place, in e: Encounter) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: place.lock == nil ? "arrow.turn.right.down" : "lock.fill")
                    .font(.caption).foregroundStyle(BoardStyle.lockAmber)
                Text(place.name).font(questFont(13)).foregroundStyle(BoardStyle.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            if let lock = place.lock { lockCapsule(lock) }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(e.combatants(in: place.id)) { chip($0, in: e) }
                }
            }
        }
        .padding(8)
        .frame(width: BoardStyle.columnWidth - 26, height: BoardStyle.lockedHeight)
        .background(BoardStyle.lockFill, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(BoardStyle.lockAmber, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { placeTapped(place.id) }
        .contextMenu {
            if e.combatants(in: place.id).isEmpty {
                Button("Remove \(place.name)", role: .destructive) { store.removePlace(place.id) }
            }
        }
    }

    // MARK: Chips (pastel fills + black text kept — they pop on the dark grey)

    private func chip(_ c: Combatant, in e: Encounter) -> some View {
        let fill = c.isMonster ? BoardStyle.monsterFill : BoardStyle.heroFill
        let border = c.isMonster ? BoardStyle.monsterBorder : BoardStyle.heroBorder
        let selected = selectedID == c.id
        let active = e.activeCombatantID == c.id

        return Button { chipTapped(c) } label: {
            HStack(spacing: 8) {
                Text(initials(c.name))
                    .font(questFont(13)).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(border, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name)
                        .font(questFont(13)).foregroundStyle(.black)
                        .strikethrough(c.isDown)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    HStack(spacing: 4) {
                        if c.isMonster {
                            Text(c.isDown ? "DOWN" : "HP \(c.hp)/\(c.maxHP)")
                                .font(questFontLight(11))
                                .foregroundStyle(c.isDown ? .red : .black.opacity(0.6))
                        }
                        ForEach(Array(c.conditions).sorted(by: { $0.rawValue < $1.rawValue }),
                                id: \.self) { conditionBadge($0) }
                    }
                }
                Spacer(minLength: 0)
                if c.isDown { Image(systemName: "zzz").font(.caption).foregroundStyle(.red.opacity(0.6)) }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill.opacity(c.isDown ? 0.45 : 1), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(border, lineWidth: 2))
            // Active-turn accent ring (orange) sits OUTSIDE the chip border…
            .overlay {
                if active {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(TierColor.signature, lineWidth: 3)
                        .padding(-4)
                }
            }
            // …and the selection ring is dashed blue, distinct from both.
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(BoardStyle.select,
                                      style: StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
                        .padding(-7)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func conditionBadge(_ k: ConditionKind) -> some View {
        Text(k.rawValue.capitalized)
            .font(questFontLight(9)).foregroundStyle(.black)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(BoardStyle.lockAmber.opacity(0.3), in: Capsule())
            .overlay(Capsule().strokeBorder(BoardStyle.lockAmber.opacity(0.7), lineWidth: 1))
    }

    private func initials(_ name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        return words.map { String($0.prefix(1)) }.joined().uppercased()
    }

    // MARK: Tap routing (select → move; selected again → detail)

    private func chipTapped(_ c: Combatant) {
        if selectedID == c.id {
            selectedID = nil
            detail = DetailRef(id: c.id)
        } else {
            selectedID = c.id
        }
    }

    private func placeTapped(_ placeID: UUID) {
        guard let sel = selectedID else { return }
        store.move(sel, to: placeID)
        selectedID = nil
    }
}

// MARK: - Combatant detail (damage entry, conditions, quirk)

private struct CombatantDetail: View {
    let combatant: Combatant
    let repo: ContentRepository
    let store: EncounterStore
    var onClose: () -> Void

    @State private var confirmingRemove = false

    /// The GM's best material, front and center. Improvised monsters have none.
    private var quirk: String? {
        if case .monster(let id?) = combatant.kind { return repo.monster(id)?.quirk }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(combatant.name.uppercased()).font(questFont(24)).foregroundStyle(BoardStyle.ink)
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2).foregroundStyle(BoardStyle.ink.opacity(0.3))
                }
                .buttonStyle(.plain)
            }

            if combatant.isMonster {
                monsterStats
            } else {
                Text("HP lives on their character sheet — this chip is just where they're standing.")
                    .font(questFontLight(14)).foregroundStyle(BoardStyle.ink.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let quirk {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Quirk", systemImage: "sparkles")
                        .font(questFont(14)).foregroundStyle(BoardStyle.quirkPurple)
                    Text(quirk).font(questFontLight(15)).foregroundStyle(BoardStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BoardStyle.quirkPurple.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(BoardStyle.quirkPurple, lineWidth: 2))
            }

            conditionsRow

            Spacer(minLength: 0)

            Button { confirmingRemove = true } label: {
                Label("Remove from the fight", systemImage: "trash")
                    .font(questFont(14)).foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .confirmationDialog("Remove \(combatant.name)?", isPresented: $confirmingRemove,
                                titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    store.remove(combatant.id)
                    onClose()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BoardStyle.boxDeep)
    }

    private var monsterStats: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("HP")
                    .font(questFont(16)).foregroundStyle(BoardStyle.ink)
                Text("\(combatant.hp)/\(combatant.maxHP)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(combatant.isDown ? .red
                        : (combatant.hp * 2 <= combatant.maxHP ? .orange : BoardStyle.heroBorder))
                    .contentTransition(.numericText())
                Spacer()
                if let toHit = combatant.toHit, let dmg = combatant.damageLine {
                    Text("+\(toHit) to hit · \(dmg)")
                        .font(.callout.monospaced()).foregroundStyle(BoardStyle.ink.opacity(0.7))
                }
            }
            HStack(spacing: 8) {
                damageButton("-5") { store.damage(combatant.id, 5) }
                damageButton("-3") { store.damage(combatant.id, 3) }
                damageButton("-1") { store.damage(combatant.id, 1) }
                damageButton("+1") { store.damage(combatant.id, -1) }
                damageButton("+3") { store.damage(combatant.id, -3) }
            }
        }
    }

    private func damageButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(questFont(15))
                .foregroundStyle(label.hasPrefix("-") ? .red : .green)
                .frame(width: 52, height: 36)
                .background(BoardStyle.field, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BoardStyle.border, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private var conditionsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CONDITIONS").font(questFont(13)).foregroundStyle(BoardStyle.ink.opacity(0.6))
            HStack(spacing: 8) {
                ForEach(ConditionKind.allCases, id: \.self) { k in
                    let on = combatant.conditions.contains(k)
                    Button { store.toggleCondition(combatant.id, k) } label: {
                        Text(k.rawValue.capitalized)
                            .font(questFont(13))
                            .foregroundStyle(BoardStyle.ink.opacity(on ? 1 : 0.5))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(on ? BoardStyle.lockAmber.opacity(0.35) : BoardStyle.field,
                                        in: Capsule())
                            .overlay(Capsule().strokeBorder(
                                on ? BoardStyle.lockAmber : BoardStyle.border,
                                lineWidth: on ? 2 : 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - "+ Place" (required mid-fight — spec §1.1) with the structured lock editor

private struct AddPlaceSheet: View {
    let strip: [Place]
    var onAdd: (String, String?, UUID?, LockedSide?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var placement: Placement = .row
    @State private var parentID: UUID? = nil
    @State private var hasLock = false
    @State private var lockStat = "Speed"           // the GM calls the stat
    @State private var lockTarget = 12              // 10 easy · 12 standard
    @State private var lockVerb = "to climb"        // "to climb", "to smash", "to solve"

    private enum Placement: String, CaseIterable, Identifiable {
        case row = "In the row", above = "Above a place", below = "Below a place"
        var id: String { rawValue }
    }

    /// The composed display string — the model stays a plain string, so the
    /// encounter format doesn't change shape.
    private var composedLock: String {
        let verb = lockVerb.trimmingCharacters(in: .whitespaces)
        return verb.isEmpty ? "\(lockStat) \(lockTarget)" : "\(lockStat) \(lockTarget) \(verb)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("NEW PLACE").font(questFont(22)).foregroundStyle(BoardStyle.ink)
                Text("Two questions: does standing there change what you can do? Is getting there a feat? Yes to the second → give it a lock.")
                    .font(questFontLight(13)).foregroundStyle(BoardStyle.ink.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Name — e.g. Inside the giant pot", text: $name)
                    .font(questFont(17))
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(BoardStyle.field, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BoardStyle.border, lineWidth: 1.5))

                // WHERE it sits: in the strip, or hanging above/below a parent.
                VStack(alignment: .leading, spacing: 6) {
                    Text("WHERE").font(questFont(13)).foregroundStyle(BoardStyle.ink.opacity(0.6))
                    Picker("Where", selection: $placement) {
                        ForEach(Placement.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if placement != .row {
                        Picker("Off which place?", selection: $parentID) {
                            ForEach(strip) { p in Text(p.name).tag(Optional(p.id)) }
                        }
                        .pickerStyle(.menu)
                        .font(questFont(15))
                        .onAppear { if parentID == nil { parentID = strip.first?.id } }
                    }
                }

                Toggle(isOn: $hasLock) {
                    Label("Locked — getting there takes a roll", systemImage: "lock.fill")
                        .font(questFont(15)).foregroundStyle(BoardStyle.ink)
                }
                .tint(BoardStyle.lockAmber)

                if hasLock {
                    VStack(alignment: .leading, spacing: 10) {
                        // The GM calls the stat — climbing is Speed, forcing a door
                        // is Might, a riddle-sealed hatch is Mind.
                        Picker("Stat", selection: $lockStat) {
                            Text("Might").tag("Might")
                            Text("Speed").tag("Speed")
                            Text("Mind").tag("Mind")
                        }
                        .pickerStyle(.segmented)

                        Stepper(value: $lockTarget, in: 5...20) {
                            HStack(spacing: 8) {
                                Text("Roll \(lockTarget)+")
                                    .font(questFont(16)).foregroundStyle(BoardStyle.ink)
                                    .contentTransition(.numericText())
                                Text(lockTarget <= 10 ? "easy" : (lockTarget <= 13 ? "standard" : "hard"))
                                    .font(questFontLight(12)).foregroundStyle(BoardStyle.ink.opacity(0.5))
                            }
                        }

                        TextField("How — e.g. to climb, to smash, to solve", text: $lockVerb)
                            .font(questFontLight(15))
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(BoardStyle.field, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(BoardStyle.border, lineWidth: 1.5))

                        Label(composedLock, systemImage: "lock.fill")
                            .font(questFontLight(13)).foregroundStyle(BoardStyle.ink)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(BoardStyle.lockFill, in: Capsule())
                            .overlay(Capsule().strokeBorder(BoardStyle.lockAmber, lineWidth: 1.5))
                    }
                    .padding(12)
                    .background(BoardStyle.lockAmber.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    let side: LockedSide?
                    switch placement {
                    case .above: side = LockedSide.above
                    case .below: side = LockedSide.below
                    case .row:   side = nil
                    }
                    onAdd(name,
                          hasLock ? composedLock : nil,
                          placement == .row ? nil : parentID,
                          side)
                    dismiss()
                } label: {
                    Text("Add place")
                        .font(questFont(16)).foregroundStyle(.black)
                        .padding(.horizontal, 24).padding(.vertical, 11)
                        .background(TierColor.selectPeach, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                          || (placement != .row && parentID == nil))
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BoardStyle.boxDeep)
    }
}
