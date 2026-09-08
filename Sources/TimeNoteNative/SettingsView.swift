import SwiftUI
import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let showTimeNote = Self("showTimeNoteV1")
    static let addTimeNoteWork = Self("addTimeNoteWorkV1")
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("weeklyReviewEnabled") private var weekly = true
    @AppStorage("monthlyReviewEnabled") private var monthly = true
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("设置与备份").font(.system(size: 25, weight: .semibold))
                section("更快打开") {
                    KeyboardShortcuts.Recorder("打开时间便签", name: .showTimeNote)
                        .shortcutValidation { shortcut in
                            if KeyboardShortcuts.getShortcut(for: .addTimeNoteWork) == shortcut {
                                return .disallow(reason: "这个组合已用于新增工作，请换一个。")
                            }
                            return .allow
                        }
                    KeyboardShortcuts.Recorder("新增工作", name: .addTimeNoteWork)
                        .shortcutValidation { shortcut in
                            if KeyboardShortcuts.getShortcut(for: .showTimeNote) == shortcut {
                                return .disallow(reason: "这个组合已用于打开时间便签，请换一个。")
                            }
                            return .allow
                        }
                    Text("点击右边录入你喜欢的组合键；默认不占用任何全局快捷键。程序运行时有效，完全退出后无效。应用内新增工作也可按 ⌘N。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                section("本机数据") {
                    HStack {
                        Button("导出备份…") { state.exportBackup() }.disabled(state.repository == nil)
                        Button("导入备份…") { state.chooseBackup() }.disabled(state.repository == nil)
                        Spacer()
                        Button("在 Finder 查看数据") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: state.dataFolder.path)
                        }
                    }
                    Text("保存位置：\(state.dataFolder.path)").font(.caption).textSelection(.enabled)
                    Text("工作和记录由 GRDB 保存在本机 SQLite 数据库。备份不会自动上传；导入先预览，只合并新内容，编号冲突会停止，不覆盖你的记录。首版只支持原生备份，网页 Demo 备份请继续保留。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("数据库和导出备份未额外加密，请像私人文档一样保管。移动应用不会移动记录，不要删除数据目录。").font(.caption).foregroundStyle(.secondary)
                }
                section("本地回顾") {
                    Toggle("显示上周分类回顾", isOn: $weekly)
                    Toggle("显示上月整体回顾", isOn: $monthly)
                    Text("打开回顾页时按最新记录计算；周一至周日为一周，自然月汇总。可在回顾页筛选分类。自定义生成日期和时刻尚未接入，当前不会定时发通知。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                section("这一版的能力边界") {
                    Label("严格提醒尚未启用，请不要用它代替重要闹钟。", systemImage: "bell.slash")
                    Text("睡眠和主程序完全退出后的准时持续响铃仍需实机验证。没有注册后台、登录启动、通知权限或电源唤醒；不拿普通通知冒充你的要求。")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("本地与在线 AI、取消/归档、网页备份迁移、自动更新暂未实现。").font(.callout).foregroundStyle(.secondary)
                }
                section("关于时间便签 0.1.0") {
                    Text("SwiftUI / AppKit 原生软件 · 公开预览版")
                    Text("已接入 GRDB.swift 7.11.1、KeyboardShortcuts 3.0.1（MIT）。Defaults 暂缓：几个开关使用系统设置存储即可，不重复引入一层。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("GRDB 许可") { openLicense("GRDB-LICENSE") }
                        Button("KeyboardShortcuts 许可") { openLicense("KeyboardShortcuts-LICENSE") }
                        Button("构建与第三方说明") { openLicense("第三方说明") }
                    }
                    Text("仅有临时签名，没有 Apple 开发者签名或公证；只验证本机 Apple Silicon，未做跨机器验收。首版可用于本地安排与记录，不代表全部产品需求已完成。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(28)
        }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(Style.panel, in: RoundedRectangle(cornerRadius: 10))
    }
    private func openLicense(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt") else {
            state.error = "许可证文件未找到，请查看随源码提供的许可声明。"; return
        }
        NSWorkspace.shared.open(url)
    }
}

struct ImportSheet: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("确认合并备份").font(.title2.bold())
            if let preview = state.importPreview {
                Text("新增 \(preview.newTasks) 项工作\n新增 \(preview.newGoals) 个目标\n跳过 \(preview.skippedTasks) 项完全相同的工作")
                    .lineSpacing(8)
            }
            Text("已有内容不会被覆盖或删除。保存时会再次校验；若期间出现编号冲突，整次导入会停止。")
                .foregroundStyle(.secondary)
            HStack {
                Button("取消") { state.importPreview = nil; state.importData = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("确认合并") { state.confirmImport() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 440)
    }
}
