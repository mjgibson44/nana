/// Seeded random numbers, ported from `src/game/rng.ts`.
///
/// Battle deals every player the same tiles by having each client run the
/// generator itself from a seed the host shares once. That only works if the
/// same seed always produces the same numbers, on every platform — so this
/// port must be **bit-exact** with the JS implementation (xmur3 + mulberry32).
/// Every operation below mirrors the JS 32-bit coercion semantics: `Math.imul`
/// is a truncating 32-bit multiply (`&*` on UInt32), `| 0` is a wrapping add
/// (`&+`), `>>>` is a logical shift (native on UInt32), and the seed is hashed
/// over **UTF-16 code units** because that is what `charCodeAt` yields.
///
/// Golden-vector fixtures generated from the TS implementation pin this in CI.

/// xmur3: hash a string down to a well-mixed 32-bit state.
@usableFromInline
internal func hashString(_ str: String) -> UInt32 {
    let units = Array(str.utf16)
    var h: UInt32 = 1_779_033_703 ^ UInt32(units.count)
    for unit in units {
        h = (h ^ UInt32(unit)) &* 3_432_918_353
        h = (h << 13) | (h >> 19)
    }
    h = (h ^ (h >> 16)) &* 2_246_822_507
    h = (h ^ (h >> 13)) &* 3_266_489_909
    h ^= h >> 16
    return h
}

/// mulberry32: a small, fast PRNG over a 32-bit state. Returns numbers in
/// [0, 1) exactly like `Math.random`, so it slots into the generator's
/// injectable `rng` parameter unchanged.
public func seededRng(_ seed: String) -> () -> Double {
    var state = hashString(seed)
    return {
        state = state &+ 0x6D2B_79F5
        var t = (state ^ (state >> 15)) &* (1 | state)
        // JS: `t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t` — the float
        // addition of two int32s followed by `^` re-truncating to int32 is
        // exactly a wrapping 32-bit add, then xor.
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        // `((t ^ (t >>> 14)) >>> 0) / 4294967296` — exact in IEEE 754.
        return Double(t ^ (t >> 14)) * 0x1p-32
    }
}

/// A fresh seed for one battle game. Only the host mints one, so it can lean
/// on real randomness — determinism is only needed downstream of the seed.
public func randomSeed() -> String {
    let digits = "0123456789abcdefghijklmnopqrstuvwxyz"
    var seed = ""
    for _ in 0..<12 {
        seed.append(digits.randomElement()!)
    }
    return seed
}
