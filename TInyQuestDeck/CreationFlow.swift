//  CreationFlow.swift
//  The new character-creation flow shell. Presented as a fullScreenCover (NO tab bar —
//  the tab bar appears only once a character sheet exists). Class-first order per the
//  rulebook: name -> pick a class/path -> path detail -> pick a kind -> kind detail
//  -> create -> dismiss into the roster/sheet.
//
//  A draft accumulates choices as screens commit; nothing becomes a real
//  CharacterChoices until the final Select. Back navigation is free browsing.
//
//  Art: every slot renders QuestArt at the locked ratio — real catalog asset if named,
//  else the dashed placeholder. Portal key is the one-off "portal".
//
//  Integration (RosterView): replace the .sheet(isPresented: $building) block with
//
//      .fullScreenCover(isPresented: $building) {
//          if let repo = content.repo {
//              CreationFlowView(repo: repo) { newHero in
//                  roster.add(newHero)
//                  building = false
//              }
//          }
//      }

import SwiftUI

// MARK: - Draft (in-memory until the final Select)

@MainActor
@Observable
final class HeroDraft {
    var name = ""
    var classID: String? = nil
    var pathID: String? = nil
    var raceID: String? = nil
}

// MARK: - Routes

enum CreationRoute: Hashable {
    case pickPath
    case pathDetail(String)   // pathID
    case pickKind
    case kindDetail(String)   // raceID
}

// MARK: - Shell

struct CreationFlowView: View {
    let repo: ContentRepository
    var onCreate: (CharacterChoices) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = HeroDraft()
    @State private var route: [CreationRoute] = []

    var body: some View {
        NavigationStack(path: $route) {
            NewHeroView(
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
            PickPathView(repo: repo, draft: draft) { pathID in
                route.append(.pathDetail(pathID))
            }
        case .pathDetail(let pathID):
            PathDetailView(repo: repo, pathID: pathID) {
                draft.pathID = pathID
                draft.classID = repo.path(pathID)?.classID
                route.append(.pickKind)
            }
        case .pickKind:
            PickKindView(repo: repo, draft: draft) { raceID in
                route.append(.kindDetail(raceID))
            }
        case .kindDetail(let raceID):
            KindDetailView(repo: repo, raceID: raceID) {
                draft.raceID = raceID
                if let hero = makeHero() {
                    onCreate(hero)
                }
                dismiss()
            }
        }
    }

    /// The one place a draft becomes a real character. Seeds the spell loadout;
    /// gear starts BLANK per the design ruling (the sheet's Add picker offers the kit).
    private func makeHero() -> CharacterChoices? {
        guard let classID = draft.classID,
              let pathID = draft.pathID,
              let raceID = draft.raceID,
              !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }

        var c = CharacterChoices(name: draft.name, raceID: raceID, classID: classID, pathID: pathID)
        let ids = startingGrants(classID: classID, pathID: pathID, repo: repo).map(\.spellID)
        c.spellbookIDs = ids
        c.readySpellIDs = ids       // L1: every starting spell is Ready (<= cap)
        return c
    }
}

// MARK: - Screen 1: New Hero (the portal)

struct NewHeroView: View {
    @Bindable var draft: HeroDraft
    var onCancel: () -> Void
    var onBegin: () -> Void

    private var nameReady: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Text("TINY QUEST DECK")
                    .font(questFont(26))
                    .foregroundStyle(Color(hex: "8A7BB8"))
                    .padding(.top, 8)

                // Name card
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Button("CANCEL", action: onCancel)
                            .font(questFont(16)).foregroundStyle(.black)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
                        Spacer()
                        Text("NEW HERO").font(questFont(22)).foregroundStyle(.black)
                        Spacer()
                        Button("CREATE", action: onBegin)
                            .font(questFont(16)).foregroundStyle(.black)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(nameReady ? TierColor.selectPeach : TierColor.panelCream,
                                        in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
                            .disabled(!nameReady)
                            .opacity(nameReady ? 1 : 0.5)
                    }

                    Text("NAME").font(questFont(18)).foregroundStyle(.black)
                    TextField("", text: $draft.name)
                        .font(questFontLight(22))
                        .textInputAutocapitalization(.words)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
                        .submitLabel(.go)
                        .onSubmit { if nameReady { onBegin() } }
                }
                .padding(18)
                .background(Color(hex: "A8CBE4"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.black, lineWidth: 2))

                // The portal — 3:4 one-off illustration (1536×2048). Later: layered
                // transparent PNGs in a ZStack so the dragon/egg/swirl can animate.
                QuestArt(
                    name: QuestArtKey.portal,
                    ratio: QuestRatio.portal,
                    colors: [Color(hex: "58C7E8"), Color(hex: "2E7FD0"), Color(hex: "7B5FC0")],
                    symbol: "sparkles.rectangle.stack",
                    caption: "portal art · 1536×2048",
                    framed: false)
                    .frame(maxWidth: 560)
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Color.white)
        .toolbar(.hidden, for: .navigationBar)
    }
}
