import NotificationsDomain
import Testing

struct PushAlertWordsTests {
    @Test func readsTheKeyAndItsValuesFromThePayload() {
        let aps: [String: Any] = [
            "alert": ["loc-key": "push.dailyProgress", "loc-args": ["3", "12"]],
            "category": "dailyProgress",
        ]
        #expect(PushAlertWords(aps: aps) == PushAlertWords(key: "push.dailyProgress", args: ["3", "12"]))
        #expect(
            PushAlertWords(aps: ["alert": ["loc-key": "push.weeklyAwards.ready"]])
                == PushAlertWords(key: "push.weeklyAwards.ready"))
    }

    @Test func aPushWithoutAKeyHasNoWordsToLookUp() {
        #expect(PushAlertWords(aps: nil) == nil)
        #expect(PushAlertWords(aps: ["alert": "本周颁奖出炉了"]) == nil)
        #expect(PushAlertWords(aps: ["alert": ["body": "Hi"]]) == nil)
    }

    @Test func numberedPlaceholdersTakeTheirValueWhereverTheLanguagePutsThem() {
        let words = PushAlertWords(key: "push.dailyProgress.poke", args: ["3", "12", "小林"])
        #expect(words.fill("%3$@拍了拍你 · 本周小队已练 %1$@/%2$@ 次") == "小林拍了拍你 · 本周小队已练 3/12 次")
        #expect(
            words.fill("%3$@ gave you a pat · squad's at %1$@/%2$@ this week")
                == "小林 gave you a pat · squad's at 3/12 this week")
    }

    @Test func plainPlaceholdersTakeTheValuesInTurnAndPercentSignsStay() {
        let words = PushAlertWords(key: "k", args: ["80", "Ann"])
        #expect(words.fill("%@%% done by %@") == "80% done by Ann")
    }

    @Test func aPlaceholderWithoutAValueOrOfAnotherKindStaysAsItIs() {
        let words = PushAlertWords(key: "k", args: ["3"])
        #expect(words.fill("%1$@ of %2$@ · %d · %0$@ · 100%") == "3 of %2$@ · %d · %0$@ · 100%")
        #expect(PushAlertWords(key: "k").fill("%@ teammates") == "%@ teammates")
    }
}
