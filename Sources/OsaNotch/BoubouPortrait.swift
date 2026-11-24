import SwiftUI

/// Boubou tel que le décrit le serveur (`humeur`, `dort`, `malade`, `accessoire`).
/// Tout le choix de l'expression est ici : BoubouArt.swift reste une copie conforme du dessin
/// de l'app Boubou (à recopier quand il change, par ex. pour les accessoires dessinés).
struct BoubouPortrait: View {
    var humeur: String
    var dort: Bool
    var malade: Bool
    var accessoire: String?
    var size: CGFloat
    /// Change → petit bond (geste réussi).
    var hop = 0

    var body: some View {
        if dort {
            BedView(size: size * 1.35)
        } else {
            Boule(mood: mood, arms: arms, size: size, hop: hop, shadow: false, tilt: malade ? -6 : 0)
                .overlay(alignment: .topTrailing) {
                    // En attendant les accessoires dessinés : un petit insigne
                    if malade {
                        Text("🤧").font(.system(size: size * 0.26)).offset(x: size * 0.08, y: -size * 0.04)
                    } else if let a = accessoire, let e = Self.insigne[a] {
                        Text(e).font(.system(size: size * 0.24)).offset(x: size * 0.08, y: -size * 0.04)
                    }
                }
        }
    }

    private var mood: Boule.Mood {
        if malade { return .worried }
        switch humeur {
        case "heureux": return .love
        case "faim", "sale": return .worried
        case "fatigue": return .sleepy
        case "triste": return .sad
        case "bof": return .curious
        default: return .calm
        }
    }
    private var arms: Boule.Arms {
        switch humeur {
        case "heureux": return .wave
        case "faim": return .hug
        default: return .rest
        }
    }
    static let insigne = ["toque": "👨‍🍳", "echarpe": "🧣", "bonnet": "🧶", "lunettes": "👓", "noeud": "🎀", "couronne": "🌸"]
}
