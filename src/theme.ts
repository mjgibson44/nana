/**
 * The colour scheme preference: follow the device, or pin light or dark.
 *
 * Applied as a `data-theme` attribute on <html>. The stylesheet defaults to
 * light, flips with the device under `prefers-color-scheme: dark` unless a
 * theme is pinned, and obeys `data-theme="light" | "dark"` outright.
 */

export type ThemePref = 'light' | 'dark' | 'system';

const STORAGE_KEY = 'nana.theme.v1';

export function loadThemePref(): ThemePref {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (raw === 'light' || raw === 'dark' || raw === 'system') return raw;
  } catch {
    // Storage blocked — follow the device.
  }
  return 'system';
}

export function applyTheme(pref: ThemePref): void {
  const root = document.documentElement;
  if (pref === 'system') delete root.dataset.theme;
  else root.dataset.theme = pref;
}

export function saveThemePref(pref: ThemePref): void {
  try {
    window.localStorage.setItem(STORAGE_KEY, pref);
  } catch {
    // Storage full or blocked — the choice just won't survive a reload.
  }
}
