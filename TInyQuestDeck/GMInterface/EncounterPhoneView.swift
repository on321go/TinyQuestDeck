//  EncounterPhoneView.swift  (iPhone / compact — the Places board)
//  The battle tracker at phone width. PARALLEL VIEW, NOT A BRANCH: EncounterView.swift
//  is byte-identical; MainTabView picks this variant at compact width, so the iPad
//  board can never shift while this one evolves.
//
//  LAYOUT: the strip pages HORIZONTALLY — one place per swipe, the next place peeking
//  at the trailing edge, so swiping literally walks the map in adjacency order (the
//  same left-right mental model the table uses). WITHIN a page, hanging locked places
//  keep the iPad's spatial metaphor VERTICALLY: above-hangers stack on top of the
//  parent card, below-hangers underneath, and the page scrolls if they overflow.
//  This is simpler than the iPad's overlay/reserved-padding machinery on purpose —
//  in a paged layout the hangers are just a VStack.
//
//  MOVEMENT: tap a chip to select it, then tap a place CAPSULE (the strip under the
//  header) or any visible place card to move it there. Tapping the selected chip
//  again opens details — same grammar as the iPad board. With nothing selected, a
//  capsule just jumps the pager to that place. New fighters land on the page you're
//  LOOKING AT (not strip.first) — on a phone, "where I am" is the only sane default.
//
//  Reuses CombatantDetail and AddPlaceSheet from EncounterView.swift (made internal —
//  see PATCHES). PhoneBoard mirrors BoardStyle's dark-theme constants: the same call
//  as StoryStyle mirroring BoardStyle — fold into a shared QuestTheme when a third
//  surface needs them.
//
//  NO LAZY CONTAINERS (the GM-surface culling gotcha). A strip is 2–6 places; the
//  plain HStack + scrollTargetLayout pages fine without laziness.

import SwiftUI

// MARK: - Phone board palette (mirrors BoardStyle's dark theme)

private enum PhoneBoard {
    static let background = Color(hex: "0F0F10")
    static let box        = Color(hex: "2A2A2E")
    static let field      = Color(hex: "323236")
    static let ink        = Color(hex: "F4F4F0")
    static let border     = Color(hex: "55555C")
    static let select     = Color(hex: "7EB3E0")
    static let lockFill   = Color(hex: "3A3226")

    // The kept visual language — identical to the iPad board.
    static let heroFill      = Color(hex: "CDE3BE")
    static let heroBorder    = Color(hex: "17A34A")
    static let monsterFill   = Color(hex: "F8D3CB")
    static let monsterBorder = Color(hex: "C94F3F")
    static let lockAmber     = Color(hex: "E8A020")
    static let headerBlue    = Color(hex: "A8CBE4")

    static let buttonHeight: CGFloat = 40
    /// Fraction of the container each page occupies — the remainder is the peek of
    /// the next place, the visual hint that the map continues.
    static let pageFraction: CGFloat = 0.92
}

// MARK: - Board

struct EncounterPhoneView: View {
    let repo: ContentRepository
    let store: EncounterStore
    let party: GMPartyStore
    var onDismiss: () -> Void

    @State private var selectedID: UUID? = nil
    @State private var detail: DetailRef? = nil
    /// The place the pager is parked on. Doubles as the add-target for new fighters.
    @State private var pageID: UUID? = nil
    @State private var addingPlace = false
    @State private var scanningHero = false
    @State private var addingPlayer = false
    @State private var improvising: MonsterThreat? = nil
    @State private var improvName = ""
    @State private var endingFight = false

    private struct DetailRef: Identifiable { let id: UUID }

    // Split into named pieces — the Swift 6 type-checker discipline from the iPad board.
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
                placeStrip(e)
                selectionHint(e)
                pager(e)
            } else {
                // The fight ended from under the cover — just close.
                Color.clear.onAppear { onDismiss() }
            }
        }
        .padding(12)
        .background(PhoneBoard.background.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    // MARK: Sheets (shared with the iPad board)

    /// Resolve live from the store each render — same reason as the iPad board.
    @ViewBuilder
    private func detailSheet(_ ref: DetailRef) -> some View {
        if let c = store.encounter?.combatants.first(where: { $0.id == ref.id }) {
            CombatantDetail(combatant: c, repo: repo, store: store) { detail = nil }
                .presentationDetents([.medium, .large])
                .environment(\.colorScheme, .dark)
        }
    }

    @ViewBuilder
    private var placeSheet: some View {
        if let e = store.encounter {
            AddPlaceSheet(strip: e.strip) { name, lock, parentID, side in
                store.addPlace(name: name, lock: lock, parentID: parentID, side: side)
            }
            .presentationDetents([.large])
            .environment(\.colorScheme, .dark)
        }
    }

    private var newPlayerSheet: some View {
        AddPartyMemberSheet(repo: repo) { member in
            party.add(member)
            store.addHero(member, to: defaultPlaceID)
        }
        .presentationDetents([.medium, .large])
    }

    /// Same two-step and the same no-duplicate guard as the iPad board's scan.
    private var scanHeroSheet: some View {
        ScanHeroCardSheet(repo: repo,
                          existingIDs: Set(party.members.map(\.id))) { card in
            let member = GMPartyMember(card: card)
            party.update(member)
            if !isOnBoard(member.id) { store.addHero(member, to: defaultPlaceID) }
        }
    }

    private func isOnBoard(_ memberID: UUID) -> Bool {
        store.encounter?.combatants.contains { c in
            if case .hero(let m) = c.kind { return m == memberID }
            return false
        } ?? false
    }

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

    /// New fighters land on the page the GM is looking at. A stale pageID (place
    /// removed since) falls back to the first strip place, so a chip can never land
    /// in a place that no longer exists.
    private var defaultPlaceID: UUID {
        if let e = store.encounter, let id = pageID,
           e.strip.contains(where: { $0.id == id }) {
            return id
        }
        return store.encounter?.strip.first?.id ?? UUID()
    }

    // MARK: Header — row 1 identity, row 2 the console. The rare actions
    // (Add Fighter / Add Place / End Fight) fold behind one menu: a parent's
    // mid-fight loop is next-turn / damage / move, and those keep the surface.

    private func header(_ e: Encounter) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(e.title.uppercased())
                    .font(questFont(16)).foregroundStyle(.black)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color(hex: "C9C4EC"), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
                Spacer(minLength: 8)
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(PhoneBoard.ink)
                        .frame(width: PhoneBoard.buttonHeight, height: PhoneBoard.buttonHeight)
                        .background(PhoneBoard.box, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(PhoneBoard.border, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                roundChip(e)

                Button { store.nextTurn() } label: {
                    Label("Next Turn", systemImage: "arrow.right.circle.fill")
                        .font(questFont(13)).foregroundStyle(PhoneBoard.ink)
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 12)
                        .frame(height: PhoneBoard.buttonHeight)
                        .background(PhoneBoard.box, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(PhoneBoard.border, lineWidth: 2))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                boardMenu(e)
            }
        }
    }

    private func roundChip(_ e: Encounter) -> some View {
        HStack(spacing: 6) {
            Button { store.setRound(e.round - 1) } label: {
                Image(systemName: "minus.circle").foregroundStyle(PhoneBoard.ink.opacity(0.5))
            }
            Text("Rd \(e.round)").font(questFont(15)).foregroundStyle(PhoneBoard.ink)
                .lineLimit(1).fixedSize()
                .contentTransition(.numericText())
            Button { store.setRound(e.round + 1) } label: {
                Image(systemName: "plus.circle").foregroundStyle(PhoneBoard.ink.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .frame(height: PhoneBoard.buttonHeight)
        .background(PhoneBoard.box, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(PhoneBoard.border, lineWidth: 2))
    }

    /// The folded console: Add Fighter (with the full bestiary/improviser/late-arrival
    /// submenus), Add Place, End Fight. One extra tap for the rare actions buys the
    /// frequent ones a phone-sized surface.
    private func boardMenu(_ e: Encounter) -> some View {
        let onBoard = Set(e.combatants.compactMap { c -> UUID? in
            if case .hero(let m) = c.kind { return m }; return nil
        })
        let benched = party.members.filter { !onBoard.contains($0.id) }

        return Menu {
            Menu {
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
                Label("Add a fighter", systemImage: "plus.circle.fill")
            }

            Button { addingPlace = true } label: {
                Label("Add a place", systemImage: "plus.square.on.square")
            }

            Divider()

            Button(role: .destructive) { endingFight = true } label: {
                Label("End the fight", systemImage: "flag.checkered")
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(PhoneBoard.ink)
                .frame(width: PhoneBoard.buttonHeight + 6, height: PhoneBoard.buttonHeight)
                .background(PhoneBoard.box, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(PhoneBoard.border, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    // MARK: Place capsules — jump with nothing selected, DROP TARGET with a chip
    // selected. Movement never requires swiping pages while holding a selection.

    private func placeStrip(_ e: Encounter) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(e.strip) { place in
                    placeCapsule(place, in: e)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func placeCapsule(_ place: Place, in e: Encounter) -> some View {
        let current = pageID == place.id
        let moving = selectedID != nil
        return Button {
            if let sel = selectedID {
                store.move(sel, to: place.id)
                selectedID = nil
            }
            withAnimation(.snappy) { pageID = place.id }
        } label: {
            HStack(spacing: 6) {
                if place.lock != nil {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9)).foregroundStyle(PhoneBoard.lockAmber)
                }
                Text(place.name)
                    .font(questFont(12))
                    .foregroundStyle(current ? .black : PhoneBoard.ink.opacity(0.8))
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                let n = e.combatants(in: place.id).count
                if n > 0 {
                    Text("\(n)")
                        .font(questFont(11))
                        .foregroundStyle(current ? .black.opacity(0.6) : PhoneBoard.ink.opacity(0.5))
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(current ? TierColor.selectPeach : PhoneBoard.box, in: Capsule())
            .overlay {
                if moving {
                    // The blue dashed ring is the selection language — here it says
                    // "this capsule is a drop target for the selected fighter."
                    Capsule().strokeBorder(PhoneBoard.select,
                                           style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                } else {
                    Capsule().strokeBorder(current ? .black : PhoneBoard.border,
                                           lineWidth: current ? 2 : 1.5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Selection hint

    @ViewBuilder
    private func selectionHint(_ e: Encounter) -> some View {
        if let sel = selectedID, let c = e.combatants.first(where: { $0.id == sel }) {
            HStack(spacing: 8) {
                Image(systemName: "hand.tap.fill").foregroundStyle(PhoneBoard.select)
                Text("Moving \(c.name) — tap a place up top, or tap them again for details.")
                    .font(questFontLight(12)).foregroundStyle(PhoneBoard.ink.opacity(0.75))
                    .lineLimit(2).minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                Button { selectedID = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(PhoneBoard.ink.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(PhoneBoard.select.opacity(0.15), in: Capsule())
        } else {
            Text("Tap a fighter, then tap where they go. Swipe to walk the map.")
                .font(questFontLight(12)).foregroundStyle(PhoneBoard.ink.opacity(0.4))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    // MARK: The pager — horizontal = the strip, vertical = the place itself

    private func pager(_ e: Encounter) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(e.strip) { place in
                    placePage(place, in: e)
                        .containerRelativeFrame(.horizontal) { length, _ in
                            length * PhoneBoard.pageFraction
                        }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $pageID)
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { if pageID == nil { pageID = e.strip.first?.id } }
    }

    /// One place, floor to ceiling: above-hangers, the place card, below-hangers.
    private func placePage(_ place: Place, in e: Encounter) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(hangers(.above, off: place, in: e)) { hangingCard($0, in: e) }
                mainCard(place, in: e)
                ForEach(hangers(.below, off: place, in: e)) { hangingCard($0, in: e) }
            }
            .padding(.vertical, 4)
        }
    }

    private func hangers(_ side: LockedSide, off place: Place, in e: Encounter) -> [Place] {
        e.lockedPlaces(off: place.id).filter { $0.resolvedSide == side }
    }

    private func mainCard(_ place: Place, in e: Encounter) -> some View {
        VStack(spacing: 8) {
            Text(place.name.uppercased())
                .font(questFont(15)).foregroundStyle(.black)
                .lineLimit(2).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(PhoneBoard.headerBlue, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(PhoneBoard.border, lineWidth: 2))

            if let lock = place.lock { lockCapsule(lock) }

            VStack(spacing: 8) {
                ForEach(e.combatants(in: place.id)) { chip($0, in: e) }
                if e.combatants(in: place.id).isEmpty {
                    Text("nobody here")
                        .font(questFontLight(12)).foregroundStyle(PhoneBoard.ink.opacity(0.3))
                        .padding(.vertical, 14)
                }
            }
            .padding(.vertical, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(PhoneBoard.box, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(PhoneBoard.border, lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { placeTapped(place.id) }
        .contextMenu {
            if e.combatants(in: place.id).isEmpty && e.lockedPlaces(off: place.id).isEmpty {
                Button("Remove \(place.name)", role: .destructive) { store.removePlace(place.id) }
            }
        }
    }

    /// A hanging locked place: slightly inset so it reads as "attached to" the main
    /// card, same amber dashed border as the iPad board.
    private func hangingCard(_ place: Place, in e: Encounter) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: place.lock == nil ? "arrow.turn.right.down" : "lock.fill")
                    .font(.caption).foregroundStyle(PhoneBoard.lockAmber)
                Text(place.name).font(questFont(13)).foregroundStyle(PhoneBoard.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            if let lock = place.lock { lockCapsule(lock) }
            VStack(spacing: 6) {
                ForEach(e.combatants(in: place.id)) { chip($0, in: e) }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(PhoneBoard.lockFill, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(PhoneBoard.lockAmber, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { placeTapped(place.id) }
        .contextMenu {
            if e.combatants(in: place.id).isEmpty {
                Button("Remove \(place.name)", role: .destructive) { store.removePlace(place.id) }
            }
        }
        .padding(.horizontal, 16)
    }

    private func lockCapsule(_ lock: String) -> some View {
        Label(lock, systemImage: "lock.fill")
            .font(questFontLight(11)).foregroundStyle(PhoneBoard.ink)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(PhoneBoard.lockAmber.opacity(0.28), in: Capsule())
            .overlay(Capsule().strokeBorder(PhoneBoard.lockAmber, lineWidth: 1.5))
            .lineLimit(1).minimumScaleFactor(0.6)
    }

    // MARK: Chips — identical grammar to the iPad board

    private func chip(_ c: Combatant, in e: Encounter) -> some View {
        let fill = c.isMonster ? PhoneBoard.monsterFill : PhoneBoard.heroFill
        let border = c.isMonster ? PhoneBoard.monsterBorder : PhoneBoard.heroBorder
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
            .overlay {
                if active {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(TierColor.signature, lineWidth: 3)
                        .padding(-4)
                }
            }
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(PhoneBoard.select,
                                      style: StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
                        .padding(-6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func conditionBadge(_ k: ConditionKind) -> some View {
        Text(k.rawValue.capitalized)
            .font(questFontLight(9)).foregroundStyle(.black)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(PhoneBoard.lockAmber.opacity(0.3), in: Capsule())
            .overlay(Capsule().strokeBorder(PhoneBoard.lockAmber.opacity(0.7), lineWidth: 1))
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
