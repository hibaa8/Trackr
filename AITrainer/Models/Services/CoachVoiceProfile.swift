import Foundation
import AVFoundation

enum CoachVoiceProfile {
    static func preferredBackendVoice(for coach: Coach) -> String {
        switch coach.id {
        case 1: return "onyx"
        case 2: return "shimmer"
        case 3: return "sage"
        case 4: return "nova"
        case 5: return "echo"
        case 6: return "alloy"
        case 7: return "nova"
        case 8: return "echo"
        case 9: return "shimmer"
        case 10: return "nova"
        case 11: return "alloy"
        default: return "alloy"
        }
    }

    static func configure(
        utterance: AVSpeechUtterance,
        coach: Coach,
        preferredVoiceHint: String? = nil
    ) {
        let language = preferredLanguage(for: coach)
        utterance.rate = speakingRate(for: coach)
        utterance.pitchMultiplier = pitch(for: coach)
        utterance.volume = 0.9

        if let hint = preferredVoiceHint?.trimmingCharacters(in: .whitespacesAndNewlines),
           !hint.isEmpty,
           let matched = voice(from: hint, language: language) {
            utterance.voice = matched
            return
        }

        if let matched = voice(from: preferredBackendVoice(for: coach), language: language) {
            utterance.voice = matched
            return
        }

        if let fallback = genderFallbackVoice(for: coach, language: language) {
            utterance.voice = fallback
            return
        }

        utterance.voice = AVSpeechSynthesisVoice(language: language)
    }

    private static func preferredLanguage(for coach: Coach) -> String {
        let style = coach.speakingStyle.lowercased()
        if style.contains("spanish") {
            return "es-US"
        }
        return "en-US"
    }

    private static func speakingRate(for coach: Coach) -> Float {
        let style = coach.speakingStyle.lowercased()
        if style.contains("calm") || style.contains("mindful") || style.contains("poetic") {
            return 0.45
        }
        if style.contains("direct") || style.contains("ener") || style.contains("upbeat") {
            return 0.53
        }
        return 0.5
    }

    private static func pitch(for coach: Coach) -> Float {
        let style = coach.speakingStyle.lowercased()
        if style.contains("power") || style.contains("ener") || style.contains("upbeat") {
            return 1.1
        }
        if style.contains("calm") || style.contains("grounded") {
            return 0.95
        }
        return 1.0
    }

    private static func voice(from hint: String, language: String) -> AVSpeechSynthesisVoice? {
        let normalized = hint.lowercased()
        let voices = AVSpeechSynthesisVoice.speechVoices()

        if let exact = AVSpeechSynthesisVoice(identifier: hint) {
            return exact
        }
        if let byLanguage = AVSpeechSynthesisVoice(language: hint) {
            return byLanguage
        }

        if normalized == "onyx" || normalized == "echo" {
            return voices.first { $0.language == language && $0.name.lowercased().contains("daniel") }
                ?? voices.first { $0.language == language && $0.name.lowercased().contains("alex") }
                ?? voices.first { $0.language == language && $0.quality == .enhanced }
                ?? voices.first { $0.language == language }
        }
        if normalized == "nova" || normalized == "shimmer" {
            return voices.first { $0.language == language && $0.name.lowercased().contains("samantha") }
                ?? voices.first { $0.language == language && $0.name.lowercased().contains("ava") }
                ?? voices.first { $0.language == language && $0.quality == .enhanced }
                ?? voices.first { $0.language == language }
        }
        if normalized == "sage" || normalized == "alloy" {
            return voices.first { $0.language == language && $0.name.lowercased().contains("alex") }
                ?? voices.first { $0.language == language && $0.quality == .enhanced }
                ?? voices.first { $0.language == language }
        }

        return voices.first { $0.language == language && $0.name.lowercased().contains(normalized) }
            ?? voices.first { $0.language == language }
    }

    private static func genderFallbackVoice(for coach: Coach, language: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        guard !voices.isEmpty else { return nil }

        let maleHints = ["daniel", "alex", "thomas", "aaron", "arthur", "fred", "jorge"]
        let femaleHints = ["samantha", "ava", "victoria", "karen", "susan", "allison", "moira", "tessa"]
        let gender = coach.gender.lowercased()

        if gender.contains("male") {
            return voices.first { voice in
                maleHints.contains { voice.name.lowercased().contains($0) }
            } ?? voices.first { $0.quality == .enhanced } ?? voices.first
        }
        if gender.contains("female") {
            return voices.first { voice in
                femaleHints.contains { voice.name.lowercased().contains($0) }
            } ?? voices.first { $0.quality == .enhanced } ?? voices.first
        }

        return voices.first { $0.quality == .enhanced } ?? voices.first
    }
}
