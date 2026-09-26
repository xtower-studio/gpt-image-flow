import Foundation

public enum RecipeTemplates {
    public static func fields(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\{\{([^{}\n]{1,60})\}\}"#) else { return [] }
        var seen = Set<String>()
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            let key = String(text[range]).trimmingCharacters(in: .whitespaces)
            return !key.isEmpty && seen.insert(key).inserted ? key : nil
        }
    }
    public static func render(_ text: String, values: [String: String]) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\{\{([^{}\n]{1,60})\}\}"#) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range(at: 1), in: text), let full = Range(match.range, in: result) else { continue }
            let key = String(text[range]).trimmingCharacters(in: .whitespaces)
            if let value = values[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.replaceSubrange(full, with: value) }
        }
        return result
    }
    public static let starters: [Recipe] = [
        make("제품 촬영", "Editorial product photograph of {{제품}}, on a {{배경}} background. Soft directional studio lighting, tactile materials, carefully composed negative space, no lettering.", "00000000-0000-4000-8000-000000000001"),
        make("브랜드 무드보드", "Create a cohesive visual moodboard for {{브랜드}}. Art direction: {{분위기}}. Explore color, materials, light, and composition in a harmonious editorial layout. No logos or text.", "00000000-0000-4000-8000-000000000002"),
        make("참조 이미지 변형", "Keep the subject's identity, shape, and composition from the reference image. Change only {{변경할 부분}}. Preserve all other details and the original visual style.", "00000000-0000-4000-8000-000000000003")
    ]
    private static func make(_ name: String, _ prompt: String, _ id: String) -> Recipe {
        var project = Project(name: name); project.prompt = prompt; project.generationMode = .automatic
        var recipe = Recipe(name: name, settings: project); recipe.id = UUID(uuidString: id)!; return recipe
    }
}
