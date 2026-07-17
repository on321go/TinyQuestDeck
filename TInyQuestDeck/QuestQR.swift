//  QuestQR.swift
//  The QR bridge between the GM's iPad and the kids' iPads. Offline, no backend,
//  honor-system-grade — the threat model is a kid double-tapping, not forgery.
//
//  ONE FILE ON PURPOSE. The envelope, the payloads, the generator, the scanner, and
//  both sheets travel together: splitting them is how you get "Cannot find type
//  'HeroCard'" plus a misleading type-check cascade (see the Encounter.swift /
//  EncounterView.swift lesson).
//
//  MILESTONE A (here) — hero cards. The kid's sheet shows a QR; the GM scans it once
//  and the party record carries the hero's REAL CharacterChoices.id. That id is the
//  attribution key awards and Milestone B's grant tokens address. Stakes-free by
//  design: a failed scan costs nothing, which is why the camera, the permission
//  prompt, and the payload plumbing get debugged here.
//
//  MILESTONE B (later) — grant tokens. Add a GrantToken payload, a `.grant` case to
//  QRScan, and a branch in QuestQR.decode. The generator and the scanner need no
//  changes; that's the whole point of the envelope.
//
//  Requires NSCameraUsageDescription in Info.plist (see PATCHES5.md).

import SwiftUI
import CoreImage.CIFilterBuiltins
import VisionKit
import Vision
import AVFoundation

// MARK: - The envelope
//
// Every payload is JSON carrying `v` (version) and `t` (type). Decoding reads the
// envelope FIRST and switches on it — same tagged-enum-with-forward-compat shape as
// RuleBlock / EffectHint. An unknown v or t is a friendly message, never a crash.

enum QuestQR {
    /// Bump ONLY on a breaking payload change. A code stamped with a HIGHER v than
    /// this build understands gets "update the app", never a throw.
    static let version = 1

    enum Kind {
        static let hero  = "hero"
        static let grant = "grant"      // Milestone B — reserved
    }

    private struct Envelope: Codable { let v: Int; let t: String }
    private static let ciContext = CIContext()

    /// Encode a payload to a QR image at its NATIVE module size (one pixel per QR
    /// module — typically ~25-40px square). Views scale it up with
    /// `.interpolation(.none)`; letting CoreImage or the view smooth the upscale is
    /// exactly what makes a code hard to scan. See QRCodeImage below.
    static func image(encoding payload: some Encodable) -> UIImage? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"        // ~15% recovery — plenty on a bright screen
        guard let output = filter.outputImage,
              let cg = ciContext.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Decode a scanned string. Never throws — every failure is a kid-readable line.
    static func decode(_ raw: String) -> QRScan {
        guard let data = raw.data(using: .utf8),
              let env = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return .unsupported("That's not a Tiny Quest code. Try the code on their Character Sheet!")
        }
        guard env.v <= version else {
            return .unsupported("This code came from a newer Tiny Quest. Update this iPad to read it!")
        }
        switch env.t {
        case Kind.hero:
            guard let card = try? JSONDecoder().decode(HeroCard.self, from: data) else {
                return .unsupported("That hero card looks scrambled — try holding steadier.")
            }
            return .hero(card)
        case Kind.grant:
            guard let token = try? JSONDecoder().decode(GrantToken.self, from: data),
                  !token.nonce.isEmpty else {
                return .unsupported("That reward code looks scrambled — try holding steadier.")
            }
            return .grant(token)
        default:
            return .unsupported("This iPad doesn't know that kind of code yet.")
        }
    }
}

enum QRScan {
    case hero(HeroCard)
    case grant(GrantToken)
    case unsupported(String)        // the message to show, already kid-readable
}

// MARK: - Payload: the hero card (Milestone A)
//
// IDs, not display names: GMPartyMember stores classID/raceID/pathID and resolves
// names through the repo (falling back to the raw id), so a content mismatch degrades
// to an ugly card, never a crash — and the payload stays small, which is what QR
// robustness actually cares about.
//
// NOTE on `portrait`: it's the portrait COMBO ("catfolk-scout"), NOT the asset name.
// GMPartyMember.portraitCombo feeds QuestArtKey.portrait(combo:), which adds the
// "portrait-" prefix itself — sending the full asset name yields
// "portrait-portrait-catfolk-scout" and a placeholder on every scanned card.

struct HeroCard: Codable, Hashable {
    var v: Int = QuestQR.version
    var t: String = QuestQR.Kind.hero
    var id: UUID
    var name: String
    var race: String
    var klass: String           // "class" on the wire — `class` is a Swift keyword
    var path: String
    var level: Int
    var portrait: String?       // portraitCombo, e.g. "catfolk-scout"

    enum CodingKeys: String, CodingKey {
        case v, t, id, name, race, path, level, portrait
        case klass = "class"
    }

    init(id: UUID, name: String, race: String, klass: String,
         path: String, level: Int, portrait: String?) {
        self.id = id; self.name = name; self.race = race; self.klass = klass
        self.path = path; self.level = level; self.portrait = portrait
    }

    /// decodeIfPresent throughout — same migration-safe pattern as CharacterChoices.
    /// A field added in v2 reads as its default here instead of throwing, so a v1
    /// build can still scan a v2 card that only ADDED fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v        = try c.decodeIfPresent(Int.self,    forKey: .v) ?? QuestQR.version
        t        = try c.decodeIfPresent(String.self, forKey: .t) ?? QuestQR.Kind.hero
        id       = try c.decodeIfPresent(UUID.self,   forKey: .id) ?? UUID()
        name     = try c.decodeIfPresent(String.self, forKey: .name) ?? "Somebody"
        race     = try c.decodeIfPresent(String.self, forKey: .race) ?? ""
        klass    = try c.decodeIfPresent(String.self, forKey: .klass) ?? ""
        path     = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        level    = try c.decodeIfPresent(Int.self,    forKey: .level) ?? 1
        portrait = try c.decodeIfPresent(String.self, forKey: .portrait)
    }
}

extension HeroCard {
    /// The kid's side: a hero becomes a card.
    init(hero: CharacterChoices) {
        self.init(id: hero.id,
                  name: hero.name,
                  race: hero.raceID,
                  klass: hero.classID,
                  path: hero.pathID,
                  level: hero.level,
                  portrait: hero.portraitID
                      ?? QuestArtKey.portraitCombo(race: hero.raceID, klass: hero.classID))
    }
}

// MARK: - Payload: the grant token (Milestone B)
//
// THE TOKEN IS THE AWARD; THE QR IS ONLY TRANSPORT. A hero on this iPad gets the same
// struct redeemed in-process (no code, no camera — an iPad physically cannot scan its
// own screen); a hero on another iPad gets it rendered and scanned. One redeem path,
// two transports.
//
// `kind` is GrantKind verbatim — the ledger's vocabulary, unforked. Its `.purchasable`
// id is already namespaced ("gear:x" / "item:y"), so the kid's device resolves it from
// its OWN content.json via Purchasable.resolve. Small payload; robust code.
//
// No signing. The threat model is a kid double-tapping, not forgery.

struct GrantToken: Codable, Hashable {
    var v: Int = QuestQR.version
    var t: String = QuestQR.Kind.grant
    /// One-shot id. Dedup keys on (nonce, hero) — NEVER nonce alone. See SeenTokens.
    var nonce: String
    /// nil = a PARTY token: ANY hero may redeem it, once each. This is the party-star
    /// mechanism — one code, each kid scans it in turn.
    var hero: UUID?
    /// Display only, and only on a single-hero token. Lets the wrong iPad say "this
    /// reward is for Mittens" instead of a shrug. Never trusted for anything.
    var heroName: String?
    var kind: GrantKind

    enum CodingKeys: String, CodingKey {
        case v, t, nonce, hero, kind
        case heroName = "n"     // short on the wire; every byte is a QR module
    }

    init(nonce: String, hero: UUID?, heroName: String?, kind: GrantKind) {
        self.nonce = nonce; self.hero = hero; self.heroName = heroName; self.kind = kind
    }

    /// decodeIfPresent throughout — the CharacterChoices pattern, so a v2 token that
    /// only ADDS fields still redeems on a v1 build. `kind` is the exception: a token
    /// with no kind isn't an award, so it throws and decode() reports "scrambled".
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v        = try c.decodeIfPresent(Int.self,    forKey: .v) ?? QuestQR.version
        t        = try c.decodeIfPresent(String.self, forKey: .t) ?? QuestQR.Kind.grant
        nonce    = try c.decodeIfPresent(String.self, forKey: .nonce) ?? ""
        hero     = try c.decodeIfPresent(UUID.self,   forKey: .hero)
        heroName = try c.decodeIfPresent(String.self, forKey: .heroName)
        kind     = try c.decode(GrantKind.self,       forKey: .kind)
    }
}

extension GrantToken {
    /// One hero's award.
    static func single(_ kind: GrantKind, hero: UUID, name: String?) -> GrantToken {
        GrantToken(nonce: UUID().uuidString, hero: hero, heroName: name, kind: kind)
    }

    /// The party's award — quest and boss stars, which are party-wide ALWAYS (the
    /// sibling-proofing rule). ONE token, no hero, redeemed once per kid.
    static func party(_ kind: GrantKind) -> GrantToken {
        GrantToken(nonce: UUID().uuidString, hero: nil, heroName: nil, kind: kind)
    }

    var isParty: Bool { hero == nil }

    /// A party token addresses everyone; a single token addresses exactly one hero.
    func addresses(_ heroID: UUID) -> Bool { hero == nil || hero == heroID }
}

extension GMPartyMember {
    /// The GM's side: a scanned card becomes the SAME record `init(hero:)` builds —
    /// carrying the hero's real id, which is the whole reason the card exists.
    init(card: HeroCard) {
        self.init(id: card.id,
                  name: card.name,
                  classID: card.klass,
                  raceID: card.race.isEmpty ? nil : card.race,
                  pathID: card.path.isEmpty ? nil : card.path,
                  level: card.level,
                  portraitCombo: card.portrait
                      ?? QuestArtKey.portraitCombo(race: card.race, klass: card.klass))
    }
}

// MARK: - QRCodeImage: the native-size code, scaled up HARD-EDGED
//
// `.interpolation(.none)` is load-bearing, not polish — a smoothed QR is a QR that
// won't scan across a table.

struct QRCodeImage: View {
    let payload: any Encodable
    var side: CGFloat = 260

    var body: some View {
        Group {
            if let ui = QuestQR.image(encoding: payload) {
                Image(uiImage: ui)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                // Encoding a small JSON blob effectively can't fail, but never crash
                // at the table over a QR.
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle).foregroundStyle(.orange)
                    Text("Couldn't draw the code").font(questFontLight(13))
                        .foregroundStyle(.black.opacity(0.6))
                }
            }
        }
        .frame(width: side, height: side)
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
    }
}

// MARK: - KID SIDE: "My Hero Card"
//
// Reached from the gold bar on the character sheet. Pure display — showing a card
// mutates nothing, so there's no confirm and no way to break a hero with it.

struct HeroCardSheet: View {
    let hero: CharacterChoices
    let repo: ContentRepository
    let bg: Color
    let accent: Color

    @Environment(\.dismiss) private var dismiss

    private var card: HeroCard { HeroCard(hero: hero) }

    private var subtitle: String {
        let cls = repo.klass(hero.classID)?.name ?? hero.classID
        let pathName = repo.path(hero.pathID)?.name ?? hero.pathID
        return "Level \(hero.level) · \(pathName) \(cls)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text(hero.name.uppercased())
                        .font(questFont(26)).foregroundStyle(.black)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(subtitle)
                        .font(questFontLight(15)).foregroundStyle(.black.opacity(0.65))

                    QRCodeImage(payload: card)

                    Text("Show this to your Game Master!")
                        .font(questFont(17)).foregroundStyle(.black)
                    Text("They scan it once so their map knows who you are. Nothing on your sheet changes — and if you level up, just show it again.")
                        .font(questFontLight(13)).foregroundStyle(.black.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background(bg.opacity(0.85).ignoresSafeArea())
            .navigationTitle("My Hero Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(questFont(16))
                }
            }
        }
    }
}

// MARK: - GM SIDE: "Scan a hero card…"
//
// Scan -> decode -> CONFIRM -> import. The confirm step is deliberate: it names who
// landed, distinguishes a fresh Add from a Refresh, and gives a wrong-code scan
// somewhere harmless to go. Body split into named pieces — giant view expressions
// time out the Swift 6 type checker (the EncounterView lesson).

struct ScanHeroCardSheet: View {
    let repo: ContentRepository
    /// Party member ids already present — decides Add vs Refresh copy.
    let existingIDs: Set<UUID>
    var onImport: (HeroCard) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .scanning
    @State private var cameraReady = AVCaptureDevice.authorizationStatus(for: .video) == .authorized

    private enum Phase: Equatable {
        case scanning
        case found(HeroCard)
        case problem(String)
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(TierColor.panelCream.ignoresSafeArea())
                .navigationTitle("Scan a Hero Card")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.font(questFont(16))
                    }
                }
        }
        .task {
            // Ask BEFORE consulting isAvailable — an un-prompted camera reads as
            // "unavailable", which would show the no-camera message on first run.
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                cameraReady = await AVCaptureDevice.requestAccess(for: .video)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .scanning:            scanner
        case .found(let card):     confirmation(card)
        case .problem(let message): problem(message)
        }
    }

    // MARK: Scanning

    @ViewBuilder private var scanner: some View {
        if !cameraReady {
            message(symbol: "camera.fill",
                    title: "The camera is off",
                    body: "Tiny Quest needs the camera to read hero cards. Turn it on in Settings → Tiny Quest, or add the player by hand instead.")
        } else if !DataScannerViewController.isSupported || !DataScannerViewController.isAvailable {
            message(symbol: "qrcode.viewfinder",
                    title: "Can't scan on this iPad",
                    body: "Add the player by hand instead — you can link their real hero later by removing them and scanning.")
        } else {
            VStack(spacing: 0) {
                DataScannerView { raw in
                    guard phase == .scanning else { return }   // first code wins
                    switch QuestQR.decode(raw) {
                    case .hero(let card):        phase = .found(card)
                    case .grant:                 phase = .problem("That's a reward code — scan it on the player's iPad, not the GM's.")
                    case .unsupported(let note): phase = .problem(note)
                    }
                }
                Text("Point at the QR on the player's Character Sheet.")
                    .font(questFontLight(14)).foregroundStyle(.black.opacity(0.6))
                    .padding(14)
            }
        }
    }
    
    // MARK: Confirmation

    private func confirmation(_ card: HeroCard) -> some View {
        let refreshing = existingIDs.contains(card.id)
        let cls = repo.klass(card.klass)?.name ?? card.klass
        let pathName = repo.path(card.path)?.name ?? card.path
        let combo = card.portrait
            ?? QuestArtKey.portraitCombo(race: card.race, klass: card.klass)

        return VStack(spacing: 18) {
            Spacer(minLength: 0)
            QuestArt(name: QuestArtKey.portrait(combo: combo), ratio: QuestRatio.card,
                     colors: [GMAccent.accent, GMAccent.page], symbol: "person.fill",
                     caption: nil, framed: true)
                .frame(width: 130)
            VStack(spacing: 4) {
                Text(card.name.uppercased()).font(questFont(24)).foregroundStyle(.black)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("Level \(card.level) · \(pathName) \(cls)")
                    .font(questFontLight(15)).foregroundStyle(.black.opacity(0.65))
            }
            Text(refreshing
                 ? "Already in the party — this updates their card to match."
                 : "New face! They'll show up on the party list and the battle board.")
                .font(questFontLight(14)).foregroundStyle(.black.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)

            HStack(spacing: 12) {
                Button { phase = .scanning } label: {
                    Text("Scan another").font(questFont(15)).foregroundStyle(.black)
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
                }
                .buttonStyle(.plain)

                Button {
                    onImport(card)
                    dismiss()
                } label: {
                    Label(refreshing ? "Refresh \(card.name)" : "Add to the party",
                          systemImage: refreshing ? "arrow.clockwise" : "person.badge.plus")
                        .font(questFont(16)).foregroundStyle(.black)
                        .padding(.horizontal, 20).padding(.vertical, 11)
                        .background(TierColor.selectPeach, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    // MARK: Problem

    private func problem(_ note: String) -> some View {
        VStack(spacing: 16) {
            message(symbol: "questionmark.circle.fill", title: "Hmm…", body: note)
            Button { phase = .scanning } label: {
                Text("Try again").font(questFont(16)).foregroundStyle(.black)
                    .padding(.horizontal, 24).padding(.vertical, 11)
                    .background(TierColor.selectPeach, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }

    private func message(symbol: String, title: String, body: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 46))
                .foregroundStyle(GMAccent.accent.opacity(0.7))
            Text(title).font(questFont(22)).foregroundStyle(.black)
            Text(body).font(questFontLight(14)).foregroundStyle(.black.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
        }
    }

    /// GMStyle is private to GMView.swift; these two are the only colors this file
    /// borrows. Fold into a shared QuestTheme if the dark-theme decision (§7) makes
    /// one.
    private enum GMAccent {
        static let accent = Color(hex: "8A4FD0")
        static let page   = Color(hex: "C9C4EC")
    }
}

// MARK: - VisionKit wrapper
//
// QR symbology only, one item at a time. The delegate fires on EVERY frame that sees
// a code, so the caller guards on its own phase — this just forwards strings.

private struct DataScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        try? vc.startScanning()      // throws if already scanning — harmless
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController,
                                          coordinator: Coordinator) {
        MainActor.assumeIsolated { vc.stopScanning() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let payload = barcode.payloadStringValue {
                    onScan(payload)
                    return
                }
            }
        }
    }
}
