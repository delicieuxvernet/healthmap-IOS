import Foundation

// MARK: - Password Strength
enum PasswordStrength: Int, Comparable {
    case weak = 0
    case fair = 1
    case strong = 2
    case veryStrong = 3

    static func < (lhs: PasswordStrength, rhs: PasswordStrength) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .weak:      return "Faible"
        case .fair:      return "Moyen"
        case .strong:    return "Fort"
        case .veryStrong: return "Très fort"
        }
    }
}

// MARK: - Validation Issue
enum PasswordValidationIssue: Equatable {
    case tooShort
    case noUppercase
    case noDigit
    case noSpecialCharacter
    case commonPassword

    var message: String {
        switch self {
        case .tooShort:
            return "Le mot de passe doit contenir au moins 8 caracteres."
        case .noUppercase:
            return "Le mot de passe doit contenir au moins une lettre majuscule."
        case .noDigit:
            return "Le mot de passe doit contenir au moins un chiffre."
        case .noSpecialCharacter:
            return "Le mot de passe doit contenir au moins un caractère spécial (!@#$%…)."
        case .commonPassword:
            return "Ce mot de passe est trop courant. Choisissez-en un plus unique."
        }
    }
}

// MARK: - PasswordValidator
struct PasswordValidator {

    /// Validates a password against security criteria.
    /// Returns an empty array if the password meets all requirements.
    static func validate(_ password: String) -> [PasswordValidationIssue] {
        var issues: [PasswordValidationIssue] = []

        if password.count < 8 {
            issues.append(.tooShort)
        }

        if !password.contains(where: { $0.isUppercase }) {
            issues.append(.noUppercase)
        }

        if !password.contains(where: { $0.isNumber }) {
            issues.append(.noDigit)
        }

        let specialCharacters = CharacterSet.alphanumerics.inverted
        if password.unicodeScalars.allSatisfy({ !specialCharacters.contains($0) }) {
            issues.append(.noSpecialCharacter)
        }

        if commonPasswords.contains(password.lowercased()) {
            issues.append(.commonPassword)
        }

        return issues
    }

    /// Computes an overall strength score based on criteria met and length.
    static func strength(of password: String) -> PasswordStrength {
        let issues = validate(password)

        if issues.contains(.tooShort) || issues.contains(.commonPassword) {
            return .weak
        }

        let criteriaFailed = issues.count
        let lengthBonus = password.count >= 12

        switch criteriaFailed {
        case 0 where lengthBonus:
            return .veryStrong
        case 0:
            return .strong
        case 1:
            return .fair
        default:
            return .weak
        }
    }

    // MARK: - Top 100 Common Passwords

    private static let commonPasswords: Set<String> = [
        "123456", "password", "12345678", "qwerty", "123456789",
        "12345", "1234", "111111", "1234567", "dragon",
        "123123", "baseball", "abc123", "football", "monkey",
        "letmein", "696969", "shadow", "master", "666666",
        "qwertyuiop", "123321", "mustang", "1234567890", "michael",
        "654321", "pussy", "superman", "1qaz2wsx", "7777777",
        "fuckyou", "121212", "000000", "qazwsx", "123qwe",
        "killer", "trustno1", "jordan", "jennifer", "zxcvbnm",
        "asdfgh", "hunter", "buster", "soccer", "harley",
        "batman", "andrew", "tigger", "sunshine", "iloveyou",
        "fuckme", "2000", "charlie", "robert", "thomas",
        "hockey", "ranger", "daniel", "starwars", "klaster",
        "112233", "george", "asshole", "computer", "michelle",
        "jessica", "pepper", "1111", "zxcvbn", "555555",
        "11111111", "131313", "freedom", "777777", "pass",
        "fuck", "maggie", "159753", "aaaaaa", "ginger",
        "princess", "joshua", "cheese", "amanda", "summer",
        "love", "ashley", "6969", "nicole", "chelsea",
        "biteme", "matthew", "access", "yankees", "987654321",
        "dallas", "austin", "thunder", "taylor", "matrix",
        "azerty", "motdepasse", "soleil", "password1", "admin",
    ]
}
