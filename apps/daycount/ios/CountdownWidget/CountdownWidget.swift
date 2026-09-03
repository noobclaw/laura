import SwiftUI
import WidgetKit

// iOS counterpart of android/.../CountdownWidgetProvider.kt.
//
// Flutter (lib/tool/widget_bridge.dart) writes only *data* — the featured
// event's title, emoji, target date, yearly flag and localized label
// templates — into the shared App Group defaults through the home_widget
// plugin. This extension computes "how many days" from the device clock
// every time it renders, so the number is right at 00:00 whether or not the
// app is ever opened again, and the timeline carries an entry per midnight.

private let appGroupId = "group.com.noobclaw.daycount"
private let widgetKind = "CountdownWidget"

struct CountdownEntry: TimelineEntry {
  let date: Date
  let hasEvent: Bool
  let heading: String
  let number: String
  let label: String
  let dateText: String

  static let placeholder = CountdownEntry(
    date: Date(), hasEvent: true, heading: "🎂 生日 Birthday",
    number: "12", label: "还有 12 天", dateText: "2026-09-15")
}

/// The raw values Flutter saved. Missing keys fall back to the empty state.
private struct SharedData {
  let hasEvent: Bool
  let title: String
  let emoji: String
  let dateIso: String
  let yearly: Bool
  let labelFuture: String
  let labelFuture1: String
  let labelPast: String
  let labelPast1: String
  let labelToday: String
  let emptyLabel: String
  let emptyDate: String

  static func load() -> SharedData {
    let d = UserDefaults(suiteName: appGroupId)
    func s(_ key: String, _ fallback: String = "") -> String {
      d?.string(forKey: key) ?? fallback
    }
    return SharedData(
      hasEvent: s("dc_has_event") == "true",
      title: s("dc_title", "倒数日"),
      emoji: s("dc_emoji"),
      dateIso: s("dc_date_iso"),
      yearly: s("dc_yearly") == "true",
      labelFuture: s("dc_label_future", "{n}"),
      labelFuture1: s("dc_label_future_1", "1"),
      labelPast: s("dc_label_past", "{n}"),
      labelPast1: s("dc_label_past_1", "1"),
      labelToday: s("dc_label_today", "🎉"),
      emptyLabel: s("dc_empty_label", "还没有添加日子"),
      emptyDate: s("dc_empty_date", "打开 App 添加"))
  }
}

private let isoFormatter: DateFormatter = {
  let f = DateFormatter()
  f.calendar = Calendar(identifier: .gregorian)
  f.locale = Locale(identifier: "en_US_POSIX")
  f.timeZone = TimeZone.current
  f.dateFormat = "yyyy-MM-dd"
  return f
}()

/// Same rule as the Dart model's `nextYearlyOccurrence` and the Kotlin
/// provider: the next occurrence of the anchor's month/day on or after today,
/// clamped to the month's length (29 Feb → 28 Feb in a common year).
private func nextYearly(anchor: Date, today: Date, calendar: Calendar) -> Date {
  let a = calendar.dateComponents([.month, .day], from: anchor)
  func clamp(year: Int) -> Date {
    var c = DateComponents()
    c.year = year
    c.month = a.month
    c.day = 1
    let first = calendar.date(from: c)!
    let length = calendar.range(of: .day, in: .month, for: first)!.count
    c.day = min(a.day ?? 1, length)
    return calendar.date(from: c)!
  }
  let y = calendar.component(.year, from: today)
  let thisYear = clamp(year: y)
  return thisYear < today ? clamp(year: y + 1) : thisYear
}

func makeEntry(at now: Date) -> CountdownEntry {
  let data = SharedData.load()
  let heading = data.emoji.isEmpty ? data.title : "\(data.emoji) \(data.title)"
  guard data.hasEvent else {
    return CountdownEntry(
      date: now, hasEvent: false, heading: heading, number: "—",
      label: data.emptyLabel, dateText: data.emptyDate)
  }
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone.current
  let today = calendar.startOfDay(for: now)
  guard let parsed = isoFormatter.date(from: data.dateIso) else {
    return CountdownEntry(
      date: now, hasEvent: true, heading: heading, number: "—", label: "", dateText: "")
  }
  let anchor = calendar.startOfDay(for: parsed)
  let target = data.yearly ? nextYearly(anchor: anchor, today: today, calendar: calendar) : anchor
  let days = calendar.dateComponents([.day], from: today, to: target).day ?? 0
  let number = days == 0 ? "🎉" : String(abs(days))
  let label: String
  switch days {
  case 0: label = data.labelToday
  case 1: label = data.labelFuture1
  case -1: label = data.labelPast1
  case let n where n > 0: label = data.labelFuture.replacingOccurrences(of: "{n}", with: String(n))
  default: label = data.labelPast.replacingOccurrences(of: "{n}", with: String(-days))
  }
  return CountdownEntry(
    date: now, hasEvent: true, heading: heading, number: number, label: label,
    dateText: isoFormatter.string(from: target))
}

struct CountdownProvider: TimelineProvider {
  func placeholder(in context: Context) -> CountdownEntry { .placeholder }

  func getSnapshot(in context: Context, completion: @escaping (CountdownEntry) -> Void) {
    completion(context.isPreview ? .placeholder : makeEntry(at: Date()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownEntry>) -> Void) {
    // One entry now, then one just after each of the next seven local
    // midnights — the number only changes when the date does.
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone.current
    let now = Date()
    var entries = [makeEntry(at: now)]
    var day = calendar.startOfDay(for: now)
    for _ in 0..<7 {
      guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
      day = next
      entries.append(makeEntry(at: day.addingTimeInterval(5)))
    }
    completion(Timeline(entries: entries, policy: .atEnd))
  }
}

struct CountdownWidgetEntryView: View {
  var entry: CountdownEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(entry.heading)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Spacer(minLength: 0)
      Text(entry.number)
        .font(.system(size: family == .systemSmall ? 44 : 52, weight: .bold, design: .rounded))
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .foregroundStyle(entry.hasEvent ? Color.accentColor : Color.secondary)
      Text(entry.label)
        .font(.footnote.weight(.medium))
        .lineLimit(1)
      Text(entry.dateText)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .modifier(WidgetBackground())
  }
}

/// iOS 17 requires `containerBackground`; earlier systems paint their own.
private struct WidgetBackground: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 17.0, *) {
      content.containerBackground(for: .widget) { Color(UIColor.systemBackground) }
    } else {
      content.padding().background(Color(UIColor.systemBackground))
    }
  }
}

@main
struct CountdownWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: widgetKind, provider: CountdownProvider()) { entry in
      CountdownWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("倒数日 DayCount")
    .description("最近的日子倒计时 · Countdown to your next big day")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
