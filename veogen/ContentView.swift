//
//  ContentView.swift
//  veogen
//
//  Created by Heavyshark on 6.06.2025.
//

import SwiftUI

struct ContentView: View {
    @State private var prompt: String = ""
    @State private var selectedAspectRatio: AspectRatio = .landscape
    @State private var isGenerating: Bool = false
    @State private var showPromptTips: Bool = false

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)

                    Text("Veo Gen")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Create stunning videos with AI")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)

                // Prompt input
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Describe your video")
                            .font(.headline)
                            .fontWeight(.semibold)

                        Spacer()

                        Button {
                            showPromptTips = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.blue)
                        }
                    }

                    TextField(
                        "A red car driving on a mountain road...", text: $prompt, axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                }
                .padding(.horizontal, 20)

                // Aspect ratio selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Aspect Ratio")
                        .font(.headline)
                        .fontWeight(.semibold)

                    HStack(spacing: 20) {
                        ForEach(AspectRatio.allCases, id: \.self) { ratio in
                            Button {
                                selectedAspectRatio = ratio
                            } label: {
                                VStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(
                                            selectedAspectRatio == ratio
                                                ? Color.blue : Color.gray.opacity(0.3)
                                        )
                                        .frame(
                                            width: ratio.isLandscape ? 60 : 45,
                                            height: ratio.isLandscape ? 34 : 60
                                        )

                                    Text(ratio.displayName)
                                        .font(.caption)
                                        .foregroundColor(
                                            selectedAspectRatio == ratio ? .blue : .primary)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        Spacer()
                    }
                }
                .padding(.horizontal, 20)

                // Generate button
                Button {
                    generateVideo()
                } label: {
                    HStack {
                        if isGenerating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "play.fill")
                        }

                        Text(isGenerating ? "Generating..." : "Generate Video")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(canGenerate ? Color.blue : Color.gray)
                    )
                }
                .disabled(!canGenerate)
                .padding(.horizontal, 20)

                Spacer()
            }
            .navigationTitle("Veo Gen")
            .sheet(isPresented: $showPromptTips) {
                PromptTipsView()
            }
        }
    }

    private var canGenerate: Bool {
        !isGenerating && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func generateVideo() {
        withAnimation {
            isGenerating = true
        }

        // Simulate generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                isGenerating = false
            }
        }
    }
}

// MARK: - Supporting Types
enum AspectRatio: String, CaseIterable {
    case landscape = "16:9"
    case portrait = "9:16"

    var displayName: String {
        return self.rawValue
    }

    var isLandscape: Bool {
        return self == .landscape
    }
}

// MARK: - Prompt Tips View
struct PromptTipsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Writing Great Prompts")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.top)

                    VStack(alignment: .leading, spacing: 16) {
                        PromptTipCard(
                            title: "Subject",
                            description: "Main focus (object, person, animal, scenery)",
                            example: "A vintage red convertible"
                        )

                        PromptTipCard(
                            title: "Context",
                            description: "Setting / environment",
                            example: "driving along Pacific Coast Highway at sunset"
                        )

                        PromptTipCard(
                            title: "Action",
                            description: "What the subject is doing",
                            example: "drifts into a hair-pin turn"
                        )

                        PromptTipCard(
                            title: "Style",
                            description: "Film or art style keywords",
                            example: "70mm IMAX, retro-noir palette"
                        )
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle("Prompt Tips")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct PromptTipCard: View {
    let title: String
    let description: String
    let example: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Example: \"\(example)\"")
                .font(.caption)
                .italic()
                .foregroundColor(.blue)
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    ContentView()
}
