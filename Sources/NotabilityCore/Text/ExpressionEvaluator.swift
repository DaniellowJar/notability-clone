import Foundation

/// Small, dependency-free arithmetic evaluator for the inline calculator
/// (Phase 7). Local evaluation runs before any AI call: handles
/// `300 x 2`-style arithmetic (× ÷ − · unicode), precedence, parentheses,
/// unary minus, and named variables from `MathAIBlockPayload.variables`.
public enum ExpressionEvaluator {
    public enum EvaluationError: Error, Equatable {
        case empty
        case unexpectedToken(String)
        case missingOperator(String)
        case divisionByZero
        case missingVariable(String)
    }

    public static func evaluate(_ expression: String, variables: [String: Double] = [:]) throws -> Double {
        let tokens = try tokenize(expression)
        guard !tokens.isEmpty else { throw EvaluationError.empty }
        var parser = Parser(tokens: tokens, variables: variables)
        let value = try parser.parseExpression()
        guard parser.isAtEnd else { throw EvaluationError.unexpectedToken(parser.current.description) }
        return value
    }

    // MARK: - Tokenizer

    private enum Token: Equatable, CustomStringConvertible {
        case number(Double)
        case op(Character)     // + - * /
        case paren(Character)  // ( )
        case identifier(String)

        var description: String {
            switch self {
            case .number(let n): return String(n)
            case .op(let c): return String(c)
            case .paren(let c): return String(c)
            case .identifier(let s): return s
            }
        }
    }

    private static func tokenize(_ raw: String) throws -> [Token] {
        // Normalize unicode math glyphs to ASCII operators.
        let expression = raw
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "·", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "–", with: "-")
        let chars = Array(expression)
        var tokens: [Token] = []
        var i = 0

        func lastToken() -> Token? { tokens.last }

        func isOperandEnd(_ token: Token?) -> Bool {
            switch token {
            case .number, .identifier, .paren(")"): true
            default: false
            }
        }

        while i < chars.count {
            let c = chars[i]
            if c == " " || c == "\t" {
                i += 1
                continue
            }
            if c.isNumber || c == "." {
                var num = ""
                while i < chars.count && (chars[i].isNumber || chars[i] == ".") {
                    num.append(chars[i])
                    i += 1
                }
                guard let value = Double(num) else { throw EvaluationError.unexpectedToken(num) }
                tokens.append(.number(value))
                continue
            }
            if c == "(" || c == ")" {
                tokens.append(.paren(c))
                i += 1
                continue
            }
            if c == "+" || c == "-" || c == "*" || c == "/" {
                tokens.append(.op(c))
                i += 1
                continue
            }
            if c.isLetter {
                var word = ""
                while i < chars.count && chars[i].isLetter {
                    word.append(chars[i])
                    i += 1
                }
                let lower = word.lowercased()
                // Standalone "x" between operands means multiplication (300 x 2);
                // otherwise it's a variable name from the payload.
                let isMultiplyX = lower == "x" && isOperandEnd(lastToken()) && startsWithOperand(chars, from: i)
                if isMultiplyX {
                    tokens.append(.op("*"))
                } else {
                    tokens.append(.identifier(lower))
                }
                continue
            }
            throw EvaluationError.unexpectedToken(String(c))
        }
        return tokens
    }

    private static func startsWithOperand(_ chars: [Character], from start: Int) -> Bool {
        var j = start
        while j < chars.count && chars[j] == " " { j += 1 }
        guard j < chars.count else { return false }
        return chars[j].isNumber || chars[j] == "(" || chars[j].isLetter
    }

    // MARK: - Parser

    private struct Parser {
        let tokens: [Token]
        let variables: [String: Double]
        var index = 0

        var current: Token { tokens[index] }
        var isAtEnd: Bool { index >= tokens.count }

        mutating func parseExpression() throws -> Double {
            var value = try parseTerm()
            while !isAtEnd {
                switch current {
                case .op("+"):
                    index += 1
                    value += try parseTerm()
                case .op("-"):
                    index += 1
                    value -= try parseTerm()
                default:
                    return value
                }
            }
            return value
        }

        mutating func parseTerm() throws -> Double {
            var value = try parseFactor()
            while !isAtEnd {
                switch current {
                case .op("*"):
                    index += 1
                    value *= try parseFactor()
                case .op("/"):
                    index += 1
                    let divisor = try parseFactor()
                    guard divisor != 0 else { throw EvaluationError.divisionByZero }
                    value /= divisor
                default:
                    return value
                }
            }
            return value
        }

        mutating func parseFactor() throws -> Double {
            guard !isAtEnd else { throw EvaluationError.unexpectedToken("end of input") }
            if case .op("-") = current {
                index += 1
                let value = try parseFactor()
                return -value
            }
            if case .op("+") = current {
                index += 1
                return try parseFactor()
            }
            switch current {
            case .number(let n):
                index += 1
                return n
            case .paren("("):
                index += 1
                let value = try parseExpression()
                guard case .paren(")") = current else { throw EvaluationError.unexpectedToken(current.description) }
                index += 1
                return value
            case .identifier(let name):
                index += 1
                guard let value = variables[name] else { throw EvaluationError.missingVariable(name) }
                return value
            default:
                throw EvaluationError.unexpectedToken(current.description)
            }
        }
    }
}
