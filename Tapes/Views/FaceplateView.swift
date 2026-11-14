import SwiftUI
import GridKit
import TapeEngine

/// The whole instrument. One screen, laid out on the column grid:
/// a single column of sections on compact widths, two panes on regular widths,
/// and three panes when the height is compact (iPhone on its side).
struct FaceplateView: View {
    @Environment(Recorder.self) private var recorder
    @Environment(\.horizontalSizeClass) private var widthClass
    @Environment(\.verticalSizeClass) private var heightClass
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("showsGrid") private var showsGrid = false
    @AppStorage("theme") private var storedTheme = ""
    /// `-showTapes` opens the tapes sheet at launch, for checking it in a simulator.
    /// The window's size, to tell a tablet from iPhone Duo's inner display. Until it is measured,
    /// the screen's own size stands in, so the first frame is already the right build.
    @State private var screen = UIScreen.main.bounds.size
    @State private var showsLibrary = ProcessInfo.processInfo.arguments.contains("-showTapes")

    var body: some View {
        @Bindable var recorder = recorder
        let theme = Theme.resolve(stored: storedTheme, system: systemScheme)
        // The palette is read directly by every part, so set it before any of them is built…
        let _ = Palette.current = theme.colors
        // The larger build is for iPad. iPhone Duo's inner display is regular both ways too, but it
        // is the size of two phones, not of a tablet: it keeps the phone's sizes and gets the mixer.
        let roomy = min(screen.width, screen.height) >= Metrics.largeFrom
        let metrics = Metrics(large: widthClass == .regular && heightClass == .regular && roomy)
        // The two panes of the regular layout draw their own grids.
        let paned = widthClass == .regular && heightClass != .compact
        GridContainer(showsOverlay: showsGrid && !paned, compactHeight: heightClass == .compact) { grid in
            Group {
                if heightClass == .compact {
                    landscape(grid)
                } else if widthClass == .regular {
                    regular(grid, metrics)
                } else {
                    compact
                }
            }
            .id(theme)      // …and build them again when the finish changes.
            .environment(\.metrics, metrics)
        }
        .background(Palette.surface.ignoresSafeArea())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { screen = $0 }
        .preferredColorScheme(storedTheme.isEmpty ? nil : theme.scheme)
        // On iPad the status bar prints the app's name at the top left. The faceplate carries no title.
        .statusBarHidden(metrics.large)
        .sheet(isPresented: $showsLibrary) { LibrarySheet() }
        .sheet(item: $recorder.exportItem) { item in
            ShareSheet(url: item.url)
        }
        .alert("Microphone is off", isPresented: $recorder.micDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Vibe Tapes needs the microphone to record. You can allow it in Settings.")
        }
    }

    /// One column of sections. The stack's height is snapped to 8pt and hangs from the top,
    /// so every section edge, the dial's included, is on the baseline grid.
    private var compact: some View {
        GeometryReader { geo in
            let metrics = Metrics(short: geo.size.height < Metrics.shortBelow)
            VStack(spacing: metrics.gap) {
                HeaderBar(showsLibrary: $showsLibrary).gridChecked()
                DisplayView().gridChecked()
                TapeScaleView().gridChecked()
                // The readouts, the wheels and keys, the dial, the tracks, the transport:
                // a little more air before each section of keys than between the readouts.
                ControlRow().padding(.top, metrics.sectionLead)
                DialView().gridChecked()
                TrackKeys().padding(.top, metrics.sectionLead)
                TransportRow().padding(.top, metrics.sectionLead)
            }
            .frame(width: geo.size.width, height: Rhythm.snapDown(geo.size.height - Rhythm.u(4), to: Rhythm.u(2)))
            .padding(.top, Rhythm.u(2))
            .environment(\.metrics, metrics)
        }
    }

    /// iPhone on its side: a `RowGrid` of four bands shared by every pane.
    /// Left half: header and display on bands 1–2, tape scale on band 3, wheels and keys on band 4.
    /// Next three modules: the dial on bands 1–3, the transport on band 4.
    /// Last module: one track key per band.
    /// The block is centred on the screen's full height, home indicator included, so the space
    /// above and below it looks equal.
    private func landscape(_ grid: ColumnGrid) -> some View {
        GeometryReader { geo in
            let phone = Metrics()
            let rows = RowGrid.fitting(height: geo.size.height - Rhythm.u(4), rows: 4, minimum: Rhythm.u(16), module: Rhythm.unit)
            let slack = geo.size.height + geo.safeAreaInsets.bottom - rows.height
            let room = max(Rhythm.u(2), Rhythm.snapDown(geo.size.height - rows.height))
            let top = min(max(Rhythm.u(2), Rhythm.snapDown(slack / 2)), room)
            let module = ColumnGrid.module
            HStack(alignment: .top, spacing: grid.gutter) {
                VStack(spacing: rows.gap) {
                    HeaderBar(showsLibrary: $showsLibrary).gridChecked()
                    DisplayView(height: rows.span(2) - phone.header - rows.gap).gridChecked()
                    TapeScaleView(height: rows.rowHeight).gridChecked()
                    ControlRow(faceHeight: rows.rowHeight - Rhythm.u(2) - phone.legendLine)
                }
                .frame(width: grid.span(4 * module))
                VStack(spacing: rows.gap) {
                    DialView()
                        .frame(height: rows.span(3))
                        .gridChecked()
                    TransportRow(units: [1, 1, 1], height: rows.rowHeight)
                }
                .frame(width: grid.span(3 * module))
                TrackKeys(axis: .vertical)
                    .frame(width: grid.span(module))
            }
            .frame(height: rows.height)
            .padding(.top, top)
        }
    }

    /// iPad, and iPhone Duo open. On iPad everything is built larger (`Metrics.large`). The two
    /// panes change with the shape of the screen so neither is left with empty space:
    /// upright, the left pane takes two thirds for a large dial and carries the wheels and keys,
    /// and the mixer is a narrow column; on its side, the panes are equal and the wheels and keys
    /// sit over the mixer. The height is snapped to 8pt and hangs from the top.
    ///
    /// Each pane is a grid of its own, cut from the faceplate's columns. While a fold runs down
    /// the screen (iPhone Duo half open), the panes move apart to keep to their own sides of it,
    /// twelve columns each, and nothing is drawn across the fold. The move is sprung
    /// (`Motion.fold`): the same parts slide and resize, none are replaced.
    private func regular(_ grid: ColumnGrid, _ metrics: Metrics) -> some View {
        GeometryReader { geo in
            let upright = geo.size.height > geo.size.width
            let band = Fold.band(in: geo)
            let pad = Rhythm.u(6)
            // A fold across the screen breaks the rows; one down the screen parts the panes.
            let rows = band.flatMap { $0.width > $0.height ? Fold.Rows(band: $0, top: pad) : nil }
            let fold = rows == nil ? band : nil
            let columns = fold != nil || !upright ? grid.columns / 2 : grid.columns * 2 / 3
            let left = fold?.minX ?? grid.span(columns)
            let gap = fold?.width ?? grid.gutter
            let right = geo.size.width - left - gap
            HStack(alignment: .top, spacing: gap) {
                GridContainer(grid: Fold.grid(columns: columns, width: left), showsOverlay: showsGrid) { _ in
                    dialPane(metrics, wheels: upright, rows: rows)
                }
                .frame(width: left)
                GridContainer(grid: Fold.grid(columns: grid.columns - columns, width: right), showsOverlay: showsGrid) { _ in
                    mixerPane(metrics, wheels: !upright, rows: rows)
                }
                .frame(width: right)
            }
            .frame(width: geo.size.width, height: Rhythm.snapDown(geo.size.height - Rhythm.u(12), to: Rhythm.u(2)), alignment: .topLeading)
            .padding(.top, pad)
            .animation(reduceMotion ? nil : Motion.fold, value: band)
        }
    }

    /// The readouts above, the dial and transport below. With a fold across the screen the upper
    /// group is given the height above the fold, and the lower group starts beneath it.
    private func dialPane(_ metrics: Metrics, wheels: Bool, rows: Fold.Rows?) -> some View {
        VStack(spacing: rows?.gap ?? metrics.gap) {
            VStack(spacing: metrics.gap) {
                HeaderBar(showsLibrary: $showsLibrary).gridChecked()
                DisplayView().gridChecked()
                TapeScaleView().gridChecked()
                if wheels { ControlRow(units: [5, 5, 2, 2, 2]).padding(.top, metrics.sectionLead) }
            }
            .frame(height: rows?.above, alignment: .top)
            VStack(spacing: metrics.gap) {
                DialView().gridChecked()
                TransportRow().padding(.top, metrics.sectionLead)
            }
        }
    }

    private func mixerPane(_ metrics: Metrics, wheels: Bool, rows: Fold.Rows?) -> some View {
        let lead = metrics.header + metrics.gap
        return VStack(spacing: metrics.gap) {
            if wheels { ControlRow() }
            // The strips start under the header's line, so the fold is that much nearer their top.
            MixerView(rows: wheels ? nil : rows.map { Fold.Rows(above: $0.above - lead, gap: $0.gap) }).gridChecked()
        }
        .padding(.top, lead)
    }
}

/// The fold of a half-open iPhone Duo, as the system reports it.
enum Fold {
    /// The band to keep clear, in the proxy's own coordinates: the fold and the margin the system
    /// asks for on either side. It runs down the screen when the device is held the way it opens,
    /// and across it when the device is turned upright. Nil when there is no fold, or when the
    /// device is fully open (the region is then inactive).
    static func band(in geo: GeometryProxy) -> CGRect? {
        #if DEBUG
        // `-fold 0.5` stands in for a fold 40pt wide at that fraction of the longer side.
        let fake = UserDefaults.standard.double(forKey: "fold")
        if fake > 0 {
            let size = geo.size
            return usable(size.width > size.height
                ? CGRect(x: size.width * fake - 20, y: 0, width: 40, height: size.height)
                : CGRect(x: 0, y: size.height * fake - 20, width: size.width, height: 40), in: geo)
        }
        #endif
        guard #available(iOS 27.1, *) else { return nil }
        return geo.reservedRegions(kind: .division).lazy.compactMap { usable($0.frame, in: geo) }.first
    }

    /// Only a fold that leaves a workable part of the faceplate on both sides.
    private static func usable(_ band: CGRect, in geo: GeometryProxy) -> CGRect? {
        if band.height > band.width {
            let pane = Rhythm.u(60)
            return band.minX >= pane && geo.size.width - band.maxX >= pane ? band : nil
        }
        // Above: header, display, tape scale, wheels and keys, 360pt at the phone's sizes with the
        // pane's top padding. Below: the dial and the transport.
        return band.minY >= Rhythm.u(90) && geo.size.height - band.maxY >= Rhythm.u(80) ? band : nil
    }

    /// The grid of one pane: its columns fill it. The faceplate's margins are already outside it.
    static func grid(columns: Int, width: CGFloat) -> ColumnGrid {
        ColumnGrid(columns: columns, margin: 0, gutter: Rhythm.u(4), width: width)
    }

    /// A fold across the screen, measured down a pane: the height above it and the height to
    /// leave clear, both on the baseline grid.
    struct Rows: Equatable {
        var above: CGFloat
        var gap: CGFloat

        init(above: CGFloat, gap: CGFloat) {
            self.above = above
            self.gap = gap
        }

        /// `top` is where the pane starts in the band's coordinates.
        init(band: CGRect, top: CGFloat) {
            above = Rhythm.snapDown(band.minY - top)
            gap = (Rhythm.snapDown(band.maxY - top) + Rhythm.unit) - above
        }
    }
}

// MARK: Header

/// A gear and a word printed on the faceplate, flush with the margins.
struct HeaderBar: View {
    @Environment(Recorder.self) private var recorder
    @Environment(\.metrics) private var metrics
    @Binding var showsLibrary: Bool

    var body: some View {
        HStack(spacing: 0) {
            Button { showsLibrary = true } label: {
                // A quiet gear, in the colour of the legends: the tapes and the few settings live behind it.
                Image(systemName: "gearshape")
                    .font(.system(size: metrics.glyph - 1, weight: .regular))
                    .foregroundStyle(Palette.legend)
            }
            .accessibilityLabel("Tapes and settings")
            .buttonStyle(TextKeyStyle(alignment: .leading))
            Spacer(minLength: 0)
            Button("export") { recorder.export() }
                .buttonStyle(TextKeyStyle(alignment: .trailing))
                .disabled(recorder.tape.duration == 0 || recorder.isBusy)
        }
        .frame(height: metrics.header)
    }
}

/// A word printed on the faceplate that can be pressed. The word sits against a margin;
/// the touch area extends inwards from it.
private struct TextKeyStyle: ButtonStyle {
    var alignment: Alignment
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.metrics) private var metrics

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .faceType(.caption)
            .foregroundStyle(Palette.label)
            .opacity(!isEnabled ? 0.3 : configuration.isPressed ? 0.5 : 1)
            .frame(minWidth: Rhythm.u(16), minHeight: Rhythm.u(11), alignment: alignment)
            .frame(height: metrics.header)
            .contentShape(Rectangle())
            .animation(Motion.lamp, value: configuration.isPressed)
    }
}

// MARK: Wheels and function keys

/// Speed and tempo wheels on a module each (three fine columns); click, cue and loop keys on
/// two fine columns each. Twelve columns in all, so every control starts and ends on the grid.
struct ControlRow: View {
    @Environment(Recorder.self) private var recorder
    @Environment(\.columnGrid) private var grid
    @Environment(\.metrics) private var metrics
    /// Columns each control takes. Twelve by default; sixteen where the pane is wider.
    var units = [3, 3, 2, 2, 2]
    /// Height of the wheels and key faces. The legends sit 8pt beneath. Defaults to the metrics'.
    var faceHeight: CGFloat?

    /// Tempo holds at every ten beats.
    private static let tempoDetents: [Double] = stride(from: 50.0, through: 230.0, by: 10).map {
        ($0 - Recorder.tempoRange.lowerBound) / (Recorder.tempoRange.upperBound - Recorder.tempoRange.lowerBound)
    }

    var body: some View {
        @Bindable var recorder = recorder
        let faceHeight = faceHeight ?? metrics.face
        UnitRow(units: units, spacing: grid.gutter) {
            Wheel(
                legend: "speed",
                value: $recorder.speedPosition,
                rest: 0.5,
                detents: [0.25, 0.5, 0.75],     // half speed, tape speed, double speed
                length: faceHeight,
                valueText: String(format: "%.2f times", recorder.tape.speed),
                onReset: { recorder.resetSpeed() }
            )
            .gridChecked()
            Wheel(
                legend: "tempo",
                value: $recorder.tempoPosition,
                travel: 400,
                detents: Self.tempoDetents,
                detentWidth: 12,
                length: faceHeight,
                valueText: "\(Int(recorder.tape.bpm)) beats per minute"
            )
            .gridChecked()
            LampKey(legend: "click", lamp: recorder.tape.click, hint: "Turns the metronome on or off", faceHeight: faceHeight) {
                recorder.toggleClick()
            }
            .gridChecked()
            LampKey(legend: "cue", lamp: false, hint: "Marks this position, or clears the mark here", faceHeight: faceHeight) {
                recorder.toggleCue()
            }
            .gridChecked()
            LampKey(
                legend: "loop",
                lamp: recorder.isLooping,
                hint: "Repeats the section of tape between the marks on either side of the playhead",
                faceHeight: faceHeight
            ) {
                recorder.toggleLoop()
            }
            .gridChecked()
        }
    }
}

// MARK: Track keys (compact)

/// Four track keys. Tap selects the track that records. Drag up or down for level,
/// sideways for pan. Touch and hold for mute, solo and erase.
struct TrackKeys: View {
    @Environment(\.columnGrid) private var grid
    /// A row of keys one column each, or a stack of keys in a single column.
    var axis: Axis = .horizontal

    var body: some View {
        if axis == .horizontal {
            HStack(spacing: grid.gutter) { keys }
                .frame(height: Rhythm.u(18))
        } else {
            VStack(spacing: Rhythm.u(4)) { keys }
        }
    }

    private var keys: some View {
        ForEach(0..<TapeCore.trackCount, id: \.self) { TrackKey(index: $0).gridChecked() }
    }
}

private struct TrackKey: View {
    @Environment(Recorder.self) private var recorder
    let index: Int

    @State private var axis: Axis?
    @State private var start = 0.0

    var body: some View {
        let mix = recorder.tape.tracks[index]
        let selected = recorder.selectedTrack == index
        let recording = selected && recorder.transport == .recording
        let silenced = mix.mute || (recorder.tape.tracks.contains(where: \.solo) && !mix.solo)

        KeyFace(down: axis != nil)
            .overlay(alignment: .topLeading) {
                Text("\(index + 1)")
                    .faceType(.numeral)
                    .foregroundStyle(Palette.ink.opacity(silenced ? 0.3 : 1))
                    .padding(.leading, Rhythm.u(4))
                    .padding(.top, Rhythm.u(2))
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: Rhythm.u(1.5)) {
                    Lamp(on: selected, color: recording ? Palette.signal : Palette.lamp)
                    if mix.solo { Legend("solo", onKey: true) } else if mix.mute { Legend("mute", onKey: true) }
                }
                .padding(.leading, Rhythm.u(4))
                .frame(height: Rhythm.u(4))
                .padding(.bottom, Rhythm.u(2))
            }
            .overlay(alignment: .trailing) {
                LevelSlot(volume: mix.volume, level: recorder.levels.tracks[index], hot: recording)
                    .padding(.vertical, Rhythm.u(2))
                    .padding(.trailing, Rhythm.u(4))
            }
            .offset(y: axis != nil ? 1.5 : 0)
            .animation(Motion.press, value: axis != nil)
            .contentShape(Rectangle())
            .onTapGesture { recorder.select(track: index) }
            .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.7), trigger: selected) { _, now in now && Haptics.enabled }
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { drag in
                        if axis == nil {
                            axis = abs(drag.translation.height) >= abs(drag.translation.width) ? .vertical : .horizontal
                            start = axis == .vertical ? mix.volume : mix.pan
                        }
                        if axis == .vertical {
                            recorder.setVolume(index, start - drag.translation.height / 160)
                        } else {
                            recorder.setPan(index, start + drag.translation.width / 100)
                        }
                    }
                    .onEnded { _ in axis = nil }
            )
            .contextMenu { TrackMenu(index: index) }
            .accessibilityElement()
            .accessibilityLabel("Track \(index + 1)")
            .accessibilityValue("level \(Int((mix.volume / TrackMix.unity * 100).rounded())) percent" + (mix.mute ? ", muted" : "") + (mix.solo ? ", solo" : ""))
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAdjustableAction { direction in
                recorder.setVolume(index, mix.volume + (direction == .increment ? 0.05 : -0.05))
            }
    }
}

private struct TrackMenu: View {
    @Environment(Recorder.self) private var recorder
    let index: Int

    var body: some View {
        let mix = recorder.tape.tracks[index]
        Button(mix.mute ? "Unmute" : "Mute", systemImage: mix.mute ? "speaker.wave.2" : "speaker.slash") {
            recorder.toggleMute(index)
        }
        Button(mix.solo ? "Solo off" : "Solo", systemImage: "headphones") {
            recorder.toggleSolo(index)
        }
        Button("Centre pan", systemImage: "arrow.left.and.right") {
            recorder.setPan(index, 0)
        }
        if recorder.hasAudio(index) {
            Button("Erase track \(index + 1)", systemImage: "trash", role: .destructive) {
                recorder.erase(track: index)
            }
        }
    }
}

/// A slot in a track key: the grey fill is the fader position, the dark fill the live level.
private struct LevelSlot: View {
    var volume: Double
    var level: Float
    var hot: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Capsule().fill(Palette.recess)
                Capsule()
                    .fill(Palette.inkSecondary.opacity(0.45))
                    .frame(height: max(4, geo.size.height * volume))
                Capsule()
                    .fill(hot ? Palette.signal : Palette.ink)
                    .frame(height: geo.size.height * volume * meterPosition(level))
                    .animation(.linear(duration: 0.05), value: level)
            }
        }
        .frame(width: Rhythm.u(2))
    }
}

// MARK: Mixer (regular)

/// Four channel strips, shown instead of the track keys when there is room.
struct MixerView: View {
    @Environment(\.columnGrid) private var grid
    /// A fold across the strips: the select key and pan wheel stay above it, the fader and keys below.
    var rows: Fold.Rows?

    var body: some View {
        HStack(alignment: .top, spacing: grid.gutter) {
            ForEach(0..<TapeCore.trackCount, id: \.self) { ChannelStrip(index: $0, rows: rows).gridChecked(rows: false) }
        }
    }
}

/// Select key, pan wheel, fader, mute and solo, top to bottom. The fader is never longer than a
/// hand wants (`maxThrow`); where the strip is taller than that, the extra height opens the
/// gaps between the parts evenly instead of stretching the fader.
private struct ChannelStrip: View {
    @Environment(Recorder.self) private var recorder
    @Environment(\.metrics) private var metrics
    let index: Int
    var rows: Fold.Rows?

    private let maxThrow = Rhythm.u(120)
    private let keyFace = Rhythm.u(12)

    var body: some View {
        GeometryReader { geo in
            let labelledKey: CGFloat = keyFace + Rhythm.u(2) + metrics.legendLine
            let fixed: CGFloat = metrics.face + metrics.labelledFace + 2 * labelledKey
            let spare: CGFloat = (geo.size.height - fixed - maxThrow) / 4
            let gap: CGFloat = rows == nil ? max(metrics.gap, Rhythm.snapDown(spare, to: Rhythm.u(2))) : metrics.gap
            let flat: CGFloat = geo.size.height - fixed - 4 * gap
            let folded: CGFloat = geo.size.height - (rows?.above ?? 0) - (rows?.gap ?? 0) - 2 * labelledKey - 2 * gap
            let faderHeight: CGFloat = max(Rhythm.u(20), rows == nil ? flat : folded)
            VStack(spacing: rows?.gap ?? gap) {
                VStack(spacing: gap) {
                    selectKey
                    panWheel
                }
                .frame(height: rows?.above, alignment: .top)
                VStack(spacing: gap) {
                    Fader(
                        value: Binding(get: { mix.volume }, set: { recorder.setVolume(index, $0) }),
                        level: recorder.levels.tracks[index],
                        unity: TrackMix.unity,
                        label: "Track \(index + 1) level"
                    )
                    .frame(height: faderHeight)
                    // One above the other, so each is a full strip wide: two side by side would be
                    // narrower than a fingertip.
                    LampKey(legend: "mute", lamp: mix.mute, faceHeight: keyFace) { recorder.toggleMute(index) }
                    LampKey(legend: "solo", lamp: mix.solo, faceHeight: keyFace) { recorder.toggleSolo(index) }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var mix: TrackMix { recorder.tape.tracks[index] }

    private var selectKey: some View {
        let selected = recorder.selectedTrack == index
        let recording = recorder.transport == .recording && selected
        return Button {
            recorder.select(track: index)
        } label: {
            HStack(spacing: 0) {
                Text("\(index + 1)").faceType(.numeral).foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                Lamp(on: selected, color: recording ? Palette.signal : Palette.lamp)
            }
            .padding(.horizontal, Rhythm.u(2))
        }
        .buttonStyle(KeyStyle())
        .frame(height: metrics.face)
        .accessibilityLabel("Track \(index + 1)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu { TrackMenu(index: index) }
    }

    private var panWheel: some View {
        let pan = mix.pan
        let spoken = pan == 0 ? "centre" : "\(Int(abs(pan) * 100)) \(pan < 0 ? "left" : "right")"
        return Wheel(
            legend: "pan",
            value: Binding(get: { (pan + 1) / 2 }, set: { recorder.setPan(index, $0 * 2 - 1) }),
            axis: .horizontal,
            travel: 160,
            rest: 0.5,
            detents: [0.5],
            length: metrics.face,
            valueText: spoken,
            onReset: { recorder.setPan(index, 0) }
        )
    }
}

// MARK: Transport

/// Return, record and play. Upright, play takes two modules: it is the key the thumb looks for.
struct TransportRow: View {
    @Environment(Recorder.self) private var recorder
    @Environment(\.columnGrid) private var grid
    @Environment(\.metrics) private var metrics
    var units = [1, 1, 2]
    /// Defaults to the height the faceplate's size calls for.
    var height: CGFloat?

    var body: some View {
        let recording = recorder.transport == .recording
        let rolling = recorder.transport != .stopped
        let dot = metrics.glyph + 4
        UnitRow(units: units, spacing: grid.gutter) {
            Button { recorder.returnToStart() } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: metrics.glyph - 1))
                    .foregroundStyle(Palette.ink)
            }
            .buttonStyle(KeyStyle())
            .gridChecked()
            .accessibilityLabel("Return to start")

            Button { recorder.toggleRecord() } label: {
                Circle()
                    .fill(Palette.signal)
                    .frame(width: dot, height: dot)
                    .scaleEffect(recording ? 0.7 : 1)
                    .animation(Motion.settle, value: recording)
            }
            .buttonStyle(KeyStyle())
            .overlay(alignment: .top) {
                Lamp(on: recording, color: Palette.signal).padding(.top, Rhythm.u(2)).allowsHitTesting(false)
            }
            .gridChecked()
            .accessibilityLabel(recording ? "Stop recording" : "Record on track \(recorder.selectedTrack + 1)")

            Button { recorder.togglePlay() } label: {
                Image(systemName: rolling ? "stop.fill" : "play.fill")
                    .font(.system(size: metrics.glyph + 1))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(KeyStyle())
            .gridChecked()
            .accessibilityLabel(rolling ? "Stop" : "Play")
        }
        .frame(height: height ?? metrics.transport)
    }
}
