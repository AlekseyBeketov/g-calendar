import AppKit
import SwiftUI
import CoreText

/// Synthetic production views only. Windows are never ordered front.
enum CalendarTimedCardNativeTests {
    static let zone = TimeZone(secondsFromGMT: 0)!
    static let day = DateOnly(rawValue: "2026-10-08")!.startOfDay(in: zone)!
    static func event(_ id: String, minute: Double, duration: Double, long: Bool = false, recurring: Bool = false) -> CalendarEvent {
        let start = day.addingTimeInterval(minute * 60)
        let end = start.addingTimeInterval(duration * 60)
        return CalendarEvent(id: id, calendarID: "synthetic", title: long ? "Длинное нейтральное название события для проверки переноса и многоточия" : "Короткая встреча",
                             start: EventTime(rawValue: ISO8601.format(start), instant: start, dateOnly: nil, timeZoneID: zone.identifier),
                             end: EventTime(rawValue: ISO8601.format(end), instant: end, dateOnly: nil, timeZoneID: zone.identifier),
                             recurring: recurring, status: "confirmed")
    }

    @discardableResult static func run() -> Int {
        let directory = ProcessInfo.processInfo.environment["G_CALENDAR_CARD_EVIDENCE_DIR"].map { URL(fileURLWithPath: $0) }
        if let directory { try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        var assertions = 0
        var metrics: [[String: Any]] = []
        func expect(_ value: Bool, _ name: String) {
            if !value { FileHandle.standardError.write(Data("FAIL timed-card: \(name)\n".utf8)); exit(1) }
            assertions += 1
        }
        func render(_ view: AnyView, width: CGFloat, height: CGFloat, appearance: String, name: String) {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = appearance == "system" ? nil : NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
            let host = NSHostingView(rootView: view)
            window.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            expect(!window.isVisible, "fixture stays offscreen")
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            if let directory { try! bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png")) }
            if name.hasPrefix("card-") {
                let dark = window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                var inkRows: [Int] = []
                for y in 0..<bitmap.pixelsHigh {
                    var hasInk = false
                    for x in 12..<max(13, bitmap.pixelsWide - 6) {
                        if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                            let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                            if dark ? brightness > 0.65 : brightness < 0.35 { hasInk = true; break }
                        }
                    }
                    if hasInk { inkRows.append(y) }
                }
                expect(!inkRows.isEmpty, "production text actually renders pixels")
                expect(inkRows.first! >= 2 && inkRows.last! < bitmap.pixelsHigh - 2, "rendered ink clears card top and bottom")
                metrics.append(["name": name + "-pixels", "firstInkRow": inkRows.first!, "lastInkRow": inkRows.last!,
                                "inkRowCount": inkRows.count, "scanExcludesStripe": true, "pixelsHigh": bitmap.pixelsHigh])
            }
            metrics.append(["name": name, "width": width, "height": height, "appearance": appearance,
                            "effectiveAppearance": window.effectiveAppearance.name.rawValue,
                            "pixelsWide": bitmap.pixelsWide, "pixelsHigh": bitmap.pixelsHigh])
            window.close()
        }
        let durations: [Double] = [1, 5, 10, 15, 30, 60, 120]
        let fixtures = durations.enumerated().map { event("duration-\($0.offset)", minute: 600 + Double($0.offset) * 90, duration: $0.element, long: $0.offset % 2 == 1) }
        let overlaps = [event("near-1000", minute: 600, duration: 5), event("near-1010", minute: 610, duration: 5, long: true, recurring: true)]
        let midnight = [event("end-day", minute: 1435, duration: 4, long: true)]
        for appearance in ["light", "dark", "system"] {
            for width: CGFloat in [160, 80, 700] {
                let calendar = CalendarInfo(id: "synthetic", title: "Синтетический календарь только для просмотра", accessRole: "reader", timeZoneID: zone.identifier, colorHex: "#B2EBF2")
                for (name, events) in [("durations", fixtures), ("overlap", overlaps), ("end-day", midnight)] {
                    let view = CalendarTimeGridDay(day: day, events: events, tasks: [], calendars: [calendar], timeZone: zone, columnWidth: width, onEdit: { _ in }, onToggleTask: { _ in })
                    #if CALENDAR_CARD_BASELINE
                    let height: CGFloat = 1440 * 0.8 + 8
                    #else
                    let height = CGFloat(1440 * 0.8 + CalendarTimedCardLayout.bottomPadding(minimumHeight: CalendarTimedCardTypography().policy.minimumHeight))
                    #endif
                    render(AnyView(view), width: width, height: height, appearance: appearance, name: "\(name)-\(Int(width))-\(appearance)")
                }
            }
        }
        #if CALENDAR_CARD_BASELINE
        let titleFont = NSFont.preferredFont(forTextStyle: .caption1)
        let subtitleFont = NSFont.preferredFont(forTextStyle: .caption2)
        let titleLine = ceil(titleFont.ascender - titleFont.descender + titleFont.leading)
        let subtitleLine = ceil(subtitleFont.ascender - subtitleFont.descender + subtitleFont.leading)
        let required = titleLine + subtitleLine + 2 + 4
        expect(required > 18, "original production two-line content exceeds short-card budget")
        metrics.append(["name": "baseline-vertical-budget", "titleLine": titleLine, "subtitleLine": subtitleLine, "spacing": 2, "verticalPadding": 4, "required": required, "available": 18, "deficit": required - 18])
        #else
        let matrix = runCardMatrix(render: render)
        assertions += matrix.assertions
        metrics.append(contentsOf: matrix.metrics)
        #endif
        if let directory {
            let data = try! JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys])
            try! data.write(to: directory.appendingPathComponent("metrics.json"))
        }
        print("PASS calendar-timed-card-native: \(assertions) assertions")
        return assertions
    }
}

#if !CALENDAR_CARD_BASELINE
extension CalendarTimedCardNativeTests {
    static func runCardMatrix(render: (AnyView, CGFloat, CGFloat, String, String) -> Void) -> (assertions: Int, metrics: [[String: Any]]) {
        var metrics: [[String: Any]] = []
        var assertions = 0
        func expect(_ value: Bool, _ name: String) { if !value { FileHandle.standardError.write(Data("FAIL timed-card: \(name)\n".utf8)); exit(1) }; assertions += 1 }
        let calendar = CalendarInfo(id: "synthetic", title: "Синтетический календарь", accessRole: "reader", timeZoneID: zone.identifier, colorHex: "#B2EBF2")
        let event = event("matrix", minute: 600, duration: 5, long: true, recurring: true)
        let placement = CalendarTimeGridLayout.timedPlacements([event], on: day, timeZone: zone)[0]
        for category in [ContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            let typography = CalendarTimedCardTypography(sizeCategory: category)
            let policy = typography.policy
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Короткая встреча Йруф", attributes: [.font: typography.titleFont]))
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let glyphBounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
            expect(Double(ascent + descent + leading) <= policy.titleLineHeight, "CoreText line fits measured native budget")
            expect(Double(glyphBounds.height) <= policy.titleLineHeight, "actual glyph bounds fit complete line")
            expect(policy.minimumHeight >= policy.titleLineHeight + 6, "minimum includes entire line and insets")
            metrics.append(["name": "font-\(category)", "font": typography.titleFont.fontName,
                            "pointSize": typography.titleFont.pointSize, "ascent": ascent, "descent": descent, "leading": leading,
                            "glyphBounds": NSStringFromRect(glyphBounds), "titleLineHeight": policy.titleLineHeight,
                            "timeLineHeight": policy.timeLineHeight, "minimumHeight": policy.minimumHeight,
                            "twoLineThreshold": policy.twoLineThreshold, "timeThreshold": policy.timeThreshold])
            let heights = category == .large ? [24.0, 39, 40, 55, 56, 96] : [policy.minimumHeight, policy.twoLineThreshold - 1, policy.twoLineThreshold, policy.timeThreshold - 1, policy.timeThreshold, 120]
            for appearance in ["light", "dark", "system"] {
                for width: CGFloat in [160, 80, 700] {
                    var cards: [AnyView] = []
                    for height in heights {
                        let budget = policy.contentBudget(height: height)
                        let required = Double(budget.titleLines) * policy.titleLineHeight + 6 + (budget.showsTime ? policy.timeLineHeight + 2 : 0)
                        expect(required <= height, "complete lines fit allocated content height")
                        let card = CalendarTimedEventCard(event: event, calendar: calendar, timeZone: zone, placement: placement,
                                                         width: width, height: height, typography: typography, onEdit: { _ in })
                        expect(card.detailText.contains(event.title) && card.detailText.contains("10:00–10:05") && card.detailText.contains(calendar.title) && card.detailText.contains("повторяется") && card.detailText.contains("только просмотр"), "full original details remain available")
                        let name = "card-\(Int(width))-h\(Int(height))-\(appearance)-\(category)"
                        render(AnyView(card), width, height, appearance, name)
                        metrics.append(["name": name + "-budget", "height": height, "titleLines": budget.titleLines,
                                        "showsTime": budget.showsTime, "requiredLineBudget": required, "slack": height - required])
                        cards.append(AnyView(VStack(alignment: .leading, spacing: 4) {
                            Text("\(Int(width)) pt · h=\(Int(height)) · \(budget.titleLines) title lines · time=\(String(budget.showsTime))").font(.caption)
                            card
                        }))
                    }
                    let sheet = VStack(alignment: .leading, spacing: 12) {
                        Text("Production timed cards · \(appearance) · \(String(describing: category))").font(.headline)
                        ForEach(cards.indices, id: \.self) { cards[$0] }
                    }.padding(12).background(AppTheme.surface)
                    render(AnyView(sheet), max(360, width + 24), CGFloat(heights.reduce(0, +)) + 260, appearance,
                           "contact-\(Int(width))-\(appearance)-\(category)")
                }
            }
            let lateEvent = self.event("grown-end-day", minute: 1435, duration: 4)
            let dayView = CalendarTimeGridDay(day: day, events: [lateEvent], tasks: [], calendars: [calendar], timeZone: zone,
                                             columnWidth: 160, onEdit: { _ in }, onToggleTask: { _ in })
                .environment(\.sizeCategory, category)
            render(AnyView(dayView), 160, CGFloat(1440 * 0.8 + CalendarTimedCardLayout.bottomPadding(minimumHeight: policy.minimumHeight)), "light", "end-day-font-\(category)")
            let placements = CalendarTimeGridLayout.timedPlacements([self.event("a", minute: 600, duration: 5), self.event("b", minute: 630, duration: 5)], on: day, timeZone: zone, minimumEventHeight: policy.minimumHeight)
            expect((placements[0].laneIndex == placements[1].laneIndex) == (policy.minimumHeight <= 24), "runtime font minimum also controls overlap lanes")
        }
        for dark in [false, true] {
            for hex: UInt32 in [0xB2EBF2, 0xFFFF00, 0xFF0000, 0x000000, 0xFFFFFF, 0x0B57D0, 0x188038, 0x7986CB, 0x33B679, 0x8E24AA, 0xE67C73, 0xF6BF26, 0xF4511E, 0x039BE5, 0x616161, 0x3F51B5, 0x0B8043, 0xD50000] {
                let background = ThemePalette.RGB(hex: hex).blended(over: ThemePalette.color(.surface, dark: dark), opacity: 0.16)
                let ratio = ThemePalette.color(.textPrimary, dark: dark).contrast(against: background)
                expect(ratio >= 4.5, "exact single-layer title contrast")
                metrics.append(["name": "contrast", "calendarColor": String(format: "#%06X", hex), "dark": dark, "opacity": 0.16, "ratio": ratio])
            }
        }
        for appearance in ["light", "dark", "system"] {
            let colors = ["#B2EBF2", "#FFFF00", "#FF0000", "#000000", "#FFFFFF", "#0B57D0", "#188038", "#7986CB", "#33B679", "#8E24AA", "#E67C73", "#F6BF26", "#F4511E", "#039BE5", "#616161", "#3F51B5", "#0B8043", "#D50000"]
            let sheet = VStack(alignment: .leading, spacing: 8) {
                Text("Production single tint · \(appearance)").font(.headline)
                ForEach(colors, id: \.self) { hex in
                    HStack(spacing: 12) {
                        Text(hex).font(.caption).frame(width: 80, alignment: .leading)
                        CalendarTimedEventCard(event: self.event("color", minute: 600, duration: 5),
                            calendar: CalendarInfo(id: "synthetic", title: "Синтетический календарь", accessRole: "writer", timeZoneID: zone.identifier, colorHex: hex),
                            timeZone: zone, placement: placement, width: 160, height: 24, typography: CalendarTimedCardTypography(), onEdit: { _ in })
                    }
                }
            }.padding(12).background(AppTheme.surface)
            render(AnyView(sheet), 300, 640, appearance, "colors-" + appearance)
        }
        for category in [ContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            let minimum = CalendarTimedCardTypography(sizeCategory: category).policy.minimumHeight
            let documentHeight = CGFloat(1440 * CalendarGridLayout.pointsPerMinute + CalendarTimedCardLayout.bottomPadding(minimumHeight: minimum))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 250, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let regions = CalendarScrollRegionsView(frame: NSRect(x: 0, y: 0, width: 250, height: 200))
            window.contentView = regions
            let late = self.event("native-end", minute: 1435, duration: 4)
            let dayView = CalendarTimeGridDay(day: day, events: [late], tasks: [], calendars: [calendar], timeZone: zone, columnWidth: 160, onEdit: { _ in }, onToggleTask: { _ in })
                .environment(\.sizeCategory, category)
            regions.configure(axis: AnyView(CalendarHourAxis(day: day, timeZone: zone, height: documentHeight)), headers: AnyView(Color.clear), days: AnyView(dayView),
                              axisWidth: 44, headerHeight: 0, documentWidth: 160, documentHeight: documentHeight, initialVerticalOffset: 0)
            regions.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            expect(regions.daysScroll.documentView!.frame.height == documentHeight && regions.axisScroll.documentView!.frame.height == documentHeight, "actual native day/axis documents share grown bottom budget")
            let end = CGFloat(1435 * CalendarGridLayout.pointsPerMinute + CalendarTimedCardLayout.displayHeight(durationMinutes: 4, minimumHeight: minimum))
            expect(end <= documentHeight, "late production card fits native document")
            let bottom = documentHeight - regions.daysScroll.contentView.bounds.height
            regions.daysScroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
            regions.daysScroll.reflectScrolledClipView(regions.daysScroll.contentView)
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            expect(regions.axisScroll.contentView.bounds.minY == regions.daysScroll.contentView.bounds.minY, "shared axis follows actual bottom scroll")
            metrics.append(["name": "native-document-\(category)", "minimumHeight": minimum, "documentHeight": documentHeight,
                            "cardEnd": end, "bottomOffset": regions.daysScroll.contentView.bounds.minY,
                            "axisOffset": regions.axisScroll.contentView.bounds.minY])
            regions.disconnect()
            window.close()
        }
        // These are native AX actions on an isolated production Button, not desktop input.
        var opened: [CalendarEventIdentity] = []
        let card = CalendarTimedEventCard(event: event, calendar: calendar, timeZone: zone, placement: placement,
                                         width: 160, height: 24, typography: CalendarTimedCardTypography(), onEdit: { opened.append($0.identity) })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 24), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: card)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let activationBitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: activationBitmap)
        func descendants(_ element: NSAccessibilityProtocol) -> [NSAccessibilityProtocol] {
            [element] + (element.accessibilityChildren() ?? []).compactMap { $0 as? NSAccessibilityProtocol }.flatMap { descendants($0) }
        }
        let unignored = NSAccessibility.unignoredChildrenForOnlyChild(from: host).compactMap { $0 as? NSAccessibilityProtocol }
        let elements = descendants(host) + unignored.flatMap { descendants($0) }
        if let button = elements.first(where: { $0.accessibilityRole() == .button }) {
            expect(button.accessibilityLabel() == card.detailText, "native Button AX label is complete")
            expect(button.accessibilityValue() as? String == "600 минут от начала дня, длительность 5 минут, полоса 1 из 1", "native AX value reports actual duration and lane")
            expect(button.accessibilityPerformPress() == true, "native AX button activation")
            expect(opened == [event.identity], "activation sends original composite identity to existing onEdit")
            metrics.append(["name": "native-activation", "axPress": true, "onEditOriginalIdentity": true])
        } else {
            // SwiftUI may omit its lazy AX tree for windows never ordered front.
            // Do not change system AX settings or show a window just to make this probe pass.
            metrics.append(["name": "native-activation", "axPress": false, "status": "unverified: offscreen SwiftUI AX children unavailable"])
            print("UNVERIFIED timed-card AX press: offscreen SwiftUI children unavailable")
        }
        let acceptsFocus = window.makeFirstResponder(host)
        metrics.append(["name": "isolated-focus-probe", "acceptsFocus": acceptsFocus])
        let beforeKeyboard = opened.count
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                  context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
        host.keyDown(with: key)
        metrics.append(["name": "isolated-keyboard-probe", "spaceOpened": opened.count > beforeKeyboard,
                        "scope": "direct NSHostingView responder; no key/front window or global events"])
        print("PROBE timed-card isolated focus=\(acceptsFocus) spaceOpened=\(opened.count > beforeKeyboard)")
        expect(!window.isVisible, "activation fixture never shown")
        window.close()
        return (assertions, metrics)
    }
}
#endif
