import Foundation

/// English WhisperKit models from argmaxinc/whisperkit-coreml.
/// Bars are relative to this list. Size follows the published download.
struct SpeechModelChoice: Identifiable, Equatable {
    var variant: String
    var title: String
    var detail: String
    var megabytes: Int
    /// Larger means faster on this list.
    var speed: Double
    /// Larger means more accurate on this list.
    var quality: Double
    var isDefault: Bool

    var id: String { variant }

    /// Share of the largest download in the list.
    var size: Double {
        Double(megabytes) / Double(Self.largestDownload)
    }

    static let defaultsKey = "speech.model"

    static let all: [SpeechModelChoice] = [
        SpeechModelChoice(
            variant: "tiny.en",
            title: "Fast",
            detail: "The smallest English model. Best when you want the words quickly.",
            megabytes: 153,
            speed: 0.92,
            quality: 0.34,
            isDefault: false
        ),
        SpeechModelChoice(
            variant: "small.en_217MB",
            title: "Balanced",
            detail: "The default. English, small enough to keep loaded.",
            megabytes: 217,
            speed: 0.68,
            quality: 0.70,
            isDefault: true
        ),
        SpeechModelChoice(
            variant: "large-v3_turbo",
            title: "Highest",
            detail: "The most accurate of these three. About a gigabyte.",
            megabytes: 954,
            speed: 0.36,
            quality: 0.90,
            isDefault: false
        ),
    ]

    static var recommended: SpeechModelChoice {
        all.first { $0.isDefault } ?? all[0]
    }

    static func stored(_ raw: String?) -> SpeechModelChoice {
        all.first { $0.variant == raw } ?? recommended
    }

    private static var largestDownload: Int {
        all.map(\.megabytes).max() ?? 1
    }
}
