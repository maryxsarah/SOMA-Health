import Foundation

/// Fixed, static legal copy -- required for App Store review since the app
/// requests HealthKit and account data. Placeholder content: review with
/// counsel and fill in the bracketed values before shipping.
enum LegalContent {
    static let privacyPolicyTitle = "Privacy Policy"

    static let privacyPolicyBody = """
    Last updated: 21st of July 2026

    Soma ("the app", "we", "our") helps you decide how hard to train each \
    day by reading data from Apple Health, Whoop, and/or Oura. This policy \
    explains what data we collect, how it's used, and your choices.

    Information We Collect
    - Health & activity data, read-only, only with your permission: sleep, \
    heart rate variability, resting heart rate, heart rate, step count, \
    active energy, and exercise time from Apple Health; recovery scores \
    from Whoop; readiness scores from Oura.
    - Account identifier from Sign in with Apple (a unique ID; we do not \
    require or request your email address).
    - Your notification wake-time preference.

    How We Use Your Information
    Your health and activity data is used solely to compute a single daily \
    training recommendation ("Rest", "Light Movement", "Moderate", or \
    "Push Hard"). We do not use your health data for advertising, do not \
    sell it, and do not share it with third parties except the service \
    providers listed below, solely to operate the app.

    Where Your Data Is Stored
    Recommendation data and connection tokens are stored with our backend \
    provider, Supabase, using industry-standard encryption in transit \
    (HTTPS) and access controls that restrict every record to your own \
    account. Whoop and Oura access tokens are never exposed to the app \
    itself.

    Third-Party Services
    The app integrates with Apple HealthKit, Whoop, Oura, and Supabase. \
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
    [team@soma4health.com]
    """

    static let termsOfServiceTitle = "Terms of Service"

    static let termsOfServiceBody = """
    Last updated: July, 21st 2026

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
    concerning symptoms.

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
