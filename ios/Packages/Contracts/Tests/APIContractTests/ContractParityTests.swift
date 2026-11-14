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
    // A bound may be fractional (a meal's 卡价比 starts at 0.2), so it reads as a number.
    let minimum: Double?
    let defaultValue: Int?
    let maximum: Double?
    let ref: String?

    enum CodingKeys: String, CodingKey {
        case properties, minItems, maxItems, minimum, maximum
        case defaultValue = "default"
        case ref = "$ref"
        case maxCharacters = "x-max-characters"
    }
}

/// `field` of the schema `name` in the committed `api/apps/server/openapi.json`, which
/// scripts/swift-openapi.sh generates from; a field that refers to a shared schema is that schema.
private func property(_ field: String, of name: String) throws -> Schema? {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appending(path: "../../../../../api/apps/server/openapi.json")
    let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url.standardizedFileURL))
    let schemas = document.components.schemas
    let found = schemas[name]?.properties?[field]
    guard let ref = found?.ref else { return found }
    return schemas[String(ref.split(separator: "/").last ?? "")]
}

@Test(arguments: ["Training", "Meal", "TrainingView", "MealView"])
func captionLimitIsTheAPIs(schema: String) throws {
    #expect(try property("caption", of: schema)?.maxCharacters == Caption.maxLength)
}

@Test(arguments: ["Training", "TrainingView"])
func customSportLimitIsTheAPIs(schema: String) throws {
    #expect(try property("customSport", of: schema)?.maxCharacters == CustomSport.maxLength)
}

@Test func cityNameLimitIsTheAPIs() throws {
    #expect(try property("city", of: "MemberLocation")?.maxCharacters == CityName.maxLength)
}

@Test(arguments: ["Training", "TrainingView"])
func workoutMinutesRangeIsTheAPIs(schema: String) throws {
    let minutes = try property("minutes", of: schema)
    #expect(minutes?.minimum == Double(WorkoutMinutes.range.lowerBound))
    #expect(minutes?.maximum == Double(WorkoutMinutes.range.upperBound))
}

@Test(arguments: ["CommentDraft", "CommentEntry"])
func commentLimitIsTheAPIs(schema: String) throws {
    #expect(try property("text", of: schema)?.maxCharacters == CommentText.maxLength)
}

@Test func mentionLimitIsTheAPIs() throws {
    #expect(try property("mentions", of: "CommentDraft")?.maxItems == Mentions.maxMembers)
}

@Test func disclaimerLimitIsTheAPIs() throws {
    #expect(try property("text", of: "Disclaimer")?.maxCharacters == Disclaimer.maxLength)
}

@Test func catchphraseLimitIsTheAPIs() throws {
    #expect(try property("catchphrase", of: "Profile")?.maxCharacters == Catchphrase.maxLength)
}

@Test func jerseyNumberRangeIsTheAPIs() throws {
    let number = try property("jerseyNumber", of: "Profile")
    #expect(number?.minimum == Double(JerseyNumber.range.lowerBound))
    #expect(number?.maximum == Double(JerseyNumber.range.upperBound))
}

@Test func nicknameLimitIsTheAPIs() throws {
    #expect(try property("nickname", of: "Character")?.maxCharacters == Nickname.maxLength)
}

@Test func squadNameLimitIsTheAPIs() throws {
    #expect(try property("name", of: "NewSquad")?.maxCharacters == SquadName.maxLength)
}

@Test func joinNoteLimitIsTheAPIs() throws {
    #expect(try property("note", of: "JoinSquadRequest")?.maxCharacters == JoinNote.maxLength)
}

@Test func savedPlaceNoteLimitIsTheAPIs() throws {
    #expect(try property("note", of: "SavedPlaceDraft")?.maxCharacters == SavedPlaceNote.maxLength)
}

@Test(arguments: ["Training", "Meal", "Disclaimer"])
func photoCountIsTheAPIs(schema: String) throws {
    #expect(try property("photos", of: schema)?.maxItems == Photos.maxCount)
}

@Test(arguments: ["width", "height"])
func photoSideRangeIsTheAPIs(side: String) throws {
    let range = try property(side, of: "PhotoSize")
    #expect(range?.minimum == Double(PhotoSize.sideRange.lowerBound))
    #expect(range?.maximum == Double(PhotoSize.sideRange.upperBound))
}

@Test(arguments: ["NewSquad", "SquadWeeklyGoal", "SquadWeeklyGoalChange"])
func squadWeeklyGoalIsTheAPIs(schema: String) throws {
    let days = try property("daysPerMember", of: schema)
    #expect(days?.minimum == Double(SquadWeeklyGoal.choices.lowerBound))
    #expect(days?.maximum == Double(SquadWeeklyGoal.choices.upperBound))
}

@Test func newSquadDefaultGoalIsTheAPIs() throws {
    #expect(try property("daysPerMember", of: "NewSquad")?.defaultValue == SquadWeeklyGoal.defaultDaysPerMember)
}

@Test(arguments: ["WeeklyPlan", "WeeklyPlanDraft", "PlanTemplate", "PlanTemplateDraft"])
func planLengthIsTheAPIs(schema: String) throws {
    let days = try property("days", of: schema)
    #expect(days?.minItems == WeeklyPlan.dayCount)
    #expect(days?.maxItems == WeeklyPlan.dayCount)
}

/// 补打卡's reach is the API's `BACKFILL_DAYS`, which the OpenAPI document only states in words,
/// so the test reads the rule's own source.
@Test(arguments: ["healthy", "tasty"])
func mealScoresAreTheAPIs(field: String) throws {
    let score = try property(field, of: "MealRating")
    #expect(score?.minimum == Double(MealRating.scores.lowerBound))
    #expect(score?.maximum == Double(MealRating.scores.upperBound))
}

@Test func aPostReachesBackAsFarAsTheAPIAllows() throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "../../../../../api/packages/check-ins/src/domain/check-in-time.ts")
    let source = try String(contentsOf: url.standardizedFileURL, encoding: .utf8)
    let line = source.split(separator: "\n").first { $0.contains("export const BACKFILL_DAYS = ") }
    let days = line.flatMap {
        Int($0.split(separator: "=").last?.trimmingCharacters(in: .init(charactersIn: " ;")) ?? "")
    }
    #expect(days == CheckIn.backfillDays)
}

@Test func feedbackLimitsAreTheAPIs() throws {
    #expect(try property("body", of: "FeedbackDraft")?.maxCharacters == FeedbackText.maxLength)
    #expect(try property("screenshots", of: "FeedbackDraft")?.maxItems == FeedbackText.maxScreenshots)
}

/// The earliest birthday is the API's `BIRTHDAY_EARLIEST`, which the OpenAPI document only states
/// in words, so the test reads the rule's own source.
@Test func theEarliestBirthdayIsTheAPIs() throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "../../../../../api/packages/members/src/domain/profile.ts")
    let source = try String(contentsOf: url.standardizedFileURL, encoding: .utf8)
    let line = source.split(separator: "\n").first { $0.contains("export const BIRTHDAY_EARLIEST = ") }
    let earliest = line.flatMap { $0.split(separator: "'").dropFirst().first }.map(String.init)
    #expect(earliest == Birthday.earliest.description)
}
