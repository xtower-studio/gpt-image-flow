import AppKit
import FlowCore

// Enabled only by the explicit --dev-directory launch argument. No network listener.
extension FlowAppDelegate {
    func processCommand(_ directory: URL) async {
        let url = directory.appendingPathComponent("command.json")
        guard let data = try? Data(contentsOf: url), let command = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let operation = command["operation"], let store else { return }
        try? FileManager.default.removeItem(at: url)
        do {
            if operation == "projectSlotsQA" {
                guard !store.library.projects.contains(where: { $0.name == "프로젝트 이미지 검증" }), let reference = store.library.assets.first(where: { $0.id == UUID(uuidString: "D1A84191-D395-43FD-9D34-7AA9763AE45D") }) else { return }
                var project = Project(name: "프로젝트 이미지 검증"); project.prompt = "Four distinct cobalt ceramic teapot designs on warm ivory backgrounds, product photography."
                project.generationMode = .automatic
                store.library.projects.append(project)
                let copy = try await store.vault.ingest(url: store.vault.original(reference), projectID: project.id, title: "첨부 이미지")
                store.upsert(copy); project.referenceIDs = [copy.id]; store.updateProject(project)
                store.journal.paused = true; store.journal.pauseReason = "화면 검증 중"
                try store.enqueue(project: project); store.requestedProjectID = project.id; store.flush()
            } else if operation == "resumeProjectSlotsQA" {
                guard store.jobs.filter({ $0.state == .queued }).allSatisfy({ store.project($0.projectID)?.name == "프로젝트 이미지 검증" }) else { return }
                store.journal.paused = false; store.journal.pauseReason = nil; store.flush()
            } else if operation == "studioV11Smoke" {
                guard !store.library.projects.contains(where: { $0.name == "v0.11 검증 · 보관함" }) else { throw FlowError.message("이미 요청한 검증입니다.") }
                var project = Project(name: "v0.11 검증 · 보관함")
                project.prompt = "A single cobalt ceramic teapot on a warm ivory background, quiet editorial product photography."
                project.generationMode = .instant
                store.library.projects.append(project)
                try store.enqueue(project: project)
                store.requestedProjectID = project.id
                store.journal.paused = false; store.journal.pauseReason = nil; store.flush()
            } else if operation == "verifyPortableLibrary" {
                let root = store.root
                let archive = try await Task.detached { let value = try PortableLibrary.load(from: root); try value.verifyFiles(in: root); return value }.value
                let proof: [String: Any] = ["folder": root.path, "assets": archive.library.assets.count, "references": archive.library.assets.filter(\.isReference).count, "projects": archive.library.projects.count, "recipes": archive.library.recipes?.count ?? 0, "jobs": archive.journal.jobs.count, "hashesVerified": true]
                try JSONSerialization.data(withJSONObject: proof, options: .prettyPrinted).write(to: directory.appendingPathComponent("portable-proof.json"))
            } else if operation == "captureImageToolProof" {
                try await captureImageToolProof(directory: directory)
            } else if operation == "verifyComposerConcurrency" {
                try await verifyComposerConcurrency(directory: directory)
            } else if ["workflowSeedQA", "workflowRunQA", "workflowStatus"].contains(operation) {
                try workflowCommand(operation, directory: directory)
            } else if operation == "studioPreview" {
                for (key, preference) in [("reduceTransparency", "devPreviewReduceTransparency"), ("increaseContrast", "devPreviewIncreaseContrast")] {
                    if let value = command[key] { UserDefaults.standard.set(value == "true", forKey: preference) }
                }
                if let mode = command["mode"] { UserDefaults.standard.set(mode, forKey: "studioBoardMode") }
                if let appearance = command["appearance"] { NSApp.appearance = appearance == "system" ? nil : NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua) }
                if let projectID = command["project"].flatMap(UUID.init(uuidString:)) { store.requestedProjectID = projectID }
                if let asset = command["inspect"].flatMap(UUID.init(uuidString:)) { store.requestedInspectorAsset = asset }
                if let width = command["width"].flatMap(Double.init), let height = command["height"].flatMap(Double.init), let window = NSApp.windows.first(where: { $0.isVisible && $0.title != "Image Flow · ChatGPT 연결" && $0.contentView != nil }) {
                    window.setContentSize(NSSize(width: width, height: height)); window.center()
                }
                NSApp.activate(ignoringOtherApps: true)
            } else if operation == "apiStatus" {
                let jobs = store.jobs.filter { $0.apiOptions != nil }.map { job in
                    ["id": job.id.uuidString, "project": job.projectID.uuidString, "state": job.state.rawValue,
                     "results": job.results.count, "requestID": job.apiRequestID ?? "", "error": job.error ?? "",
                     "stream": job.apiOptions?.stream ?? false] as [String: Any]
                }
                try JSONSerialization.data(withJSONObject: ["connected": store.apiConnection.ready, "jobs": jobs], options: .prettyPrinted)
                    .write(to: directory.appendingPathComponent("api-status.json"))
            } else if operation == "apiSmokeGenerate" {
                guard store.apiConnection.ready else { throw FlowError.message("API 키 연결이 필요합니다.") }
                // Explicit developer action only. Never launched automatically; one paid image.
                guard !store.library.projects.contains(where: { $0.name == "API 검증 · Sunburst" }) else {
                    throw FlowError.message("API 검증 프로젝트가 이미 있습니다. 중복 유료 요청을 중단했습니다.")
                }
                var project = Project(name: "API 검증 · Sunburst")
                project.prompt = "One sculptural cobalt blue ceramic teapot on a warm ivory background, editorial product photograph, soft side light, no lettering."
                project.generationMode = .sunburstAPI
                var options = ImageAPIOptions(); options.quality = "low"; options.size = "1024x1024"; options.count = 1
                project.apiOptions = options
                store.library.projects.append(project)
                let jobs = try JobRules.makeBatch(project: project)
                store.reserveCanvasPositions(for: jobs); store.journal.jobs.append(contentsOf: jobs)
                store.requestedProjectID = project.id; store.journal.paused = false; store.journal.pauseReason = nil; store.flush()
            } else if operation == "apiSmokeEdit" {
                guard var project = store.library.projects.first(where: { $0.name == "API 검증 · Sunburst" }),
                      let original = store.jobs.first(where: { $0.projectID == project.id && $0.state == .saved }),
                      let asset = original.results.first,
                      !store.jobs.contains(where: { $0.projectID == project.id && !$0.referenceIDs.isEmpty }) else {
                    throw FlowError.message("원본이 없거나 이미 수정 검증을 요청했습니다.")
                }
                project.prompt = "Keep the teapot's shape, composition and lighting. Change only its glaze from cobalt blue to terracotta orange."
                project.referenceIDs = [asset.id]
                project.apiOptions?.stream = true; project.apiOptions?.partialImages = 1
                let jobs = try JobRules.makeBatch(project: project)
                store.reserveCanvasPositions(for: jobs); store.journal.jobs.append(contentsOf: jobs)
                store.requestedProjectID = project.id; store.requestedJobID = jobs.first?.id
                store.journal.paused = false; store.journal.pauseReason = nil; store.flush()
            } else if operation == "verifyWorkflowRestore" {
                let data = try Data(contentsOf: directory.appendingPathComponent("workflow-verification.json"))
                let proof = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                let projectID = UUID(uuidString: proof["project"] as! String)!
                let assetID = UUID(uuidString: proof["asset"] as! String)!
                guard let project = store.project(projectID), project.referenceIDs.contains(assetID),
                      project.layout?[assetID.uuidString] == CanvasPoint(x: 665,y: -55),
                      project.viewport == CanvasViewport(x: 45,y: 80,scale: 0.65),
                      store.library.recipes?.contains(where: { $0.name == "검증 · 세라믹 레시피" }) == true,
                      !(store.library.hiddenAssetIDs ?? []).contains(assetID) else { throw FlowError.message("워크플로 복원 검증 실패") }
                try "canvas, viewport, references, recipe, undo: restored".write(to: directory.appendingPathComponent("workflow-restore.txt"), atomically: true, encoding: .utf8)
                // Give the validated test board a readable final presentation.
                store.setCanvasPositions([assetID.uuidString: CanvasPoint(x: 920, y: -30)], projectID: projectID)
                store.requestedProjectID = projectID; store.flush()
            } else if operation == "showResponse", let job = store.jobs.last(where: { $0.state == .responded }) {
                store.requestedProjectID = job.projectID; store.requestedJobID = job.id
            } else if operation == "workflowSmoke", let project = store.library.projects.last,
               let asset = store.library.assets.last(where: { $0.projectID == project.id && !$0.isReference }) {
                let before = store.library.assets.count
                store.importImages([store.vault.original(asset), store.vault.original(asset)], projectID: project.id)
                for _ in 0..<30 { if !store.importing { break }; try await Task.sleep(for: .milliseconds(100)) }
                guard let updated = store.project(project.id) else { return }
                guard before == store.library.assets.count, updated.referenceIDs.filter({ $0 == asset.id }).count == 1 else { throw FlowError.message("내부 파일 재첨부 검증 실패") }
                let position = CanvasPoint(x: 665, y: -55)
                store.setCanvasPositions([asset.id.uuidString:position], projectID: project.id)
                store.setViewport(CanvasViewport(x: 45, y: 80, scale: 0.65), projectID: project.id)
                store.saveRecipe(project: updated, name: "검증 · 세라믹 레시피")
                store.hideAssets([asset.id]); store.undoHide(); store.flush()
                let proof: [String:Any] = ["project":project.id.uuidString,"asset":asset.id.uuidString,"assetCountUnchanged":true,"referenceCount":updated.referenceIDs.count,"position":["x":position.x,"y":position.y],"recipeSaved":true,"hideUndone":!(store.library.hiddenAssetIDs ?? []).contains(asset.id)]
                try JSONSerialization.data(withJSONObject:proof, options:.prettyPrinted).write(to:directory.appendingPathComponent("workflow-verification.json"))
                store.requestedProjectID = project.id
            } else if operation == "verifyActualMetadata", let session {
                let worker = try WebWorker(slot: 0, session: session)
                defer { worker.close() }
                guard let job = store.jobs.last(where: { $0.conversationID != nil }) else { return }
                try await worker.load(job.conversationID)
                let evidence = try await worker.generationMetadata()
                try JSONEncoder().encode(evidence).write(to: directory.appendingPathComponent("actual-model-metadata.json"))
            } else if operation == "inspectImageComposer", let session {
                let worker = try WebWorker(slot: 0, session: session)
                defer { worker.close() }
                try await worker.load()
                let script = """
                JSON.stringify({editors:Array.from(document.querySelectorAll('#prompt-textarea,[contenteditable]')).map(el=>({html:el.outerHTML,editable:el.isContentEditable})),buttons:Array.from(document.querySelectorAll('form button')).map(el=>({text:el.innerText,label:el.getAttribute('aria-label'),testid:el.getAttribute('data-testid')}))})
                """
                var proof: [String: String] = ["before": try await worker.web.evaluateJavaScript(script) as? String ?? ""]
                do { _ = try await worker.call("composeImage", payload: ["prompt": "A cobalt ceramic teapot"], as: WebWorker.Ack.self) }
                catch { proof["error"] = String(describing: error) }
                proof["after"] = try await worker.web.evaluateJavaScript(script) as? String ?? ""
                try JSONSerialization.data(withJSONObject: proof, options: .prettyPrinted).write(to: directory.appendingPathComponent("image-composer.json"))
            } else if operation == "verifyImageModels", let session {
                let worker = try WebWorker(slot: 0, session: session)
                defer { worker.close() }
                var proof: [[String: Any]] = []
                for model in GenerationMode.allCases.filter({ $0 != .sunburstAPI }) {
                    var project = Project(name: "Model preparation verification")
                    project.prompt = "A cobalt ceramic teapot"; project.aspect = "1:1"
                    project.background = .transparent; project.generationMode = model
                    let job = try JobRules.makeBatch(project: project)[0]
                    let files: [URL] = model == .automatic ? store.library.assets.first(where: { $0.id == UUID(uuidString: "D1A84191-D395-43FD-9D34-7AA9763AE45D") }).map { [store.vault.original($0)] } ?? [] : []
                    do { _ = try await worker.prepare(job: job, files: files) }
                    catch {
                        proof.append(["model": model.label, "error": String(describing: error), "form": try await worker.web.evaluateJavaScript("document.querySelector('form')?.outerHTML || ''") as? String ?? ""])
                        try JSONSerialization.data(withJSONObject: proof, options: .prettyPrinted).write(to: directory.appendingPathComponent("image-model-verification.json"))
                        throw error
                    }
                    let text = try await worker.web.evaluateJavaScript("document.querySelector('#prompt-textarea,div[contenteditable=true].ProseMirror')?.innerText || ''") as? String ?? ""
                    proof.append(["model": model.label, "applied": worker.appliedReasoning ?? -1, "composer": text, "imageModeVerified": true])
                    try JSONSerialization.data(withJSONObject: proof, options: .prettyPrinted).write(to: directory.appendingPathComponent("image-model-verification.json"))
                }
            } else if operation == "retryComposerCompatibility", let engine,
                      let project = store.library.projects.first(where: { $0.name == "입력창 호환성 검증 · 2026-09" }),
                      let job = store.jobs.first(where: { $0.projectID == project.id && $0.state == .failed && $0.submittedAt == nil }) {
                engine.retryBeforeSubmission(job)
            } else if operation == "composerCompatibilitySmoke" {
                let name = "입력창 호환성 검증 · 2026-09"
                guard !store.library.projects.contains(where: { $0.name == name }) else {
                    throw FlowError.message("이미 검증 요청이 있습니다. 중복 전송하지 않았습니다.")
                }
                var project = Project(name: name)
                project.prompt = "A small cobalt blue ceramic teapot on an ivory background, product photograph, no lettering."
                store.library.projects.append(project)
                for mode in [GenerationMode.automatic, .instant] {
                    project.generationMode = mode
                    if mode == .automatic, let reference = store.library.assets.first(where: { $0.id == UUID(uuidString: "D1A84191-D395-43FD-9D34-7AA9763AE45D") }) {
                        project.referenceIDs = [reference.id]
                    } else { project.referenceIDs = [] }
                    let jobs = try JobRules.makeBatch(project: project)
                    store.reserveCanvasPositions(for: jobs); store.journal.jobs.append(contentsOf: jobs)
                }
                store.journal.paused = false; store.journal.pauseReason = nil; store.flush()
            } else if operation == "imageModelSmoke" {
                var project = Project(name: "v0.6 검증 · 생성 방식")
                project.prompt = "A small cobalt blue ceramic teapot, isolated product photograph, no lettering"
                project.aspect = "1:1"; project.background = .transparent
                store.library.projects.append(project)
                for model in GenerationMode.allCases.filter({ $0 != .sunburstAPI }) {
                    project.generationMode = model
                    var job = try JobRules.makeBatch(project: project)[0]; job.label = model.label
                    store.reserveCanvasPositions(for: [job]); store.journal.jobs.append(job)
                }
                store.journal.paused = false; store.journal.pauseReason = nil; store.flush()
                store.requestedProjectID = project.id
            } else if operation == "verifyReasoning", let session {
                let worker = try WebWorker(slot: 0, session: session)
                defer { worker.close() }
                try await worker.load()
                _ = try await worker.call("type", payload: ["prompt":"Generate a blue ceramic vase."], as: WebWorker.Ack.self)
                try await worker.wait(1)
                var levels: [[String: Any]] = []
                for level in ReasoningLevel.allCases {
                    try await worker.applyReasoning(level)
                    let label = try await worker.web.evaluateJavaScript("Array.from(document.querySelectorAll('button.__composer-pill')).map(el=>el.innerText).join(' | ')") as? String ?? ""
                    levels.append(["requested":level.rawValue,"applied":worker.appliedReasoning ?? -1,"label":label])
                    try JSONSerialization.data(withJSONObject: levels, options: .prettyPrinted).write(to: directory.appendingPathComponent("reasoning-verification.json"))
                }
                try await worker.applyReasoning(.standard)
            } else if operation == "parallelSmoke" {
                var project = Project(name: "v0.2 검증 · 병렬 스튜디오")
                project.prompt = "Create one editorial photograph of a sculptural ceramic teapot, pale warm background, soft natural light, no lettering."
                project.copies = 3; project.viewport = CanvasViewport(x: 30, y: 25, scale: 0.75)
                store.library.projects.append(project)
                var batch = try JobRules.makeBatch(project: project)
                for index in batch.indices { batch[index].reasoning = [ReasoningLevel.instant, .standard, .heavy][index] }
                store.reserveCanvasPositions(for: batch)
                store.journal.jobs.append(contentsOf: batch)
                store.journal.paused = false; store.journal.pauseReason = nil; store.flush()
                store.requestedProjectID = project.id; engine?.eco = false
            } else if operation == "textSmoke", let project = store.library.projects.last {
                var job = Job(batchID: UUID(), projectID: project.id, prompt: "Do not generate any image. Reply only in Korean with this question: 주전자의 색상을 어떤 색으로 바꿀까요?", label: "텍스트 응답 검증", referenceIDs: [])
                job.reasoning = .instant
                store.reserveCanvasPositions(for: [job]); store.journal.jobs.append(job); store.flush()
                store.requestedProjectID = project.id; store.requestedJobID = job.id
            } else if operation == "followupSmoke", let job = store.jobs.last(where: { $0.state == .responded }) {
                try store.enqueueFollowup(to: job, text: "파스텔 민트색 도자기 주전자로 만들어 주세요. 따뜻한 흰색 배경 위의 제품 사진 한 장을 지금 생성해 주세요.", mode: .sunburstExperimental)
                store.requestedProjectID = job.projectID
            } else if operation == "failureSmoke", let project = store.library.projects.last {
                let job = Job(batchID: UUID(), projectID: project.id, prompt: "Local attachment failure fixture", label: "첨부 실패 검증", referenceIDs: [UUID()])
                store.reserveCanvasPositions(for: [job]); store.journal.jobs.append(job); store.flush()
            } else if operation == "inspectReasoning", let session {
                let worker = try WebWorker(slot: 0, session: session)
                defer { worker.close() }
                try await worker.load()
                _ = try await worker.call("type", payload: ["prompt": "Generate one image of a blue ceramic vase."], as: WebWorker.Ack.self)
                try await worker.wait(2)
                let script = """
                (() => {
                  const pill = Array.from(document.querySelectorAll('button')).find(el => el.classList.contains('__composer-pill') && /Instant|추론|Thinking|Reasoning|High|Standard|Light|Extended|Heavy|Pro/i.test(el.innerText));
                  const before = {composer:document.querySelector('#prompt-textarea')?.closest('form')?.outerHTML.slice(-22000),buttons:Array.from(document.querySelectorAll('main button,header button,[data-testid*=model]')).map(el=>({text:el.innerText,label:el.getAttribute('aria-label'),testid:el.getAttribute('data-testid')}))};
                  if(pill) {pill.focus();pill.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowDown',code:'ArrowDown',bubbles:true,cancelable:true}));}
                  return JSON.stringify({before,clicked:!!pill});
                })()
                """
                let before = try await worker.web.evaluateJavaScript(script) as? String ?? ""
                try await worker.wait(1)
                let after = try await worker.web.evaluateJavaScript("JSON.stringify(Array.from(document.querySelectorAll('[role=slider],[role=dialog],[role=menu], [data-radix-popper-content-wrapper]')).map(el=>el.outerHTML.slice(0,16000)))") as? String ?? ""
                try (before + "\n" + after).write(to: directory.appendingPathComponent("reasoning-controls.json"), atomically: true, encoding: .utf8)
            } else if operation == "smoke" {
                var project = Project(name: "연결 검증 · 세라믹 스튜디오")
                project.prompt = "Generate one image of a single sculptural cobalt-blue ceramic vase on warm ivory paper, soft side lighting, editorial product photography, no text, square composition."
                store.library.projects.append(project); store.requestedProjectID = project.id
                try store.enqueue(project: project)
                store.journal.paused = false; store.flush()
            } else if operation == "editSmoke", let asset = store.library.assets.last(where: { !$0.isReference }) {
                var project = store.project(asset.projectID)!
                project.prompt = "Edit the attached image. Keep the vase shape and composition exactly as in the reference. Change only the vase color to warm terracotta orange. Generate one image."
                project.referenceIDs = [asset.id]; project.copies = 1; project.variations = ""
                try store.enqueue(project: project, parentID: asset.id)
                store.requestedProjectID = project.id; store.journal.paused = false; store.flush()
            } else if operation == "batchSmoke" {
                let references = Array(store.library.assets.filter { !$0.isReference }.suffix(2))
                guard references.count == 2 else { return }
                var project = store.project(references[0].projectID)!
                project.prompt = "Generate one editorial product photograph using BOTH reference images: the cobalt blue vase and the terracotta orange vase standing together, keep their sculptural shapes, warm ivory seamless background, soft shadows, no text."
                project.referenceIDs = references.map(\.id); project.copies = 3; project.variations = ""
                store.updateProject(project)
                try store.enqueue(project: project)
                store.requestedProjectID = project.id; store.journal.paused = false; store.flush()
            } else if operation == "showLatest", let asset = store.library.assets.last(where: { !$0.isReference }) {
                store.requestedProjectID = asset.projectID
                NSApp.activate(ignoringOtherApps: true)
            } else if operation == "favoriteSmoke", let asset = store.library.assets.first(where: { !$0.isReference && !$0.isFavorite }) {
                store.toggleFavorite(asset)
            } else if operation == "compare" {
                store.requestedComparison = Array(store.library.assets.filter { !$0.isReference }.prefix(2).map(\.id))
            } else if operation == "exportSmoke" {
                let assets = store.library.assets.filter { !$0.isReference }
                let folder = try await store.vault.export(assets, jobs: store.jobs, to: directory.appendingPathComponent("Export"))
                try folder.path.write(to: directory.appendingPathComponent("export-path.txt"), atomically: true, encoding: .utf8)
            } else if operation == "capture", let window = NSApp.windows.first(where: { $0.isVisible && $0.title != "Image Flow · ChatGPT 연결" }), let view = window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) { try png.write(to: directory.appendingPathComponent("workspace.png")) }
            } else if operation == "recover", let job = store.jobs.last(where: { $0.state == .needsReview }) { engine?.recover(job) }
            else if operation == "inspectWorkers", let engine {
                var snapshots: [[String: Any]] = []
                for (id, worker) in engine.workers {
                    if let state = try? await worker.snapshot() {
                        snapshots.append(["id": id.uuidString, "ready": state.ready, "generating": state.generating,
                            "assistantCount": state.assistantCount, "userCount": state.userCount,
                            "composerEmpty": state.composerEmpty, "images": state.images.map { ["width": $0.width, "height": $0.height, "complete": $0.complete] },
                            "reply": state.reply])
                    }
                }
                try JSONSerialization.data(withJSONObject: snapshots, options: .prettyPrinted).write(to: directory.appendingPathComponent("workers.json"))
            }
            else if operation == "uiState" {
                func collections(_ view: NSView) -> [NSCollectionView] { (view as? NSCollectionView).map { [$0] } ?? view.subviews.flatMap(collections) }
                let info = NSApp.windows.filter { $0.isVisible }.map { window in
                    ["title": window.title, "key": window.isKeyWindow, "responder": String(describing: window.firstResponder),
                     "selection": window.contentView.map { collections($0).flatMap { $0.selectionIndexPaths.map(\.item) } } ?? []] as [String: Any]
                }
                try JSONSerialization.data(withJSONObject: info).write(to: directory.appendingPathComponent("ui-state.json"))
            }
            else if operation == "windowInfo" {
                func splits(_ view: NSView) -> [NSSplitView] { (view as? NSSplitView).map { [$0] + view.subviews.flatMap(splits) } ?? view.subviews.flatMap(splits) }
                let info = NSApp.windows.filter { $0.isVisible }.map { window in
                    ["id": window.windowNumber, "title": window.title, "contentWidth": window.contentView?.bounds.width ?? 0, "contentHeight": window.contentView?.bounds.height ?? 0,
                     "splits": window.contentView.map { splits($0).map { split in ["frame": NSStringFromRect(split.convert(split.bounds, to: nil)), "children": split.subviews.map { NSStringFromRect($0.convert($0.bounds, to: nil)) }] } } ?? [],
                     "toolbar": window.toolbar?.items.map { item in ["id": item.itemIdentifier.rawValue, "view": item.view.map { NSStringFromRect($0.convert($0.bounds, to: nil)) } ?? "", "tracking": (item as? NSTrackingSeparatorToolbarItem).map { NSStringFromRect($0.splitView.convert($0.splitView.bounds, to: nil)) } ?? ""] } ?? []] as [String: Any]
                }
                try JSONSerialization.data(withJSONObject: info).write(to: directory.appendingPathComponent("windows.json"))
            }
            else if operation == "inspectConversation", let job = store.jobs.last, let conversation = command["conversation"].flatMap({ UUID(uuidString: $0) != nil ? $0 : nil }) ?? job.conversationID, let session {
                let worker = try WebWorker(slot: 0, session: session)
                defer { worker.close() }
                try await worker.load(conversation)
                worker.host.makeKeyAndOrderFront(nil)
                try await worker.wait(3)
                let diagnostics = try await worker.web.evaluateJavaScript("""
                  JSON.stringify({assistantHTML:Array.from(document.querySelectorAll('[data-message-author-role=assistant]')).map(el=>el.outerHTML.slice(0,18000)),streaming:Array.from(document.querySelectorAll('button[data-testid=stop-button],button[aria-label*=Stop],[data-is-streaming=true]')).map(el=>({tag:el.tagName,text:el.innerText,html:el.outerHTML.slice(0,1200)})),text:(document.querySelector('main')?.innerText || '').slice(-5000),
                  images:Array.from(document.querySelectorAll('main img')).map(im=>({width:im.naturalWidth,src:(im.currentSrc||im.src).split('?')[0],role:im.closest('[data-message-author-role]')?.dataset.messageAuthorRole,alt:im.alt})),
                  messageBlocks:Array.from(document.querySelectorAll('main [data-chatgpt-search-message-ids]')).filter(el=>!el.matches('[data-chatgpt-search-unit-key$=":user"]')).map(el=>el.outerHTML.slice(0,16000)),
                  articles:Array.from(document.querySelectorAll('main article')).map(el=>({role:el.getAttribute('data-message-author-role'),id:el.getAttribute('data-testid'),classes:el.className}))})
                """)
                if let text = diagnostics as? String { try text.write(to: directory.appendingPathComponent("conversation-diagnostics.json"), atomically: true, encoding: .utf8) }
                let image = try await worker.web.takeSnapshot(configuration: nil)
                if let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: directory.appendingPathComponent("conversation.png")) }
            }
            else if operation == "hideConnection" { session?.window?.orderOut(nil) }
        } catch { store.report(error) }
    }
}
