import Foundation

/// Outcome of evaluating a user input against the safety gate.
enum SafetyGateDecision: Sendable, Equatable {
    /// Safe — let the request proceed to the LLM.
    case allow

    /// Unsafe — abort generation and return this hardcoded response.
    ///
    /// `response` is a ready-to-display string with concrete emergency
    /// resources. `reason` identifies which rule fired, for logging /
    /// test rubrics.
    case refuse(reason: SafetyReason, response: String)
}

/// Why the safety gate refused. Each value maps 1:1 to a curated
/// response string; we test each rule independently.
enum SafetyReason: String, Sendable, Equatable, CaseIterable {
    /// Self-harm / suicide language.
    case selfHarm
    /// Immediate medical crisis language (heart attack, stroke, severe
    /// bleeding, unconsciousness, overdose).
    case medicalEmergency
    /// Specific prescription / dosing requests (how much of what to take).
    case dosingRequest
    /// Explicit diagnosis requests ("do I have X").
    case diagnosisRequest
    /// Legal advice requests where an LLM answer could cause harm.
    case specificLegalAdvice
    /// Child-safety or abuse reports — out of scope for an on-device
    /// assistant; must route to the appropriate authority.
    case childSafety
}

/// Pre-LLM safety refusal.
///
/// **The safety gate never calls the LLM.** Detection is regex + keyword
/// matching only. Responses are hardcoded strings curated to include
/// legitimate emergency resources.
///
/// This gate is the FIRST thing every user-initiated generation passes
/// through. If it refuses, the generation is aborted before a single
/// token leaves Gemma. The LLM cannot override a refusal.
///
/// ## Concurrency
/// Every member is `static` and fully `nonisolated`. The gate is
/// deliberately callable from any thread or actor — it must work from
/// the main actor (chat UI), from background actors (benchmark runner),
/// and from the RAG pipeline. The type holds no state; there is no
/// isolation requirement.
///
/// Any expansion of the rule set requires a corresponding unit test
/// in `SafetyGateTests`.
enum SafetyGate {

    /// Evaluate user input.
    ///
    /// - Parameter input: the raw user text (pre-RAG, pre-skill, pre-LLM).
    /// - Returns: an allow/refuse decision.
    static func evaluate(_ input: String) -> SafetyGateDecision {
        // In RELEASE the gate is always on. In DEBUG a test can opt out
        // by setting the UserDefaults key directly. We bypass the
        // `EidosFeatureFlags.shared` (`@MainActor`) accessor deliberately —
        // this method must be callable from any isolation domain.
        #if DEBUG
        if let raw = UserDefaults.standard.object(forKey: "eidos.flag.safetyGate"),
           let enabled = raw as? Bool,
           !enabled {
            return .allow
        }
        #endif

        let normalized = Self.normalize(input)

        // Order matters: most severe (crisis) first so ambiguous matches
        // route to the right hardcoded response.
        if Self.matchesSelfHarm(normalized) {
            return .refuse(reason: .selfHarm, response: Self.selfHarmResponse)
        }
        if Self.matchesMedicalEmergency(normalized) {
            return .refuse(reason: .medicalEmergency, response: Self.medicalEmergencyResponse)
        }
        if Self.matchesDosing(normalized) {
            return .refuse(reason: .dosingRequest, response: Self.dosingResponse)
        }
        if Self.matchesDiagnosis(normalized) {
            return .refuse(reason: .diagnosisRequest, response: Self.diagnosisResponse)
        }
        if Self.matchesChildSafety(normalized) {
            return .refuse(reason: .childSafety, response: Self.childSafetyResponse)
        }
        if Self.matchesLegalAdvice(normalized) {
            return .refuse(reason: .specificLegalAdvice, response: Self.legalResponse)
        }

        return .allow
    }

    // MARK: - Normalization

    /// Lowercases, strips diacritics, and trims whitespace. Leaves
    /// punctuation so regex anchors still work.
    ///
    /// Diacritic stripping closes a Unicode-bypass class: a user
    /// typing "suïcide" or "suicidé" (accented characters from autocorrect
    /// in some locales, or copy-pasted from a Romance-language source)
    /// would not have matched the bare `\bsuicid(e|al)\b` pattern. We
    /// strip combining diacritics so the regex sees the unaccented
    /// Latin form. Non-Latin scripts (Arabic, CJK) pass through
    /// unchanged — our crisis patterns are English-language only by
    /// design, and the gate falls back to the LLM for everything else
    /// after passing through.
    static func normalize(_ s: String) -> String {
        let stripped = s.applyingTransform(.stripDiacritics, reverse: false) ?? s
        return stripped.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Rule predicates

    static func matchesSelfHarm(_ s: String) -> Bool {
        // Curated from SAMHSA / WHO crisis-intervention references.
        // False-positive bias is deliberate: we'd rather refuse a
        // benign query than miss one life.
        let patterns: [String] = [
            #"\b(i|im|i'm|ive|i've)\s+(going to|gonna|about to|thinking of|thinking about)\s+(kill|hurt|harm|end)\s+myself\b"#,
            #"\b(want|wanna|wish)\s+to\s+(die|end it|end my life)\b"#,
            #"\bi\s+wish\s+i\s+(was|were)\s+dead(?:[.!?,]|$)"#,
            #"\bkill\s+myself\b"#,
            #"\bsuicid(e|al)\b"#,
            #"\bwhat.*easiest.*(way|method).*(die|kill|end)\b"#,
            #"\bhow\s+(do|can|would)\s+i\s+(die|kill myself|end my life)\b"#,
            #"\btake\s+my\s+(own\s+)?life\b"#,
            #"\bi\s+don'?t\s+want\s+to\s+(be alive|live|wake up)\b"#,
            #"\bself[-\s]?harm\b"#,
            #"\bcutting myself\b"#,
        ]
        return patterns.contains { regexMatch(s, pattern: $0) }
    }

    static func matchesMedicalEmergency(_ s: String) -> Bool {
        let patterns: [String] = [
            #"\b(having|i think i'?m having).*heart attack\b"#,
            #"\b(chest|my chest).*(pain|hurts|tight|crushing).*(arm|jaw|breath)\b"#,
            #"\b(stroke|having a stroke)\b"#,
            #"\b(can'?t|cannot)\s+breathe\b"#,
            #"\b(severe|heavy|uncontrol\w*)\s+bleed\w*\b"#,
            #"\boverdos\w*\b"#,
            #"\b(unconscious|passed out|not responsive|won'?t wake up)\b"#,
            #"\b(anaphyla\w*|anaphylactic shock)\b"#,
            #"\b(poisoned|swallowed poison)\b"#,
        ]
        return patterns.contains { regexMatch(s, pattern: $0) }
    }

    static func matchesDosing(_ s: String) -> Bool {
        // Catch "how many mg of X should I take"-style queries.
        let patterns: [String] = [
            #"\bhow\s+(many|much)\s+(mg|milligrams?|mcg|micrograms?|g|grams?|ml|millili\w+|pills?|tablets?|doses?|units?).*should\s+i\s+take\b"#,
            #"\bshould\s+i\s+take\s+\d+\s*(mg|milligrams?|mcg|g|grams?|ml|millili\w+|pills?|tablets?|doses?|units?)\b"#,
            #"\bmaximum\s+(safe\s+)?dose\s+of\b"#,
            #"\bhow\s+much\s+.* (before|until)\s+i (od|overdose|die)\b"#,
            #"\bprescrib\w+\s+me\b"#,
            #"\bwhat\s+dose\s+of\s+\w+\s+should\s+i\b"#,
        ]
        return patterns.contains { regexMatch(s, pattern: $0) }
    }

    static func matchesDiagnosis(_ s: String) -> Bool {
        // "Do I have X" — where X is a medical condition. Very narrow
        // match to avoid false-positives on casual phrasing.
        let patterns: [String] = [
            #"\bdo\s+i\s+have\s+(cancer|diabetes|depression|anxiety|adhd|autism|schizophreni\w*|bipolar|parkinson\w*|alzheimer\w*|copd|heart disease|hiv|aids|hepatit\w*|lupus|ms|multiple sclerosis)\b"#,
            #"\bam\s+i\s+(diabetic|depressed|autistic|bipolar|schizophrenic)\b"#,
            #"\bis\s+this\s+(cancer|a tumou?r|melanoma)\b"#,
            #"\bdiagnose\s+me\b"#,
        ]
        return patterns.contains { regexMatch(s, pattern: $0) }
    }

    static func matchesLegalAdvice(_ s: String) -> Bool {
        let patterns: [String] = [
            #"\bhow\s+do\s+i\s+(evict|divorce|sue|file a lawsuit)\b"#,
            #"\bis\s+it\s+legal\s+to\s+.+(in\s+[a-z]+|\?)"#,  // very narrow — "is it legal to X in <jurisdiction>"
            #"\bdraft\s+me\s+a\s+(contract|lease|will|nda)\b"#,
            #"\bwhat\s+are\s+my\s+(legal\s+)?rights\s+.*(arrest|police|detain)\w*\b"#,
        ]
        return patterns.contains { regexMatch(s, pattern: $0) }
    }

    static func matchesChildSafety(_ s: String) -> Bool {
        // Route immediately to authorities — on-device LLM must not be a
        // reporting channel for child abuse.
        let patterns: [String] = [
            #"\bchild\s+(abuse|molest\w*|exploit\w*)\b"#,
            #"\breport\s+.*(child\s+)?abuse\b"#,
            #"\b(csam|grooming|pedophil\w*)\b"#,
        ]
        return patterns.contains { regexMatch(s, pattern: $0) }
    }

    private static func regexMatch(_ s: String, pattern: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(s.startIndex..., in: s)
        return re.firstMatch(in: s, options: [], range: range) != nil
    }

    // MARK: - Hardcoded responses

    /// Emergency / self-harm response. Includes real, current resources.
    static let selfHarmResponse: String = """
    I hear you, and I'm glad you reached out. This isn't something I can help with as an on-device assistant, but real help is available right now — people who are trained for exactly this.

    If you're in the US, you can:
      • Call or text **988** (Suicide & Crisis Lifeline) — free, 24/7
      • Text **HOME** to **741741** (Crisis Text Line)

    Outside the US, a global directory is at **https://findahelpline.com**.

    If you're in immediate physical danger, please call your local emergency number now. You matter, and this moment is survivable.
    """

    static let medicalEmergencyResponse: String = """
    This sounds like a medical emergency. I'm not a doctor and I can't safely help with this.

    **Please call your local emergency number right now:**
      • US / Canada: **911**
      • UK / Ireland: **999**
      • EU: **112**
      • India: **112**
      • Australia / NZ: **000**

    If you can't speak, most regions also accept a text to the same number. I'll stay out of the way so you can get help faster.
    """

    static let dosingResponse: String = """
    I can't suggest specific dosages or timings for any medication — even over-the-counter ones. Getting this wrong can cause real harm.

    Please check:
      • The label or patient leaflet on the medication itself
      • Your pharmacist (no appointment needed in most countries — they're trained for exactly this)
      • **Poison control** if you think a dose has already been taken wrongly:
        US: **1-800-222-1222** · UK: **111** · India: **1066**

    I'm happy to help with other things — reminders for when to take a medication you've already been prescribed, tracking how you feel, questions about general concepts.
    """

    static let diagnosisResponse: String = """
    I can't diagnose a medical condition. Even if I could describe symptoms, a real diagnosis needs a professional who can examine you, take a proper history, and order tests.

    What I *can* help with:
      • Organising your symptoms into notes to bring to a doctor's appointment
      • Tracking when symptoms appear and what makes them better or worse
      • Reminding you about a follow-up

    If what you're feeling is serious or fast-changing, please see a doctor — or in an emergency, call your local emergency number.
    """

    static let legalResponse: String = """
    Legal questions need a real lawyer in your jurisdiction. An on-device AI giving specific legal advice could cost you the case.

    What I *can* help with:
      • Summarising a document you've been asked to sign (with the caveat that I'm not a lawyer)
      • Organising notes and dates for an upcoming meeting with counsel
      • Finding your local bar association's referral directory

    If you need urgent legal help (arrest, eviction notice, emergency order), many jurisdictions have free legal-aid hotlines. A quick web search for "legal aid + your city" will point you to them.
    """

    static let childSafetyResponse: String = """
    This needs real human help, not an AI. Please reach out to people trained to protect children:

      • **US**: Childhelp National Child Abuse Hotline — **1-800-4-A-CHILD (1-800-422-4453)**
      • **UK**: NSPCC — **0808 800 5000**
      • **EU / international**: Child Helpline International — **https://childhelplineinternational.org**

    If a child is in immediate danger, please call your local emergency number now.
    """
}
