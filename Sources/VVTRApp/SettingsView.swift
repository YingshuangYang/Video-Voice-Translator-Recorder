import SwiftUI
import VVTRCore

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    Form {
      Section("OpenAI / 兼容接口") {
        SecureField("API Key", text: Binding(get: { model.settings.openAIAPIKey }, set: { model.settings.openAIAPIKey = $0; model.saveSettings() }))
          .textContentType(.password)

        TextField("Base URL（例如 https://api.openai.com/v1）", text: Binding(get: { model.settings.openAIBaseURL }, set: { model.settings.openAIBaseURL = $0; model.saveSettings() }))

        TextField("模型（例如 gpt-4o-mini）", text: Binding(get: { model.settings.openAIModel }, set: { model.settings.openAIModel = $0; model.saveSettings() }))
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
        Text("提示：后续接入系统音频采集与云端转写后，这些设置会直接影响调用成本与延迟。")
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }
}

