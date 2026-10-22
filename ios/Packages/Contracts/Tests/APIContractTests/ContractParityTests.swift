import APIContract
import Contracts
import Foundation
import Testing

// The few rules `Contracts` keeps so the app can shape what people type (how long a caption
// may get, how many photos fit) must be the API's. Its OpenAPI document states them: lengths
// people see as `x-max-characters`, counts as `minItems` and `maxItems`.

/// The parts of the OpenAPI document these tests read.
private struct Document: Decodable {
    struct Components: Decodable { let schemas: [String: Schema] }

    let components: Components
}

private final class Schema: Decodable, Sendable {
    let properties: [String: Schema]?
    let minItems: Int?
    let maxItems: Int?
    let maxCharacters: Int?

    enum CodingKeys: String, CodingKey {
        case properties, minItems, maxItems
        case maxCharacters = "x-max-characters"
    }
}

/// `field` of the schema `name` in the committed `api/apps/server/openapi.json`, which
/// scripts/swift-openapi.sh generates from.
private func property(_ field: String, of name: String) throws -> Schema? {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appending(path: "../../../../../api/apps/server/openapi.json")
    let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url.standardizedFileURL))
    return document.components.schemas[name]?.properties?[field]
}

@Test func sportsAreTheAPIsListPlusCustom() {
    #expect(
        Components.Schemas.Sport.allCases.map(\.rawValue) == Sport.allCases.map(\.rawValue) + ["custom"])
}

@Test(arguments: ["Training", "Meal", "TrainingView", "MealView"])
func captionLimitIsTheAPIs(schema: String) throws {
    #expect(try property("caption", of: schema)?.maxCharacters == Caption.maxLength)
}

@Test(arguments: ["Training", "TrainingView"])
func customSportLimitIsTheAPIs(schema: String) throws {
    #expect(try property("customSport", of: schema)?.maxCharacters == CustomSport.maxLength)
}

@Test func disclaimerLimitIsTheAPIs() throws {
    #expect(try property("text", of: "Disclaimer")?.maxCharacters == Disclaimer.maxLength)
}

@Test func catchphraseLimitIsTheAPIs() throws {
    #expect(try property("catchphrase", of: "Profile")?.maxCharacters == Catchphrase.maxLength)
}

@Test func nicknameLimitIsTheAPIs() throws {
    #expect(try property("nickname", of: "Character")?.maxCharacters == Nickname.maxLength)
}

@Test(arguments: ["Training", "Meal", "Disclaimer"])
func photoCountIsTheAPIs(schema: String) throws {
    #expect(try property("photos", of: schema)?.maxItems == Photos.maxCount)
}

@Test(arguments: ["TrainedCheckInDraft", "HealthyMealCheckInDraft", "CheatMealCheckInDraft", "DisclaimerCheckInDraft"])
func audienceSizeIsTheAPIs(schema: String) throws {
    #expect(try property("audience", of: schema)?.maxItems == Audience.maxSquads)
}

@Test(arguments: ["WeeklyPlan", "WeeklyPlanDraft"])
func planLengthIsTheAPIs(schema: String) throws {
    let days = try property("days", of: schema)
    #expect(days?.minItems == WeeklyPlan.dayCount)
    #expect(days?.maxItems == WeeklyPlan.dayCount)
}
