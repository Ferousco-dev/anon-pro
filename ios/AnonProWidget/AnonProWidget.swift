import WidgetKit
import SwiftUI
import AppIntents
import Foundation

// ─── App Group ───────────────────────────────────────────────────────────────
private let appGroupId = "group.com.ferous.anonpro"

// ─── Colors ──────────────────────────────────────────────────────────────────
private let appBlack      = Color(red: 0.04, green: 0.04, blue: 0.05)
private let surfaceColor  = Color(white: 1, opacity: 0.07)
private let borderColor   = Color(white: 1, opacity: 0.10)

private enum Neon {
    static let blue   = Color(red: 0.00, green: 0.60, blue: 1.00)
    static let purple = Color(red: 0.50, green: 0.22, blue: 1.00)
    static let green  = Color(red: 0.20, green: 0.88, blue: 0.55)
    static let amber  = Color(red: 1.00, green: 0.65, blue: 0.10)
    static let red    = Color(red: 1.00, green: 0.27, blue: 0.27)
}

// ─── Post model ──────────────────────────────────────────────────────────────
struct WidgetPost: Identifiable {
    let id: Int
    let author: String
    let initial: String
    let content: String
    let timeAgo: String
    let isAnon: Bool

    var accentColor: Color { isAnon ? Neon.purple : Neon.blue }
}

// ─── Entry ───────────────────────────────────────────────────────────────────
struct AnonProEntry: TimelineEntry {
    let date: Date
    let posts: [WidgetPost]
    let newPosts, newAnon, unreadMessages: Int
    let latestPreview, profileInitial, userName, lastUpdated: String

    static let placeholder: AnonProEntry = {
        let sample = [
            WidgetPost(id: 0, author: "Anonymous",  initial: "?", content: "Sometimes silence speaks louder...", timeAgo: "2m",  isAnon: true),
            WidgetPost(id: 1, author: "FERANMI",    initial: "F", content: "Just dropped something big 🔥",      timeAgo: "5m",  isAnon: false),
            WidgetPost(id: 2, author: "Anonymous",  initial: "?", content: "Why do people pretend online?",       timeAgo: "12m", isAnon: true),
            WidgetPost(id: 3, author: "AnonPro",    initial: "A", content: "This app goes hard no cap",           timeAgo: "1h",  isAnon: false),
            WidgetPost(id: 4, author: "Anonymous",  initial: "?", content: "I have a secret crush 👀",            timeAgo: "2h",  isAnon: true),
        ]
        return AnonProEntry(date: Date(), posts: sample, newPosts: 24, newAnon: 8,
                            unreadMessages: 3,
                            latestPreview: "Sometimes silence speaks louder than words...",
                            profileInitial: "A", userName: "AnonPro", lastUpdated: "Just now")
    }()
}

// ─── Reload intent ────────────────────────────────────────────────────────────
struct ReloadWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Reload AnonPro Widget"
    static var description = IntentDescription("Refreshes the widget data.")
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult { .result() }
}

// ─── Timeline provider ────────────────────────────────────────────────────────
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> AnonProEntry { .placeholder }
    func getSnapshot(in context: Context, completion: @escaping (AnonProEntry) -> ()) {
        completion(readEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AnonProEntry>) -> ()) {
        let entry = readEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func readEntry() -> AnonProEntry {
        let ud = UserDefaults(suiteName: appGroupId)

        // Parse posts JSON
        var posts: [WidgetPost] = []
        if let jsonStr = ud?.string(forKey: "recent_posts_json"),
           let data = jsonStr.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for (i, item) in arr.prefix(20).enumerated() {
                let author  = item["author"]  as? String ?? "Unknown"
                let initial = item["initial"] as? String ?? "?"
                let content = item["content"] as? String ?? ""
                let timeAgo = item["timeAgo"] as? String ?? ""
                let isAnon  = item["isAnon"]  as? Bool   ?? false
                posts.append(WidgetPost(id: i, author: author, initial: initial,
                                        content: content, timeAgo: timeAgo, isAnon: isAnon))
            }
        }

        let name    = ud?.string(forKey: "user_display_name") ?? "You"
        let lastUp  = ud?.string(forKey: "last_updated") ?? ""
        var timeLabel = "Just now"
        if !lastUp.isEmpty, let d = ISO8601DateFormatter().date(from: lastUp) {
            let diff = Int(Date().timeIntervalSince(d) / 60)
            if diff < 1      { timeLabel = "Just now" }
            else if diff < 60 { timeLabel = "\(diff)m ago" }
            else              { timeLabel = "\(diff / 60)h ago" }
        }

        return AnonProEntry(
            date: Date(),
            posts: posts.isEmpty ? AnonProEntry.placeholder.posts : posts,
            newPosts:        ud?.integer(forKey: "new_posts_count") ?? 0,
            newAnon:         ud?.integer(forKey: "anon_confessions_count") ?? 0,
            unreadMessages:  ud?.integer(forKey: "unread_messages_count") ?? 0,
            latestPreview:   ud?.string(forKey: "latest_anon_preview") ?? "No recent confessions.",
            profileInitial:  String(name.prefix(1)).uppercased(),
            userName:        name,
            lastUpdated:     timeLabel
        )
    }
}

// ─── Dispatcher ───────────────────────────────────────────────────────────────
struct AnonProWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:  SmallFeedView(entry: entry)
            case .systemMedium: MediumFeedView(entry: entry)
            case .systemLarge:  LargeCommandView(entry: entry)
            default:            SmallFeedView(entry: entry)
            }
        }
        .containerBackground(appBlack, for: .widget)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: — SMALL — Gmail-style post feed (3–4 rows)
// ═══════════════════════════════════════════════════════════════════════════════
struct SmallFeedView: View {
    var entry: AnonProEntry

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ─────────────────────────────────
            HStack(spacing: 6) {
                Text("AnonPro")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Button(intent: ReloadWidgetIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Neon.blue)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)

            // ── Post rows (fit as many as possible) ────
            VStack(spacing: 0) {
                ForEach(entry.posts.prefix(4)) { post in
                    Link(destination: URL(string: "anonpro://home")!) {
                        smallPostRow(post)
                    }
                    if post.id < min(3, entry.posts.count - 1) {
                        Divider().background(borderColor)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(surfaceColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(borderColor, lineWidth: 0.6)
                    )
            )

            Spacer(minLength: 0)

            // ── Footer ─────────────────────────────────
            Text(entry.lastUpdated)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(Color.white.opacity(0.28))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 5)
        }
        .widgetURL(URL(string: "anonpro://home"))
    }

    @ViewBuilder
    private func smallPostRow(_ post: WidgetPost) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Avatar circle
            ZStack {
                Circle()
                    .fill(post.accentColor.opacity(0.20))
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(post.accentColor.opacity(0.40), lineWidth: 0.6))
                Text(post.initial)
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(post.accentColor)
            }

            // Text
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 0) {
                    Text(post.author)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer()
                    Text(post.timeAgo)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.35))
                }
                Text(post.content)
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.60))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: — MEDIUM — Gmail-style post feed (6–8 rows)
// ═══════════════════════════════════════════════════════════════════════════════
struct MediumFeedView: View {
    var entry: AnonProEntry

    var body: some View {
        VStack(spacing: 0) {
            // ── Header bar ─────────────────────────────
            HStack(spacing: 8) {
                // Brand
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Neon.purple.opacity(0.22))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Neon.purple.opacity(0.45), lineWidth: 0.6))
                        Text(entry.profileInitial)
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(Neon.purple)
                    }
                    Text("AnonPro")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                }

                Spacer()

                // Stats pills
                HStack(spacing: 6) {
                    statPill(value: entry.newPosts, label: "posts", color: Neon.blue)
                    statPill(value: entry.newAnon,  label: "anon",  color: Neon.purple)
                    statPill(value: entry.unreadMessages, label: "msgs", color: Neon.green)
                }

                // Reload
                Button(intent: ReloadWidgetIntent()) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(surfaceColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Neon.blue.opacity(0.35), lineWidth: 0.6)
                            )
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Neon.blue)
                    }
                    .frame(width: 26, height: 22)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)

            // ── Feed list ──────────────────────────────
            VStack(spacing: 0) {
                ForEach(entry.posts.prefix(7)) { post in
                    Link(destination: URL(string: "anonpro://home")!) {
                        mediumPostRow(post)
                    }
                    if post.id < min(6, entry.posts.count - 1) {
                        Rectangle()
                            .fill(borderColor)
                            .frame(height: 0.4)
                            .padding(.leading, 38)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(surfaceColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(borderColor, lineWidth: 0.6)
                    )
            )
            .frame(maxWidth: .infinity)

            // ── Timestamp ──────────────────────────────
            Text(entry.lastUpdated)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(Color.white.opacity(0.28))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 5)
        }
    }

    @ViewBuilder
    private func mediumPostRow(_ post: WidgetPost) -> some View {
        HStack(alignment: .center, spacing: 8) {
            // Avatar
            ZStack {
                Circle()
                    .fill(post.accentColor.opacity(0.18))
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(post.accentColor.opacity(0.35), lineWidth: 0.6))
                Text(post.initial)
                    .font(.system(size: 9.5, weight: .black))
                    .foregroundColor(post.accentColor)
            }

            // Author + content
            VStack(alignment: .leading, spacing: 1) {
                Text(post.author)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(post.content)
                    .font(.system(size: 9.5, weight: .regular, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Time
            Text(post.timeAgo)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Color.white.opacity(0.32))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func statPill(value: Int, label: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundColor(Color.white.opacity(0.38))
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: — LARGE — Command Center (kept, no gradients/orbs)
// ═══════════════════════════════════════════════════════════════════════════════
struct LargeCommandView: View {
    var entry: AnonProEntry

    var body: some View {
        VStack(spacing: 10) {
            // ── Header ──────────────────────────────────────────────────────
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Neon.purple.opacity(0.22))
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(Neon.purple.opacity(0.50), lineWidth: 0.8))
                    Text(entry.profileInitial)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(Neon.purple)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("AnonPro")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("@\(entry.userName.lowercased().replacingOccurrences(of: " ", with: ""))")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.38))
                }

                Spacer()

                HStack(spacing: 8) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Updated")
                            .font(.system(size: 7.5, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.25))
                        Text(entry.lastUpdated)
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.45))
                    }

                    Button(intent: ReloadWidgetIntent()) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(surfaceColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Neon.blue.opacity(0.40), lineWidth: 0.7)
                                )
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Sync")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(Neon.blue)
                        }
                        .frame(width: 56, height: 28)
                    }
                    .buttonStyle(.plain)

                    Link(destination: URL(string: "anonpro://profile")!) {
                        ZStack {
                            Circle()
                                .fill(surfaceColor)
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(borderColor, lineWidth: 0.7))
                            Text(entry.profileInitial)
                                .font(.system(size: 12, weight: .black))
                                .foregroundColor(.white)
                        }
                    }
                }
            }

            // Divider
            Rectangle().fill(borderColor).frame(height: 0.5)

            // ── Latest confession card ───────────────────────────────────────
            Link(destination: URL(string: "anonpro://anonymous")!) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(surfaceColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(borderColor, lineWidth: 0.6)
                        )
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Text("🤫")
                                .font(.system(size: 12))
                            Text("LATEST CONFESSION")
                                .font(.system(size: 8.5, weight: .black, design: .rounded))
                                .foregroundColor(Neon.purple)
                                .tracking(1)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.30))
                        }
                        Text(entry.latestPreview)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.85))
                            .lineSpacing(2)
                            .lineLimit(3)
                    }
                    .padding(12)
                }
            }
            .frame(maxWidth: .infinity)

            // ── Stat pillars ────────────────────────────────────────────────
            HStack(spacing: 8) {
                largeStat(icon: "✦", value: entry.newPosts, label: "New Posts",
                          sub: "last 24h", color: Neon.blue, url: "anonpro://home")
                largeStat(icon: "◎", value: entry.newAnon,  label: "Anon Posts",
                          sub: "confessions", color: Neon.purple, url: "anonpro://anonymous")
                largeStat(icon: "✉", value: entry.unreadMessages, label: "Messages",
                          sub: "unread", color: Neon.green, url: "anonpro://inbox")
            }

            // ── Quick dock ──────────────────────────────────────────────────
            HStack(spacing: 8) {
                dockButton(icon: "house.fill",              label: "Home",      color: Neon.blue,   url: "anonpro://home")
                dockButton(icon: "theatermasks.fill",       label: "Anonymous", color: Neon.purple, url: "anonpro://anonymous")
                dockButton(icon: "envelope.fill",           label: "Inbox",     color: Neon.green,  url: "anonpro://inbox")
                dockButton(icon: "person.crop.circle.fill", label: "Profile",   color: Neon.amber,  url: "anonpro://profile")
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func largeStat(icon: String, value: Int, label: String, sub: String, color: Color, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(surfaceColor)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(borderColor, lineWidth: 0.6))
                VStack(spacing: 3) {
                    Text(icon)
                        .font(.system(size: 14))
                        .foregroundColor(color)
                    Text("\(value)")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(color)
                    Text(label)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.75))
                    Text(sub)
                        .font(.system(size: 7.5, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.30))
                }
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func dockButton(icon: String, label: String, color: Color, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(color.opacity(0.13))
                        .frame(width: 36, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(color.opacity(0.28), lineWidth: 0.7)
                        )
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(color)
                }
                Text(label)
                    .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.42))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// ─── Widget declaration ───────────────────────────────────────────────────────
struct AnonProWidgetEntryWidget: Widget {
    let kind: String = "AnonProWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            AnonProWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("AnonPro")
        .description("Latest posts from your AnonPro feed.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
