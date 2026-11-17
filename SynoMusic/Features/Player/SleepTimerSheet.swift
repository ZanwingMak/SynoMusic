import SwiftUI

/// 定时停止 sheet：倒计时预设 / 自定义时长 / 时间点停止 / 本曲结束 / 取消。
struct SleepTimerSheet: View {
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var theme: ThemeManager
    @Binding var isPresented: Bool

    private static let presets: [Int] = [5, 10, 15, 30, 45, 60, 90]

    @State private var showCustomDuration: Bool = false
    @State private var showDeadline: Bool = false
    @State private var customHours: Int = 1
    @State private var customMinutes: Int = 0
    @State private var deadline: Date = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            List {
                currentSection
                presetsSection
                customSection
                stopAtTrackEndSection
            }
            .navigationTitle("定时停止".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isPresented = false } label: { Label("完成".t, systemImage: "checkmark") }
                }
            }
            .sheet(isPresented: $showCustomDuration) { customDurationPicker }
            .sheet(isPresented: $showDeadline) { deadlinePicker }
            .tint(theme.current.accent(in: .dark))
            .animation(.easeInOut(duration: 0.18), value: theme.currentID)
        }
    }

    // MARK: 子 section

    @ViewBuilder
    private var currentSection: some View {
        Section {
            if let remain = playback.sleepRemaining {
                HStack(spacing: 12) {
                    Image(systemName: "moon.zzz.fill").foregroundStyle(Theme.accent)
                    Text("剩余".t + " \(format(remain))").monospacedDigit()
                    Spacer()
                    cancelButton
                }
            } else if playback.stopAtTrackEnd {
                HStack(spacing: 12) {
                    Image(systemName: "stop.circle.fill").foregroundStyle(Theme.accent)
                    Text("本曲结束后停止".t)
                    Spacer()
                    cancelButton
                }
            } else {
                Label("当前未设置".t, systemImage: "moon.zzz")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var presetsSection: some View {
        Section("倒计时".t) {
            ForEach(Self.presets, id: \.self) { mins in
                Button {
                    apply(seconds: TimeInterval(mins * 60))
                } label: {
                    HStack {
                        Image(systemName: "timer").foregroundStyle(Theme.accent)
                        Text("\(mins) \("分钟".t)")
                        Spacer()
                    }
                }
            }
            Button {
                showCustomDuration = true
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.accent)
                    Text("自定义时长…".t)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var customSection: some View {
        Section("时间点停止".t) {
            Button {
                showDeadline = true
            } label: {
                HStack {
                    Image(systemName: "alarm.waves.left.and.right.fill")
                        .foregroundStyle(Theme.accent)
                    Text("选择停止时间…".t)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var stopAtTrackEndSection: some View {
        Section("按曲结束".t) {
            Button {
                Haptics.soft()
                playback.enableStopAtTrackEnd()
                isPresented = false
            } label: {
                HStack {
                    Image(systemName: "stop.circle").foregroundStyle(Theme.accent)
                    Text("本曲结束后停止".t)
                    Spacer()
                }
            }
        }
    }

    // MARK: 自定义时长选择

    private var customDurationPicker: some View {
        NavigationStack {
            VStack {
                HStack(spacing: 0) {
                    Picker("小时".t, selection: $customHours) {
                        ForEach(0...23, id: \.self) { h in
                            Text("\(h) \("小时".t)").tag(h)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Picker("分钟".t, selection: $customMinutes) {
                        ForEach(0...59, id: \.self) { m in
                            Text("\(m) \("分钟".t)").tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, Metrics.s)

                Button {
                    let total = TimeInterval(customHours * 3600 + customMinutes * 60)
                    if total > 0 {
                        apply(seconds: total)
                        showCustomDuration = false
                    }
                } label: {
                    Text("开始倒计时".t)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Metrics.l)
                .padding(.bottom, Metrics.l)
                .disabled(customHours == 0 && customMinutes == 0)
            }
            .navigationTitle("自定义倒计时".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { showCustomDuration = false } label: { Label("取消".t, systemImage: "xmark") }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: 时间点选择

    private var deadlinePicker: some View {
        NavigationStack {
            VStack(spacing: Metrics.l) {
                DatePicker(
                    "停止时间".t,
                    selection: $deadline,
                    in: Date()...Date().addingTimeInterval(24 * 3600),
                    displayedComponents: [.hourAndMinute]
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding(.top, Metrics.s)

                Text("将在".t + " \(format(deadline.timeIntervalSinceNow)) " + "后停止播放".t)
                    .font(.nocCaption)
                    .foregroundStyle(.secondary)

                Button {
                    let interval = deadline.timeIntervalSinceNow
                    if interval > 0 {
                        apply(seconds: interval)
                        showDeadline = false
                    }
                } label: {
                    Text("设置".t)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Metrics.l)
                .padding(.bottom, Metrics.l)
                .disabled(deadline.timeIntervalSinceNow <= 0)
            }
            .navigationTitle("时间点停止".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { showDeadline = false } label: { Label("取消".t, systemImage: "xmark") }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: 共用

    private func apply(seconds: TimeInterval) {
        Haptics.soft()
        playback.setSleepTimer(seconds)
        isPresented = false
    }

    /// 取消按钮：用图标按钮 + .contentShape 保证整体可点击；
    /// 同时把 sheet 关掉以给用户明确视觉反馈。
    private var cancelButton: some View {
        Button {
            Haptics.tap()
            playback.setSleepTimer(nil)
            isPresented = false
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                Text("取消".t)
            }
            .foregroundStyle(.red)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func format(_ s: TimeInterval) -> String {
        let total = max(0, Int(s))
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }
}
