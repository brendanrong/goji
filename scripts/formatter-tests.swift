// Fixture-table tests for TranscriptFormatter. No test target needed; run on the Mac:
//   bash scripts/formatter-tests.sh
// Exit code is the number of failures.
import Foundation

let all = TranscriptFormatter.Options.all
let commandsOnly = TranscriptFormatter.Options(spokenCommands: true, removeFillers: false, collapseStutters: false)
let fillersOnly = TranscriptFormatter.Options(spokenCommands: false, removeFillers: true, collapseStutters: false)
let stuttersOnly = TranscriptFormatter.Options(spokenCommands: false, removeFillers: false, collapseStutters: true)

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

var failures = 0
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
print(failures == 0 ? "OK, \(cases.count + lowercaseCases.count) cases" : "\(failures) of \(cases.count + lowercaseCases.count) failed")
exit(Int32(failures))
