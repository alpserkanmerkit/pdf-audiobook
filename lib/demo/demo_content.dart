// DEMO mode FAKE AI content: discussion, quiz, tutoring and explanation texts
// written by hand for the sample book Ömer Seyfettin's "Üç Hikâye" (Kaşağı,
// Forsa, Primo Türk Çocuğu). None of it comes from a model; everything was
// written in advance (source/attribution: assets/demo/KAYNAK.txt).
//
// Discussion rules (aligned with the app's own prompt/lint rules):
// speaker labels A=Ahmet, B=Emel, C=Deniz, D=Kaya; each turn 3-4 sentences;
// no parentheses; no standalone A/B/C/D letter inside a turn; nobody names
// themselves; address is only to the immediately previous speaker; a batch
// ends with an unresolved conflict. test/demo/demo_llm_router_test.dart checks
// these with the real parser and lint.

/// (speaker letter, turn text)
typedef DemoLine = (String, String);

/// Opening session: 12 turns on Kaşağı.
const List<DemoLine> kDemoOpening = [
  (
    'A',
    'For the child in Kaşağı, I think the most accurate word is coward. The moment his father spots the broken currycomb in the trough and shouts for Dadaruh, he points at his younger brother Hasan to save his own skin. He even decorates the lie with detail, saying "Dadaruh came into the room yesterday while he was sleeping," so he speaks with cold calculation, not panic. Feeling pity for this child means underestimating the blame the text places on him.',
  ),
  (
    'B',
    "You have to forget the child's age to pass such a harsh verdict. The text tells us he barely reaches the horse's belly, and one look from his father scares him out of his wits. Terrified of punishment, the child lies not by calculating, but to keep from drowning. The real proof is that he cannot rest after the lie, because his brother's image keeps rising before his eyes and he weeps over having slandered him.",
  ),
  (
    'C',
    'You are both looking inside the child, but my thesis knots up in the father. The man who said "Tell the truth, I will not be angry" slaps Hasan and declares him a liar when he denies it, then keeps him locked in the house. He is the one who built the system of fear that produced the lie, and the child simply took the easiest path inside it. That is why the real culprit is that house itself, run by harshness rather than love.',
  ),
  (
    'D',
    "Let us get concrete, because Pervin's sentence challenges all of your theses. At midnight the child wants to confess, but Pervin tells him to say it tomorrow, since his father is sleeping now. By morning Hasan has died, so what delayed the confession was neither the child's cowardice nor the father's harshness, but the postponement by the adults. The child Ahmet calls a coward is the only one who tried to tell the truth at the first chance.",
  ),
  (
    'A',
    "Kaya, confessing late does not erase the cost of the lie. For a whole year the child watches in silence as Hasan is slapped, banned from the stable, and kept locked in the house. Even his mother does not consider that he could have made up the accusation, so everyone carries his lie without knowing it. Blaming Pervin means shifting onto someone else's shoulders a sentence that came out of your own mouth.",
  ),
  (
    'B',
    "Ahmet, you keep the child in the defendant's chair, but the text punishes him too. On the morning Hasan dies, the narrator rushes to unload the guilt that poisons him, and he finds Dadaruh and the imam weeping in the courtyard. The story ends exactly on this scene, because the chance to confess has been taken from him. No father's slap could inflict a heavier punishment than this, yet you ignore it and still stamp him as a coward.",
  ),
  (
    'C',
    "Emel presents death as a punishment, yet the story does not treat the pangs of conscience as a form of release. My view is that this weight is the bill for the system of fear the father built, not the child's. The sentence that comes out of the father's mouth on the day Hasan is slapped silences the entire house, and the child gives in to that silence as well. Those who look for solutions take refuge in conscience, but I want the hand that set the rule to answer for it.",
  ),
  (
    'D',
    "Deniz, you use the word system only to feel comfortable, because the father's only move in the text is not the slap. The same father never leaves his son's bedside during the diphtheria, and the text makes a point of writing this. Besides, when Dadaruh sees the broken currycomb he says I do not know, so everyone in the adult world is hiding something too. Yet inflating the child's lie and making the father a villain both cover up this shared silence.",
  ),
  (
    'A',
    "The shared silence you mention does not make up for the child's lie. Dadaruh's saying I do not know protects his own job, while the child naming Hasan hurts someone else. Placing the two side by side is Kaya's weakest move, because Dadaruh blames nobody in the text. The difference is exactly here: one stays silent, while the other pushes a brother onto the stage.",
  ),
  (
    'B',
    'The difference you see is, to me, only a difference in age. Dadaruh is an old man who does not raise his voice even in front of the father, and he never takes a slap in the text. The child, on the other hand, has just crushed a currycomb, and the narrator himself says he vented his anger on a piece of iron. Lying right after an outburst of rage does not count as mature cowardice.',
  ),
  (
    'D',
    'Let me make the anger concrete, because it is no coincidence that he crushed the currycomb with the heaviest stone he could lift from the edge of the trough. The same child then calls Hasan and waits for him to come running, knowing full well how harsh the father is. When these two acts follow each other, anger and calculation become tangled. What Emel calls age is nothing more than lumping the anger that crushed the currycomb together with the calculation that pointed at Hasan into the same sack.',
  ),
  (
    'C',
    "Both calculation and anger are on the table, but a slap from a father who questioned neither of them is what they produced. Ahmet blames cowardice, Emel blames his age, and Kaya blames the postponement by the adults, yet none of them can take back the slap Hasan received. Since the child is both perpetrator and victim, Ahmet's verdict of cowardice and Emel's verdict of innocence come out right on the same lines at the same time, and I accept neither of them.",
  ),
];

/// Continuation sessions (endless mode): returned in rotation, covering
/// Forsa, Primo, and the three stories as a whole.
const List<List<DemoLine>> kDemoContinuations = [
  [
    (
      'B',
      'Let us leave Kaşağı aside, since the forty-year dream of Kara Memiş in Forsa makes a more interesting claim. The story describes the man seeing ships come every night and, finally, the Turkish fleet entering the harbor. I think this dream is proof of resistance, since a man who has pulled an oar in chains for twenty years keeps his hope in a single dream. The sentence that a dream seen for forty years cannot be a lie is exactly why it is the strongest part of the story.',
    ),
    (
      'A',
      'It may be the strongest part, but that sentence is not proof, it is blindness. To make sure whether he is awake or dreaming, Kara Memiş strikes his own forehead with a stone, so he himself cannot measure the distance between faith and reality. As far as I am concerned, the story says that hope does not need to verify the truth, and that is a very dangerous idea. Salvation arriving by chance does not show that waiting was justified.',
    ),
    (
      'D',
      'Let us look at the concrete scene. The Bey who faces Kara Memiş verifies his identity through the cross-shaped scar on his upper arm, and only then says I am your son. In other words, the author ties the coincidence to a proof: a reunion that begins like chance is confirmed by a mark. Where Ahmet sees blindness, the text in fact leaves a clue that can be checked.',
    ),
    (
      'C',
      "Both of you are stuck on the reunion itself, but to me the real issue is that the story ties its measure to a definition of homeland. At the very end Kara Memiş says that if he falls as a martyr, the flag should cover him, since the homeland is the place where the red flag waves. With this sentence, forty years of captivity find meaning under a banner, and an individual's suffering is handed over to the flag. I read this handover not as a beauty, but as a debt collection.",
    ),
    (
      'A',
      'Deniz, calling it a debt collection is unfair to the text, because it is not a state that wants the flag but an old sailor who gritted his teeth for forty years. Nobody in the story forces the banner on him; he himself asks his son for a shield and a sword to go into battle. When an individual makes his own choice, calling that choice a debt collection means stripping him of his own will.',
    ),
    (
      'B',
      'Ahmet points to free will, Deniz points to the debt collection, but both skip what the son says: you will be wounded, you will go away longing for the homeland. Turgut wants to leave his father on the ship, because he is afraid of losing him again, and this fear is more human than love of homeland. Kara Memiş, however, pays no attention to that fear, says my heart is strong, and asks for a shield. On one side there is the love between father and son, on the other the banner, and the text deliberately does not say which one weighs more.',
    ),
  ],
  [
    (
      'D',
      'In Primo Türk Çocuğu, the fact that Kenan Bey gives his children numbers as names sums up the whole story. Of the two boys they call Primo and Sekundo, Sekundo falls ill and dies. The text presents the Europeanness of Kenan Bey not as an idea but as a habit that reaches down to the names of his children. So his admiration for Europe lives not in his words but in every corner of his home.',
    ),
    (
      'C',
      "Kaya, the numbered names of the children look more like an engineer's habit than admiration for Europe. Kenan Bey is someone used to measuring and ranking everything, and he applies this to his children too. The real break comes with the news of the attack on Tripoli, when that night on the Thessaloniki quay he sees himself as an insignificant servant of the Europeans. My thesis is this: this story is not a story of identity but a reckoning with betrayal.",
    ),
    (
      'A',
      'If you say betrayal, you must say who betrayed whom. The text does not describe Kenan Bey turning his back on his wife, the house of his father, and his faith in civilization all at once; it only recalls the cuckoo clock at the top of the stairs in his old house. I read this not as a reckoning but as a late regret. In my view, a life that collapses under forty-eight hours of anger is not a sincere transformation.',
    ),
    (
      'B',
      'Calling it regret would be too generous to Kenan Bey. The text plainly says that he is weary even of declaring himself a Turk, and that for ten years he has neither visited Bursa nor seen his relatives. So a man who wakes up in one night pays the bill for a decade of neglect, and the author does not hide this. That is why I find no proof in what Ahmet calls a sincere transformation, since the story shows not the transformation but only its beginning.',
    ),
    (
      'D',
      "Emel says beginning but does not look at where the beginning comes from. Grazia's father, Monsieur Vitalis, says that apart from the sultan's family there are no Turkish families in Turkey, and turns his son-in-law into a Greek in his own mind. Kenan Bey's sense of inferiority does not come from within him alone; his surroundings teach him this humiliation. Part of what Deniz counts as betrayal is a betrayal committed against Kenan Bey.",
    ),
    (
      'A',
      'You list the injustice done to him, but it is he himself who understands that Grazia is preparing for the journey when he sees two travel trunks in the house in the morning. The story does not resolve here; the door stays open. Kaya calls him the victim, Deniz calls it reckoning, Emel calls it negligence. All three verdicts rest on the same two travel trunks, and the text approves none of them.',
    ),
  ],
  [
    (
      'C',
      'When I put the three stories side by side, I see something in common: in all three there is a father, a generation, and someone who holds a word of authority. In Kaşağı the father slaps, in Forsa the son rescues his father, and in Primo the plaque in the house of the father comes to mind for Kenan Bey. I read these three scenes as scenes of authority. Love in these stories is a weak side effect living in the shadow of authority.',
    ),
    (
      'D',
      'Since you mention a shadow, let us look at a concrete detail: the plaque in Primo reads: "Do not cross the bridge of the scoundrel." This line comes to the mind of Kenan Bey at the exact moment of turning back, so authority appears there as a measure rather than a punishment. The slap of the father in Kaşağı and the plaque of the father in Primo do not fit the same mold. The frame of authority that Deniz uses squeezes these two scenes into a single type.',
    ),
    (
      'B',
      'Kaya draws a distinction, but I see the difference on the plane of love. The father in Kaşağı says "Tell the truth, I will not be angry," but when Hasan denies it he slaps him, so he does not keep his word. The plaque in Primo writes down the measure, but nobody is obliged to follow it. In one case punishment has crushed love, while in the other the principle has remained a mere memory.',
    ),
    (
      'A',
      'Emel, a principle that remains a mere memory does not help Kenan Bey, because he cannot even carry that principle home after forty-eight hours. Kara Memiş in Forsa, on the other hand, carries his principle for forty years and takes it all the way to the flag. To me this difference looks less like morality itself and more like a matter of endurance. Kenan Bey is weak, Kara Memiş is strong, and stories still do not forgive this weakness.',
    ),
    (
      'C',
      'Dividing things into strong and weak is the easy way that Ahmet likes best. Kara Memiş draws his strength from his chains, while Kenan Bey draws his weakness from his comfort, and weighing these two on the same scale is unfair. Even the death of Hasan is not a matter of power but a matter of silence. The endurance you speak of comes to light in three stories by making each one pay a different price.',
    ),
    (
      'D',
      'The costs are on the table, but who pays which cost, and why, is still disputed. In Kaşağı the child pays with his brother, in Forsa the old sailor pays with forty years, and in Primo Kenan Bey pays with a trunk that is still unwritten. Those who add up these three costs on the same scale load their own theses onto the book. The text, however, leaves all three unresolved, and this contradiction shows the limit of our interpretation.',
    ),
  ],
];

/// Listener question answer (2-4 turns). The question is inserted in place of `{SORU}`.
const List<DemoLine> kDemoAnswer = [
  (
    'B',
    'I heard the listener\'s question: "{SORU}". The book has no direct answer to it, so I will talk through the scenes we have. The closest example in the text is the child losing Hasan without being able to confess to his father. What this example shows is that giving a one-sentence answer to the question is hard.',
  ),
  (
    'A',
    'Let me answer in one sentence: in my view, the answer to the question lies in the cost of the decisions in the stories. In Kaşağı the cost of the lie is a brother, in Forsa the cost of hope is forty years. These two examples answer the question without shrinking it.',
  ),
  (
    'D',
    'Counting costs is a method, but the concrete answer lies in the scar in Forsa. Kara Memiş proves his identity to his son with the cross-shaped scar on his upper arm. So in these stories, what carries a claim is not speech but proof that turns into a mark left on the body.',
  ),
  (
    'C',
    'Kaya emphasizes the scar, but I am asking why a scar counts as proof. Because the Bey believes no one until he hears I am your son, and he ties everything to evidence. That is why the question from the listener turns into a tension between proof and faith, and our discussion picks up exactly where it left off.',
  ),
];

/// Multiple-choice quiz pool: (question, options, correctIndex).
const List<(String, List<String>, int)> kDemoQuiz = [
  (
    "What is the name of the narrator's younger brother in the story Kaşağı?",
    ['Turgut', 'Tosun', 'Hasan', 'Kenan'],
    2,
  ),
  (
    "Who is the narrator's father's groom?",
    ['Pervin', 'Dadaruh', 'Kara Memiş', 'Mösyö Vitalis'],
    1,
  ),
  (
    'Which disease does Hasan die of?',
    ['Diphtheria (kuşpalazı)', 'Malaria', 'Tuberculosis', 'Typhus'],
    0,
  ),
  (
    'What is the name of the old captive in the story Forsa?',
    ['Turgut', 'Hızır', 'Kara Memiş', 'Dadaruh'],
    2,
  ),
  (
    'How does Kara Memiş get his son to recognize him?',
    [
      'With his sword',
      'With the cross-shaped scar on his upper arm',
      'With the headdress on his head',
      'With his ring',
    ],
    1,
  ),
  (
    'In which city does the story Primo Türk Çocuğu begin?',
    ['İzmir', 'Bursa', 'İstanbul', 'Thessaloniki'],
    3,
  ),
  (
    "What is the name of Kenan Bey's wife?",
    [
      'Eleni, of Greek origin',
      'Grazia, of Italian origin',
      'Marie, of French origin',
      'Greta, of German origin',
    ],
    1,
  ),
  (
    'How do Kenan Bey and his wife address their children?',
    [
      'With numbers, like Primo and Sekundo',
      'With Turkish names',
      'With the names of their grandfathers',
      'With nicknames',
    ],
    0,
  ),
];

/// Question bank (8-12 items; type: olgusal | kavramsal | uygulamali).
const List<(String, String, String)> kDemoStudyQuestions = [
  (
    'In the story Kaşağı, what object was broken, and by whom?',
    'It was the shiny currycomb the mother had sent from Istanbul; the narrator crushed it with a stone in anger.',
    'olgusal',
  ),
  (
    'Who did the narrator blame for the broken currycomb?',
    'His younger brother Hasan.',
    'olgusal',
  ),
  (
    'How does Pervin\'s advice "you can tell him tomorrow" affect the ending of the story?',
    'The confession was put off until morning; Hasan died that night, and by then it was too late to confess.',
    'kavramsal',
  ),
  (
    'Where and how did Kara Memiş live for twenty years?',
    'In the galley of Maltese pirates, rowing in chains on his feet.',
    'olgusal',
  ),
  (
    'What does Kara Memiş\'s saying "a dream seen for forty years cannot be a lie" show?',
    'That hope holds on to reality through faith, and that faith keeps a person standing even without waiting for the truth.',
    'kavramsal',
  ),
  (
    'How did the Bey verify the identity of Kara Memiş?',
    'He used the cross-shaped scar on his upper arm, and said he was his son Turgut.',
    'olgusal',
  ),
  (
    "What does Kenan Bey's giving his children numbered names tell us about him?",
    'That he placed European customs before his own identity, and that this imitation reached into family life.',
    'kavramsal',
  ),
  (
    'If a friend accidentally broke something and pinned it on you, how would you resolve the dilemma faced by the child in Kaşağı?',
    'I would tell the truth right away and take responsibility; as the example of Hasan shows, delay can carry a cost that cannot be undone.',
    'uygulamali',
  ),
  (
    'If you compared the waiting in Forsa to a long-term goal in everyday life, what lesson would you draw?',
    "Sustaining hope needs small proofs and persistence; Kara Memiş's patience was rewarded only at the moment he was ready.",
    'uygulamali',
  ),
  (
    'What event shook Kenan Bey in Primo Türk Çocuğu?',
    'The attack of Italy on Tripoli.',
    'olgusal',
  ),
];

/// Word/sentence explanations ("Ask"): lowercase key.
const Map<String, String> kDemoWords = {
  'kaşağı':
      'A curry comb: a toothed iron comb used to groom horses. In the story Dadaruh uses it to clean the horses, and it is also the object the child crushes in anger.',
  'tımar':
      "Grooming an animal, especially brushing and cleaning a horse's coat. The child most of all wants to do this work.",
  'seyis': "Horse groom. Dadaruh is the groom of the narrator's father.",
  'yalak': 'A stone or wooden trough from which animals drink water.',
  'forsa':
      'A convict or captive who was chained to an oar and rowed in a galley. Kara Memiş lived as a forsa for years.',
  'kadırga': 'A large sailing warship propelled by oars.',
  'esir': 'A person taken captive in war or in a pirate raid.',
  'sancak':
      'A flag. In the story it is the symbol of the homeland for Kara Memiş.',
  'iftira': 'Falsely accusing someone of a crime they did not commit.',
  'vicdan':
      'The inner voice that distinguishes good from bad and makes a person uneasy when they do wrong.',
  'naçiz':
      "Powerless and worthless; here it describes Kenan Bey's view of himself as small.",
  'rıhtım': 'The quay where ships dock, a shore structure adjoining the sea.',
};

/// Tutoring parts: chapter title -> 3 parts (explanation, question, expected).
const Map<String, List<(String, String, String)>> kDemoLessons = {
  'Kaşağı': [
    (
      "In this passage we enter the world of the stable through the eyes of the child. The father's groom Dadaruh, the younger brother Hasan, and the narrator spend all their days among the horses. The child's greatest wish is to do grooming, that is, to comb a horse's coat with a currycomb, but he is not allowed because he is too short to reach the horse's belly. One day, when he is alone, he finds the shiny currycomb in Dadaruh's chest, which his mother had sent from Istanbul, and crushes it with a stone out of anger and throws it into the trough.",
      'Why did the narrator crush the currycomb?',
      'He was angry because he could not groom and the horses would not stay still, so he took out his anger on the currycomb.',
    ),
    (
      "When the father sees the broken currycomb in the trough, he calls Dadaruh and asks who did it. Dadaruh says he does not know, and the father's eyes turn to the narrator; out of fear the child blames his brother Hasan. Hasan denies it, but the father calls him a liar and slaps him, and keeps him away from the stable. In this way the lie turns into an event that changes the fate of two children and the whole house.",
      'Whom did the narrator blame for the broken currycomb, and what was the result?',
      'He blamed his brother Hasan; Hasan denied it, but his father slapped him and kept him away from the stable.',
    ),
    (
      'The next year Hasan catches diphtheria. Hearing that his brother may die, the narrator confesses the truth to Pervin at night, tormented by conscience, and wants to tell his father in the morning. Pervin advises him to tell tomorrow, but that night Hasan dies and it is too late for the confession. The story shows how an unspoken truth leaves a burden that cannot be undone.',
      "Why could the narrator's confession not take place?",
      'Pervin told him to wait until morning, and Hasan died that night, so he was too late.',
    ),
  ],
  'Forsa': [
    (
      'In an almond orchard on the Mediterranean coast, an old man sees in a dream the salvation he has waited for forty years. This man is Kara Memiş, a former Turkish forsa; he fell into the hands of Maltese pirates, rowed in chains in a galley for twenty years, then was made to work for a farmer. Yet he never lost his hope of returning to Edremit. Every night in his dream he sees the arrival of Turkish ships.',
      'What kept Kara Memiş going for forty years?',
      'The hope of returning to his homeland Edremit, and the dreams in which he saw Turkish ships arriving.',
    ),
    (
      'One day the Turkish fleet really enters the harbor. Kara Memiş strikes his forehead with a stone to make sure he is not dreaming, and runs toward the soldiers shouting I am a Turk, lads! The Bey on the ship asks him to bare his arm; when he sees the cross-shaped scar on his upper arm, he says that he is his son Turgut. In this way father and son reunite after forty years.',
      'With what did the Bey confirm the identity of Kara Memiş?',
      'With the cross-shaped scar on his upper arm; the Bey was his son Turgut.',
    ),
    (
      'The son wants to leave his old father on the ship, saying that he is too old. Kara Memiş says his heart is strong, that he has longed for battle for forty years, and asks for a shield and a sword. If he falls as a martyr, he asks for the red flag from the ship to be draped over him, because for him the homeland is where the flag waves. The story ends by gathering the longing for the homeland in one banner.',
      'If Kara Memiş fell as a martyr, what did he ask to be draped over him, and why?',
      'He asked for the red flag on the ship to be draped over him, because for him the homeland was where the flag waves.',
    ),
  ],
  'Primo Türk Çocuğu': [
    (
      'The story begins on the Thessaloniki quay on a September night when news of war arrives. Young engineer Kenan Bey is shaken when he learns that Italy has attacked Tripoli. Kenan Bey, who studied in Paris and admires Europe, sees for the first time the hypocrisy of the Europeans in this war. Because his wife Grazia is Italian, he also feels alienated in his own house.',
      'What event shook Kenan Bey that night?',
      'The attack of Italy on Tripoli.',
    ),
    (
      "Kenan Bey spends the night in a hotel room and remembers his marriage to Grazia. The children are called Primo and Sekundo, meaning first and second, as Italian custom has it; Sekundo falls ill and dies. Grazia's father did not want to give his daughter to a son-in-law he took for a Turk, and later accepted him as a Greek. These memories show how far Kenan Bey has moved away from his own identity.",
      "What are the children's names, and why are they noteworthy?",
      'Primo and Sekundo mean first and second, because they imitate European customs.',
    ),
    (
      'The next morning Kenan Bey returns home and sees two travel trunks in the house, and understands that Grazia is preparing for a journey. He notices that there is no trace of Turkish life among the belongings in the house, and remembers his childhood home in Bursa and the plaque in the room of his father. The verses on the plaque give advice such as "Do not cross the bridge of the scoundrel." For Kenan Bey these memories are the beginning of a reckoning with identity.',
      'What does Kenan Bey see in the house, and what does this tell him?',
      'He sees two travel trunks; he understands that Grazia is preparing for a journey.',
    ),
  ],
};
