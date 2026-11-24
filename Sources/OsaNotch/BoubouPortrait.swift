import SwiftUI

/// Boubou tel que le décrit le serveur (`humeur`, `dort`, `malade`, `accessoire`).
/// Tout le choix de l'expression est ici : BoubouArt.swift reste une copie conforme du dessin
/// de l'app Boubou (accessoires, rhume et taches compris).
struct BoubouPortrait: View {
    var humeur: String
    var dort: Bool
    var malade: Bool
    var accessoire: String?
    var sale = false
    var size: CGFloat
    /// Change → petit bond (geste réussi).
    var hop = 0

    var body: some View {
        if dort {
            BedView(size: size * 1.35)
        } else {
            Boule(mood: mood, arms: arms, size: size, hop: hop, shadow: false, tilt: malade ? -6 : 0,
                  accessoire: accessoire, malade: malade, sale: sale)
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
}
