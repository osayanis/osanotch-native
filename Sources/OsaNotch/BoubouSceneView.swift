import SwiftUI

/// La scène 3D jouée par-dessus l'onglet Boubou juste après un geste de Yanis (courses au marché, bain,
/// cuisine, repas, potager). Le dessin est dans BoubouScenes.swift (copie de l'app Boubou).
struct BoubouSceneView: View {
    var scene: BoubouScene
    var etat: BoubouEtat
    var largeur: CGFloat = 250

    var body: some View {
        if let kind = BoubouScene.genres[scene.nom] {
            SceneAnimee(spec: SceneSpec(kind: kind, debut: scene.debut, emojis: scene.emojis, resultat: scene.resultat,
                                        accessoire: etat.accessoire), width: largeur)
        }
    }
}
