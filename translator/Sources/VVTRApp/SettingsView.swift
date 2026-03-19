import SwiftUI
import VVTRCore

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel
  @State private var showKeys: Bool = false

  var body: some View {
    Form {
      Section("云端提供商") {
        Picker("Provider", selection: Binding(get: { model.settings.provider }, set: { model.settings.provider = $0; model.saveSettings() })) {
          Text("Gemini（Google AI Studio）").tag(VVTRProvider.gemini)
          Text("OpenAI / 兼容接口").tag(VVTRProvider.openai)
        }
      }

      if model.settings.provider == .gemini {
        Section("Gemini（Google AI Studio）") {
          APIKeyRow(
            title: "API Key",
            value: Binding(get: { model.settings.geminiAPIKey }, set: { model.settings.geminiAPIKey = $0; model.saveSettings() }),
            reveal: $showKeys
          )
          TextField("Base URL（默认 https://generativelanguage.googleapis.com/v1beta）", text: Binding(get: { model.settings.geminiBaseURL }, set: { model.settings.geminiBaseURL = $0; model.saveSettings() }))
          TextField("模型（例如 gemini-2.0-flash）", text: Binding(get: { model.settings.geminiModel }, set: { model.settings.geminiModel = $0; model.saveSettings() }))
        }
      } else {
        Section("OpenAI / 兼容接口") {
          APIKeyRow(
            title: "API Key",
            value: Binding(get: { model.settings.openAIAPIKey }, set: { model.settings.openAIAPIKey = $0; model.saveSettings() }),
            reveal: $showKeys
          )

          TextField("Base URL（例如 https://api.openai.com/v1）", text: Binding(get: { model.settings.openAIBaseURL }, set: { model.settings.openAIBaseURL = $0; model.saveSettings() }))

          TextField("模型（例如 gpt-4o-mini）", text: Binding(get: { model.settings.openAIModel }, set: { model.settings.openAIModel = $0; model.saveSettings() }))
        }
      }

      Section("分片") {
        HStack {
          Text("片段长度（秒）")
          Spacer()
          TextField("", value: Binding(get: { model.settings.chunkSeconds }, set: { model.settings.chunkSeconds = $0; model.saveSettings() }), format: .number)
            .frame(width: 80)
        }

        HStack {
          Text("重叠（秒）")
          Spacer()
          TextField("", value: Binding(get: { model.settings.overlapSeconds }, set: { model.settings.overlapSeconds = $0; model.saveSettings() }), format: .number)
            .frame(width: 80)
        }
      }

      Section("策略") {
        Picker("模式", selection: Binding(get: { model.settings.realtimeMode }, set: { model.settings.realtimeMode = $0; model.saveSettings() })) {
          Text("实时").tag(VVTRRealtimeMode.realtime)
          Text("静默后总结").tag(VVTRRealtimeMode.summarizeOnSilence)
        }

        Picker("输出格式", selection: Binding(get: { model.settings.outputFormat }, set: { model.settings.outputFormat = $0; model.saveSettings() })) {
          Text("JSON").tag(VVTROutputFormat.json)
          Text("纯文本").tag(VVTROutputFormat.plainText)
        }
      }

      Section("隐私") {
        Picker("落库策略", selection: Binding(get: { model.settings.privacyMode }, set: { model.settings.privacyMode = $0; model.saveSettings() })) {
          Text("全部保存（原文/输出/原始JSON）").tag(VVTRPrivacyMode.storeAll)
          Text("不保存原文（只存输出与时间）").tag(VVTRPrivacyMode.storeNoAudioText)
          Text("不保存原始JSON（只存可读输出）").tag(VVTRPrivacyMode.storeNoRawJSON)
        }
      }

      Section {
        Text("提示：分片越短越实时，但调用次数越多，成本更高。")
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }
}

private struct APIKeyRow: View {
  let title: String
  @Binding var value: String
  @Binding var reveal: Bool

  var body: some View {
    HStack(spacing: 10) {
      if reveal {
        TextField(title, text: $value)
          .textContentType(.password)
          .disableAutocorrection(true)
      } else {
        // NOTE: SecureField 在某些运行方式下会出现无法粘贴/无法输入的问题，
        // 所以这里也用 TextField，但通过 privacySensitive 降低泄露风险。
        TextField(title, text: $value)
          .textContentType(.password)
          .disableAutocorrection(true)
          .privacySensitive()
      }

      Button {
        reveal.toggle()
      } label: {
        Image(systemName: reveal ? "eye.slash" : "eye")
      }
      .buttonStyle(.borderless)
      .help(reveal ? "隐藏" : "显示")
    }
  }
}

