import Foundation

/// An unevaluated sum `hi + lo` of two doubles, with about 32 significant digits.
/// View centers use it so deep zooms can address points more finely than one double allows.
public struct DoubleDouble: Equatable {
    public private(set) var hi: Double
    public private(set) var lo: Double

    private init(exact hi: Double, _ lo: Double) { self.hi = hi; self.lo = lo }
    public init(_ value: Double) { self.init(exact: value, 0) }
    /// Normalizes any pair so that `hi` is the correctly rounded value.
    public init(hi: Double, lo: Double) { self = Self.twoSum(hi, lo) }

    public var isFinite: Bool { hi.isFinite && lo.isFinite }

    private static func twoSum(_ a: Double, _ b: Double) -> Self {
        let s = a + b, v = s - a
        return Self(exact: s, (a - (s - v)) + (b - v))
    }
    private static func twoProduct(_ a: Double, _ b: Double) -> Self {
        let p = a * b
        return Self(exact: p, (-p).addingProduct(a, b))
    }

    public static func + (a: Self, b: Self) -> Self {
        var s = twoSum(a.hi, b.hi)
        let t = twoSum(a.lo, b.lo)
        s = twoSum(s.hi, s.lo + t.hi)
        return twoSum(s.hi, s.lo + t.lo)
    }
    public static prefix func - (a: Self) -> Self { Self(exact: -a.hi, -a.lo) }
    public static func - (a: Self, b: Self) -> Self { a + -b }
    public static func * (a: Self, b: Self) -> Self {
        let p = twoProduct(a.hi, b.hi)
        return twoSum(p.hi, p.lo + (a.hi * b.lo + a.lo * b.hi))
    }
    public static func / (a: Self, b: Self) -> Self {
        let q1 = a.hi / b.hi
        var r = a - b * Self(q1)
        let q2 = r.hi / b.hi
        r = r - b * Self(q2)
        return twoSum(q1, q2) + Self(r.hi / b.hi)
    }

    private static func powerOfTen(_ exponent: Int) -> Self {
        var result = Self(1), base = Self(10), n = exponent
        while n > 0 {
            if n & 1 == 1 { result = result * base }
            n >>= 1
            if n > 0 { base = base * base }
        }
        return result
    }

    /// Parses decimal or scientific notation, such as `-0.74364388703715870475219150611477` or `1e-20`.
    public init?(_ text: String) {
        var rest = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        var negative = false
        if let sign = rest.first, sign == "+" || sign == "-" { negative = sign == "-"; rest = rest.dropFirst() }
        var mantissa = Self(0), exponent = 0, significant = 0, sawDigit = false, sawPoint = false
        while let character = rest.first {
            if character.isASCII, let digit = character.wholeNumberValue {
                sawDigit = true
                if significant < 36 {
                    if significant > 0 || digit != 0 { significant += 1 }
                    mantissa = mantissa * Self(10) + Self(Double(digit))
                    if sawPoint { exponent -= 1 }
                } else if !sawPoint { exponent += 1 }
            } else if character == ".", !sawPoint {
                sawPoint = true
            } else { break }
            rest = rest.dropFirst()
        }
        guard sawDigit else { return nil }
        if let marker = rest.first, marker == "e" || marker == "E" {
            guard let value = Int(rest.dropFirst()) else { return nil }
            exponent += value; rest = ""
        }
        guard rest.isEmpty, abs(exponent) <= 400 else { return nil }
        var value = exponent < 0 ? mantissa / Self.powerOfTen(-exponent) : mantissa * Self.powerOfTen(exponent)
        if !value.isFinite {
            guard exponent < 0 else { return nil }
            value = Self(0)
        }
        self = negative ? -value : value
    }

    /// The shortest decimal string (up to 34 significant digits) that parses back to within `tolerance`.
    public func formatted(tolerance: Double = 0) -> String {
        guard isFinite else { return String(hi) }
        guard hi != 0 else { return "0" }
        let negative = hi < 0
        var x = negative ? -self : self
        var exponent = Int(log10(x.hi).rounded(.down))
        x = exponent >= 0 ? x / Self.powerOfTen(exponent) : x * Self.powerOfTen(-exponent)
        if x.hi >= 10 { x = x / Self(10); exponent += 1 }
        if x.hi < 1 { x = x * Self(10); exponent -= 1 }
        var digits: [Int] = []
        for _ in 0..<35 {
            var digit = min(9, max(0, Int(x.hi.rounded(.down))))
            var remainder = x - Self(Double(digit))
            if remainder.hi < 0, digit > 0 { digit -= 1; remainder = remainder + Self(1) }
            digits.append(digit)
            x = remainder * Self(10)
        }
        for count in 1...34 {
            let candidate = Self.decimal(digits, count: count, exponent: exponent, negative: negative)
            if count == 34 { return candidate }
            if let parsed = Self(candidate), abs((parsed - self).hi) <= tolerance { return candidate }
        }
        return String(hi)
    }

    /// Rounds `digits` (d0.d1d2… × 10^exponent) to `count` significant digits and writes it out.
    private static func decimal(_ digits: [Int], count: Int, exponent: Int, negative: Bool) -> String {
        var kept = Array(digits.prefix(count)), exponent = exponent
        if digits[count] >= 5 {
            var index = count - 1
            while index >= 0 {
                if kept[index] < 9 { kept[index] += 1; break }
                kept[index] = 0; index -= 1
            }
            if index < 0 { kept.insert(1, at: 0); kept.removeLast(); exponent += 1 }
        }
        while kept.count > 1, kept.last == 0 { kept.removeLast() }
        let text = kept.map(String.init).joined()
        var result: String
        if exponent < -4 || exponent >= 16 {
            result = String(text.prefix(1)) + (text.count > 1 ? "." + text.dropFirst() : "") + "e\(exponent)"
        } else if exponent < 0 {
            result = "0." + String(repeating: "0", count: -exponent - 1) + text
        } else if text.count > exponent + 1 {
            result = text.prefix(exponent + 1) + "." + text.dropFirst(exponent + 1)
        } else {
            result = text + String(repeating: "0", count: exponent + 1 - text.count)
        }
        return negative ? "-" + result : result
    }
}
