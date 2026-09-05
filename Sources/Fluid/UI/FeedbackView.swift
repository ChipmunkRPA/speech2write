//
//  FeedbackView.swift
//  fluid
//
//  Extracted from ContentView.swift to reduce monolithic architecture.
//  Created: 2025-12-14
//

import AppKit
import SwiftUI

struct FeedbackView: View {
    @Environment(\.theme) private var theme

    // MARK: - State Variables (moved from ContentView)

    @State private var feedbackText: String = ""
    @State private var appear: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(self.theme.palette.accent)
                        VStack(alignment: .leading) {
                            Text("Send feedback")
                                .font(.system(size: 28, weight: .bold))
                            Text("Help us improve Speech2Write")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                            Text("An open-source CPA Automation project · cpaautomation.ai")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(self.theme.palette.secondaryText)
                        }
                    }
                }
                .padding(.bottom, 8)

                ThemedCard(style: .prominent, hoverEffect: false) {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(self.theme.palette.accent)

                        Text("Speech recognition and AI enhancement run entirely on your Mac, and vendor telemetry has been removed.")
                            .font(.system(size: 13))
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                }

                // Feedback Form
                ThemedCard(style: .standard, hoverEffect: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Feedback")
                                .font(.headline)
                                .fontWeight(.semibold)

                            TextEditor(text: self.$feedbackText)
                                .font(.system(size: 14))
                                .frame(height: 120)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(self.theme.palette.contentBackground)
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(self.theme.palette.cardBorder.opacity(0.45), lineWidth: 1.2)))
                                .scrollContentBackground(.hidden)
                                .overlay(
                                    Group {
                                        if self.feedbackText.isEmpty {
                                            Text("Share your thoughts, report bugs, or suggest features...")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .padding(.leading, 4)
                                        }
                                    }
                                    .allowsHitTesting(false)
                                )

                            Text("Submitting opens a GitHub issue on the public repository with your feedback, the app version, and your macOS version.")
                                .font(.system(size: 12))
                                .foregroundStyle(self.theme.palette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)

                            // Send Button
                            HStack {
                                Spacer()

                                Button(action: {
                                    self.openFeedbackIssue()
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "paperplane.fill")
                                        Text("Open GitHub issue")
                                            .fontWeight(.semibold)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                }
                                .fluidButton(.glass, size: .medium)
                                .disabled(self.feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .buttonHoverEffect()
                            }
                        }
                    }
                    .padding(20)
                }
                .modifier(CardAppearAnimation(delay: 0.1, appear: self.$appear))
            }
            .padding(24)
        }
        .onAppear {
            self.appear = true
        }
    }

    // MARK: - Feedback Functions

    private func openFeedbackIssue() {
        let feedback = self.feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !feedback.isEmpty else { return }

        let firstLine = feedback.components(separatedBy: .newlines).first ?? "Feedback"
        let title = "Feedback: \(String(firstLine.prefix(60)))"

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        let body = """
        \(feedback)

        ---
        App version: \(appVersion) (build \(build))
        macOS version: \(ProcessInfo.processInfo.operatingSystemVersionString)
        """

        var components = URLComponents(string: "\(AppBundleMetadata.repositoryURLString)/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: body),
        ]

        guard let url = components?.url else {
            DebugLogger.shared.error("Invalid feedback issue URL", source: "FeedbackView")
            return
        }

        NSWorkspace.shared.open(url)
        self.feedbackText = ""
    }
}
