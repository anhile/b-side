// YouTube Music song search without an account, for the comparison only:
// the app checks artists itself, with the user's own session.

const endpoint = "https://music.youtube.com/youtubei/v1/search?prettyPrint=false";
const songsFilter = "EgWKAQIIAWoMEA4QChADEAQQCRAF";
const context = { client: { clientName: "WEB_REMIX", clientVersion: "1.20260928.13.00", hl: "en" } };

export interface Song {
  title: string;
  /// The credit before the first " • ": "Duke Ellington & John Coltrane".
  credit: string;
}

export async function searchSongs(query: string): Promise<Song[]> {
  for (let attempt = 0; attempt < 2; attempt++) {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json", Origin: "https://music.youtube.com" },
      body: JSON.stringify({ context, query, params: songsFilter }),
    });
    if (!response.ok) throw new Error(`search failed: HTTP ${response.status}`);
    const songs: Song[] = [];
    collect(await response.json(), songs);
    if (songs.length) return songs;
    await new Promise((resolve) => setTimeout(resolve, 500)); // empty now and then; once more
  }
  return [];
}

function collect(node: unknown, songs: Song[]): void {
  if (Array.isArray(node)) return node.forEach((child) => collect(child, songs));
  if (!node || typeof node !== "object") return;
  const item = (node as Record<string, any>).musicResponsiveListItemRenderer;
  if (item) {
    const text = (column: any) =>
      (column?.musicResponsiveListItemFlexColumnRenderer?.text?.runs ?? []).map((run: any) => run.text).join("");
    songs.push({ title: text(item.flexColumns?.[0]), credit: text(item.flexColumns?.[1]).split(" • ")[0] });
  }
  Object.values(node).forEach((child) => collect(child, songs));
}

/// Search confirms the artist when a song credits exactly that name, alone
/// or among others, in either script ("Kino" and "Кино").
export function credits(song: Song, artist: string): boolean {
  const names = [song.credit, ...song.credit.split(/\s*(?:&|,| x | feat\. )\s*/)].map(fold);
  const wanted = fold(artist);
  return names.some((name) => name === wanted || latin(name) === latin(wanted));
}

function fold(text: string): string {
  return text.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase().trim();
}

const cyrillic: Record<string, string> = {
  а: "a", б: "b", в: "v", г: "g", д: "d", е: "e", ё: "e", ж: "zh", з: "z", и: "i", й: "y", к: "k", л: "l",
  м: "m", н: "n", о: "o", п: "p", р: "r", с: "s", т: "t", у: "u", ф: "f", х: "kh", ц: "ts", ч: "ch", ш: "sh",
  щ: "shch", ъ: "", ы: "y", ь: "", э: "e", ю: "yu", я: "ya",
};

/// A rough Russian transliteration, with the usual variants made equal.
function latin(text: string): string {
  return [...text].map((letter) => cyrillic[letter] ?? letter).join("")
    .replace(/ia/g, "ya").replace(/iu/g, "yu").replace(/h/g, "").replace(/[^a-z0-9]/g, "");
}
