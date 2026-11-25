import Foundation
import SwiftUI
import UIKit

enum ChartExportFormat: String, CaseIterable {
    case midi, musicXML, pdf
    var fileExtension: String {
        switch self {
        case .midi: return "mid"
        case .musicXML: return "musicxml"
        case .pdf: return "pdf"
        }
    }
}

enum ChartExporter {
    static let watermark = "Made with Groovelens"

    @MainActor
    static func export(_ chart: DrumChart, title: String, format: ChartExportFormat) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(safeName(title)).\(format.fileExtension)")
        try? FileManager.default.removeItem(at: url)
        switch format {
        case .midi: try MIDIExporter.data(chart, title: title).write(to: url)
        case .musicXML: try Data(MusicXMLExporter.xml(chart, title: title).utf8).write(to: url)
        case .pdf: try PDFExporter.data(chart, title: title).write(to: url)
        }
        return url
    }

    static func safeName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = s.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Groovelens chart" : String(cleaned.prefix(80))
    }
}

// MARK: - MIDI (SMF type 0, GM drums on channel 10)

enum MIDIExporter {
    static let ppq = 480

    static func data(_ chart: DrumChart, title: String) -> Data {
        let ticksPerChartTick = ppq / DrumChart.ticksPerBeat   // 40
        var events: [(tick: Int, bytes: [UInt8])] = []

        // Meta: name, copyright-style watermark, tempo, time signature.
        events.append((0, meta(0x03, Array(title.utf8.prefix(120)))))
        events.append((0, meta(0x01, Array(ChartExporter.watermark.utf8))))
        let mpq = Int((60_000_000 / max(chart.tempo, 20)).rounded())
        events.append((0, meta(0x51, [UInt8((mpq >> 16) & 0xFF), UInt8((mpq >> 8) & 0xFF), UInt8(mpq & 0xFF)])))
        events.append((0, meta(0x58, [UInt8(chart.beatsPerBar), 2, 24, 8])))

        let noteLen = ppq / 8
        for h in chart.hits where h.bar >= 0 {
            let t = (h.bar * chart.beatsPerBar * DrumChart.ticksPerBeat + h.tick) * ticksPerChartTick
            let note = h.piece.midiNote(open: h.isOpen)
            let vel = UInt8(max(1, min(127, Int((h.isGhost ? h.velocity * 0.5 : h.velocity) * 127))))
            events.append((t, [0x99, note, vel]))
            events.append((t + noteLen, [0x89, note, 0]))
        }
        // Stable sort: note-offs before note-ons at the same tick.
        let sorted = events.enumerated().sorted { a, b in
            if a.element.tick != b.element.tick { return a.element.tick < b.element.tick }
            let ao = a.element.bytes.first == 0x89, bo = b.element.bytes.first == 0x89
            if ao != bo { return ao }
            return a.offset < b.offset
        }.map(\.element)

        var track: [UInt8] = []
        var last = 0
        for e in sorted {
            track += vlq(e.tick - last)
            track += e.bytes
            last = e.tick
        }
        track += [0x00, 0xFF, 0x2F, 0x00]

        var out: [UInt8] = Array("MThd".utf8) + be32(6) + be16(0) + be16(1) + be16(UInt16(ppq))
        out += Array("MTrk".utf8) + be32(UInt32(track.count)) + track
        return Data(out)
    }

    static func meta(_ type: UInt8, _ payload: [UInt8]) -> [UInt8] { [0xFF, type] + vlq(payload.count) + payload }

    static func vlq(_ value: Int) -> [UInt8] {
        var v = max(0, value)
        var bytes: [UInt8] = [UInt8(v & 0x7F)]
        v >>= 7
        while v > 0 {
            bytes.insert(UInt8((v & 0x7F) | 0x80), at: 0)
            v >>= 7
        }
        return bytes
    }

    static func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
    static func be16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
}

// MARK: - MusicXML (partwise 4.0, percussion clef, two voices)

enum MusicXMLExporter {
    /// divisions per quarter = chart ticks per beat (12), so ticks map 1:1 to durations.
    static let divisions = DrumChart.ticksPerBeat

    /// Representable note values in divisions, largest first: (duration, type, dots, triplet).
    static let values: [(Int, String, Int, Bool)] = [
        (48, "whole", 0, false), (36, "half", 1, false), (24, "half", 0, false), (18, "quarter", 1, false),
        (12, "quarter", 0, false), (9, "eighth", 1, false), (8, "quarter", 0, true), (6, "eighth", 0, false),
        (4, "eighth", 0, true), (3, "16th", 0, false), (2, "16th", 0, true), (1, "32nd", 0, true)
    ]

    static func step(_ piece: DrumPiece) -> (String, Int) {
        let names = ["E", "F", "G", "A", "B", "C", "D"]
        let pos = piece.staffPosition         // 0 = E4
        let idx = pos % 7
        let octave = 4 + (pos + 2) / 7        // E4..B4 → 4, C5.. → 5
        return (names[idx], octave)
    }

    static func xml(_ chart: DrumChart, title: String) -> String {
        let esc: (String) -> String = {
            $0.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        var x = """
        <?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">
        <score-partwise version="4.0">
          <work><work-title>\(esc(title))</work-title></work>
          <identification><encoding><software>\(ChartExporter.watermark)</software></encoding></identification>
          <part-list>
            <score-part id="P1">
              <part-name>Drums</part-name>

        """
        for p in DrumPiece.allCases {
            x += "      <score-instrument id=\"P1-\(p.rawValue)\"><instrument-name>\(p.displayName)</instrument-name></score-instrument>\n"
        }
        for p in DrumPiece.allCases {
            x += "      <midi-instrument id=\"P1-\(p.rawValue)\"><midi-channel>10</midi-channel><midi-unpitched>\(Int(p.midiNote(open: false)) + 1)</midi-unpitched></midi-instrument>\n"
        }
        x += "    </score-part>\n  </part-list>\n  <part id=\"P1\">\n"

        let byBar = Dictionary(grouping: chart.hits.filter { $0.bar >= 0 }, by: \.bar)
        let barTicks = chart.ticksPerBar
        for bar in 0..<chart.barCount {
            x += "    <measure number=\"\(bar + 1)\">\n"
            if bar == 0 {
                x += """
                      <attributes><divisions>\(divisions)</divisions><time><beats>\(chart.beatsPerBar)</beats><beat-type>4</beat-type></time><clef><sign>percussion</sign></clef></attributes>
                      <direction placement="above"><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>\(Int(chart.tempo.rounded()))</per-minute></metronome></direction-type><sound tempo="\(Int(chart.tempo.rounded()))"/></direction>

                """
            }
            if chart.sections.contains(where: { $0.startBar == bar }), let s = chart.sections.first(where: { $0.startBar == bar }) {
                x += "      <direction placement=\"above\"><direction-type><rehearsal>\(esc(s.label))</rehearsal></direction-type></direction>\n"
            }
            let hits = byBar[bar] ?? []
            let voices: [(Int, String, [DrumHit])] = [(1, "up", hits.filter { !$0.piece.isFoot }), (2, "down", hits.filter { $0.piece.isFoot })]
            for (vi, (voice, stem, vh)) in voices.enumerated() {
                if vi == 1 { x += "      <backup><duration>\(barTicks)</duration></backup>\n" }
                x += voiceXML(vh, voice: voice, stem: stem, barTicks: barTicks)
            }
            x += "    </measure>\n"
        }
        x += "  </part>\n</score-partwise>\n"
        return x
    }

    static func voiceXML(_ hits: [DrumHit], voice: Int, stem: String, barTicks: Int) -> String {
        var out = ""
        let onsets = Array(Set(hits.map { min(max(0, $0.tick), barTicks - 1) })).sorted()
        var cursor = 0
        func rest(_ len: Int) {
            for (d, type, dots, trip) in decompose(len) {
                out += "      <note><rest/><duration>\(d)</duration><voice>\(voice)</voice><type>\(type)</type>\(String(repeating: "<dot/>", count: dots))\(trip ? tripletXML : "")</note>\n"
            }
        }
        for (i, onset) in onsets.enumerated() {
            if onset > cursor { rest(onset - cursor) }
            let next = i + 1 < onsets.count ? onsets[i + 1] : barTicks
            let gap = next - onset
            let pieces = decompose(gap)
            let (d, type, dots, trip) = pieces[0]
            let at = hits.filter { min(max(0, $0.tick), barTicks - 1) == onset }
            for (j, h) in at.enumerated() {
                let (stepName, octave) = step(h.piece)
                let head = h.piece.isCymbal ? "<notehead>\(h.isOpen ? "circle-x" : "x")</notehead>" : ""
                out += "      <note>\(j > 0 ? "<chord/>" : "")<unpitched><display-step>\(stepName)</display-step><display-octave>\(octave)</display-octave></unpitched><duration>\(d)</duration><instrument id=\"P1-\(h.piece.rawValue)\"/><voice>\(voice)</voice><type>\(type)</type>\(String(repeating: "<dot/>", count: dots))\(trip ? tripletXML : "")<stem>\(stem)</stem>\(head)</note>\n"
            }
            // Drums don't sustain: fill the rest of the gap with rests.
            cursor = onset + d
            if gap > d { rest(gap - d) }
            cursor = next
        }
        if onsets.isEmpty { rest(barTicks) }
        return out
    }

    static let tripletXML = "<time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification>"

    static func decompose(_ length: Int) -> [(Int, String, Int, Bool)] {
        var left = length
        var out: [(Int, String, Int, Bool)] = []
        while left > 0 {
            guard let v = values.first(where: { $0.0 <= left }) else { break }
            out.append(v)
            left -= v.0
        }
        return out.isEmpty ? [values.last!] : out
    }
}

// MARK: - PDF

enum PDFExporter {
    static let barsPerPage = 9

    @MainActor
    static func data(_ chart: DrumChart, title: String) throws -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)   // US Letter; A4 printers scale it
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let pages = stride(from: 0, to: chart.barCount, by: barsPerPage).map { $0 }
        let byBar = Dictionary(grouping: chart.hits, by: \.bar)
        return renderer.pdfData { ctx in
            for (pi, first) in pages.enumerated() {
                ctx.beginPage()
                let view = PDFPage(chart: chart, title: title, firstBar: first, lastBar: min(chart.barCount, first + barsPerPage),
                                   byBar: byBar, pageNumber: pi + 1, pageCount: pages.count)
                    .frame(width: page.width, height: page.height)
                let r = ImageRenderer(content: view)
                r.proposedSize = ProposedViewSize(page.size)
                r.render { _, draw in
                    let cg = ctx.cgContext
                    cg.saveGState()
                    // ImageRenderer draws with a flipped origin relative to the PDF context.
                    cg.translateBy(x: 0, y: page.height)
                    cg.scaleBy(x: 1, y: -1)
                    draw(cg)
                    cg.restoreGState()
                }
            }
        }
    }
}

private struct PDFPage: View {
    let chart: DrumChart
    let title: String
    let firstBar: Int
    let lastBar: Int
    let byBar: [Int: [DrumHit]]
    let pageNumber: Int
    let pageCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if pageNumber == 1 {
                Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(.black)
                Text("\(Int(chart.tempo.rounded())) BPM · \(chart.meterLabel)").font(.system(size: 11)).foregroundStyle(.gray)
                    .padding(.bottom, 8)
            }
            ForEach(firstBar..<lastBar, id: \.self) { bar in
                BarRow(chart: chart, bar: bar, hits: byBar[bar] ?? [], section: chart.sections.first { $0.startBar == bar },
                       isFill: chart.fillBars.contains(bar), playhead: nil, editing: false, printMode: true) { _, _ in }
            }
            Spacer(minLength: 0)
            HStack {
                Text(ChartExporter.watermark).font(.system(size: 9, weight: .semibold)).foregroundStyle(.gray)
                Spacer()
                Text("\(pageNumber) / \(pageCount)").font(.system(size: 9)).foregroundStyle(.gray)
            }
        }
        .padding(36)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}
