//
//  AnonProWidgetLiveActivity.swift
//  AnonProWidget
//
//  Created by Oresajo Oluwaferanmi Idunuoluwa on 09/03/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct AnonProWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct AnonProWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AnonProWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension AnonProWidgetAttributes {
    fileprivate static var preview: AnonProWidgetAttributes {
        AnonProWidgetAttributes(name: "World")
    }
}

extension AnonProWidgetAttributes.ContentState {
    fileprivate static var smiley: AnonProWidgetAttributes.ContentState {
        AnonProWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: AnonProWidgetAttributes.ContentState {
         AnonProWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: AnonProWidgetAttributes.preview) {
   AnonProWidgetLiveActivity()
} contentStates: {
    AnonProWidgetAttributes.ContentState.smiley
    AnonProWidgetAttributes.ContentState.starEyes
}
