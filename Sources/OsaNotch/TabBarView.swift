import SwiftUI

struct TabBarView: View {
    @ObservedObject var model: AppModel
    var accent: Color
    var dropHover: Bool
    var battery: BatteryInfo?
    var lowBat: Bool

    var body: some View {
        HStack(spacing: 16) {
            tbButton("house.fill", .home)
            tbButton("square.grid.2x2.fill", .dashboard)
            tbButton("paperplane.fill", .drop)
            tbButton("note.text", .notes)
            Spacer()
            if dropHover { Text("Lâcher pour AirDrop").font(.system(size: 10, weight: .semibold)).foregroundColor(accent) }
            
            if let b = battery {
                HStack(spacing: 2) { 
                    if b.charging { Image(systemName: "bolt.fill").font(.system(size: 9)) }
                    Text("\(b.percent)%").font(.system(size: 11, weight: .semibold)).monospacedDigit() 
                }
                .foregroundColor(b.charging ? .green : (lowBat ? .red : .white.opacity(0.5)))
            }
            
            OsaCharacter(model: model, mood: .idle, accent: accent, size: 16)
        }.padding(.horizontal, 18).padding(.top, 11)
    }

    func tbButton(_ icon: String, _ target: AppView) -> some View {
        Button { model.view = target } label: { 
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(model.view == target ? .white : .white.opacity(0.45)).padding(5).contentShape(Rectangle()) 
        }.buttonStyle(.plain)
    }
}
