export function parseDictionary(text: string): Set<string> {
  const words = new Set<string>();
  for (const line of text.split('\n')) {
    const word = line.trim().toLowerCase();
    if (word) words.add(word);
  }
  return words;
}

export async function loadDictionary(url: string): Promise<Set<string>> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`failed to load dictionary: ${response.status}`);
  }
  return parseDictionary(await response.text());
}
