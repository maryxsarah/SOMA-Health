import Foundation

/// Client-side mirror of supabase/functions/_shared/age.ts's ageFromDOB --
/// used ONLY for the Goal Body adult-only gate (hiding the photo-upload UI
/// before a network round-trip). The server re-checks independently in
/// analyze-body-photo and is the actual enforcement point; this is UX only.
enum AgeGate {
    static let adultAge = 18

    /// `dob` is "yyyy-MM-dd" (UserProfile.dateOfBirth's wire format). Fails
    /// closed: an unparseable or missing date is NOT treated as adult.
    static func isAdult(dobString: String?) -> Bool {
        guard let dobString else { return false }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        guard let birth = formatter.date(from: dobString) else { return false }

        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: birth, to: Date())
        guard let age = ageComponents.year else { return false }
        return age >= adultAge
    }
}
