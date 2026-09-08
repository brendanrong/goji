// Fixture-table tests for TranscriptFormatter. No test target needed; run on the Mac:
//   bash scripts/formatter-tests.sh
// Exit code is the number of failures.
import Foundation

let all = TranscriptFormatter.Options.all
let commandsOnly = TranscriptFormatter.Options(spokenCommands: true, removeFillers: false, collapseStutters: false, numbersAsDigits: false, spokenPunctuation: false)
let fillersOnly = TranscriptFormatter.Options(spokenCommands: false, removeFillers: true, collapseStutters: false, numbersAsDigits: false, spokenPunctuation: false)
let stuttersOnly = TranscriptFormatter.Options(spokenCommands: false, removeFillers: false, collapseStutters: true, numbersAsDigits: false, spokenPunctuation: false)
let numbersOnly = TranscriptFormatter.Options(spokenCommands: false, removeFillers: false, collapseStutters: false, numbersAsDigits: true, spokenPunctuation: false)
let punctOnly = TranscriptFormatter.Options(spokenCommands: false, removeFillers: false, collapseStutters: false, numbersAsDigits: false, spokenPunctuation: true)

struct Case {
    let input: String
    let expected: String
    let options: TranscriptFormatter.Options
    init(_ input: String, _ expected: String, _ options: TranscriptFormatter.Options = all) {
        self.input = input
        self.expected = expected
        self.options = options
    }
}

let cases: [Case] = [
    // Pass-through
    Case("Hello there.", "Hello there."),
    Case("", ""),
    Case("Ship it, we test in prod.", "Ship it, we test in prod.", .none),

    // Fillers
    Case("Um, so the plan is simple.", "So the plan is simple.", fillersOnly),
    Case("So, um, the plan is simple.", "So, the plan is simple.", fillersOnly),
    Case("The plan, uh, is simple.", "The plan, is simple.", fillersOnly),
    Case("It was, you know, fine.", "It was, fine.", fillersOnly),
    Case("Like, the thing is broken.", "The thing is broken.", fillersOnly),
    Case("I like the thing.", "I like the thing.", fillersOnly),
    Case("Do you know the answer?", "Do you know the answer?", fillersOnly),
    Case("The album is by Umm.", "The album is by Umm.", .none),
    Case("Summer humming drum.", "Summer humming drum.", fillersOnly),

    // Stutters
    Case("The the plan is ready.", "The plan is ready.", stuttersOnly),
    Case("I I think so.", "I think so.", stuttersOnly),
    Case("The, the plan is ready.", "The plan is ready.", stuttersOnly),
    Case("The the the plan.", "The plan.", stuttersOnly),
    Case("It was very very good.", "It was very very good.", stuttersOnly),
    Case("I had had enough.", "I had had enough.", stuttersOnly),
    Case("Call zero zero seven.", "Call zero zero seven.", stuttersOnly),
    Case("No no, that's wrong.", "No no, that's wrong.", stuttersOnly),

    // new line / new paragraph
    Case("First point new line second point", "First point\nSecond point", commandsOnly),
    Case("First point. New line. Second point.", "First point.\nSecond point.", commandsOnly),
    Case("First point, new paragraph, second point", "First point\n\nSecond point", commandsOnly),
    Case("Hi team. New paragraph. Quick update.", "Hi team.\n\nQuick update.", commandsOnly),
    Case("We launched a new line of products.", "We launched a new line of products.", commandsOnly),
    Case("Start the new paragraph with a quote.", "Start the new paragraph with a quote.", commandsOnly),
    Case("Ready new line", "Ready", commandsOnly),

    // scratch that
    Case("We ship Friday, scratch that, we ship Monday.", "We ship Monday.", commandsOnly),
    Case("We ship Friday. Scratch that. We ship Monday.", "We ship Monday.", commandsOnly),
    Case("Plan is set. We ship Friday, scratch that, Monday.", "Plan is set. Monday.", commandsOnly),
    Case("Scratch that, start again.", "Start again.", commandsOnly),
    Case("First. Second scratch that third. Fourth scratch that fifth.", "First. Third. Fifth.", commandsOnly),

    // Numbers
    Case("I can pull up eighty kilos.", "I can pull up 80 kilos.", numbersOnly),
    Case("It costs a hundred dollars to enter.", "It costs 100 dollars to enter.", numbersOnly),
    Case("Fable Five Point One wins.", "Fable 5.1 wins.", numbersOnly),
    Case("A fifteen-year-old question.", "A 15-year-old question.", numbersOnly),
    Case("The fifteenth thingy.", "The 15th thingy.", numbersOnly),
    Case("Twenty first of March.", "21st of March.", numbersOnly),
    Case("One hundred and twenty three people.", "123 people.", numbersOnly),
    Case("Two thousand and twenty six.", "2026.", numbersOnly),
    Case("Three point five million users.", "3.5 million users.", numbersOnly),
    Case("One thing, two things, nine things.", "One thing, two things, nine things.", numbersOnly),
    Case("First, we ship. Second, we test.", "First, we ship. Second, we test.", numbersOnly),
    Case("Call zero zero seven.", "Call zero zero seven.", numbersOnly),
    Case("A hundred percent.", "100 percent.", numbersOnly),
    Case("Ten and a half.", "10 and a half.", numbersOnly),
    Case("So GPT six is out.", "So GPT 6 is out.", numbersOnly),
    Case("Q three results and iOS nine.", "Q3 results and iOS 9.", numbersOnly),
    Case("Do step three, then version two.", "Do step 3, then version 2.", numbersOnly),
    Case("Eight kilos, five percent, three pm.", "8 kilos, 5 percent, 3 pm.", numbersOnly),
    Case("I have two dogs and one cat.", "I have two dogs and one cat.", numbersOnly),
    Case("I mean, three of them.", "I mean, three of them.", numbersOnly),

    // Spoken punctuation
    Case("Hi team comma the plan is ready full stop", "Hi team, the plan is ready.", punctOnly),
    Case("Hi team comma, the plan is ready. Full stop.", "Hi team, the plan is ready.", punctOnly),
    Case("Is it ready question mark", "Is it ready?", punctOnly),
    Case("Ship it exclamation mark", "Ship it!", punctOnly),
    Case("Wait period we ship Monday", "Wait. We ship Monday", punctOnly),
    Case("The period was long.", "The period was long.", punctOnly),
    Case("The comma is misplaced.", "The comma is misplaced.", punctOnly),
    Case("Two things colon speed and trust", "Two things: speed and trust", punctOnly),
    Case("She said open quote we ship Monday close quote and left.", "She said \"we ship Monday\" and left.", punctOnly),
    Case("Add this open quotation the cat and the hat end quotation and then done", "Add this \"the cat and the hat\" and then done", punctOnly),
    Case("Note open bracket see above close bracket for details", "Note (see above) for details", punctOnly),
    Case("Email me at brendan at sign example dot com", "Email me at brendan@example dot com", punctOnly),
    Case("Wait dot dot dot what", "Wait\u{2026} what", punctOnly),
    Case("Questions ampersand answers", "Questions & answers", punctOnly),
    Case("Slack dash it's fine", "Slack - it's fine", punctOnly),
    Case("The first quote was better.", "The first quote was better.", punctOnly),

    // Everything together (the plan's done-when case)
    Case("um so the the plan is new paragraph we ship scratch that we test first",
         "So the plan is\n\nWe test first"),
    Case("Hey, uh, quick one new line can you, you know, check the the deck? New paragraph. Thanks!",
         "Hey, quick one\nCan you, check the deck?\n\nThanks!"),
]

// Lowercase profile: names, acronyms, and replacements keep their case.
let lowercaseCases: [(String, [String], String)] = [
    ("Hey team, the PRD for Figma is in Jira.", ["Figma", "Jira"], "hey team, the PRD for Figma is in Jira."),
    ("I think Q3 looks OK.", [], "i think Q3 looks OK."),
    ("Ask Brendan Rong about AirPods.", ["Brendan Rong", "AirPods"], "ask Brendan Rong about AirPods."),
    ("A plain sentence.", [], "a plain sentence."),
]

// Caret shaping: (text, before, after, expected). nil context = old behaviour.
typealias Ctx = InsertionShaper.Context
let shapeCases: [(String, Ctx?, String)] = [
    ("Hello there", nil, "Hello there "),
    ("Hello there", Ctx(before: "", after: ""), "Hello there "),
    ("Hello there", Ctx(before: "Hi team. ", after: ""), "Hello there "),
    ("Hello there", Ctx(before: "Hi team.", after: ""), " Hello there "),
    ("And then we ship", Ctx(before: "We test first", after: ""), " and then we ship "),
    ("And then we ship", Ctx(before: "We test first ", after: ""), "and then we ship "),
    ("I think so", Ctx(before: "Well", after: ""), " I think so "),
    ("PRD is ready", Ctx(before: "the", after: ""), " PRD is ready "),
    ("Figma is ready", Ctx(before: "the", after: ""), " figma is ready "),
    ("Hello", Ctx(before: "(", after: ")"), "Hello"),
    ("Hello", Ctx(before: "\"", after: "\""), "Hello"),
    ("Hello", Ctx(before: "Line one\n", after: ""), "Hello "),
    ("Hello", Ctx(before: "Hi", after: " there"), " hello"),
    ("Hello", Ctx(before: "Hi ", after: "there"), "hello "),
    ("Really", Ctx(before: "Is it", after: "?"), " really"),
]

// Correction diff: (what Goji wrote, what you meant, expected rules).
typealias Sug = CorrectionDiff.Suggestion
let diffCases: [(String, String, [Sug])] = [
    ("hey team, the pod for figma is ready", "hey team, the PRD for Figma is ready", [Sug(find: "pod", replace: "PRD"), Sug(find: "figma", replace: "Figma")]),
    ("remove the capsule as well", "remove the caps lock as well", [Sug(find: "capsule", replace: "caps lock")]),
    ("How does it respond so quickly?", "How does it respond so quick then?", [Sug(find: "quickly", replace: "quick then")]),
    ("Same text.", "Same text.", []),
    ("Short", "A completely different long sentence about other things", []),
    ("I said pod.", "I said PRD.", [Sug(find: "pod", replace: "PRD")]),
]

var failures = 0
for (original, corrected, expected) in diffCases {
    let got = CorrectionDiff.suggestions(original: original, corrected: corrected)
    if got != expected {
        failures += 1
        print("FAIL diff\n  in:  \(original.debugDescription) -> \(corrected.debugDescription)\n  exp: \(expected)\n  got: \(got)")
    }
}
for (text, ctx, expected) in shapeCases {
    let got = InsertionShaper.shape(text, context: ctx, preserveCase: ["Figma"].filter { _ in false })
    if got != expected {
        failures += 1
        print("FAIL shape\n  in:  \(text.debugDescription) before=\(ctx?.before.debugDescription ?? "nil") after=\(ctx?.after.debugDescription ?? "nil")\n  exp: \(expected.debugDescription)\n  got: \(got.debugDescription)")
    }
}
for (input, preserving, expected) in lowercaseCases {
    let got = TranscriptCasing.lowercase(input, preserving: preserving)
    if got != expected {
        failures += 1
        print("FAIL lowercase\n  in:  \(input.debugDescription)\n  exp: \(expected.debugDescription)\n  got: \(got.debugDescription)")
    }
}
for c in cases {
    let got = TranscriptFormatter.format(c.input, options: c.options)
    if got != c.expected {
        failures += 1
        print("FAIL\n  in:  \(c.input.debugDescription)\n  exp: \(c.expected.debugDescription)\n  got: \(got.debugDescription)")
    }
}
let total = cases.count + lowercaseCases.count + shapeCases.count + diffCases.count
print(failures == 0 ? "OK, \(total) cases" : "\(failures) of \(total) failed")
exit(Int32(failures))
