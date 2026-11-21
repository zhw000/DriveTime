import AppIntents
import SwiftUI

struct SiriRouteSnippetView: View {
    let summary: SiriRouteSummary

    init(summary: SiriRouteSummary) {
        self.summary = summary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "car.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DriveTimeTheme.accent)
                Text("DriveTime")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(summary.provider.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("\(summary.originName) → \(summary.destinationName)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(summary.formattedDuration)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 12) {
                Label("\(summary.formattedArrival) 抵达", systemImage: "clock")
                Text(summary.formattedDistance)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            if let notice = summary.notice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(16)
        .frame(maxWidth: 360, alignment: .leading)
    }
}

struct DriveTimeRouteIntent: AppIntent {
    static var title: LocalizedStringResource = "查询驾车时间"
    static var description = IntentDescription(
        "查询两个地点之间的真实驾车时间、路线距离和预计到达时间。"
    )

    @Parameter(title: "起点", requestValueDialog: "从哪里出发？")
    var origin: String

    @Parameter(title: "终点", requestValueDialog: "要去哪里？")
    var destination: String

    static var parameterSummary: some ParameterSummary {
        Summary("查询从 \(\.$origin) 到 \(\.$destination) 的驾车时间")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        do {
            let summary = try await SiriRouteQueryService.live().query(
                originText: origin,
                destinationText: destination
            )
            return .result(
                dialog: IntentDialog(stringLiteral: summary.dialogText),
                view: SiriRouteSnippetView(summary: summary)
            )
        } catch let error as SiriRouteError {
            throw error
        } catch {
            throw SiriRouteError.unavailable
        }
    }
}
