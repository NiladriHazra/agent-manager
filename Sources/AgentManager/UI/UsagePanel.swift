import SwiftUI

/// The numbers block every row shares: one split bar, then the two windows.
///
/// The bar's two halves are the same quantity — tokens — so they can share a
/// track honestly. The right half is the 7-day total, drawn full as the
/// reference; the left half is today drawn as its share of that week. When the
/// vendor publishes a real limit for a window, that half switches to the accent
/// colour and fills to the actual percentage used instead.
struct UsagePanel: View {
    let quota: Quota?
    let quotaObserved: Date?
    let usage: Usage?
    let usageToday: Usage?
    let includeCacheReads: Bool
    let warn: Int
    let critical: Int

    private var weekTokens: Int { usage?.total(includingCacheReads: includeCacheReads) ?? 0 }
    private var dayTokens: Int { usageToday?.total(includingCacheReads: includeCacheReads) ?? 0 }

    /// Codex publishes a weekly limit, so that half becomes a true quota bar.
    private var weekIsQuota: Bool { quota?.windowMinutes == 10_080 }
    private var dayIsQuota: Bool { quota?.windowMinutes == 1_440 }

    private var weekFraction: Double {
        if weekIsQuota, let quota { return quota.usedPercent / 100 }
        return weekTokens > 0 ? 1 : 0
    }

    private var dayFraction: Double {
        if dayIsQuota, let quota { return quota.usedPercent / 100 }
        guard weekTokens > 0 else { return 0 }
        return Double(dayTokens) / Double(weekTokens)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            WindowBar(
                dayFraction: dayFraction,
                weekFraction: weekFraction,
                dayIsQuota: dayIsQuota,
                weekIsQuota: weekIsQuota
            )

            if let quota {
                QuotaLine(quota: quota, observed: quotaObserved, warn: warn, critical: critical)
            }

            WindowLine(today: usageToday, week: usage, includeCacheReads: includeCacheReads)
        }
    }
}
