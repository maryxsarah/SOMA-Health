import Foundation

/// Fixed, static legal copy -- required for App Store review since the app
/// requests HealthKit and account data. NOT reviewed by counsel: this copy
/// describes what the code actually does, which is the necessary starting
/// point, but it is not a substitute for legal review before wider release.
///
/// IMPORTANT: this text is duplicated at docs/privacy.html, which is served
/// publicly via GitHub Pages and linked from the App Store listing. The two
/// must be changed together -- they have silently drifted from what the app
/// does once already. Anything added here that touches data collection or
/// third-party processors belongs in both files, plus a bumped date.
enum LegalContent {
    /// Bumped whenever a material change is made to either document below.
    /// Compared against `users.legal_ack_version` to decide whether a
    /// returning user needs to re-acknowledge -- see SupabaseClient's
    /// sign-in methods, which write both this and a timestamp on every
    /// successful gated sign-in.
    static let currentVersion = "2026-07-30"

    static let privacyPolicyTitle = "Privacy Policy"

    static let privacyPolicyBody = """
    Last updated: 30th of July 2026

    Soma ("the app", "we", "our") helps you decide how hard to train each \
    day by reading data from Apple Health, Whoop, and/or Oura. This policy \
    explains what data we collect, how it's used, and your choices.

    Information We Collect
    - Health & activity data, read-only, only with your permission: sleep, \
    heart rate variability, resting heart rate, heart rate, step count, \
    active energy, and exercise time from Apple Health; recovery, strain, \
    and sleep data from Whoop; readiness, sleep, and stress data from Oura. \
    Workouts recorded by Apple Health or a connected wearable are also \
    stored so your history persists across devices.
    - Information you give us during onboarding and in your profile: sex, \
    date of birth, current and target weight, training goals and pace, how \
    often you train, whether you work with a trainer, how you heard about \
    us, what gets in your way, diet preference, available equipment, \
    training experience, and any injuries you choose to note (including \
    free-text notes).
    - Pregnancy, only if you choose to tell us. This is never assumed or \
    inferred, is entirely optional, and is used for one purpose: to \
    withhold an automatically generated workout and suggest you speak to a \
    qualified professional instead. You can clear it at any time in your \
    profile.
    - Photographs you take of gym or workout equipment, if you use the \
    gym-photo feature. These are sent for equipment recognition and are \
    NOT stored by us -- we keep only the resulting list of equipment after \
    you confirm it.
    - Workouts you mark as complete, and any feedback you write about them.
    - Account information depending on how you sign in: with Apple, a \
    unique ID (and your email only if Apple shares it and you allow it); \
    with Google, a unique ID and the email associated with your Google \
    account; with email and password, the email address and password you \
    choose. Passwords are never visible to us in plain text -- they are \
    handled entirely by our authentication provider, Supabase.
    - Your notification wake-time preference and marketing preference.

    How We Use Your Information
    Your health and activity data is used to compute your daily training \
    recommendation ("Rest", "Light Movement", "Moderate", or "Push Hard") \
    and to generate the personalized workout plans you request in the app. \
    Generating a plan means sending relevant context -- your goals, \
    available equipment, noted injuries, training experience, that day's \
    health metrics, and your recent workout history -- to the AI providers \
    listed below, which return the plan text. Your data is not used to \
    train their models. We do not use your health data for advertising, do \
    not sell it, and do not share it with anyone except the service \
    providers listed below, solely to operate the app.

    Where Your Data Is Stored
    Recommendation data and connection tokens are stored with our backend \
    provider, Supabase, using industry-standard encryption in transit \
    (HTTPS) and access controls that restrict every record to your own \
    account. Whoop and Oura access tokens are never exposed to the app \
    itself.

    Third-Party Services
    The app relies on the following providers, each of which processes some \
    of your data on our behalf:
    - Apple (Sign in with Apple, HealthKit)
    - Google (Sign in with Google, if you choose it)
    - Whoop and Oura, if you connect them
    - Supabase -- backend, database, and hosting
    - Anthropic -- generates workout plans and workout suggestions from the \
    context described above
    - OpenAI -- recognizes equipment in gym photos and writes exercise \
    instructions
    Each provider's use of data they process is governed by their own \
    privacy policy in addition to this one.

    Data Retention & Deletion
    You can disconnect a wearable at any time from within the app. To \
    request deletion of your account and associated data, contact us at \
    the address below.

    Children's Privacy
    Soma is not directed at children under 13, and we do not knowingly \
    collect data from children under 13.

    Your Rights
    Depending on where you live, you may have rights to access, correct, \
    or delete your personal data. Contact us to exercise these rights.

    Changes to This Policy
    We may update this policy from time to time. Material changes will be \
    reflected by updating the "Last updated" date above.

    Contact Us
    team@soma4health.com
    """

    static let termsOfServiceTitle = "Terms of Service"

    static let termsOfServiceBody = """
    Last updated: 30th of July 2026

    By using Soma ("the app"), you agree to these Terms of Service.

    Description of Service
    Soma reads data from connected health and wearable sources and sends \
    one daily notification recommending a training intensity, chosen by a \
    fixed set of rules based on your recovery data. It does not generate \
    personalized medical or freeform advice.

    Not Medical Advice
    Soma provides general fitness suggestions and is not a substitute for \
    professional medical advice, diagnosis, or treatment. Always consult a \
    qualified physician before beginning or changing an exercise program, \
    particularly if you have any medical condition. Stop exercising and \
    seek medical attention if you experience pain, dizziness, or other \
    concerning symptoms. Any injury you note in your profile, and any \
    related severity, contraindication guidance, or recovery-protocol \
    check-in, is informational only and generated from fixed rules, not a \
    substitute for evaluation or clearance by a medical professional. \
    Continuing to train while injured is entirely at your own risk.

    Eligibility
    You must be at least 13 years old (or the age of digital consent in \
    your country) to use Soma.

    Your Responsibilities
    You are responsible for the accuracy of any device pairing and for \
    keeping your Whoop/Oura/Apple accounts secure. Recommendations are \
    only as good as the underlying data reported by connected devices.

    Third-Party Integrations
    Your use of Apple Health, Whoop, and Oura through the app is also \
    subject to those providers' own terms of service.

    Disclaimers & Limitation of Liability
    Soma is provided "as is" without warranties of any kind. To the \
    maximum extent permitted by law, we are not liable for any damages \
    arising from your use of the app, including any injury resulting from \
    following a training recommendation.

    Termination
    You may stop using the app at any time. We may suspend or terminate \
    access for violations of these terms.

    Changes to These Terms
    We may update these terms from time to time; continued use of the app \
    after changes constitutes acceptance.

    Governing Law
    These Terms of Service and any dispute or claim arising out of or in \
    connection with them or their subject matter or formation (including \
    non-contractual disputes or claims) shall be governed by and construed \
    in accordance with the laws of the Emirate of Dubai and the federal \
    laws of the United Arab Emirates.

    Jurisdiction. Any dispute, difference, controversy or claim arising \
    out of or in connection with this contract, including any question \
    regarding its existence, validity, interpretation, performance, breach \
    or termination, shall be subject to the exclusive jurisdiction of the \
    Courts of the Dubai International Financial Centre ("the DIFC Courts").

    Small Claims Tribunal. The parties further agree that any dispute, \
    difference, controversy or claim where the total value in controversy \
    does not exceed AED 500,000 (five hundred thousand United Arab \
    Emirates Dirhams) shall be submitted to, and exclusively and finally \
    resolved by, the Small Claims Tribunal (SCT) of the DIFC Courts.

    Contact Us
    team@soma4health.com
    """
}
