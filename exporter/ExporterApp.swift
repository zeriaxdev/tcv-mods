import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers

struct SavedSession: Decodable, Identifiable {
    let id: String
    let name: String
    let takes: Int
    let total: Int
    let freestyle: Bool
}
struct DubPack: Decodable, Identifiable {
    let id: String
    let title: String
    let width: Int
    let height: Int
    let fps: String
    let duration: Double
    let sessions: [SavedSession]
    var picture: String {
        let components = fps.split(separator: "/").compactMap { Double($0) }
        let rate = components.count == 2 && components[1] != 0 ? String(format: "%.2f", components[0] / components[1]) : "source"
        return "\(width) × \(height), \(rate) fps, \(Int(duration)) seconds"
    }
}
struct LibraryResult: Decodable { let packs: [DubPack] }

@MainActor final class ExportModel: ObservableObject {
    @Published var packs: [DubPack] = []
    @Published var packID = ""
    @Published var sessionID = ""
    @Published var busy = false
    @Published var fraction = 0.0
    @Published var status = "Loading saved dubs…"
    @Published var lastVideo: URL?
    @Published var lastAudio: URL?
    @Published var muteBacking = false
    @Published var keepOriginal = true
    @Published var cloudFolder = UserDefaults.standard.string(forKey: "cloudFolder") ?? ""
    @Published var exportsFolder = UserDefaults.standard.string(forKey: "exportsFolder") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/Choicer Voicer Exports").path
    @Published var automatic = UserDefaults.standard.bool(forKey: "automatic")
    @Published var includePacks = true
    @Published var includeRecordings = true
    @Published var includeVideos = true
    private var child: Process?
    private let defaults = UserDefaults.standard
    var selectedPack: DubPack? { packs.first { $0.id == packID } }
    var selectedSession: SavedSession? { selectedPack?.sessions.first { $0.id == sessionID } }
    var backend: URL { Bundle.main.resourceURL!.appendingPathComponent("exporter.py") }
    var python: String? { ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"].first { FileManager.default.isExecutableFile(atPath: $0) } }
    var categories: String { [(includePacks ? "packs" : nil), (includeRecordings ? "recordings" : nil), (includeVideos ? "videos" : nil)].compactMap { $0 }.joined(separator: ",") }
    var agentURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/dev.zeriax.tcv.export-backup.plist") }

    func consume(_ object: [String: Any]) {
        switch object["type"] as? String {
        case "library":
            if let data = try? JSONSerialization.data(withJSONObject: object), let result = try? JSONDecoder().decode(LibraryResult.self, from: data) {
                packs = result.packs
                let newest = packs.flatMap { pack in pack.sessions.map { (pack.id, $0.id) } }.max { $0.1 < $1.1 }
                packID = newest?.0 ?? ""
                sessionID = newest?.1 ?? ""
                status = packs.isEmpty ? "No saved dubs found. Finish and save a dub in the game first." : "Latest saved dub selected. Export MP4 saves it to your exports folder."
            }
        case "status": status = object["message"] as? String ?? status
        case "progress": fraction = object["fraction"] as? Double ?? fraction
        case "result":
            lastVideo = URL(fileURLWithPath: object["video"] as? String ?? "")
            lastAudio = URL(fileURLWithPath: object["audio"] as? String ?? "")
            status = "Exported MP4 and full-quality WAV."
            fraction = 1
        case "backup_result":
            if let reason = object["reason"] as? String { status = reason }
            else if let copied = object["copied"] as? Int { status = "Copied \(copied) files. Existing backups were kept." }
            else {
                let count = object["files"] as? Int ?? 0
                let bytes = object["bytes"] as? Int64 ?? 0
                status = "Backup preview: \(count) files, \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)). No files copied yet."
            }
        case "error": status = object["message"] as? String ?? "The operation failed."
        default: break
        }
    }
    func run(_ arguments: [String]) {
        guard !busy, let python else { status = "Python 3 is required. Install it from python.org."; return }
        busy = true
        fraction = 0
        let task = Process()
        let output = Pipe(), errors = Pipe()
        task.executableURL = URL(fileURLWithPath: python)
        task.arguments = ["-u", backend.path] + arguments
        task.standardOutput = output
        task.standardError = errors
        child = task
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try task.run()
                var buffer = Data()
                while true {
                    let data = output.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    buffer.append(data)
                    while let newline = buffer.firstIndex(of: 10) {
                        let line = buffer.prefix(upTo: newline)
                        buffer.removeSubrange(...newline)
                        if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                            DispatchQueue.main.async { self.consume(object) }
                        }
                    }
                }
                task.waitUntilExit()
                let errorText = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    self.busy = false
                    self.child = nil
                    if task.terminationStatus != 0 && !errorText.isEmpty { self.status = String(errorText.suffix(1200)) }
                }
            } catch {
                DispatchQueue.main.async { self.status = error.localizedDescription; self.busy = false; self.child = nil }
            }
        }
    }
    func reload() { run(["--library"]) }
    func selectPack() {
        if selectedPack?.sessions.contains(where: { $0.id == sessionID }) != true {
            sessionID = selectedPack?.sessions.first?.id ?? ""
        }
    }
    func export() {
        guard let pack = selectedPack, selectedSession != nil else { return }
        let folder = URL(fileURLWithPath: exportsFolder)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { status = error.localizedDescription; return }
        let title = pack.title.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|:")).joined(separator: "_")
        let base = "\(title) — \(sessionID)"
        var name = base, index = 2
        while ["mp4", "wav", "export.json"].contains(where: { FileManager.default.fileExists(atPath: folder.appendingPathComponent(name + "." + $0).path) }) {
            name = "\(base) (\(index))"
            index += 1
        }
        export(to: folder.appendingPathComponent(name + ".mp4"))
    }
    func exportAs() {
        guard let pack = selectedPack, selectedSession != nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        let safeTitle = pack.title.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|:")).joined(separator: "_")
        panel.nameFieldStringValue = "\(safeTitle) — \(sessionID).mp4"
        panel.directoryURL = URL(fileURLWithPath: exportsFolder)
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        exportsFolder = destination.deletingLastPathComponent().path
        defaults.set(exportsFolder, forKey: "exportsFolder")
        if automatic { setAutomatic(true) }
        export(to: destination)
    }
    private func export(to destination: URL) {
        var arguments = ["--export", "--pack", packID, "--session", sessionID, "--output", destination.path]
        if muteBacking { arguments.append("--mute-backing") }
        if !keepOriginal { arguments.append("--missing-silence") }
        run(arguments)
    }
    func chooseCloud() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use this folder"
        panel.message = "Choose a Synology Drive, iCloud Drive, or mounted WebDAV folder. A Choicer Voicer subfolder will hold the backups."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        cloudFolder = url.appendingPathComponent("Choicer Voicer").path
        defaults.set(cloudFolder, forKey: "cloudFolder")
        if automatic { setAutomatic(true) }
    }
    func backup(preview: Bool) {
        guard !cloudFolder.isEmpty, !categories.isEmpty else { status = "Choose a backup folder and at least one item type."; return }
        var arguments = ["--backup", cloudFolder, "--exports-folder", exportsFolder, "--categories", categories]
        if preview { arguments.append("--dry-run") }
        run(arguments)
    }
    func cancel() { child?.terminate() }
    func setAutomatic(_ enabled: Bool) {
        let domain = "gui/\(getuid())"
        let label = "dev.zeriax.tcv.export-backup"
        do {
            if enabled {
                guard !cloudFolder.isEmpty, !categories.isEmpty, let python else { status = "Choose a synced folder first."; return }
                let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Choicer Voicer Exporter")
                try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let configuration: [String: Any] = ["Label": label,
                    "ProgramArguments": [python, "-u", backend.path, "--backup", cloudFolder, "--exports-folder", exportsFolder, "--categories", categories, "--automatic"],
                    "StartInterval": 120, "RunAtLoad": true,
                    "StandardOutPath": support.appendingPathComponent("backup.log").path,
                    "StandardErrorPath": support.appendingPathComponent("backup-error.log").path]
                let data = try PropertyListSerialization.data(fromPropertyList: configuration, format: .xml, options: 0)
                try data.write(to: agentURL, options: .atomic)
                _ = launchctl(["bootout", domain + "/" + label])
                guard launchctl(["bootstrap", domain, agentURL.path]) == 0 else { throw NSError(domain: "Backup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not enable automatic backup. Check the selected folder and try again."]) }
                status = "Automatic backup enabled. Checks every 2 minutes, after the game closes."
            } else {
                _ = launchctl(["bootout", domain + "/" + label])
                if FileManager.default.fileExists(atPath: agentURL.path) { try FileManager.default.removeItem(at: agentURL) }
                status = "Automatic backup disabled. Existing backups are kept."
            }
            automatic = enabled
            defaults.set(enabled, forKey: "automatic")
        } catch { status = error.localizedDescription }
    }
    private func launchctl(_ arguments: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do { try task.run(); task.waitUntilExit(); return task.terminationStatus } catch { return -1 }
    }
}

struct ExporterView: View {
    @StateObject private var model = ExportModel()
    @State private var page = "Export"
    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Text("Export").tag("Export")
                Text("Cloud backup").tag("Cloud backup")
            }.navigationSplitViewColumnWidth(145)
        } detail: {
            VStack(alignment: .leading, spacing: 18) {
                if page == "Export" {
                    Text("Export a saved dub").font(.title2)
                    Form {
                        Picker("Pack", selection: $model.packID) { ForEach(model.packs) { Text($0.title).tag($0.id) } }
                            .onChange(of: model.packID) { _ in model.selectPack() }
                        Picker("Recording", selection: $model.sessionID) {
                            ForEach(model.selectedPack?.sessions ?? []) { Text($0.name).tag($0.id) }
                        }
                        if let pack = model.selectedPack { Text(pack.picture).foregroundStyle(.secondary) }
                        if let session = model.selectedSession { Text(session.freestyle ? "Freestyle recording" : "\(session.takes) of \(session.total) takes recorded").foregroundStyle(.secondary) }
                        Toggle("Include backing track", isOn: Binding(get: { !model.muteBacking }, set: { model.muteBacking = !$0 }))
                        Toggle("Keep original lines I didn’t record", isOn: $model.keepOriginal)
                    }.disabled(model.busy)
                    Text("Exports an MP4 and a full-quality WAV at the source video’s resolution. No screen capture or upscaling.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Refresh", action: model.reload).disabled(model.busy)
                        Spacer()
                        Button("Export as…", action: model.exportAs).disabled(model.busy || model.selectedSession == nil)
                        Button("Export MP4", action: model.export).keyboardShortcut(.defaultAction).disabled(model.busy || model.selectedSession == nil)
                    }
                    if let video = model.lastVideo {
                        HStack {
                            Button("Play video") { NSWorkspace.shared.open(video) }
                            Button("Show exports") { NSWorkspace.shared.activateFileViewerSelecting([video]) }
                        }
                    }
                } else {
                    Text("Cloud backup").font(.title2)
                    Text("Use a folder synced by Synology Drive or iCloud Drive. Mounted WebDAV folders also work. Your sync app handles the upload.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text(model.cloudFolder.isEmpty ? "No destination selected" : model.cloudFolder).lineLimit(2).textSelection(.enabled)
                        Spacer()
                        Button("Choose folder…", action: model.chooseCloud).disabled(model.busy)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Custom packs", isOn: $model.includePacks)
                        Toggle("Recordings", isOn: $model.includeRecordings)
                        Toggle("Exported MP4 and WAV files", isOn: $model.includeVideos)
                    }.disabled(model.busy || model.automatic)
                    Toggle("Back up automatically after playing", isOn: Binding(get: { model.automatic }, set: { model.setAutomatic($0) }))
                        .disabled(model.busy || model.cloudFolder.isEmpty)
                    Text("Checks every 2 minutes while the game is closed, even when this app is closed. Existing backups are kept when files differ. This backs up files; it does not merge cloud changes into the game.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Preview backup") { model.backup(preview: true) }
                        Spacer()
                        Button("Back up now") { model.backup(preview: false) }
                    }.disabled(model.busy || model.cloudFolder.isEmpty)
                }
                Spacer(minLength: 0)
                Divider()
                if model.busy {
                    ProgressView(value: model.fraction)
                    HStack { Text(model.status).lineLimit(3); Spacer(); Button("Cancel", action: model.cancel) }
                } else { Text(model.status).font(.callout).textSelection(.enabled).lineLimit(4) }
            }.padding(24)
        }.frame(minWidth: 760, minHeight: 470)
         .task { model.reload() }
    }
}

@main struct ChoicerExporterApp: App {
    var body: some Scene { WindowGroup("Choicer Voicer Exporter") { ExporterView() } }
}
