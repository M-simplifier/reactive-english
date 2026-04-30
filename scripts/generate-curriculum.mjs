#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const outputPath = path.join(root, "curriculum", "english-cefr-c2.json");

const levels = [
  {
    level: "A1",
    xp: 40,
    units: [
      unit("Meeting People", "names, greetings, countries, and classroom language", [
        lesson("Names And Greetings", "first meetings", "Introduce yourself and reply politely.", "A new classmate says hello.", "Nice to meet you, my name is Lina.", "meet", true, "Nice to meet you is used for a first meeting.", "greeting", "noun", "a polite word or phrase used when meeting someone"),
        lesson("Countries And Cities", "where people are from", "Say where you and other people are from.", "You are answering a simple origin question.", "I am from Brazil, and she is from Canada.", "from", true, "From can introduce a place of origin.", "origin", "noun", "the place where someone or something comes from"),
        lesson("Classroom Requests", "asking for help", "Use short classroom requests and polite words.", "You cannot hear the teacher clearly.", "Could you repeat that, please?", "repeat", true, "Please can make a request more polite.", "repeat", "verb", "to say or do something again"),
        lesson("Personal Details", "basic identity", "Ask and answer simple questions about name, age, and job.", "You are filling in a short learner profile.", "My sister is twenty years old.", "twenty", false, "Twenty means twelve.", "detail", "noun", "a small piece of information")
      ]),
      unit("Everyday Objects", "common things, colors, rooms, and possession", [
        lesson("Things On The Desk", "classroom objects", "Name common objects near you.", "You point to something on the table.", "This is a notebook, and that is a pen.", "notebook", true, "This and that can point to objects.", "notebook", "noun", "a book of blank pages for writing notes"),
        lesson("Colors And Sizes", "describing objects", "Describe simple color and size differences.", "You compare two bags in a shop.", "The blue bag is small, but the red bag is big.", "blue", true, "Blue and red are color words.", "color", "noun", "the appearance of something such as red, blue, or green"),
        lesson("Rooms At Home", "home vocabulary", "Say where things are in a home.", "You tell a guest where to sit.", "The sofa is in the living room.", "sofa", true, "A living room is a room in a home.", "sofa", "noun", "a comfortable seat for more than one person"),
        lesson("Mine And Yours", "possession", "Use basic possessive words.", "You find a phone on a desk.", "This phone is mine, and that bag is yours.", "mine", false, "Mine means belonging to another person only.", "possession", "noun", "ownership or having something")
      ]),
      unit("Daily Life", "routines, time, food, and transport", [
        lesson("Morning Routine", "daily habits", "Describe simple morning actions.", "You talk about a normal weekday.", "I wake up at seven and eat breakfast.", "breakfast", true, "Breakfast is usually eaten in the morning.", "breakfast", "noun", "the first meal of the day"),
        lesson("Telling The Time", "hours and schedules", "Say when everyday actions happen.", "You explain your class schedule.", "Our English lesson starts at nine o'clock.", "starts", true, "At nine o'clock is a time expression.", "schedule", "noun", "a plan that says when things happen"),
        lesson("Food Likes", "likes and dislikes", "Say what food you like or do not like.", "You are choosing lunch.", "I like rice, but I do not like onions.", "like", false, "Do not like means enjoy very much.", "onion", "noun", "a vegetable with a strong smell and taste"),
        lesson("Going Places", "simple transport", "Talk about how people go somewhere.", "You describe your trip to school.", "We go to school by bus.", "bus", true, "By bus describes a way to travel.", "transport", "noun", "a way of moving people from one place to another")
      ]),
      unit("Simple Social Plans", "days, invitations, weather, and short messages", [
        lesson("Days Of The Week", "calendar basics", "Use days to make simple plans.", "You tell a friend about a lesson.", "The music class is on Monday.", "Monday", true, "Monday is a day of the week.", "weekday", "noun", "one of the days from Monday to Friday"),
        lesson("Inviting A Friend", "short invitations", "Invite someone with a simple sentence.", "You want to drink tea with a friend.", "Do you want to have tea after class?", "tea", true, "Do you want to can start an invitation.", "invitation", "noun", "a request asking someone to join an event"),
        lesson("Weather Words", "talking about weather", "Describe simple weather conditions.", "You look outside before leaving.", "It is cold and windy today.", "cold", false, "Cold means very hot.", "weather", "noun", "the condition of the air outside"),
        lesson("Short Texts", "basic messages", "Write and understand short friendly messages.", "You send a short phone message.", "I am at the station now.", "station", true, "A station is a place where trains or buses stop.", "message", "noun", "a short piece of information sent to someone")
      ])
    ]
  },
  {
    level: "A2",
    xp: 50,
    units: [
      unit("Personal Stories", "past events, experiences, and simple descriptions", [
        lesson("Yesterday's Activities", "simple past", "Say what happened yesterday.", "You tell a friend about your evening.", "Yesterday I cooked dinner and watched a film.", "cooked", true, "Cooked is a regular past-tense verb.", "activity", "noun", "something that a person does"),
        lesson("Weekend Memories", "past time phrases", "Describe a short weekend experience.", "You describe last Saturday.", "Last weekend we visited a small museum.", "visited", true, "Last weekend points to past time.", "museum", "noun", "a place where important or interesting objects are shown"),
        lesson("Travel Experiences", "basic travel talk", "Say where you went and how it was.", "You talk about a trip.", "The train was crowded, but the view was beautiful.", "crowded", false, "Crowded means almost empty.", "view", "noun", "what you can see from a place"),
        lesson("Describing People", "appearance and character", "Describe people with simple adjectives.", "You describe a helpful neighbor.", "My neighbor is friendly and very patient.", "friendly", true, "Friendly describes someone who is kind and pleasant.", "neighbor", "noun", "a person who lives near you")
      ]),
      unit("Plans And Needs", "future arrangements, shopping, quantities, and requests", [
        lesson("Future Arrangements", "going to", "Talk about plans already decided.", "You explain tomorrow's plan.", "I am going to meet my cousin tomorrow.", "going", true, "Going to can describe a future plan.", "arrangement", "noun", "a plan made for something to happen"),
        lesson("Shopping For Clothes", "sizes and prices", "Ask for items and prices in a shop.", "You are buying a jacket.", "Do you have this jacket in a larger size?", "larger", true, "Larger compares size.", "size", "noun", "how big or small something is"),
        lesson("Quantities At Home", "some and any", "Use quantities for everyday needs.", "You check the kitchen before shopping.", "We need some milk, but we do not need any bread.", "some", false, "Some is usually used only for impossible things.", "quantity", "noun", "an amount or number of something"),
        lesson("Polite Requests", "could and would", "Make simple polite requests.", "You ask someone to open a window.", "Could you open the window for a moment?", "Could", true, "Could you is a polite request frame.", "request", "noun", "something you ask someone to do")
      ]),
      unit("Places And Directions", "directions, local services, appointments, and rules", [
        lesson("Finding The Way", "directions", "Ask for and give simple directions.", "You are looking for a bank.", "Go straight and turn left at the corner.", "left", true, "Turn left gives a direction.", "corner", "noun", "the place where two streets or sides meet"),
        lesson("Around Town", "local services", "Explain where places are in town.", "You tell a visitor about the library.", "The library is opposite the post office.", "opposite", true, "Opposite means on the other side facing something.", "library", "noun", "a place where people can read or borrow books"),
        lesson("Appointments", "making arrangements", "Make a simple appointment.", "You call a clinic.", "I would like to make an appointment for Friday.", "appointment", true, "An appointment is an arranged meeting or visit.", "clinic", "noun", "a place where people receive medical advice or treatment"),
        lesson("Simple Rules", "must and have to", "Talk about everyday rules.", "You explain a museum rule.", "You must not take photos inside the gallery.", "must", false, "Must not means something is required.", "rule", "noun", "an instruction saying what is allowed or required")
      ]),
      unit("Comparing Choices", "comparatives, preferences, health, and simple advice", [
        lesson("Better Options", "comparatives", "Compare two simple choices.", "You compare two routes.", "The bus is cheaper than the taxi.", "cheaper", true, "Cheaper compares price.", "option", "noun", "one thing that can be chosen"),
        lesson("Preferences", "would rather", "State simple preferences.", "You choose an evening activity.", "I would rather stay home than go out tonight.", "rather", true, "Would rather expresses preference.", "preference", "noun", "a feeling that one thing is better for you than another"),
        lesson("Health Advice", "should", "Give simple advice about health.", "A friend has a headache.", "You should drink water and rest for a while.", "should", true, "Should can give advice.", "rest", "verb", "to stop working or moving in order to relax"),
        lesson("Explaining Reasons", "because and so", "Connect simple reasons and results.", "You explain why you are late.", "I missed the bus, so I arrived late.", "so", false, "So always introduces the reason before the action.", "reason", "noun", "why something happens or why someone does something")
      ])
    ]
  },
  {
    level: "B1",
    xp: 65,
    units: [
      unit("Everyday Opinions", "views, agreement, reasons, and examples", [
        lesson("Giving Opinions", "balanced views", "Give a clear opinion with a reason.", "You discuss studying online.", "I think online lessons are useful because they are flexible.", "flexible", true, "Because introduces a reason.", "opinion", "noun", "what someone thinks about something"),
        lesson("Agreeing Partly", "partial agreement", "Agree with limits and explain why.", "You respond to a friend's idea.", "I agree to some extent, but the price is too high.", "extent", true, "To some extent means partly.", "extent", "noun", "the degree to which something is true"),
        lesson("Giving Examples", "supporting a point", "Support a point with an example.", "You explain why parks matter.", "For example, children need safe places to play.", "example", true, "For example introduces support.", "support", "verb", "to help show that an idea is reasonable"),
        lesson("Changing Your Mind", "revising opinions", "Explain how a view changed.", "You talk about a film you expected to dislike.", "At first I was doubtful, but the ending changed my mind.", "doubtful", false, "Doubtful means completely certain.", "doubtful", "adjective", "not sure whether something is true or good")
      ]),
      unit("Problems And Solutions", "complaints, advice, causes, and results", [
        lesson("Making A Complaint", "service problems", "Complain politely about a practical problem.", "Your meal arrives cold.", "I am afraid my soup is cold, and I ordered it hot.", "afraid", true, "I am afraid can soften bad news or a complaint.", "complaint", "noun", "a statement that something is wrong or unsatisfactory"),
        lesson("Suggesting Solutions", "practical advice", "Suggest a useful solution.", "A team cannot finish on time.", "We could divide the task into smaller parts.", "divide", true, "Could can suggest an option.", "solution", "noun", "an answer to a problem"),
        lesson("Explaining Causes", "why problems happen", "Describe a cause clearly.", "You explain a missed meeting.", "The delay was caused by heavy traffic.", "caused", true, "Was caused by introduces a cause.", "cause", "noun", "the reason something happens"),
        lesson("Consequences", "results of actions", "Explain what happened as a result.", "You describe a missed deadline.", "As a result, the team had to change its plan.", "result", false, "As a result introduces an unrelated example.", "consequence", "noun", "a result of an action or situation")
      ]),
      unit("Stories And Experiences", "narratives, sequence, contrast, and detail", [
        lesson("Telling A Story", "sequence markers", "Tell events in a clear order.", "You describe a surprising day.", "First we missed the train, then we found a better route.", "then", true, "Then shows the next event.", "sequence", "noun", "the order in which things happen"),
        lesson("Background Details", "past continuous", "Set the scene in a story.", "You describe a street scene.", "It was raining when we arrived at the hotel.", "raining", true, "Was raining describes background action.", "background", "noun", "information that helps explain a situation"),
        lesson("Unexpected Turns", "although and however", "Show contrast in a story.", "You describe a hard but successful trip.", "Although the climb was difficult, the view was worth it.", "Although", true, "Although introduces contrast.", "contrast", "noun", "a difference between two things"),
        lesson("Personal Reflection", "lessons learned", "Reflect on an experience.", "You explain what a mistake taught you.", "The experience taught me to prepare more carefully.", "taught", false, "Taught is the future form of teach.", "reflection", "noun", "careful thought about an experience")
      ]),
      unit("Work And Community", "coordination, updates, meetings, and public issues", [
        lesson("Work Updates", "progress reports", "Give a short progress update.", "You report on a task.", "I have finished the first section and started the second.", "finished", true, "Have finished connects past work to now.", "update", "noun", "new information about progress or a situation"),
        lesson("Meeting Plans", "agenda language", "Talk about a simple meeting plan.", "You explain what the group will discuss.", "The main purpose of the meeting is to agree on priorities.", "purpose", true, "Purpose means the reason for doing something.", "agenda", "noun", "a list of things to discuss in a meeting"),
        lesson("Community Issues", "local concerns", "Describe a local issue and its effect.", "You discuss noise in the area.", "Many residents are concerned about traffic near the school.", "concerned", true, "Concerned means worried or interested about a problem.", "resident", "noun", "a person who lives in a place"),
        lesson("Offering Help", "volunteering", "Offer help with limits.", "A neighbor needs support.", "I can help on Saturday if you still need someone.", "if", false, "If always introduces a certain fact.", "volunteer", "verb", "to offer to do something without being forced")
      ])
    ]
  },
  {
    level: "B2",
    xp: 80,
    units: [
      unit("Explaining Opinions Clearly", "argument structure, evidence, concession, and emphasis", [
        lesson("Main Claims", "clear arguments", "State a claim and support it.", "You discuss public transport.", "The city should improve buses because reliable transport benefits everyone.", "reliable", true, "Reliable means that something can be trusted to work well.", "claim", "noun", "a statement that something is true"),
        lesson("Using Evidence", "supporting views", "Refer to evidence without overclaiming.", "You discuss survey results.", "The survey suggests that most commuters prefer cheaper fares.", "suggests", true, "Suggests is more cautious than proves.", "evidence", "noun", "information used to support a belief or claim"),
        lesson("Conceding A Point", "balanced argument", "Acknowledge a weakness before responding.", "You evaluate a new policy.", "Although the policy is expensive, it could reduce long-term costs.", "Although", true, "Although introduces concession.", "concession", "noun", "an admission that something is partly true"),
        lesson("Emphasizing Priorities", "what matters most", "Highlight the most important point.", "You compare speed and accuracy.", "What matters most is accuracy, not speed.", "accuracy", false, "Accuracy means being quick rather than correct.", "priority", "noun", "something more important than other things")
      ]),
      unit("Handling Problems", "analysis, alternatives, risk, and recommendation", [
        lesson("Root Causes", "underlying problems", "Identify a deeper cause.", "You analyze a failed event.", "The problem stems from poor coordination rather than lack of effort.", "stems", true, "Stems from means originates in.", "coordination", "noun", "organizing parts so they work together"),
        lesson("Comparing Alternatives", "weighing options", "Compare options in a reasoned way.", "You choose between two plans.", "The second option is less convenient but considerably more secure.", "considerably", true, "Considerably means by a large degree.", "alternative", "noun", "another possible choice"),
        lesson("Discussing Risk", "possible problems", "Describe risk without panic.", "You review a travel plan.", "There is a risk of delay if the weather deteriorates.", "risk", true, "Risk means the possibility of something bad happening.", "deteriorate", "verb", "to become worse"),
        lesson("Making Recommendations", "advice with reasons", "Recommend an action with justification.", "You advise a manager.", "I would recommend postponing the launch until the tests are complete.", "recommend", false, "Recommend means forbid something officially.", "recommendation", "noun", "advice about what should be done")
      ]),
      unit("Formal And Informal Communication", "register, tact, requests, and clarification", [
        lesson("Adjusting Register", "formal alternatives", "Choose language for the audience.", "You write to a manager.", "I would appreciate further information about the schedule.", "appreciate", true, "Would appreciate is formal and polite.", "register", "noun", "the level of formality in language"),
        lesson("Tactful Feedback", "constructive criticism", "Give criticism that helps.", "You comment on a draft.", "The introduction would be clearer if the main question appeared earlier.", "clearer", true, "Would be clearer softens criticism.", "feedback", "noun", "comments intended to help improve something"),
        lesson("Clarifying Expectations", "precision in tasks", "Ask exactly what is needed.", "You receive an unclear assignment.", "Could you clarify what level of detail you expect?", "clarify", true, "Clarify means make clearer.", "expectation", "noun", "a belief about what should happen"),
        lesson("Diplomatic Disagreement", "measured tone", "Disagree without attacking someone.", "You respond to a proposal.", "I see the advantage, but I am not convinced it is practical.", "convinced", false, "Not convinced means fully persuaded.", "diplomatic", "adjective", "careful and tactful in dealing with people")
      ]),
      unit("Complex Experiences", "change, contrast, speculation, and summary", [
        lesson("Describing Change", "trends over time", "Explain how something has changed.", "You discuss neighborhood shops.", "The area has become more diverse over the past decade.", "diverse", true, "Diverse means including different kinds of people or things.", "trend", "noun", "a general direction of change"),
        lesson("Contrasting Perspectives", "different viewpoints", "Compare two views fairly.", "You discuss remote work.", "Some employees value flexibility, whereas others miss daily contact.", "whereas", true, "Whereas contrasts two facts.", "perspective", "noun", "a way of thinking about something"),
        lesson("Speculating Carefully", "possibility and probability", "Talk about uncertain causes.", "You explain low attendance.", "The low turnout may have been due to the heavy rain.", "may", true, "May have been expresses uncertain possibility.", "speculation", "noun", "a guess based on limited information"),
        lesson("Summarizing A Discussion", "synthesis", "Summarize the main outcome.", "You close a meeting.", "Overall, the group supported the idea despite several reservations.", "reservations", false, "Reservations are complete agreements with no doubts.", "summary", "noun", "a short statement of the main points")
      ])
    ]
  },
  {
    level: "C1",
    xp: 100,
    units: [
      unit("Nuanced Argument", "qualification, counterargument, causality, and synthesis", [
        lesson("Qualified Claims", "avoiding overstatement", "Use cautious language to make claims credible.", "You evaluate mixed evidence.", "The policy appears to be effective, provided it is implemented consistently.", "provided", true, "Provided introduces a condition.", "tentative", "adjective", "not final or certain because more evidence may be needed"),
        lesson("Counterarguments", "responding fairly", "Acknowledge opposing views and answer them.", "You respond to a serious objection.", "While the objection is reasonable, it overlooks the long-term benefits.", "overlooks", true, "Overlooks means fails to consider.", "objection", "noun", "a reason for disagreeing with something"),
        lesson("Layered Consequences", "cause chains", "Describe indirect causes and effects.", "You analyze a participation problem.", "Limited access to training may contribute to lower confidence, thereby reducing participation.", "thereby", true, "Thereby introduces a result of the previous action.", "underlying", "adjective", "basic or hidden but important"),
        lesson("Balanced Conclusions", "synthesis", "End with a qualified judgment.", "You conclude a formal discussion.", "Overall, the benefits outweigh the drawbacks if the transition is managed carefully.", "outweigh", false, "Outweigh means be less important than something else.", "synthesize", "verb", "to combine ideas into a coherent whole")
      ]),
      unit("Professional Interaction", "tact, expectations, priorities, and feedback", [
        lesson("Tactful Disagreement", "productive conflict", "Disagree clearly while preserving collaboration.", "You challenge a colleague's plan.", "I see your point, but I am not fully convinced this is the most practical option.", "convinced", true, "Not fully convinced signals measured disagreement.", "tactful", "adjective", "careful not to offend people while addressing a difficult issue"),
        lesson("Clarifying Scope", "responsibilities", "Make expectations and limits explicit.", "You ask about a report.", "Could you clarify whether the summary should include recommendations?", "clarify", true, "Clarify means make something clearer.", "scope", "noun", "the range or limits of what is included"),
        lesson("Negotiating Priorities", "trade-offs", "Discuss priorities under constraints.", "You have limited time.", "Given the time available, I suggest prioritizing accuracy over extra detail.", "Given", true, "Given can mean considering.", "constraint", "noun", "a limit that affects what is possible"),
        lesson("Constructive Feedback", "specific improvement", "Give feedback that is fair and actionable.", "You review a presentation.", "The structure is strong, but the evidence needs greater specificity.", "specificity", false, "Specificity means vagueness or lack of detail.", "actionable", "adjective", "clear enough to be acted on")
      ]),
      unit("Advanced Reading And Listening", "stance, structure, inference, and emphasis", [
        lesson("Implied Stance", "reading between lines", "Recognize attitudes that are suggested indirectly.", "You analyze a speaker's tone.", "The speaker describes the plan as ambitious, but her tone suggests doubt.", "doubt", true, "Doubt is uncertainty or lack of belief.", "stance", "noun", "a person's attitude or position on an issue"),
        lesson("Main Claim And Support", "argument roles", "Separate a central claim from support.", "You read a dense article.", "The statistics support the broader claim that habits are shaped by environment.", "claim", true, "A claim is an assertion that may need support.", "anecdote", "noun", "a short story based on personal experience"),
        lesson("Inference From Context", "unknown words", "Infer meaning from surrounding clues.", "You meet an unfamiliar adjective.", "Although the word was unfamiliar, the surrounding examples made its meaning clear.", "surrounding", true, "Surrounding means near or around something.", "infer", "verb", "to understand something from evidence rather than direct statement"),
        lesson("Listening For Emphasis", "key points", "Use emphasis and signposting to follow speech.", "You listen to a talk.", "The speaker repeatedly stresses that trust is the central issue.", "central", false, "Central means minor or unimportant.", "signpost", "verb", "to indicate the structure or direction of speech or writing")
      ]),
      unit("Sophisticated Expression", "reformulation, emphasis, concession, and register", [
        lesson("Reformulation", "saying it more precisely", "Restate an idea with greater precision.", "You refine a vague explanation.", "The issue is not a lack of effort; more precisely, it is a lack of coordination.", "precisely", true, "Precisely means exactly or accurately.", "reformulate", "verb", "to express an idea again in a clearer or different way"),
        lesson("Emphatic Structures", "highlighting ideas", "Use structures that focus attention.", "You emphasize the key issue.", "What matters most is whether the explanation is convincing.", "convincing", true, "Convincing means able to make someone believe something.", "emphatic", "adjective", "giving special importance or force to something"),
        lesson("Concession And Contrast", "mixed evaluation", "Use formal contrast language smoothly.", "You discuss limited evidence.", "The evidence is limited; nevertheless, it raises an important question.", "nevertheless", true, "Nevertheless introduces contrast.", "reservation", "noun", "a doubt or concern about something"),
        lesson("Register And Precision", "formal style", "Replace vague language with precise alternatives.", "You revise a report.", "The revised version provides a considerably more precise explanation.", "considerably", false, "Considerably means by a very small amount only.", "register", "noun", "the level of formality or style used in language")
      ])
    ]
  },
  {
    level: "C2",
    xp: 120,
    units: [
      unit("Precision In Argument", "qualification, concession, evidence, and counterargument", [
        lesson("Qualified Claims", "exact limits", "Say exactly how far an argument goes.", "You evaluate a proposal with incomplete evidence.", "Arguably, the proposal is defensible only if its long-term costs are made explicit.", "Arguably", true, "Arguably marks a claim as reasonable but open to dispute.", "provisional", "adjective", "temporary and likely to change when more information is available"),
        lesson("Concession", "acknowledging force", "Concede a point without surrendering the argument.", "You answer a thoughtful critic.", "While the criticism is not without merit, it overlooks the broader historical context.", "merit", true, "Merit means value or worthiness.", "concede", "verb", "to admit that something is true or reasonable"),
        lesson("Evidential Weight", "how much proof proves", "Judge the strength of evidence precisely.", "You interpret research findings.", "The data suggest a correlation, but they do not establish causation.", "correlation", true, "Correlation is not the same as causation.", "anecdotal", "adjective", "based on personal stories rather than systematic evidence"),
        lesson("Fair Counterargument", "no straw men", "Represent an opposing view fairly before challenging it.", "You write a reply to an objection.", "The objection is persuasive at first glance; nevertheless, it depends on a false premise.", "premise", false, "A premise is the final decorative sentence in a story.", "caricature", "verb", "to describe something in an exaggerated or oversimplified way")
      ]),
      unit("Sophisticated Register", "tact, formality, diplomacy, and nuance", [
        lesson("Tactful Criticism", "clear but not blunt", "Make criticism constructive and precise.", "You review a colleague's introduction.", "The introduction could be more focused if the central question appeared earlier.", "focused", true, "Focused means clearly directed at the main point.", "constructive", "adjective", "intended to help improve something"),
        lesson("Formal Alternatives", "controlled precision", "Select formal expressions for official contexts.", "You write instructions for participants.", "Participants were required to obtain written permission in advance.", "obtain", true, "Obtain is a formal verb meaning get.", "approximately", "adverb", "nearly exact but not exact"),
        lesson("Diplomatic Disagreement", "rejecting ideas carefully", "Disagree in a measured and collaborative tone.", "You challenge a broad conclusion.", "I am not convinced that the evidence supports such a broad conclusion.", "convinced", true, "Not convinced expresses doubt without insult.", "measured", "adjective", "careful, controlled, and not extreme"),
        lesson("Nuanced Tone", "implication", "Recognize subtle evaluative tone.", "You analyze a claim that sounds simple.", "The solution is ostensibly simple, though its consequences are far from obvious.", "ostensibly", false, "Ostensibly always means certainly and without doubt.", "neutral", "adjective", "not supporting one side or showing strong feeling")
      ]),
      unit("Complex Meaning And Cohesion", "reference, contrast, causality, and focus", [
        lesson("Cohesive Reference", "clear pointing", "Use reference words without ambiguity.", "You connect two analytical points.", "This distinction matters because it changes how the evidence should be interpreted.", "distinction", true, "A distinction is a difference between similar things.", "antecedent", "noun", "the earlier word or phrase that a pronoun refers to"),
        lesson("Contrastive Logic", "precise markers", "Distinguish contrast, concession, and correction.", "You correct a mistaken explanation.", "The issue is not a lack of effort; rather, it is a lack of coordination.", "rather", true, "Rather can correct or replace a previous idea.", "whereas", "conjunction", "used to compare or contrast two facts"),
        lesson("Cause And Consequence", "partial causation", "Explain causality without oversimplifying.", "You analyze a misunderstanding.", "The misunderstanding stemmed from a difference in expectations rather than a lack of goodwill.", "stemmed", true, "Stemmed from means originated in.", "goodwill", "noun", "friendly or cooperative feelings toward others"),
        lesson("Emphasis And Focus", "guiding attention", "Use focusing structures to shape interpretation.", "You compare speed and accuracy.", "What matters most is not the speed of the response but its accuracy.", "accuracy", false, "Accuracy means dramatic style rather than correctness.", "foreground", "verb", "to make something especially noticeable or important")
      ]),
      unit("Advanced Interpretation", "stance, purpose, inference boundaries, and rhetorical effect", [
        lesson("Implied Stance", "attitude beneath words", "Infer stance from lexical cues.", "You analyze a supposedly neutral plan.", "The plan is supposedly neutral, but its effects are uneven.", "supposedly", true, "Supposedly can signal doubt about a claim.", "uneven", "adjective", "not equal, consistent, or balanced"),
        lesson("Rhetorical Purpose", "why it is phrased that way", "Identify the effect a phrase seeks to create.", "You interpret a public statement.", "By framing the issue as temporary, the speaker seeks to reassure the audience.", "reassure", true, "Reassure means make someone feel less worried.", "frame", "verb", "to present an issue in a way that shapes understanding"),
        lesson("Inference Boundaries", "not overreading", "Draw careful inferences without adding unsupported claims.", "You interpret a pause in conversation.", "The hesitation may imply uncertainty, but it does not prove disagreement.", "imply", true, "Imply means suggest without saying directly.", "restraint", "noun", "careful control over what one says or does"),
        lesson("Rhetorical Effect", "how language works", "Explain effects created by wording.", "You analyze repeated phrasing.", "The repetition reinforces the speaker's sense of urgency.", "reinforces", false, "Reinforces means weakens or undercuts.", "heighten", "verb", "to increase the intensity of something")
      ])
    ]
  }
];

const placementQuestions = [
  pq("placement-a1-1", "A1", "greetings", "Choose the best reply to: Hi, I'm Yuki.", ["Nice to meet you.", "At seven o'clock.", "Because I was late.", "Although it is useful."], "Nice to meet you.", "A1 checks basic social response."),
  pq("placement-a1-2", "A1", "objects", "Choose the sentence that names an object correctly.", ["This is a notebook.", "This are notebook.", "Notebook is yesterday.", "Although notebook."], "This is a notebook.", "A1 checks simple be-verb object naming."),
  pq("placement-a1-3", "A1", "routine", "Choose the simple daily routine sentence.", ["I wake up at seven.", "I waking seven.", "I have woken arguably.", "Seven wakes me because."], "I wake up at seven.", "A1 checks common present-tense routine language."),
  pq("placement-a2-1", "A2", "past events", "Choose the sentence about a past weekend.", ["Last weekend we visited a museum.", "Tomorrow we visited a museum.", "We visiting museum yesterday.", "The museum visits our weekend."], "Last weekend we visited a museum.", "A2 checks simple past with a time marker."),
  pq("placement-a2-2", "A2", "plans", "Choose the sentence that clearly describes a plan.", ["I am going to meet my cousin tomorrow.", "I met my cousin every tomorrow.", "I am meet cousin yesterday.", "Meet cousin going I."], "I am going to meet my cousin tomorrow.", "A2 checks going to for future arrangements."),
  pq("placement-a2-3", "A2", "directions", "Choose the useful direction.", ["Go straight and turn left at the corner.", "Straight left corner the go.", "The corner is yesterday.", "Because left is straight."], "Go straight and turn left at the corner.", "A2 checks local direction language."),
  pq("placement-b1-1", "B1", "opinion", "Choose the balanced opinion.", ["I agree to some extent, but the price is too high.", "Everything is always perfect.", "No opinion because yes.", "The price agrees me."], "I agree to some extent, but the price is too high.", "B1 checks opinion plus reservation."),
  pq("placement-b1-2", "B1", "problem solving", "Choose the practical suggestion.", ["We could divide the task into smaller parts.", "We task could smaller because.", "The problem is no.", "Divide is always impossible."], "We could divide the task into smaller parts.", "B1 checks simple solution language."),
  pq("placement-b1-3", "B1", "story", "Choose the sentence with clear sequence.", ["First we missed the train, then we found a better route.", "Then first better train missed.", "We missed because route better first.", "The train was a reason of first."], "First we missed the train, then we found a better route.", "B1 checks narrative sequence."),
  pq("placement-b2-1", "B2", "evidence", "Choose the appropriately cautious evidence statement.", ["The survey suggests that commuters prefer cheaper fares.", "The survey proves every commuter agrees.", "The survey is fare cheaper because all.", "Evidence means no support."], "The survey suggests that commuters prefer cheaper fares.", "B2 checks evidence without overclaiming."),
  pq("placement-b2-2", "B2", "concession", "Choose the best concession sentence.", ["Although the policy is expensive, it could reduce long-term costs.", "Because expensive although costs.", "The policy expensive is reduce.", "Costs are long because policy."], "Although the policy is expensive, it could reduce long-term costs.", "B2 checks concessive argument structure."),
  pq("placement-b2-3", "B2", "register", "Choose the most formal request.", ["I would appreciate further information about the schedule.", "Tell me the schedule now.", "Schedule info, give it.", "I wanna know the stuff."], "I would appreciate further information about the schedule.", "B2 checks audience-appropriate register."),
  pq("placement-c1-1", "C1", "qualified argument", "Choose the qualified claim.", ["The policy appears to be effective, provided it is implemented consistently.", "The policy always solves every problem.", "Effective policy because yes.", "The implementation appears all."], "The policy appears to be effective, provided it is implemented consistently.", "C1 checks conditional qualification."),
  pq("placement-c1-2", "C1", "causality", "Choose the sentence that expresses layered consequence.", ["Limited access to training may contribute to lower confidence, thereby reducing participation.", "Training access confidence participation lower limited.", "Participation reduces because all training proves.", "Thereby means unrelated."], "Limited access to training may contribute to lower confidence, thereby reducing participation.", "C1 checks multi-step causality."),
  pq("placement-c1-3", "C1", "synthesis", "Choose the balanced conclusion.", ["Overall, the benefits outweigh the drawbacks if the transition is managed carefully.", "Everything is perfect and no drawbacks exist.", "Drawbacks outweigh benefits means benefits bigger.", "Overall because transition if."], "Overall, the benefits outweigh the drawbacks if the transition is managed carefully.", "C1 checks synthesis with limitation."),
  pq("placement-c2-1", "C2", "evidential weight", "Choose the precise evidence statement.", ["The data suggest a correlation, but they do not establish causation.", "The data prove every cause completely.", "Correlation always means causation.", "The evidence is merely decorative."], "The data suggest a correlation, but they do not establish causation.", "C2 checks evidential precision."),
  pq("placement-c2-2", "C2", "implied stance", "Choose the sentence with subtle stance and implication.", ["The solution is ostensibly simple, though its consequences are far from obvious.", "The solution is simple and simple.", "Consequences are obvious because ostensibly.", "Ostensibly means certainly true."], "The solution is ostensibly simple, though its consequences are far from obvious.", "C2 checks implied distance from an apparent claim."),
  pq("placement-c2-3", "C2", "inference boundary", "Choose the careful inference.", ["The hesitation may imply uncertainty, but it does not prove disagreement.", "The hesitation proves dishonesty.", "Silence always means agreement.", "Uncertainty is proven by every pause."], "The hesitation may imply uncertainty, but it does not prove disagreement.", "C2 checks restraint in interpretation.")
];

function unit(title, focus, lessons) {
  return { title, focus, lessons };
}

function lesson(title, subtitle, goal, scenario, sentence, cloze, tfAnswer, tfPrompt, term, partOfSpeech, definition) {
  return { title, subtitle, goal, scenario, sentence, cloze, tfAnswer, tfPrompt, term, partOfSpeech, definition };
}

function pq(questionId, cefrBand, skill, prompt, choices, answer, explanation) {
  return {
    questionId,
    cefrBand,
    skill,
    prompt,
    promptDetail: null,
    choices,
    acceptableAnswers: [answer],
    explanation
  };
}

function buildCurriculum() {
  const lexemes = [];
  const units = [];
  let unitIndex = 1;

  levels.forEach((levelData) => {
    levelData.units.forEach((unitData, unitOffset) => {
      const unitId = `${levelData.level.toLowerCase()}-u${String(unitOffset + 1).padStart(2, "0")}`;
      const lessons = unitData.lessons.map((lessonData, lessonOffset) => {
        const lessonId = `${unitId}-l${String(lessonOffset + 1).padStart(2, "0")}`;
        lexemes.push(primaryLexeme(levelData.level, unitId, lessonId, lessonData, lessonOffset));
        lexemes.push(functionLexeme(levelData.level, unitId, lessonId, unitData, lessonOffset));
        return {
          lessonId,
          index: lessonOffset + 1,
          title: lessonData.title,
          subtitle: lessonData.subtitle,
          goal: lessonData.goal,
          xpReward: levelData.xp + lessonOffset * 5,
          narrative: `${lessonData.scenario} ${lessonData.goal} The target sentence is: ${lessonData.sentence}`,
          tips: tipsFor(levelData.level, lessonData),
          exercises: exercisesFor(levelData.level, lessonId, lessonData)
        };
      });

      units.push({
        unitId,
        index: unitIndex,
        title: unitData.title,
        cefrBand: levelData.level,
        focus: unitData.focus,
        lessons
      });
      unitIndex += 1;
    });
  });

  return { lexemes, placementQuestions, units };
}

function primaryLexeme(level, unitId, lessonId, lessonData, lessonOffset) {
  return {
    lexemeId: `lex-${lessonId}-primary`,
    headword: lessonData.term,
    partOfSpeech: lessonData.partOfSpeech,
    cefrBand: level,
    lessonId,
    definition: lessonData.definition,
    exampleSentence: lessonData.sentence,
    translation: null,
    collocations: collocationsFor(lessonData.term),
    distractors: distractorsFor(level, lessonOffset),
    confusables: confusablesFor(lessonData.term),
    tags: [level, unitId, "curriculum"]
  };
}

function functionLexeme(level, unitId, lessonId, unitData, lessonOffset) {
  const item = functionTerms[level][lessonOffset % functionTerms[level].length];
  return {
    lexemeId: `lex-${lessonId}-function`,
    headword: item.headword,
    partOfSpeech: item.partOfSpeech,
    cefrBand: level,
    lessonId,
    definition: item.definition,
    exampleSentence: item.example,
    translation: null,
    collocations: item.collocations,
    distractors: distractorsFor(level, lessonOffset + 3),
    confusables: item.confusables,
    tags: [level, slug(unitData.title), "function"]
  };
}

const functionTerms = {
  A1: [
    term("please", "adverb", "used to make a request polite", "Could you repeat that, please?", ["please help", "please repeat"], ["thanks", "sorry"]),
    term("this", "determiner", "used to point to a nearby thing", "This is my bag.", ["this book", "this room"], ["that", "these"]),
    term("from", "preposition", "used to show origin", "She is from Canada.", ["from Spain", "from home"], ["for", "to"]),
    term("today", "adverb", "on the present day", "It is cold today.", ["today is", "today at"], ["tomorrow", "yesterday"])
  ],
  A2: [
    term("would like", "phrase", "a polite way to say want", "I would like a cup of tea.", ["would like to", "would like a"], ["want", "prefer"]),
    term("going to", "phrase", "used for future plans", "I am going to study tonight.", ["going to meet", "going to visit"], ["will", "about to"]),
    term("because", "conjunction", "used to introduce a reason", "I stayed home because I was tired.", ["because of", "because I"], ["so", "although"]),
    term("should", "modal verb", "used to give advice", "You should rest.", ["should try", "should not"], ["must", "could"])
  ],
  B1: [
    term("to some extent", "phrase", "partly but not completely", "I agree to some extent.", ["agree to some extent", "true to some extent"], ["partly", "completely"]),
    term("as a result", "phrase", "used to introduce a consequence", "As a result, the plan changed.", ["as a result of", "as a result"], ["therefore", "for example"]),
    term("at first", "phrase", "at the beginning of a situation", "At first I was doubtful.", ["at first glance", "at first"], ["initially", "finally"]),
    term("could", "modal verb", "used to suggest a possibility", "We could divide the work.", ["could be", "could try"], ["can", "would"])
  ],
  B2: [
    term("although", "conjunction", "used to introduce contrast", "Although it was costly, it worked.", ["although the plan", "although it"], ["though", "whereas"]),
    term("whereas", "conjunction", "used to compare contrasting facts", "Some agreed, whereas others refused.", ["whereas others", "whereas the first"], ["while", "however"]),
    term("considerably", "adverb", "by a large amount", "The second option is considerably safer.", ["considerably more", "improve considerably"], ["significantly", "slightly"]),
    term("overall", "adverb", "considering everything", "Overall, the plan was successful.", ["overall effect", "overall impression"], ["generally", "finally"])
  ],
  C1: [
    term("provided", "conjunction", "if a condition is met", "The plan works provided it is funded.", ["provided that", "provided it"], ["if", "unless"]),
    term("thereby", "adverb", "as a result of what was just mentioned", "The change saved time, thereby reducing costs.", ["thereby reducing", "thereby allowing"], ["therefore", "thus"]),
    term("nevertheless", "adverb", "despite what has just been said", "It was difficult; nevertheless, it succeeded.", ["nevertheless important", "nevertheless true"], ["however", "nonetheless"]),
    term("more precisely", "phrase", "used before a more exact restatement", "More precisely, the issue is timing.", ["more precisely", "state more precisely"], ["specifically", "exactly"])
  ],
  C2: [
    term("arguably", "adverb", "used when a claim can reasonably be supported", "Arguably, the final section is strongest.", ["arguably true", "arguably flawed"], ["presumably", "undoubtedly"]),
    term("ostensibly", "adverb", "apparently, often with doubt about the appearance", "The rule is ostensibly neutral.", ["ostensibly simple", "ostensibly neutral"], ["apparently", "supposedly"]),
    term("rather", "adverb", "used to correct or replace a previous statement", "It is not speed; rather, it is accuracy.", ["rather than", "or rather"], ["instead", "somewhat"]),
    term("may imply", "phrase", "suggests a possible meaning without proving it", "The pause may imply hesitation.", ["may imply uncertainty", "may imply doubt"], ["suggest", "prove"])
  ]
};

function term(headword, partOfSpeech, definition, example, collocations, confusables) {
  return { headword, partOfSpeech, definition, example, collocations, confusables };
}

function tipsFor(level, lessonData) {
  if (level === "A1" || level === "A2") {
    return [
      `Use the target sentence aloud: ${lessonData.sentence}`,
      `Focus on ${lessonData.cloze}; it carries the lesson pattern.`,
      "Answer with a complete short sentence before checking."
    ];
  }
  if (level === "B1" || level === "B2") {
    return [
      "State the main idea before adding detail.",
      `Use ${lessonData.cloze} to connect the sentence logically.`,
      "Keep the tone clear and natural for the situation."
    ];
  }
  return [
    "Match confidence to evidence; avoid saying more than the wording supports.",
    `Notice how ${lessonData.cloze} shapes stance, logic, or register.`,
    "Explain why the sentence works, not only what it means."
  ];
}

function exercisesFor(level, lessonId, lessonData) {
  return [
    {
      exerciseId: `${lessonId}-e01`,
      kind: "MultipleChoice",
      prompt: "Choose the sentence that best fits the situation.",
      promptDetail: lessonData.scenario,
      choices: shuffleStable([lessonData.sentence, foil(level, lessonData, 1), foil(level, lessonData, 2), foil(level, lessonData, 3)]),
      fragments: [],
      answerText: null,
      acceptableAnswers: [lessonData.sentence],
      translation: null,
      hint: "Choose the option that is grammatical and matches the situation.",
      explanation: `The correct option fits the situation and practices ${lessonData.subtitle}.`
    },
    {
      exerciseId: `${lessonId}-e02`,
      kind: "Cloze",
      prompt: "Complete the sentence.",
      promptDetail: blankSentence(lessonData.sentence, lessonData.cloze),
      choices: [],
      fragments: [],
      answerText: lessonData.cloze,
      acceptableAnswers: unique([lessonData.cloze, lessonData.cloze.toLowerCase()]),
      translation: null,
      hint: `Use the key word or phrase from ${lessonData.subtitle}.`,
      explanation: `${lessonData.cloze} is the form that completes the target sentence.`
    },
    {
      exerciseId: `${lessonId}-e03`,
      kind: "Ordering",
      prompt: "Put the words in order.",
      promptDetail: null,
      choices: [],
      fragments: lessonData.sentence.split(" "),
      answerText: null,
      acceptableAnswers: [lessonData.sentence],
      translation: null,
      hint: "Start with the subject or opening connector, then build the complete sentence.",
      explanation: "The ordered sentence preserves the lesson pattern and its punctuation."
    },
    {
      exerciseId: `${lessonId}-e04`,
      kind: "TrueFalse",
      prompt: `True or false: ${lessonData.tfPrompt}`,
      promptDetail: null,
      choices: ["true", "false"],
      fragments: [],
      answerText: null,
      acceptableAnswers: [lessonData.tfAnswer ? "true" : "false"],
      translation: null,
      hint: "Check whether the statement accurately describes the target language.",
      explanation: lessonData.tfAnswer ? "The statement is accurate for this lesson." : "The statement misrepresents the target language."
    }
  ];
}

function foil(level, lessonData, index) {
  const simple = [
    `I no ${lessonData.term} at yesterday.`,
    `${capitalize(lessonData.term)} is go to the table.`,
    `Because the ${lessonData.term} are very Monday.`
  ];
  const advanced = [
    "The evidence proves every possible interpretation beyond dispute.",
    "The issue is simple, certain, and requires no qualification.",
    "The speaker changes the topic instead of addressing the objection."
  ];
  return (["A1", "A2", "B1"].includes(level) ? simple : advanced)[index - 1];
}

function capitalize(text) {
  return text.length === 0 ? text : `${text[0].toUpperCase()}${text.slice(1)}`;
}

function blankSentence(sentence, cloze) {
  const index = sentence.toLowerCase().indexOf(cloze.toLowerCase());
  if (index < 0) {
    throw new Error(`Cloze "${cloze}" not found in "${sentence}"`);
  }
  return `${sentence.slice(0, index)}____${sentence.slice(index + cloze.length)}`;
}

function collocationsFor(headword) {
  return [`${headword} example`, `${headword} pattern`];
}

function confusablesFor(headword) {
  return [`similar to ${headword}`, `not ${headword}`];
}

function distractorsFor(level, offset) {
  const banks = {
    A1: ["desk", "green", "walk"],
    A2: ["appointment", "larger", "straight"],
    B1: ["concern", "result", "sequence"],
    B2: ["evidence", "register", "alternative"],
    C1: ["specificity", "scope", "stance"],
    C2: ["premise", "causation", "ostensibly"]
  };
  const bank = banks[level];
  return [bank[offset % bank.length], bank[(offset + 1) % bank.length], bank[(offset + 2) % bank.length]];
}

function shuffleStable(values) {
  return [values[1], values[0], values[3], values[2]];
}

function unique(values) {
  return Array.from(new Set(values));
}

function slug(text) {
  return text.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
}

function validate(curriculum) {
  const ids = new Set();
  const addId = (id) => {
    if (ids.has(id)) throw new Error(`Duplicate id: ${id}`);
    ids.add(id);
  };
  curriculum.lexemes.forEach((lexeme) => addId(lexeme.lexemeId));
  curriculum.placementQuestions.forEach((question) => {
    addId(question.questionId);
    if (question.choices.length < 2) throw new Error(`Placement question has too few choices: ${question.questionId}`);
    if (question.acceptableAnswers.length < 1) throw new Error(`Placement question has no answer: ${question.questionId}`);
  });
  curriculum.units.forEach((unit) => {
    addId(unit.unitId);
    if (unit.lessons.length !== 4) throw new Error(`Unit does not have 4 lessons: ${unit.unitId}`);
    unit.lessons.forEach((lesson) => {
      addId(lesson.lessonId);
      if (lesson.exercises.length !== 4) throw new Error(`Lesson does not have 4 exercises: ${lesson.lessonId}`);
      lesson.exercises.forEach((exercise) => {
        addId(exercise.exerciseId);
        if (exercise.acceptableAnswers.length < 1) throw new Error(`Exercise has no answer: ${exercise.exerciseId}`);
        if (exercise.kind === "Ordering" && exercise.fragments.length < 2) throw new Error(`Ordering exercise too short: ${exercise.exerciseId}`);
      });
    });
  });
}

const curriculum = buildCurriculum();
validate(curriculum);
fs.writeFileSync(outputPath, `${JSON.stringify(curriculum, null, 2)}\n`);
console.log(`Wrote ${path.relative(root, outputPath)}`);
console.log(`${curriculum.units.length} units, ${curriculum.units.reduce((sum, unit) => sum + unit.lessons.length, 0)} lessons, ${curriculum.lexemes.length} lexemes, ${curriculum.placementQuestions.length} placement questions`);
