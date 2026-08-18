import Foundation

/// Loads a golden fixture generated from the TypeScript core by
/// `tools/gen-fixtures.ts` (run `npm run gen:fixtures` at the repo root).
func loadFixture<T: Decodable>(_ name: String) -> T {
    let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    let data = try! Data(contentsOf: url)
    return try! JSONDecoder().decode(T.self, from: data)
}
