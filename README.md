<div align="center">
  <img src="https://raw.githubusercontent.com/osayanis/osanotch-native/main/Resources/icon.png" width="128" alt="OsaNotch Logo" />
  
  # OsaNotch
  **Une réinvention élégante et puissante de l'encoche macOS, écrite en 100% SwiftUI.**
  
  [![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-blue?logo=apple)](https://www.apple.com/macos/)
  [![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)](https://swift.org)
  [![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
</div>

---

OsaNotch transforme l'encoche statique de votre MacBook en un centre de contrôle interactif, intelligent et parfaitement intégré au système. Inspiré par la Dynamic Island d'iOS, OsaNotch exploite l'encoche physique (ou la simule sur les anciens Mac) pour afficher des informations utiles au quotidien de manière fluide et non-intrusive.

## ✨ Fonctionnalités Principales

- 🎵 **Lecteur Musical Natif**
  - Synchronisation parfaite avec **Apple Music** et **Spotify**.
  - Extraction de la pochette en haute définition directement depuis la mémoire du lecteur (fini les fausses pochettes internet).
  - Contrôles de lecture intégrés.
  - Couleurs d'accentuation générées dynamiquement basées sur l'artwork.

- 🎛 **Remplacement du HUD macOS (Volume & Luminosité)**
  - Intercepte silencieusement les touches multimédias natives (F1/F2, Volume).
  - Supprime les gros carrés translucides natifs de macOS au profit d'animations subtiles émanant de l'encoche.

- 📅 **Dashboard & Calendrier**
  - Mini-dashboard accessible au survol contenant la batterie, la date, et l'agenda.
  - Calendrier interactif : glissez avec deux doigts sur votre trackpad pour naviguer d'une semaine à l'autre en toute fluidité.

- 📋 **Gestionnaire de Presse-papiers (Clipboard)**
  - Historique automatique de vos 20 derniers textes copiés.
  - Un clic suffit pour récupérer un ancien texte copié.

- 🎥 **OsaCast (Partage d'écran WebRTC)**
  - Diffusez votre écran avec une latence ultra-faible directement depuis votre encoche.
  - Serveur de signalisation intégré avec retour d'état en temps réel.
  
- 📂 **OsaDrop (Partage de fichiers)**
  - Glissez-déposez n'importe quel fichier sur l'encoche pour l'envoyer rapidement.

- 🥷 **Invisibilité Intelligente**
  - OsaNotch devient 100% transparent lors des partages d'écrans ou des captures vidéos, pour garder vos enregistrements propres.

## 🚀 Installation & Build

Ce projet est une application macOS native écrite en **SwiftUI** (Architecture MVVM).

### Pré-requis
- Xcode 15 ou supérieur.
- macOS Sonoma (14.0) minimum.
- Certificat Développeur Apple (nécessaire pour conserver les permissions d'accessibilité à chaque compilation).

### Compilation
1. Clonez le dépôt :
   ```bash
   git clone https://github.com/osayanis/osanotch-native.git
   cd osanotch-native
   ```
2. Compilez via le script fourni (qui s'occupe de la signature de code) :
   ```bash
   ./build.sh
   ```
3. L'application générée sera disponible à la racine du projet sous le nom `OsaNotch.app`.

## 🔐 Permissions macOS

Pour fonctionner parfaitement, OsaNotch vous demandera lors de son premier lancement (via une fenêtre d'Onboarding élégante) :
- **Accessibilité (Accessibility)** : Requis pour intercepter les touches de volume/luminosité et supprimer le HUD natif.
- **Enregistrement de l'écran (Screen Capture)** : Requis pour la fonctionnalité de stream OsaCast.
- **Calendrier (Calendar)** : Requis pour afficher vos évènements dans le Dashboard.

*Note : Si les permissions posent problème lors du développement en raison de changements de signature, utilisez `tccutil reset All com.osalabs.osanotch` dans le terminal.*

## 🛠 Architecture

- `IslandView.swift` : La vue principale contenant l'encoche dynamique et gérant ses états (rétrécie, étendue, dashboard).
- `SystemObserver.swift` : Cerveau de l'app. Intercepte les évènements systèmes via `CGEventTap`, gère les API de la batterie, luminosité (DisplayServices), et audio (CoreAudio).
- `SystemData.swift` : Gère les appels AppleScript vers Spotify/Music de manière non bloquante.
- `DashboardView.swift` : Interface utilisateur étendue, avec détection de gestes trackpad et animations.

## 👨‍💻 Contribution

Les pull requests sont les bienvenues ! Pour toute modification majeure, veuillez d'abord ouvrir une issue pour discuter de ce que vous aimeriez changer.

## 📄 Licence

Ce projet est sous licence MIT - voir le fichier [LICENSE](LICENSE) pour plus de détails.
