import raw from '../assets/common-words.txt?raw';

/** ~5,000 common English words (3–8 letters), all present in the validation
 * dictionary. Used only for puzzle generation. */
export const COMMON_WORDS: string[] = raw
  .split('\n')
  .map((w) => w.trim())
  .filter(Boolean);
