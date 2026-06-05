import ActivityKit
import WidgetKit
import SwiftUI

// Live Activity for an in-progress charging session — Lock Screen banner + Dynamic Island.
// Purely informational; mirrors TeslaMate's charge data and never commands the car.

struct ChargingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChargingActivityAttributes.self) { context in
            ChargingLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Brand.background)
                .activitySystemActionForegroundColor(Brand.crimson)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text("\(context.state.batteryLevel)%").font(.title3.weight(.bold))
                    } icon: {
                        Image(systemName: context.state.isComplete ? "checkmark.circle.fill" : "bolt.fill")
                            .foregroundStyle(Brand.crimson)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    (context.state.isComplete ? Text("Done") : Text(verbatim: context.state.powerString))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(context.state.isComplete ? Brand.online : Brand.crimson)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.carName)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressView(value: context.state.progress)
                            .tint(Brand.crimson)
                        HStack {
                            Text(verbatim: context.state.rangeString)
                            Spacer()
                            if !context.state.isComplete {
                                Label { Text(verbatim: context.state.etaString) } icon: { Image(systemName: "clock") }
                            }
                            Spacer()
                            Text(verbatim: "→ \(context.state.chargeLimitSoc)%")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isComplete ? "checkmark.circle.fill" : "bolt.fill")
                    .foregroundStyle(Brand.crimson)
            } compactTrailing: {
                Text("\(context.state.batteryLevel)%").foregroundStyle(Brand.textPrimary)
            } minimal: {
                Image(systemName: "bolt.fill").foregroundStyle(Brand.crimson)
            }
            .widgetURL(URL(string: "tesstats://charging"))
            .keylineTint(Brand.crimson)
        }
    }
}

private struct ChargingLockScreenView: View {
    let attributes: ChargingActivityAttributes
    let state: ChargingActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label {
                    Text(attributes.carName).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.textPrimary)
                } icon: {
                    Image(systemName: state.isComplete ? "checkmark.circle.fill" : "bolt.fill")
                        .foregroundStyle(Brand.crimson)
                }
                Spacer()
                (state.isComplete ? Text("Charging complete") : Text("Charging"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state.isComplete ? Brand.online : Brand.crimson)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(state.batteryLevel)%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text(verbatim: "→ \(state.chargeLimitSoc)%").font(.callout).foregroundStyle(Brand.textTertiary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if !state.isComplete {
                        Text(verbatim: state.powerString).font(.callout.weight(.semibold)).foregroundStyle(Brand.crimson)
                    }
                    Text(verbatim: state.rangeString).font(.caption).foregroundStyle(Brand.textSecondary)
                }
            }
            ProgressView(value: state.progress).tint(Brand.crimson)
            if !state.isComplete {
                HStack {
                    Label { Text("Time to full") } icon: { Image(systemName: "clock") }
                    Spacer()
                    Text(verbatim: state.etaString)
                }
                .font(.caption).foregroundStyle(Brand.textSecondary)
            }
        }
        .padding()
    }
}
