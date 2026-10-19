#if os(macOS)
import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import FrontstageCore

@MainActor
enum ProductionDocument {
    static func render(project: Project, dayID: String, paper: ScreenplayPaper) throws -> RenderedScreenplay {
        let report = try project.callSheetText(for: dayID)
        let sections: Set<String> = ["LOCATION & SAFETY", "KEY CREW", "SCHEDULED SCENES", "CAST CALLS", "PRODUCTION NOTES", "SCHEDULE CHECKS"]
        let text = NSMutableAttributedString(string: "")
        for (index, line) in report.components(separatedBy: "\n").enumerated() {
            let type: ScreenplayElement = index < 2 || sections.contains(line) ? .sceneHeading : .action
            var attributes = ScreenplayTypography.attributes(type, width: paper.contentWidth, printing: true)
            if let paragraph = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
                paragraph.paragraphSpacing = 4
                attributes[.paragraphStyle] = paragraph
            }
            text.append(NSAttributedString(string: line + "\n", attributes: attributes))
        }
        return try ScreenplayPDF.renderText(text, title: project.name + " Call Sheet", paper: paper)
    }
}

extension Workspace {
    func exportCSV(_ text: String, name: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = name.replacingOccurrences(of: "/", with: "-") + ".csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try ProductionCSV.save(text, to: url) }
        catch { errorMessage = error.localizedDescription }
    }
}

struct ProductionView: View {
    @ObservedObject var workspace: Workspace
    @State private var selectedDay: String?
    @State private var newDate = Date()
    @State private var preview: PDFDocument?
    private var day: ProductionDay? { workspace.project.productionDays.first { $0.id == selectedDay } }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Production").font(.headline)
                DatePicker("New day", selection: $newDate, displayedComponents: .date)
                Button("Add Shooting Day") {
                    var id: String?
                    workspace.edit("Add Shooting Day") { id = try $0.addProductionDay(date: ProductionDates.string(newDate)) }
                    if let id { selectedDay = id }
                }
                List(workspace.project.productionDays, selection: $selectedDay) { day in
                    VStack(alignment: .leading) {
                        Text("Day \(day.number) · \(day.date)")
                        Text("\(workspace.project.scheduledScenes(for: day.id).count) scenes · \(day.callTime)")
                            .font(.caption).foregroundStyle(.secondary)
                    }.tag(day.id)
                }
                Button("Export Schedule CSV") { workspace.exportCSV(workspace.project.scheduleCSV(), name: workspace.project.name + " Schedule") }
                Button("Export Breakdown CSV") { workspace.exportCSV(workspace.project.breakdownCSV(), name: workspace.project.name + " Breakdown") }
            }.padding(16).frame(minWidth: 205, idealWidth: 230)
            if let day {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Day \(day.number)").font(.title2)
                        Spacer()
                        Button(preview == nil ? "Preview Call Sheet" : "Back to Planning") {
                            if preview != nil { preview = nil }
                            else { reportAction { preview = PDFDocument(data: $0.data) } }
                        }
                        Menu("Call Sheet") {
                            Button("Export PDF…") { reportAction { try workspace.exportPDF($0, name: workspace.project.name + " Day \(day.number) Call Sheet") } }
                            Button("Print…") { reportAction { try workspace.printPDF($0) } }
                        }
                    }
                    if let preview { ScreenplayPDFView(document: preview) }
                    else { planning(day) }
                }.padding(18).frame(minWidth: 350)
            } else {
                ContentUnavailableView("Plan a shooting day", systemImage: "calendar",
                    description: Text("Create a day, assign scenes, and prepare its crew and cast calls."))
            }
        }.onAppear { if selectedDay == nil { selectedDay = workspace.project.productionDays.first?.id } }
            .onChange(of: selectedDay) { _, _ in preview = nil }
            .onChange(of: workspace.changeID) { _, _ in preview = nil }
            .onChange(of: workspace.paper) { _, _ in preview = nil }
    }

    private func planning(_ day: ProductionDay) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DatePicker("Shoot Date", selection: Binding(get: { ProductionDates.date(self.day?.date ?? day.date) ?? Date() }, set: { date in
                    workspace.edit("Change Shooting Date") { try $0.updateProductionDay(day.id, field: .date, value: ProductionDates.string(date, timeZone: TimeZone(secondsFromGMT: 0)!)) }
                }), displayedComponents: .date).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                HStack { dayTimePicker(day, field: .callTime); dayTimePicker(day, field: .wrapTime) }
                ForEach(workspace.project.scheduleWarnings(for: day.id), id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                Text("Scenes and estimates").font(.headline)
                ForEach(workspace.project.scenes.filter { !$0.isDisabled }) { scene in
                    HStack {
                        Toggle("\(workspace.project.sceneNumber(for: scene.id)) · \(scene.title)", isOn: Binding(
                            get: { self.day?.sceneIDs.contains(scene.id) ?? false },
                            set: { assigned in workspace.edit(assigned ? "Schedule Scene" : "Unschedule Scene") { try $0.assignScene(scene.id, toProductionDay: assigned ? day.id : nil) } }))
                        if let assigned = workspace.project.productionDays.first(where: { $0.sceneIDs.contains(scene.id) }), assigned.id != day.id {
                            Text("Day \(assigned.number)").font(.caption).foregroundStyle(.secondary)
                        }
                        Stepper("\(workspace.project.sceneEstimate(scene.id)) min", value: Binding(
                            get: { workspace.project.sceneEstimate(scene.id) },
                            set: { value in workspace.edit("Change Scene Estimate") { try $0.setSceneEstimate(scene.id, minutes: value) } }), in: 1...1440, step: 5)
                            .frame(width: 140)
                    }
                }
                let assigned = workspace.project.scheduledScenes(for: day.id)
                if !assigned.isEmpty {
                    Text("Shooting order").font(.headline)
                    ForEach(assigned) { scene in
                        HStack {
                            Text(scene.title)
                            Spacer()
                            Button { workspace.edit("Reorder Shooting Scenes") { try $0.moveScheduledScene(scene.id, dayID: day.id, offset: -1) } }
                                label: { Image(systemName: "arrow.up") }
                            Button { workspace.edit("Reorder Shooting Scenes") { try $0.moveScheduledScene(scene.id, dayID: day.id, offset: 1) } }
                                label: { Image(systemName: "arrow.down") }
                        }
                    }
                }
                let stale = day.sceneIDs.filter { id in !workspace.project.scenes.contains { $0.id == id && !$0.isDisabled } }
                ForEach(stale, id: \.self) { id in
                    Button("Unassign omitted/missing scene \(id)") { workspace.edit("Remove Stale Assignment") { try $0.assignScene(id, toProductionDay: nil) } }
                }
                Divider()
                Text("Location, safety and crew").font(.headline)
                Text("Enter real contact and weather information before distributing a call sheet.").font(.caption).foregroundStyle(.secondary)
                ForEach(ProductionField.allCases.filter { ![.date, .callTime, .wrapTime].contains($0) }, id: \.self) { field in
                    TextField(field.label, text: Binding(get: { self.day?.fields[field.rawValue] ?? "" }, set: { value in
                        workspace.edit("Edit Production Details", key: "day-\(day.id)-\(field.rawValue)") { try $0.updateProductionDay(day.id, field: field, value: value) }
                    }), axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...5)
                }
                Divider()
                Text("Cast calls").font(.headline)
                ForEach(workspace.project.castForProductionDay(day.id)) { role in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(role.name) · \(role.artists.first { $0.id == role.confirmedArtistID }?.name ?? "Casting unconfirmed")").font(.headline)
                        ForEach(CastTimingField.allCases.filter { $0 != .notes }, id: \.self) { field in
                            castTimePicker(day, role: role, field: field)
                        }
                        TextField("Call notes", text: Binding(get: { self.day?.castCalls[role.id]?["notes"] ?? "" }, set: { value in
                            workspace.edit("Edit Cast Call Notes", key: "cast-call-\(day.id)-\(role.id)") { try $0.updateCastCall(dayID: day.id, characterID: role.id, field: .notes, value: value) }
                        }), axis: .vertical).textFieldStyle(.roundedBorder)
                    }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func timeDate(_ time: String, day: ProductionDay) -> Date {
        (ProductionDates.date(day.date) ?? Date(timeIntervalSince1970: 0))
            .addingTimeInterval(Double((ProductionDates.minutes(time) ?? 0) * 60))
    }

    private func dayTimePicker(_ day: ProductionDay, field: ProductionField) -> some View {
        DatePicker(field.label, selection: Binding(get: {
            timeDate((field == .callTime ? self.day?.callTime : self.day?.wrapTime) ?? day.callTime, day: day)
        }, set: { date in workspace.edit("Change Shooting Times") { try $0.updateProductionDay(day.id, field: field, value: ProductionDates.time(date)) } }),
        displayedComponents: .hourAndMinute).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
    }

    private func castTimePicker(_ day: ProductionDay, role: CharacterRecord, field: CastTimingField) -> some View {
        let value = self.day?.castCalls[role.id]?[field.rawValue]
        return HStack {
            if let value {
                DatePicker(field.label, selection: Binding(get: { timeDate(value, day: day) }, set: { date in
                    workspace.edit("Change Cast Call Time") { try $0.updateCastCall(dayID: day.id, characterID: role.id, field: field, value: ProductionDates.time(date)) }
                }), displayedComponents: .hourAndMinute).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                Button("Clear") { workspace.edit("Clear Cast Call Time") { try $0.updateCastCall(dayID: day.id, characterID: role.id, field: field, value: "") } }
            } else {
                Text("\(field.label): \(field == .onSetTime ? "Crew call (default)" : "Not entered")").font(.caption)
                Button("Set Time") { workspace.edit("Set Cast Call Time") { try $0.updateCastCall(dayID: day.id, characterID: role.id, field: field, value: day.callTime) } }
            }
        }
    }

    private func reportAction(_ action: (RenderedScreenplay) throws -> Void) {
        guard let day else { return }
        do { try action(ProductionDocument.render(project: workspace.project, dayID: day.id, paper: workspace.paper)) }
        catch { workspace.errorMessage = error.localizedDescription }
    }
}
#endif
