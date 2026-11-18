import SwiftUI

/// Where the hands-free conversation loop is right now.
enum ConversationPhase: Equatable {
    case idle        // nothing heard; tap to talk
    case listening   // microphone open
    case waiting     // sent; agent working
    case speaking    // reading the reply aloud
}

/// Big hands-free screen shown over a session while conversation mode is on:
/// listen -> send -> wait -> read reply -> listen again, until "Terminar".
struct ConversationPanel: View {
    let phase: ConversationPhase
    let heard: String
    let lastReply: String?
    let problem: String?
    let onTapMain: () -> Void
    let onEnd: () -> Void

    private var title: String {
        switch phase {
        case .idle: return "Toca para falar"
        case .listening: return "A ouvir…"
        case .waiting: return "À espera do agente…"
        case .speaking: return "A responder…"
        }
    }

    private var hint: String {
        switch phase {
        case .idle: return "Não ouvi nada. Toca no círculo quando quiseres continuar."
        case .listening: return "Fala à vontade. Envio quando ficares 2,5 s em silêncio. Toca para enviar já."
        case .waiting: return "Assim que o agente responder, leio em voz alta."
        case .speaking: return "Toca para interromper e falar."
        }
    }

    private var icon: String {
        switch phase {
        case .idle, .listening: return "mic.fill"
        case .waiting: return "hourglass"
        case .speaking: return "speaker.wave.2.fill"
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Text(title).font(.title2.weight(.semibold)).foregroundStyle(Theme.text)
            Button(action: onTapMain) {
                ZStack {
                    Circle().fill(phase == .listening ? Theme.amber : Theme.elevated)
                        .frame(width: 168, height: 168)
                        .overlay(Circle().stroke(phase == .speaking ? Theme.green : Theme.amber, lineWidth: 3))
                    if phase == .waiting {
                        ProgressView().tint(Theme.amber).scaleEffect(1.8)
                    } else {
                        Image(systemName: icon).font(.system(size: 54, weight: .semibold))
                            .foregroundStyle(phase == .listening ? Theme.onAmber : Theme.text)
                    }
                }
            }
            .disabled(phase == .waiting)
            .accessibilityLabel(title)
            Text(hint).font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center).padding(.horizontal, 32)
            if let problem { Text(problem).font(.footnote).foregroundStyle(Theme.danger).multilineTextAlignment(.center).padding(.horizontal, 24) }
            if phase == .listening && !heard.isEmpty {
                Text("“\(heard)”").font(.body).foregroundStyle(Theme.text).multilineTextAlignment(.center)
                    .lineLimit(6).padding(.horizontal, 24)
            } else if let lastReply, phase == .speaking || phase == .idle {
                Text(lastReply).font(.callout).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    .lineLimit(6).padding(.horizontal, 24)
            }
            Spacer()
            Button(action: onEnd) {
                Text("Terminar conversa").font(.headline).foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.opacity(0.97))
    }
}
