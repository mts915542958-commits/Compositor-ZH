import SwiftUI

struct CameraRawCurveControls: View {
    @Bindable var session: EditorSession
    private var raw: CameraRawSettings { session.filterEdit?.settings.cameraRaw ?? CameraRawSettings() }
    private var edit: FilterEdit? { session.filterEdit }
    /// What a drag in the graph is moving, picked when it starts and kept until it ends, as Image › Curves does: a
    /// point (by index), a divider, or a tonal region and the amount it started at.
    private enum Drag { case point(Int), divider(Int), region(WritableKeyPath<CameraRawCurveSettings, Double>, Double) }
    @State private var drag: Drag?
    @State private var selected: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("曲线", selection: Binding(get: { edit?.cameraRawCurvePage ?? .parametric }, set: { session.filterEdit?.cameraRawCurvePage = $0 })) {
                ForEach(CameraRawCurvePage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("参数化提升色调区域。点模式在曲线上放置锚点。")
            if edit?.cameraRawCurvePage == .point {
                Picker("通道", selection: Binding(get: { edit?.cameraRawPointChannel ?? .rgb }, set: { session.filterEdit?.cameraRawPointChannel = $0 })) {
                    ForEach(CameraRawPointChannel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("RGB 改变亮度。红、绿、蓝还改变颜色。")
                .onChange(of: edit?.cameraRawPointChannel) { _, _ in selected = nil; drag = nil }
            }
            curveGraph
                .frame(height: 150)
                .help(edit?.cameraRawCurvePage == .parametric
                      ? "上下拖动以提升或降低这些色调。沿底部拖动分隔线可改变每个区域覆盖的色调。"
                      : "拖动节点。点击添加节点。双击节点将其移除。")
            if edit?.cameraRawCurvePage != .point {
                amount("高光", \.highlights, "提升或降低最亮的色调。")
                amount("亮部", \.lights, "提升或降低较亮的色调。")
                amount("暗部", \.darks, "提升或降低较暗的色调。")
                amount("阴影", \.shadows, "提升或降低最暗的色调。")
            } else {
                if let point = selectedPoint {
                    Text("输入 \(Int((point.x * 255).rounded()))  输出 \(Int((point.y * 255).rounded()))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help("所选曲线点的输入和输出。")
                }
                Picker("预设", selection: Binding(get: { CurvePreset.matching(currentPoints) }, set: applyPreset)) {
                    Text("自定义").tag(CurvePreset.custom)
                    Text("线性").tag(CurvePreset.linear)
                    Text("中等对比度").tag(CurvePreset.medium)
                    Text("强对比度").tag(CurvePreset.strong)
                }
                .help("用直线或对比曲线替换此曲线。")
                if edit?.cameraRawPointChannel == .rgb {
                    slider("细化饱和度", \.refineSaturation, -100...100, 0, "曲线同时改变颜色强度的程度。零与 Photoshop 一致；更低保持亮度，更高增加更多颜色。")
                }
            }
            targetButton(armed: edit?.targetsCameraRawCurve == true, help: "在图片上拖动，为指针下的色调移动曲线。") {
                session.filterEdit?.targetsCameraRawMixer = false
                session.filterEdit?.targetsCameraRawCurve.toggle()
            }
        }
    }

    private var curveGraph: some View {
        GeometryReader { geometry in
            let size = geometry.size
            Canvas { context, canvasSize in
                var axis = Path()
                axis.move(to: CGPoint(x: 0, y: canvasSize.height))
                axis.addLine(to: CGPoint(x: canvasSize.width, y: 0))
                context.stroke(axis, with: .color(.white.opacity(0.25)), lineWidth: 1)
                if edit?.cameraRawCurvePage == .parametric {
                    stroke(samples: (0..<64).map { raw.curve.parametric(Double($0) / 63) }, in: context, size: canvasSize)
                    for split in [raw.curve.shadowSplit, raw.curve.darkSplit, raw.curve.lightSplit] {
                        let x = split / 100 * canvasSize.width
                        var line = Path()
                        line.move(to: CGPoint(x: x, y: canvasSize.height - 8))
                        line.addLine(to: CGPoint(x: x, y: canvasSize.height))
                        context.stroke(line, with: .color(.white), lineWidth: 3)
                    }
                } else {
                    stroke(samples: raw.curve.channelTable(currentPoints).map(Double.init), in: context, size: canvasSize)
                    for (index, point) in currentPoints.enumerated() {
                        let rect = CGRect(x: CGFloat(point.x) * canvasSize.width - 4, y: CGFloat(1 - point.y) * canvasSize.height - 4, width: 8, height: 8)
                        context.fill(Path(ellipseIn: rect), with: .color(selected == index ? .accentColor : .white))
                    }
                }
            }
            .contentShape(Rectangle())
            // One drag does everything, as in Image › Curves: two separate drags left the second never firing, so
            // nothing could be dragged, and picking the nearest point afresh at every step jumped between points.
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if drag == nil { drag = edit?.cameraRawCurvePage == .parametric ? parametricDrag(at: value.startLocation, in: size)
                                                                                     : pointDrag(at: value.startLocation, in: size) }
                    continueDrag(value, in: size)
                }
                .onEnded { _ in drag = nil })
            .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { value in
                guard edit?.cameraRawCurvePage == .point else { return }
                removePoint(at: value.location, in: size)
            })
        }
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var currentPoints: [CurvePoint] {
        switch edit?.cameraRawPointChannel ?? .rgb {
        case .rgb: return raw.curve.rgb
        case .red: return raw.curve.red
        case .green: return raw.curve.green
        case .blue: return raw.curve.blue
        }
    }

    private var selectedPoint: CurvePoint? { selected.flatMap { currentPoints.indices.contains($0) ? currentPoints[$0] : nil } }

    private func amount(_ title: String, _ key: WritableKeyPath<CameraRawCurveSettings, Double>, _ help: String) -> some View {
        slider(title, key, -100...100, 0, help)
    }

    private func slider(_ title: String, _ key: WritableKeyPath<CameraRawCurveSettings, Double>, _ range: ClosedRange<Double>, _ reset: Double, _ help: String) -> some View {
        HStack {
            Text(title).frame(width: 88, alignment: .leading).help(help)
                .scrubbable(sensitivity: 1,
                            value: Binding(get: { raw.curve[keyPath: key] },
                                           set: { value in update { $0.curve[keyPath: key] = value } }), range: range)
            CameraRawSlider(value: raw.curve[keyPath: key], range: range, track: .plain, help: help,
                            onChange: { value in update { $0.curve[keyPath: key] = value } },
                            onReset: { update { $0.curve[keyPath: key] = reset } })
            TextField(title, value: Binding(get: { raw.curve[keyPath: key] }, set: { value in update { $0.curve[keyPath: key] = value } }),
                      format: .number.precision(.fractionLength(0...0)))
                .frame(width: 48).help(help)
        }
    }

    private func stroke(samples: [Double], in context: GraphicsContext, size: CGSize) {
        var path = Path()
        for (index, sample) in samples.enumerated() {
            let point = CGPoint(x: CGFloat(index) / CGFloat(max(1, samples.count - 1)) * size.width, y: (1 - sample) * size.height)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        context.stroke(path, with: .color(.white), lineWidth: 1.5)
    }

    /// Parametric: pressing along the bottom takes the nearest divider; anywhere else, the tonal region under the pointer,
    /// raised or lowered as the pointer moves up or down, as Camera Raw's does.
    private func parametricDrag(at start: CGPoint, in size: CGSize) -> Drag {
        let tone = Double(start.x / max(size.width, 1)) * 100
        let splits = [raw.curve.shadowSplit, raw.curve.darkSplit, raw.curve.lightSplit]
        if start.y > size.height - 18 {
            return .divider(splits.indices.min { abs(splits[$0] - tone) < abs(splits[$1] - tone) } ?? 0)
        }
        let key: WritableKeyPath<CameraRawCurveSettings, Double> = tone < splits[0] ? \.shadows : tone < splits[1] ? \.darks
            : tone < splits[2] ? \.lights : \.highlights
        return .region(key, raw.curve[keyPath: key])
    }

    /// Point: pressing on a point takes it; anywhere else adds one there and takes that.
    private func pointDrag(at start: CGPoint, in size: CGSize) -> Drag? {
        let x = Double(start.x / max(size.width, 1)), y = 1 - Double(start.y / max(size.height, 1))
        var points = currentPoints
        let near = points.indices.min { hypot(points[$0].x - x, points[$0].y - y) < hypot(points[$1].x - x, points[$1].y - y) }
        if let near, hypot(points[near].x - x, points[near].y - y) < 0.055 { selected = near; return .point(near) }
        guard points.count < 16, x > 0.01, x < 0.99, points.allSatisfy({ abs($0.x - x) > 0.01 }) else { return nil }
        let point = CurvePoint(x: x, y: min(1, max(0, y)))
        points.append(point)
        points.sort { $0.x < $1.x }
        store(points)
        let index = points.firstIndex(of: point)
        selected = index
        return index.map { .point($0) }
    }

    private func continueDrag(_ value: DragGesture.Value, in size: CGSize) {
        let x = Double(value.location.x / max(size.width, 1)), y = 1 - Double(value.location.y / max(size.height, 1))
        switch drag {
        case .point(let index):
            var points = currentPoints
            guard points.indices.contains(index) else { return }
            points[index].y = min(1, max(0, y))
            // The ends stay at the ends; the rest keep their order.
            if index > 0, index < points.count - 1 { points[index].x = min(points[index + 1].x - 0.01, max(points[index - 1].x + 0.01, x)) }
            store(points)
        case .divider(let index):
            let value = min(98, max(2, x * 100))
            update {
                // Dividers keep their order: shadows before darks before lights.
                switch index {
                case 0: $0.curve.shadowSplit = min(value, $0.curve.darkSplit - 2)
                case 1: $0.curve.darkSplit = min($0.curve.lightSplit - 2, max($0.curve.shadowSplit + 2, value))
                default: $0.curve.lightSplit = max(value, $0.curve.darkSplit + 2)
                }
            }
        case .region(let key, let start):
            let amount = min(100, max(-100, start - Double(value.translation.height / max(size.height, 1)) * 200))
            update { $0.curve[keyPath: key] = amount.rounded() }
        case nil: break
        }
    }

    private func removePoint(at location: CGPoint, in size: CGSize) {
        var points = currentPoints
        let x = location.x / size.width
        guard let index = points.indices.dropFirst().dropLast().min(by: { abs(points[$0].x - x) < abs(points[$1].x - x) }),
              abs(points[index].x - x) < 0.04 else { return }
        points.remove(at: index)
        selected = nil
        store(points)
    }

    private func store(_ points: [CurvePoint]) {
        update {
            switch edit?.cameraRawPointChannel ?? .rgb {
            case .rgb: $0.curve.rgb = points
            case .red: $0.curve.red = points
            case .green: $0.curve.green = points
            case .blue: $0.curve.blue = points
            }
        }
    }

    private func applyPreset(_ preset: CurvePreset) {
        guard let points = preset.points else { return }
        store(points)
    }

    private func targetButton(armed: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label("Targeted Adjustment", systemImage: "scope") }
            .buttonStyle(.bordered)
            .tint(armed ? Color.accentColor : Color.secondary)
            .help(help)
    }

    private func update(_ change: (inout CameraRawSettings) -> Void) {
        var settings = session.filterEdit?.settings ?? FilterSettings()
        change(&settings.cameraRaw)
        session.updateFilter(settings, preview: session.filterEdit?.preview ?? true)
    }
}

private enum CurvePreset: Hashable {
    case custom, linear, medium, strong
    var points: [CurvePoint]? {
        switch self {
        case .custom: return nil
        case .linear: return CameraRawCurveSettings.linear
        case .medium: return CameraRawCurveSettings.mediumContrast
        case .strong: return CameraRawCurveSettings.strongContrast
        }
    }
    static func matching(_ points: [CurvePoint]) -> Self {
        if points == CameraRawCurveSettings.linear { return .linear }
        if points == CameraRawCurveSettings.mediumContrast { return .medium }
        if points == CameraRawCurveSettings.strongContrast { return .strong }
        return .custom
    }
}

struct CameraRawMixerControls: View {
    @Bindable var session: EditorSession
    private var raw: CameraRawSettings { session.filterEdit?.settings.cameraRaw ?? CameraRawSettings() }
    private var edit: FilterEdit? { session.filterEdit }
    /// What a drag in the graph is moving, picked when it starts and kept until it ends, as Image › Curves does: a
    /// point (by index), a divider, or a tonal region and the amount it started at.
    private enum Drag { case point(Int), divider(Int), region(WritableKeyPath<CameraRawCurveSettings, Double>, Double) }
    @State private var drag: Drag?
    @State private var selected: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("混合器", selection: Binding(get: { edit?.cameraRawMixerPage ?? .hsl }, set: { session.filterEdit?.cameraRawMixerPage = $0 })) {
                ForEach(CameraRawMixerPage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("HSL 列出每种颜色。颜色编辑一个色系。点颜色调整你选择的颜色。")
            switch edit?.cameraRawMixerPage ?? .hsl {
            case .hsl:
                Picker("分量", selection: Binding(get: { edit?.cameraRawMixerTab ?? .hue }, set: { session.filterEdit?.cameraRawMixerTab = $0 })) {
                    ForEach(CameraRawMixerTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .help("色相改变颜色，饱和度改变强度，亮度改变明暗。")
                ForEach(0..<8, id: \.self) { index in familySlider(index) }
            case .color:
                swatches
                colorSlider("色相", \.hue, "让所选色系在色轮上移动。")
                colorSlider("饱和度", \.saturation, "让所选色系更强或更安静。")
                colorSlider("亮度", \.luminance, "让所选色系更亮或更暗。")
            case .point:
                pointColor
            }
            Button {
                session.filterEdit?.targetsCameraRawCurve = false
                session.filterEdit?.targetsCameraRawMixer.toggle()
            } label: { Label("定向调整", systemImage: "scope") }
            .buttonStyle(.bordered)
            .tint(edit?.targetsCameraRawMixer == true ? Color.accentColor : Color.secondary)
            .help("在图片中拖动一种颜色。附近的色系一起移动。")
        }
    }

    private func colorSlider(_ title: String, _ key: WritableKeyPath<CameraRawMixerSettings, [Double]>, _ help: String) -> some View {
        let index = min(7, edit?.cameraRawMixerSwatch ?? 0)
        return HStack {
            Text(title).frame(width: 88, alignment: .leading).help(help)
            CameraRawSlider(value: raw.mixer[keyPath: key][index], range: -100...100, track: familyTrack(index, key), help: help,
                            onChange: { value in update { $0.mixer[keyPath: key][index] = value } },
                            onReset: { update { $0.mixer[keyPath: key][index] = 0 } })
        }
    }

    private func familySlider(_ index: Int) -> some View {
        let key = mixerKey
        let help = "\((edit?.cameraRawMixerTab ?? .hue).rawValue)：\(CameraRawMixerSettings.names[index])。"
        return HStack {
            Text(CameraRawMixerSettings.names[index]).frame(width: 78, alignment: .leading).help(help)
                .scrubbable(sensitivity: 1,
                            value: Binding(get: { raw.mixer[keyPath: key][index] },
                                           set: { value in update { $0.mixer[keyPath: key][index] = value } }), range: -100...100)
            CameraRawSlider(value: raw.mixer[keyPath: key][index], range: -100...100, track: familyTrack(index, key), help: help,
                            onChange: { value in update { $0.mixer[keyPath: key][index] = value } },
                            onReset: { update { $0.mixer[keyPath: key][index] = 0 } })
            TextField(CameraRawMixerSettings.names[index], value: Binding(get: { raw.mixer[keyPath: key][index] }, set: { value in update { $0.mixer[keyPath: key][index] = value } }),
                      format: .number.precision(.fractionLength(0...0)))
                .frame(width: 48).help(help)
        }
    }

    private var mixerKey: WritableKeyPath<CameraRawMixerSettings, [Double]> {
        switch edit?.cameraRawMixerTab ?? .hue {
        case .hue: return \.hue
        case .saturation: return \.saturation
        case .luminance: return \.luminance
        }
    }
    private var swatches: some View {
        HStack {
            ForEach(0..<8, id: \.self) { index in
                Button {
                    session.filterEdit?.cameraRawMixerSwatch = index
                } label: {
                    Circle().fill(Color(hue: CameraRawMixerSettings.centers[index] / 360, saturation: 0.8, brightness: 0.9))
                        .frame(width: 18, height: 18)
                        .overlay { Circle().stroke(edit?.cameraRawMixerSwatch == index ? Color.white : Color.clear, lineWidth: 2) }
                }
                .buttonStyle(.plain)
                .help("编辑\(CameraRawMixerSettings.names[index])。")
            }
        }
    }

    private var pointColor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    session.filterEdit?.samplesPointColor.toggle()
                    session.brushRevision += 1
                } label: { Image(systemName: "eyedropper") }
                .help("点击图片保存一种颜色。最多八种。")
                .tint(edit?.samplesPointColor == true ? Color.accentColor : Color.secondary)
                ForEach(raw.mixer.points.indices, id: \.self) { index in
                    let point = raw.mixer.points[index]
                    Button { session.filterEdit?.cameraRawPointIndex = index } label: {
                        Circle().fill(Color(hue: point.hue / 360, saturation: point.saturation, brightness: point.luminance))
                            .frame(width: 16, height: 16)
                            .overlay { Circle().stroke(edit?.cameraRawPointIndex == index ? Color.white : Color.clear, lineWidth: 2) }
                    }
                    .buttonStyle(.plain)
                    .help("选择这个拾取的颜色。")
                }
            }
            if raw.mixer.points.indices.contains(edit?.cameraRawPointIndex ?? 0) {
                pointSlider("色相偏移", \.hueShift, help: "让拾取的颜色在色轮上移动。",
                           track: .hue(raw.mixer.points[edit?.cameraRawPointIndex ?? 0].hue))
                pointSlider("饱和度偏移", \.saturationShift, help: "让拾取的颜色更强或更安静。",
                           track: .saturation(raw.mixer.points[edit?.cameraRawPointIndex ?? 0].hue))
                pointSlider("亮度偏移", \.luminanceShift, help: "让拾取的颜色更亮或更暗。",
                           track: .luminance(raw.mixer.points[edit?.cameraRawPointIndex ?? 0].hue))
                pointSlider("色相范围", \.hueRange, help: "调整在色相上的作用范围。", range: 5...180, reset: 30)
                pointSlider("饱和度范围", \.saturationRange, help: "调整在饱和度上的作用范围。", range: 0.05...1, reset: 0.4)
                pointSlider("亮度范围", \.luminanceRange, help: "调整在亮度上的作用范围。", range: 0.05...1, reset: 0.4)
                Toggle("可视化范围", isOn: Binding(get: { raw.mixer.points[edit?.cameraRawPointIndex ?? 0].visualize },
                                                       set: { value in updatePoint { $0.visualize = value } }))
                    .help("调暗此颜色范围外的图片。按确定时不保留。")
            }
        }
    }

    private func familyTrack(_ index: Int, _ key: WritableKeyPath<CameraRawMixerSettings, [Double]>) -> CameraRawSliderTrack {
        let hue = CameraRawMixerSettings.centers[index]
        if key == \.saturation { return .saturation(hue) }
        if key == \.luminance { return .luminance(hue) }
        return .hue(hue)
    }

    private func pointSlider(_ title: String, _ key: WritableKeyPath<CameraRawPointColor, Double>, help: String,
                             range: ClosedRange<Double> = -100...100, reset: Double = 0, track: CameraRawSliderTrack = .plain) -> some View {
        let index = edit?.cameraRawPointIndex ?? 0
        return HStack {
            Text(title).frame(width: 110, alignment: .leading).help(help)
            CameraRawSlider(value: raw.mixer.points[index][keyPath: key], range: range, track: track, help: help,
                            onChange: { value in updatePoint { $0[keyPath: key] = value } },
                            onReset: { updatePoint { $0[keyPath: key] = reset } })
        }
    }

    private func updatePoint(_ change: (inout CameraRawPointColor) -> Void) {
        let index = edit?.cameraRawPointIndex ?? 0
        update {
            guard $0.mixer.points.indices.contains(index) else { return }
            change(&$0.mixer.points[index])
        }
    }

    private func update(_ change: (inout CameraRawSettings) -> Void) {
        var settings = session.filterEdit?.settings ?? FilterSettings()
        change(&settings.cameraRaw)
        session.updateFilter(settings, preview: session.filterEdit?.preview ?? true)
    }
}

struct CameraRawGradingControls: View {
    @Bindable var session: EditorSession
    private var raw: CameraRawSettings { session.filterEdit?.settings.cameraRaw ?? CameraRawSettings() }
    private var page: CameraRawGradePage { session.filterEdit?.cameraRawGradePage ?? .threeWay }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Five segments spelled out want 453 points and the docked panel has 374, so the
            // choice is a menu rather than a row that runs past the panel's edge.
            Picker("分级", selection: Binding(get: { page }, set: { session.filterEdit?.cameraRawGradePage = $0 })) {
                ForEach(CameraRawGradePage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .help("三向显示阴影、中间调和高光。其他选项显示一个色轮。")
            if page == .threeWay {
                HStack(spacing: 30) {
                    wheel("阴影", \.shadows)
                    wheel("中间调", \.midtones)
                    wheel("高光", \.highlights)
                }
            } else {
                wheel(page.rawValue, pageKey)
            }
            slider("混合", raw.grading.blending, 0...100, 50, "控制三个色调色轮的叠加程度。") { value in
                update { $0.grading.blending = value }
            }
            slider("平衡", raw.grading.balance, -100...100, 0, "将色轮向阴影或高光偏移。") { value in
                update { $0.grading.balance = value }
            }
        }
    }

    private var pageKey: WritableKeyPath<CameraRawGradingSettings, CameraRawGradeWheel> {
        switch page {
        case .threeWay, .shadows: return \.shadows
        case .midtones: return \.midtones
        case .highlights: return \.highlights
        case .global: return \.global
        }
    }

    private func wheel(_ title: String, _ key: WritableKeyPath<CameraRawGradingSettings, CameraRawGradeWheel>) -> some View {
        let wheel = raw.grading[keyPath: key]
        return VStack(spacing: 4) {
            Text(title).font(.caption).help("在色轮内拖动。角度设置色相，距离设置饱和度。")
            GradeWheel(hue: wheel.hue, saturation: wheel.saturation,
                       set: { hue, saturation in update { $0.grading[keyPath: key].hue = hue; $0.grading[keyPath: key].saturation = saturation } },
                       reset: { update { $0.grading[keyPath: key].hue = 0; $0.grading[keyPath: key].saturation = 0 } })
                .frame(width: 86, height: 86)
            Text("\(Int(wheel.hue.rounded()))°  \(Int(wheel.saturation.rounded()))")
                .font(.caption2.monospacedDigit())
                .help("此色轮的色相和饱和度。")
            // A slider asks for 120 on its own, which put three columns past the panel's edge.
            CameraRawSlider(value: wheel.luminance, range: -100...100, track: .plain, help: "此色轮增加的亮度。",
                            onChange: { value in update { $0.grading[keyPath: key].luminance = value } },
                            onReset: { update { $0.grading[keyPath: key].luminance = 0 } })
                .frame(width: 96)
        }
    }

    private func slider(_ title: String, _ value: Double, _ range: ClosedRange<Double>, _ reset: Double, _ help: String, set: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(title).frame(width: 78, alignment: .leading).help(help)
            CameraRawSlider(value: value, range: range, track: .plain, help: help, onChange: set, onReset: { set(reset) })
        }
    }

    private func update(_ change: (inout CameraRawSettings) -> Void) {
        var settings = session.filterEdit?.settings ?? FilterSettings()
        change(&settings.cameraRaw)
        session.updateFilter(settings, preview: session.filterEdit?.preview ?? true)
    }
}

private struct GradeWheel: View {
    var hue: Double
    var saturation: Double
    var set: (Double, Double) -> Void
    var reset: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let radius = side / 2 - 6
            let angle = hue * Double.pi / 180
            let distance = CGFloat(saturation / 100) * radius
            ZStack {
                // Hue runs counterclockwise from red at the right, as the drag and the dot measure it. SwiftUI's
                // angular gradient runs clockwise, so its stops go through the hues backwards.
                Circle().fill(AngularGradient(gradient: Gradient(colors: stride(from: 360.0, through: 0, by: -30).map {
                    Color(hue: $0.truncatingRemainder(dividingBy: 360) / 360, saturation: 1, brightness: 1)
                }), center: .center))
                    .opacity(0.85)
                Circle().stroke(.white.opacity(0.8), lineWidth: 1)
                Circle().fill(.white).frame(width: 10, height: 10)
                    .offset(x: CGFloat(cos(angle) * distance), y: CGFloat(-sin(angle) * distance))
            }
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let dx = value.location.x - side / 2
                let dy = side / 2 - value.location.y
                var degrees = Double(atan2(dy, dx)) * 180 / .pi
                if degrees < 0 { degrees += 360 }
                set(degrees, min(100, Double(hypot(dx, dy) / radius) * 100))
            })
            .onTapGesture(count: 2) { reset() }
            .help("拖动设置色相和饱和度。双击重置此色轮。")
        }
    }
}
