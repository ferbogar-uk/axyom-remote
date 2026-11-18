import SwiftUI
import UIKit
import AxyomRemoteCore

/// Settings in the style of the Claude app: grouped rows with icons, and an
/// appearance picker with previews. Every row does something real; anything
/// the PC or server cannot do yet is not shown as a switch.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmUnpair = false

    @AppStorage(Prefs.Key.appearance) private var appearance = "system"
    @AppStorage(Prefs.Key.voiceLanguage) private var voiceLanguage = "pt-BR"
    @AppStorage(Prefs.Key.speechRate) private var speechRate = "normal"
    @AppStorage(Prefs.Key.silence) private var silence = 1.8
    @AppStorage(Prefs.Key.haptics) private var haptics = true
    @AppStorage(Prefs.Key.notifications) private var notifications = true
    @AppStorage(Prefs.Key.notifyFinished) private var notifyFinished = true

    private var desktops: [DeviceInfo] { model.snapshot.devices.filter { $0.type == "desktop" } }

    var body: some View {
        NavigationStack {
            List {
                Section("Computadores") {
                    if desktops.isEmpty {
                        row("desktopcomputer", "Nenhum PC visto ainda", detail: model.snapshot.connected ? nil : "a ligar…")
                    }
                    ForEach(desktops, id: \.deviceId) { pc in
                        HStack(spacing: 14) {
                            Image(systemName: "laptopcomputer").frame(width: 26).foregroundStyle(Theme.text)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pc.name).foregroundStyle(Theme.text)
                                HStack(spacing: 6) {
                                    Circle().fill(pc.isOnline == true ? Theme.green : Theme.muted).frame(width: 7, height: 7)
                                    Text(pc.isOnline == true ? "Ligado" : "Desligado").font(.footnote).foregroundStyle(Theme.muted)
                                    if let n = pc.syncedProjectIds?.count { Text("· \(n) projeto\(n == 1 ? "" : "s")").font(.footnote).foregroundStyle(Theme.muted) }
                                }
                            }
                        }
                        .listRowBackground(Theme.surface)
                    }
                }

                if !model.snapshot.planUsage.isEmpty {
                    Section("Uso do plano") {
                        PlanUsageStrip(usage: model.snapshot.planUsage)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section("Aparência") {
                    HStack(spacing: 12) {
                        appearanceCard("light", "Claro")
                        appearanceCard("dark", "Escuro")
                        appearanceCard("system", "Sistema")
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Theme.surface)
                }

                Section {
                    pickerRow("globe", "Idioma da voz", selection: $voiceLanguage, options: [("pt-BR", "Português (Brasil)"), ("pt-PT", "Português (Portugal)")])
                    pickerRow("speaker.wave.2", "Velocidade da leitura", selection: $speechRate, options: [("slow", "Devagar"), ("normal", "Normal"), ("fast", "Rápida")])
                    HStack(spacing: 14) {
                        Image(systemName: "timer").frame(width: 26).foregroundStyle(Theme.text)
                        Text("Enviar após silêncio").foregroundStyle(Theme.text)
                        Spacer()
                        Picker("", selection: $silence) {
                            Text("1,5 s").tag(1.5)
                            Text("1,8 s").tag(1.8)
                            Text("2,5 s").tag(2.5)
                        }
                        .labelsHidden()
                        .tint(Theme.muted)
                    }
                    .listRowBackground(Theme.surface)
                } header: {
                    Text("Voz e ditado")
                } footer: {
                    Text("Na conversa por voz, a app envia quando ficas este tempo em silêncio e lê a resposta com a voz do iPhone.")
                }

                Section {
                    toggleRow("bell", "Avisar quando um agente espera por ti", isOn: $notifications)
                    toggleRow("checkmark.circle", "Avisar quando um agente termina", isOn: $notifyFinished)
                    row("iphone.radiowaves.left.and.right", "Avisos com a app fechada", detail: model.pushStatus)
                        .listRowBackground(Theme.surface)
                    toggleRow("hand.tap", "Vibração ao enviar", isOn: $haptics)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: {
                        row("gearshape", "Permissões no iPhone", detail: "microfone, câmara, avisos", chevron: true)
                    }
                    .listRowBackground(Theme.surface)
                } header: {
                    Text("App")
                } footer: {
                    Text("Com a app fechada ou o iPhone bloqueado, o servidor envia o aviso (texto genérico, sem conteúdo da conversa). Tocar no aviso abre a conversa.")
                }

                Section("Sobre") {
                    row("info.circle", "Versão", detail: Self.version)
                    row("server.rack", "Servidor", detail: model.pairing.map { URL(string: $0.server)?.host ?? $0.server } ?? "—")
                }

                Section {
                    Button { confirmUnpair = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "rectangle.portrait.and.arrow.right").frame(width: 26)
                            Text("Desemparelhar este iPhone")
                        }
                        .foregroundStyle(Theme.danger)
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Definições")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Theme.text) }
                        .accessibilityLabel("Fechar")
                }
            }
            .confirmationDialog("Desemparelhar este iPhone?", isPresented: $confirmUnpair, titleVisibility: .visible) {
                Button("Desemparelhar", role: .destructive) { model.unpair(); dismiss() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Apaga a chave guardada neste iPhone. Para voltar, gera um código novo no PC.")
            }
        }
    }

    // MARK: Rows

    private func row(_ icon: String, _ title: String, detail: String? = nil, chevron: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).frame(width: 26).foregroundStyle(Theme.text)
            Text(title).foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            if let detail { Text(detail).font(.subheadline).foregroundStyle(Theme.muted).lineLimit(1) }
            if chevron { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted) }
        }
        .listRowBackground(Theme.surface)
    }

    private func toggleRow(_ icon: String, _ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 14) {
                Image(systemName: icon).frame(width: 26).foregroundStyle(Theme.text)
                Text(title).foregroundStyle(Theme.text)
            }
        }
        .tint(Theme.accent)
        .listRowBackground(Theme.surface)
    }

    private func pickerRow(_ icon: String, _ title: String, selection: Binding<String>, options: [(String, String)]) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).frame(width: 26).foregroundStyle(Theme.text)
            Text(title).foregroundStyle(Theme.text)
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .labelsHidden()
            .tint(Theme.muted)
        }
        .listRowBackground(Theme.surface)
    }

    /// A small preview of the screen in that theme, with the orange action dot.
    private func appearanceCard(_ value: String, _ label: String) -> some View {
        let on = appearance == value
        return Button { appearance = value } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0xF6F7F8))
                    if value == "dark" {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x161618))
                    } else if value == "system" {
                        DiagonalHalf().fill(Color(hex: 0x161618))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().fill(Color.gray.opacity(0.6)).frame(width: 44, height: 4)
                        Capsule().fill(Color.gray.opacity(0.6)).frame(width: 30, height: 4)
                        Spacer()
                        HStack { Spacer(); Circle().fill(Theme.accent).frame(width: 12, height: 12) }
                    }
                    .padding(10)
                }
                .frame(height: 74)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(on ? Theme.accent : Theme.border, lineWidth: on ? 2.5 : 1))
                Text(label).font(.subheadline).foregroundStyle(on ? Theme.text : Theme.muted)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Aparência \(label)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}

/// The lower-right half of a rectangle, for the "System" preview.
private struct DiagonalHalf: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
