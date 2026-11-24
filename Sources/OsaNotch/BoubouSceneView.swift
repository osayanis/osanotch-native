import SwiftUI

/// Scène jouée dans l'en-tête de l'onglet Boubou juste après un geste (courses, bain, cuisiner,
/// nourrir, planter, arroser, recolter : voir `BoubouScene.durees`). Placeholder : le vrai dessin
/// viendra de l'app Boubou. Contrat : 84 × 66 pt, `debut` = moment du clic (pour un TimelineView).
struct BoubouSceneView: View {
    var nom: String
    var debut: Date
    var etat: BoubouEtat

    private static let accessoires: [String: String] = ["courses": "🛒", "bain": "🛁", "cuisiner": "🍲", "nourrir": "🍽️",
                                                       "planter": "🌱", "arroser": "💧", "recolter": "🧺"]
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSince(debut)
            ZStack(alignment: .bottomTrailing) {
                BoubouPortrait(humeur: "heureux", dort: false, malade: etat.malade == true, accessoire: etat.accessoire,
                               sale: false, size: 54)
                    .offset(y: -abs(sin(t * 5)) * 6)
                Text(Self.accessoires[nom] ?? "✨").font(.system(size: 18))
                    .offset(x: 4, y: 2)
            }
        }
    }
}
