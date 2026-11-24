import AppKit

// Rendu hors écran de l'onglet Boubou (tests) : OsaNotch apercu-boubou <etat.json> <jeu.json> <dossier>
if CommandLine.arguments.count > 4, CommandLine.arguments[1] == "apercu-boubou" {
    let a = CommandLine.arguments
    MainActor.assumeIsolated {
        BoubouFoyer.apercu(etat: (try? Data(contentsOf: URL(fileURLWithPath: a[2]))) ?? Data(),
                           jeu: (try? Data(contentsOf: URL(fileURLWithPath: a[3]))) ?? Data(),
                           dossier: URL(fileURLWithPath: a[4]))
    }
    exit(0)
}

if CommandLine.arguments.count > 1, CommandLine.arguments[1] == "essai-boubou" {
    Task { @MainActor in exit(await BoubouFoyer.essai() ? 0 : 1) }
    RunLoop.main.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
