#if (DEBUG && !APP_STORE) || SIDEY_REALS
import SwiftUI

struct RealsEditorView: View {
    @ObservedObject var editor: RealsEditor
    @ObservedObject private var player: RealsPlayer
    @State private var selectedTab = 0
    @State private var showsImport = false
    @State private var confirmsExample = false

    init(editor: RealsEditor) {
        self.editor = editor
        player = editor.player
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                settings.frame(minWidth: 300, idealWidth: 320, maxWidth: 370)
                workspace.frame(minWidth: 620)
            }
            Divider()
            playbackBar
        }
        .frame(minWidth: 1000, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Color(red: 0.45, green: 0.49, blue: 0.85))
        .alert("확인이 필요해요", isPresented: Binding(get: { editor.error != nil }, set: { if !$0 { editor.error = nil } })) {
            Button("확인") { editor.error = nil }
        } message: { Text(editor.error ?? "") }
        .confirmationDialog("지금 내용을 수업 대화 예제로 바꿀까요?", isPresented: $confirmsExample) {
            Button("예제로 바꾸기", role: .destructive) { editor.project = .example }
        } message: { Text("현재 내용을 보관하려면 먼저 파일로 저장하세요.") }
        .sheet(isPresented: $showsImport) { RealsImportSheet(editor: editor) }
        .onDisappear { editor.shutdown() }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "film.stack.fill").font(.system(size: 28)).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text("sidey-reals").font(.system(size: 23, weight: .bold, design: .rounded))
                Text("대화와 액션을 짜고, 한 장면으로 찍어요.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(editor.fileStatus).font(.caption).foregroundStyle(.secondary)
            Button("불러오기", systemImage: "folder") { editor.openFile() }.disabled(player.isEditingLocked)
            Button("파일 저장", systemImage: "square.and.arrow.down") { editor.saveFile() }
                .keyboardShortcut("s", modifiers: .command)
        }.padding(20)
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("프로젝트", "01")
                    TextField("촬영 제목", text: $editor.project.title).textFieldStyle(.roundedBorder)
                    Button("수업 대화 예제 불러오기") { confirmsExample = true }.font(.caption)
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        sectionTitle("출연자", "02")
                        Spacer()
                        Stepper("\(editor.project.participants.count)명", onIncrement: { editor.addParticipant() }, onDecrement: {
                            if let last = editor.project.participants.last { editor.removeParticipant(last.id) }
                        }).fixedSize()
                    }
                    ForEach($editor.project.participants) { $person in
                        RealsParticipantRow(person: $person, onRemove: { editor.removeParticipant(person.id) })
                    }
                    Text("최대 12명 · 대화 붙여넣기에서는 유저1, 유저2 순서로 연결돼요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("타이밍", "03")
                    secondsField("기본 채팅 간격", value: $editor.project.defaultInterval)
                    secondsField("시작 전 준비", value: $editor.project.countdown)
                    secondsField("말풍선 유지", value: $editor.project.bubbleLifetime)
                    secondsField("마지막 여운", value: $editor.project.endingHold)
                    Text("개별 간격을 설정하지 않은 채팅에 기본 간격을 적용해요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("촬영 화면", "04")
                    HStack {
                        Text("오버레이 폭")
                        Spacer()
                        TextField("960", value: $editor.project.overlayWidth, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 70)
                        Text("pt").foregroundStyle(.secondary)
                    }
                    Toggle("캐릭터 위치 고정", isOn: $editor.project.fixedPositions)
                    Toggle("피격 효과음", isOn: $editor.project.soundEnabled)
                    Text("화면 아래에 투명하게 표시해요. 인원이 많으면 폭을 넓혀주세요. 확대는 실제 앱처럼 7배예요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20)
        }.disabled(player.isEditingLocked)
    }

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Picker("편집 항목", selection: $selectedTab) {
                    Text("채팅 \(editor.project.lines.count)").tag(0)
                    Text("액션 \(editor.project.actions.count)").tag(1)
                }.pickerStyle(.segmented).frame(width: 250)
                Spacer()
                if selectedTab == 0 {
                    Button("대화 붙여넣기", systemImage: "doc.on.clipboard") { showsImport = true }
                    Button("채팅 추가", systemImage: "plus") { editor.addLine() }
                } else {
                    Button("액션 추가", systemImage: "plus") { editor.addAction() }
                }
            }.disabled(player.isEditingLocked)
            if let issue = editor.project.issues.first {
                Label(issue, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange)
            }
            if selectedTab == 0 {
                chatList
            } else {
                actionList
            }
        }.padding(20)
    }

    private var chatList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("위에서 아래로 재생 · 간격은 이 채팅이 나온 뒤 다음 채팅까지의 시간이에요.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 10) {
                    if editor.project.lines.isEmpty {
                        ContentUnavailableView("아직 채팅이 없어요", systemImage: "bubble.left.and.bubble.right",
                                               description: Text("채팅을 추가하거나 대화를 통째로 붙여넣으세요."))
                    }
                    ForEach($editor.project.lines) { $line in
                        RealsChatRow(line: $line, people: editor.project.participants,
                            number: (editor.project.lines.firstIndex(where: { $0.id == line.id }) ?? 0) + 1,
                            defaultInterval: editor.project.defaultInterval,
                            onMove: { editor.moveLine(line.id, by: $0) },
                            onDelete: { editor.project.lines.removeAll { $0.id == line.id } })
                    }
                }.padding(.bottom, 12)
            }.disabled(player.isEditingLocked)
        }
    }

    private var actionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("첫 채팅이 나오는 순간이 0초예요. 시작 = 종료면 한 번, 다르면 구간 안에서 반복해요.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 12) {
                    if editor.project.actions.isEmpty {
                        ContentUnavailableView("움직임을 더해보세요", systemImage: "sparkles",
                                               description: Text("10~15초 말랑공 던지기, 20초에 커지기처럼 예약할 수 있어요."))
                    }
                    ForEach($editor.project.actions) { $action in
                        RealsActionRow(action: $action, people: editor.project.participants,
                                       onDelete: { editor.project.actions.removeAll { $0.id == action.id } })
                    }
                }.padding(.bottom, 12)
            }.disabled(player.isEditingLocked)
            Text("던지기는 최소 0.5초, 확대는 최소 1초 간격. 10초 안에 10번 맞으면 6초간 기절하며, 기절한 동안 본인의 액션은 실행되지 않아요.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var playbackBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Circle().fill(player.state == .playing ? Color.green : Color.secondary).frame(width: 7, height: 7)
                    Text(player.status).fontWeight(.semibold)
                    Text(timeLabel).monospacedDigit().foregroundStyle(.secondary)
                }
                Text("조작창을 최소화한 뒤 macOS 영역 녹화로 촬영하세요.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(player.overlayVisible ? "화면 닫기" : "화면 미리보기") {
                if player.overlayVisible { player.stop() }
                else { editor.perform { try player.preview(editor.project) } }
            }.disabled(player.isEditingLocked)
            Button("처음부터", systemImage: "backward.end") { editor.perform { try player.start(editor.project) } }
                .disabled(!editor.project.issues.isEmpty)
            if player.state == .playing || player.state == .paused {
                Button(player.state == .playing ? "일시정지" : "계속 재생",
                       systemImage: player.state == .playing ? "pause.fill" : "play.fill") { player.pauseOrResume() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("재생", systemImage: "play.fill") { editor.perform { try player.start(editor.project) } }
                    .buttonStyle(.borderedProminent).disabled(!editor.project.issues.isEmpty)
            }
            Button("정지", systemImage: "stop.fill") { player.stop() }.disabled(!player.overlayVisible)
        }.padding(20)
    }

    private var timeLabel: String {
        let total = player.overlayVisible ? player.duration : RealsTimeline(project: editor.project).duration
        guard total.isFinite else { return "—" }
        return String(format: "%.1f / %.1f초", max(0, player.elapsed), total)
    }

    private func sectionTitle(_ title: String, _ number: String) -> some View {
        HStack(spacing: 8) {
            Text(number).font(.caption.monospaced()).foregroundStyle(.secondary)
            Text(title).font(.headline)
        }
    }

    private func secondsField(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("초", value: value, format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder).frame(width: 65)
            Text("초").foregroundStyle(.secondary)
        }
    }
}

private struct RealsParticipantRow: View {
    @Binding var person: RealsParticipant
    let onRemove: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            if let definition = PixelCharacterCatalog.all.first(where: { $0.id == person.characterID }) {
                Image(nsImage: PixelCharacterPreviewImage.image(for: definition))
                    .interpolation(.none).resizable().frame(width: 48, height: 48)
            }
            VStack(spacing: 6) {
                TextField("이름", text: $person.nickname).textFieldStyle(.roundedBorder)
                Picker("캐릭터", selection: $person.characterID) {
                    ForEach(PixelCharacterCatalog.all) { Text($0.displayName).tag($0.id) }
                }.labelsHidden()
            }
            Button(action: onRemove) { Image(systemName: "minus.circle") }.buttonStyle(.plain).help("출연자 삭제")
        }
    }
}

private struct RealsChatRow: View {
    @Binding var line: RealsLine
    let people: [RealsParticipant]
    let number: Int
    let defaultInterval: Double
    let onMove: (Int) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(format: "%02d", number)).font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 26)
                Picker("발신자", selection: $line.speakerID) {
                    ForEach(people) { Text($0.nickname).tag($0.id) }
                }.labelsHidden().frame(width: 120)
                Spacer()
                Toggle("기본 간격", isOn: Binding(get: { line.interval == nil }, set: { line.interval = $0 ? nil : defaultInterval }))
                    .toggleStyle(.checkbox)
                if line.interval != nil {
                    TextField("초", value: Binding(get: { line.interval ?? defaultInterval }, set: { line.interval = $0 }),
                              format: .number.precision(.fractionLength(0...1))).textFieldStyle(.roundedBorder).frame(width: 55)
                    Text("초").font(.caption).foregroundStyle(.secondary)
                }
                Button { onMove(-1) } label: { Image(systemName: "arrow.up") }.help("위로 이동")
                Button { onMove(1) } label: { Image(systemName: "arrow.down") }.help("아래로 이동")
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.help("채팅 삭제")
            }.controlSize(.small)
            TextField("보낼 채팅을 입력하세요", text: $line.body, axis: .vertical)
                .lineLimit(1...3).textFieldStyle(.plain).font(.system(size: 14)).padding(.leading, 3)
        }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}

private struct RealsActionRow: View {
    @Binding var action: RealsAction
    let people: [RealsParticipant]
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("누가", selection: $action.actorID) { ForEach(people) { Text($0.nickname).tag($0.id) } }
                Picker("행동", selection: $action.kind) {
                    Text("던지기").tag(RealsAction.Kind.toss)
                    Text("커지기").tag(RealsAction.Kind.pulse)
                }
                if action.kind == .toss {
                    Picker("누구에게", selection: $action.targetID) {
                        Text("대상 선택").tag(Optional<UUID>.none)
                        ForEach(people.filter { $0.id != action.actorID }) { Text($0.nickname).tag(Optional($0.id)) }
                    }
                }
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.help("액션 삭제")
            }
            HStack(spacing: 14) {
                timeField("시작", value: $action.start)
                Text("~").foregroundStyle(.secondary)
                timeField("종료", value: $action.end)
                timeField("반복 간격", value: $action.interval)
                Spacer()
            }
            if action.kind == .toss {
                Picker("투척물", selection: $action.throwableID) {
                    ForEach(RealsAction.throwables, id: \.0) { Text($0.1).tag($0.0) }
                }.frame(maxWidth: 250)
            } else {
                Text("자기 캐릭터가 7배 커졌다 돌아와요.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }

    private func timeField(_ name: String, value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Text(name).font(.caption)
            TextField("초", value: value, format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder).frame(width: 65)
            Text("초").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct RealsImportSheet: View {
    @ObservedObject var editor: RealsEditor
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var replacing = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("대화 붙여넣기").font(.title2.bold())
            Text("한 줄에 하나씩 ‘유저1: 대사’ 또는 ‘닉네임: 대사’를 입력하세요.\n유저 번호는 왼쪽 출연자 순서예요. 빈 줄은 건너뛰어요.")
                .foregroundStyle(.secondary)
            TextEditor(text: $text).font(.body.monospaced()).frame(height: 300)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            Toggle("기존 채팅을 지우고 이 대화로 교체", isOn: $replacing)
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("적용") {
                    do { try editor.importText(text, replacing: replacing); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 620)
    }
}
#endif
