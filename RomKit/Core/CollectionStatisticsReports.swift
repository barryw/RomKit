//
//  CollectionStatisticsReports.swift
//  RomKit
//
//  Report generation for collection statistics
//

import Foundation

/// Extension for generating reports from collection statistics
extension CollectionStatistics {

    /// Generate a text report
    public func generateTextReport() -> String {
        var report = ""

        report += generateTextReportHeader()

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .decimal

        report += generateOverallSummarySection(formatter: formatter)
        report += generateSpecialCategoriesSection()

        if let chdSection = generateCHDSection(formatter: formatter) {
            report += chdSection
        }

        report += generateTopManufacturersSection()
        report += generateGamesByYearSection()

        if let issuesSection = generateIssuesSection() {
            report += issuesSection
        }

        report += generateTextReportFooter()

        return report
    }

    private func generateTextReportHeader() -> String {
        """
        ╔══════════════════════════════════════════════════════════════════╗
        ║                    COLLECTION STATISTICS REPORT                   ║
        ╚══════════════════════════════════════════════════════════════════╝


        """
    }

    private func generateOverallSummarySection(formatter: ByteCountFormatter) -> String {
        let romCompletionBar = createProgressBar(percentage: romCompletionPercentage)
        let gameCompletionBar = createProgressBar(percentage: completionPercentage)

        return """
        📊 OVERALL SUMMARY
        ═══════════════════════════════════════════════════════════════════

        Games:      \(String(format: "%,d", totalGames)) total
                    ✅ \(String(format: "%,d", completeGames)) complete
                    ⚠️  \(String(format: "%,d", partialGames)) partial
                    ❌ \(String(format: "%,d", missingGames)) missing

        ROMs:       \(String(format: "%,d", totalROMs)) total
                    ✅ \(String(format: "%,d", foundROMs)) found
                    ❌ \(String(format: "%,d", missingROMs)) missing

        Size:       \(formatter.string(fromByteCount: Int64(totalSize))) total
                    \(formatter.string(fromByteCount: Int64(collectionSize))) in collection
                    \(formatter.string(fromByteCount: Int64(missingSize))) missing

        Completion: Games \(gameCompletionBar) \(String(format: "%.1f%%", completionPercentage))
                    ROMs  \(romCompletionBar) \(String(format: "%.1f%%", romCompletionPercentage))

        Health:     \(getHealthIndicator()) \(String(format: "%.0f%%", healthScore))


        """
    }

    private func generateSpecialCategoriesSection() -> String {
        """
        🎮 SPECIAL CATEGORIES
        ═══════════════════════════════════════════════════════════════════

        Parent Games:  \(String(format: "%,d", parentStats.total)) (\(parentStats.complete) complete)
        Clone Games:   \(String(format: "%,d", cloneStats.total)) (\(cloneStats.complete) complete)
        BIOS Sets:     \(String(format: "%,d", biosStats.total)) (\(biosStats.complete) complete)
        Device ROMs:   \(String(format: "%,d", deviceStats.total)) (\(deviceStats.complete) complete)


        """
    }

    private func generateCHDSection(formatter: ByteCountFormatter) -> String? {
        guard let chd = chdStats else { return nil }

        return """
        💿 CHD FILES
        ═══════════════════════════════════════════════════════════════════

        Total CHDs:    \(String(format: "%,d", chd.totalCHDs))
        Found:         \(String(format: "%,d", chd.foundCHDs))
        Missing:       \(String(format: "%,d", chd.missingCHDs))

        Size:          \(formatter.string(fromByteCount: Int64(chd.totalSize))) total
                       \(formatter.string(fromByteCount: Int64(chd.foundSize))) found
                       \(formatter.string(fromByteCount: Int64(chd.missingSize))) missing


        """
    }

    private func generateTopManufacturersSection() -> String {
        let topManufacturers = byManufacturer.values
            .sorted { $0.total > $1.total }
            .prefix(10)

        guard !topManufacturers.isEmpty else {
            return ""
        }

        var section = """
        🏭 TOP MANUFACTURERS
        ═══════════════════════════════════════════════════════════════════

        """

        for stats in topManufacturers {
            let percentage = Double(stats.complete) / Double(stats.total) * 100
            let bar = createMiniProgressBar(percentage: percentage)
            section += String(format: "%-20s %s %3.0f%% (%d/%d)\n",
                            String(stats.manufacturer.prefix(20)),
                            bar,
                            percentage,
                            stats.complete,
                            stats.total)
        }

        section += "\n"
        return section
    }

    private func generateGamesByYearSection() -> String {
        let yearsSorted = byYear.keys.sorted()

        guard !yearsSorted.isEmpty else {
            return ""
        }

        var section = """
        📅 GAMES BY YEAR
        ═══════════════════════════════════════════════════════════════════

        """

        for year in yearsSorted.suffix(10) {
            if let stats = byYear[year] {
                let percentage = Double(stats.complete) / Double(stats.total) * 100
                let bar = createMiniProgressBar(percentage: percentage)
                section += String(format: "%s: %s %3.0f%% (%d/%d)\n",
                                year,
                                bar,
                                percentage,
                                stats.complete,
                                stats.total)
            }
        }

        section += "\n"
        return section
    }

    private func generateIssuesSection() -> String? {
        guard !issues.isEmpty else { return nil }

        var section = """
        ⚠️  ISSUES DETECTED
        ═══════════════════════════════════════════════════════════════════

        """

        let groupedIssues = Dictionary(grouping: issues, by: { $0.severity })

        for severity in [CollectionIssue.IssueSeverity.critical, .warning, .info] {
            if let severityIssues = groupedIssues[severity], !severityIssues.isEmpty {
                let icon = severity == .critical ? "🔴" : severity == .warning ? "🟡" : "🔵"
                section += "\n\(icon) \(severity):\n"
                for issue in severityIssues.prefix(5) {
                    section += "   • \(issue.description)\n"
                }
            }
        }

        section += "\n"
        return section
    }

    private func generateTextReportFooter() -> String {
        """
        ═══════════════════════════════════════════════════════════════════
        Generated: \(Date().formatted(date: .abbreviated, time: .shortened))
        RomKit v1.0.0
        ═══════════════════════════════════════════════════════════════════
        """
    }

    /// Generate an HTML report
    public func generateHTMLReport() -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .decimal

        return """
        <!DOCTYPE html>
        <html lang="en">
        \(generateHTMLHead())
        <body>
            <div class="container">
                \(generateHTMLHeader())
                \(generateHTMLStatsCards(formatter: formatter))
                \(generateHTMLChartCard())
                \(generateHTMLManufacturersCard())
            </div>
            \(generateHTMLChartScript())
        </body>
        </html>
        """
    }

    private func generateHTMLHead() -> String {
        """
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Collection Statistics Report</title>
            \(generateHTMLStyles())
            <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
        </head>
        """
    }

    private func generateHTMLStyles() -> String {
        """
        <style>
            \(generateBaseStyles())
            \(generateLayoutStyles())
            \(generateComponentStyles())
            \(generateTypographyStyles())
        </style>
        """
    }

    private func generateBaseStyles() -> String {
        """
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                margin: 0;
                padding: 20px;
                min-height: 100vh;
            }
            .container {
                max-width: 1200px;
                margin: 0 auto;
            }
        """
    }

    private func generateLayoutStyles() -> String {
        """
            .header {
                background: white;
                border-radius: 12px;
                padding: 30px;
                margin-bottom: 30px;
                box-shadow: 0 10px 40px rgba(0,0,0,0.1);
            }
            .stats-grid {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
                gap: 20px;
                margin-bottom: 30px;
            }
        """
    }

    private func generateComponentStyles() -> String {
        """
            .stat-card {
                background: white;
                border-radius: 12px;
                padding: 25px;
                box-shadow: 0 10px 40px rgba(0,0,0,0.1);
            }
            .stat-value {
                font-size: 36px;
                font-weight: bold;
                margin: 10px 0;
            }
            .stat-label {
                color: #666;
                font-size: 14px;
                text-transform: uppercase;
                letter-spacing: 1px;
            }
            .progress-bar {
                height: 8px;
                background: #e0e0e0;
                border-radius: 4px;
                overflow: hidden;
                margin: 15px 0;
            }
            .progress-fill {
                height: 100%;
                background: linear-gradient(90deg, #667eea, #764ba2);
                transition: width 0.3s ease;
            }
            .chart-container {
                background: white;
                border-radius: 12px;
                padding: 25px;
                box-shadow: 0 10px 40px rgba(0,0,0,0.1);
                margin-bottom: 30px;
            }
            .manufacturer-list {
                background: white;
                border-radius: 12px;
                padding: 25px;
                box-shadow: 0 10px 40px rgba(0,0,0,0.1);
            }
            .manufacturer-item {
                display: flex;
                justify-content: space-between;
                align-items: center;
                padding: 12px 0;
                border-bottom: 1px solid #f0f0f0;
            }
            .manufacturer-item:last-child {
                border-bottom: none;
            }
        """
    }

    private func generateTypographyStyles() -> String {
        """
            h1, h2 {
                margin: 0;
                color: #333;
            }
            .subtitle {
                color: #666;
                margin-top: 10px;
            }
        """
    }

    private func generateHTMLHeader() -> String {
        """
        <div class="header">
            <h1>Collection Statistics Report</h1>
            <p class="subtitle">Generated on \(Date().formatted(date: .abbreviated, time: .shortened))</p>
        </div>
        """
    }

    private func generateHTMLStatsCards(formatter: ByteCountFormatter) -> String {
        """
        <div class="stats-grid">
            \(generateCompletionCard())
            \(generateSizeCard(formatter: formatter))
            \(generateHealthCard())
        </div>
        """
    }

    private func generateCompletionCard() -> String {
        """
        <div class="stat-card">
            <div class="stat-label">Game Completion</div>
            <div class="stat-value">\(String(format: "%.1f%%", completionPercentage))</div>
            <div class="progress-bar">
                <div class="progress-fill" style="width: \(completionPercentage)%"></div>
            </div>
            <div style="color: #666; font-size: 14px;">
                \(completeGames) of \(totalGames) games complete
            </div>
        </div>
        """
    }

    private func generateSizeCard(formatter: ByteCountFormatter) -> String {
        """
        <div class="stat-card">
            <div class="stat-label">Collection Size</div>
            <div class="stat-value">\(formatter.string(fromByteCount: Int64(collectionSize)))</div>
            <div style="color: #666; font-size: 14px; margin-top: 10px;">
                Missing: \(formatter.string(fromByteCount: Int64(missingSize)))
            </div>
        </div>
        """
    }

    private func generateHealthCard() -> String {
        let healthEmoji = getHealthIndicator()
        return """
        <div class="stat-card">
            <div class="stat-label">Health Score</div>
            <div class="stat-value">\(healthEmoji) \(String(format: "%.0f%%", healthScore))</div>
            <div style="color: #666; font-size: 14px; margin-top: 10px;">
                \(issues.isEmpty ? "No issues detected" : "\(issues.count) issues found")
            </div>
        </div>
        """
    }

    private func generateHTMLChartCard() -> String {
        """
        <div class="chart-container">
            <h2>Games by Year</h2>
            <canvas id="yearChart"></canvas>
        </div>
        """
    }

    private func generateHTMLManufacturersCard() -> String {
        let topManufacturers = byManufacturer.values
            .sorted { $0.total > $1.total }
            .prefix(10)

        var manufacturerHTML = """
        <div class="manufacturer-list">
            <h2>Top Manufacturers</h2>
        """

        for stats in topManufacturers {
            let percentage = Double(stats.complete) / Double(stats.total) * 100
            manufacturerHTML += """
            <div class="manufacturer-item">
                <span>\(stats.manufacturer)</span>
                <span>\(String(format: "%.0f%%", percentage)) (\(stats.complete)/\(stats.total))</span>
            </div>
            """
        }

        manufacturerHTML += "</div>"
        return manufacturerHTML
    }

    private func generateHTMLChartScript() -> String {
        let yearsSorted = byYear.keys.sorted().suffix(20)
        let yearLabels = yearsSorted.map { "\"\($0)\"" }.joined(separator: ", ")
        let completeData = yearsSorted.compactMap { byYear[$0]?.complete }.map { String($0) }.joined(separator: ", ")
        let partialData = yearsSorted.compactMap { byYear[$0]?.partial }.map { String($0) }.joined(separator: ", ")
        let missingData = yearsSorted.compactMap { byYear[$0]?.missing }.map { String($0) }.joined(separator: ", ")

        return """
        <script>
        const ctx = document.getElementById('yearChart').getContext('2d');
        new Chart(ctx, {
            type: 'bar',
            data: {
                labels: [\(yearLabels)],
                datasets: [{
                    label: 'Complete',
                    data: [\(completeData)],
                    backgroundColor: 'rgba(75, 192, 192, 0.8)'
                }, {
                    label: 'Partial',
                    data: [\(partialData)],
                    backgroundColor: 'rgba(255, 206, 86, 0.8)'
                }, {
                    label: 'Missing',
                    data: [\(missingData)],
                    backgroundColor: 'rgba(255, 99, 132, 0.8)'
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    x: {
                        stacked: true
                    },
                    y: {
                        stacked: true,
                        beginAtZero: true
                    }
                }
            }
        });
        </script>
        """
    }

    // MARK: - Helper Methods

    private func createProgressBar(percentage: Double) -> String {
        let filled = Int(percentage / 5)
        let empty = 20 - filled
        return "[" + String(repeating: "█", count: filled) + String(repeating: "░", count: empty) + "]"
    }

    private func createMiniProgressBar(percentage: Double) -> String {
        let filled = Int(percentage / 10)
        let empty = 10 - filled
        return String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
    }

    private func getHealthIndicator() -> String {
        switch healthScore {
        case 90...100:
            return "🟢"
        case 70..<90:
            return "🟡"
        case 50..<70:
            return "🟠"
        default:
            return "🔴"
        }
    }
}
