<template>
  <div class="songbook-wrapper" @click="handleWrapperClick">
    <!-- Transpose controls -->
    <div class="transpose-controls" @click.stop>
      <button class="transpose-btn" @click="changeTranspose(-1)" title="Descer meio tom">−½</button>
      <span class="transpose-label">Tom: {{ currentSongTranspose >= 0 ? '+' : '' }}{{ currentSongTranspose }}</span>
      <button class="transpose-btn" @click="changeTranspose(1)" title="Subir meio tom">+½</button>
    </div>
    <!-- Probe: renders all lines of first song invisible to measure exact line height -->
    <div class="cifra-content cifra-probe" ref="probeRef" aria-hidden="true">
      <div
        v-for="(line, i) in probeLines"
        :key="i"
        :class="line.isChord ? 'chord-line' : 'lyric-line'"
      >{{ line.text || '\u00A0' }}</div>
    </div>

    <div v-if="loading" class="message delayed">
      <div class="spinner">
        <div class="bounce1"></div>
        <div class="bounce2"></div>
        <div class="bounce3"></div>
      </div>
      <span>{{ t("files.loading") }}</span>
    </div>

    <!-- Paginated mode: one sub-page at a time, no scrollbar -->
    <div v-else-if="layoutStore.songbookPaginated && !layoutStore.songbookDualPage" class="songbook-page-full" ref="pageRef">
      <div v-if="currentSubPage" class="songbook-page-full-inner">
        <div class="cifra-content" ref="contentRef">
          <div
            v-for="(line, lineIndex) in currentSubPage.lines"
            :key="lineIndex"
            :class="line.isChord ? 'chord-line' : 'lyric-line'"
          >{{ line.isChord ? transposeLine(line.text, getSongTranspose(currentSubPage!.title)) : (line.text || '\u00A0') }}</div>
        </div>
      </div>
    </div>

    <!-- Dual-page mode: two sub-pages side by side, no scrollbar -->
    <div v-else-if="layoutStore.songbookPaginated && layoutStore.songbookDualPage" class="songbook-dual-wrapper" ref="pageRef">
      <div class="songbook-page-full songbook-page-col">
        <div v-if="leftSubPage" class="songbook-page-full-inner">
          <div class="cifra-content" ref="contentRef">
            <div
              v-for="(line, lineIndex) in leftSubPage.lines"
              :key="lineIndex"
              :class="line.isChord ? 'chord-line' : 'lyric-line'"
            >{{ line.isChord ? transposeLine(line.text, getSongTranspose(leftSubPage!.title)) : (line.text || '\u00A0') }}</div>
          </div>
        </div>
      </div>
      <div class="songbook-page-col-divider"></div>
      <div class="songbook-page-full songbook-page-col">
        <div v-if="rightSubPage" class="songbook-page-full-inner">
          <div class="cifra-content">
            <div
              v-for="(line, lineIndex) in rightSubPage.lines"
              :key="lineIndex"
              :class="line.isChord ? 'chord-line' : 'lyric-line'"
            >{{ line.isChord ? transposeLine(line.text, getSongTranspose(rightSubPage!.title)) : (line.text || '\u00A0') }}</div>
          </div>
        </div>
      </div>
    </div>

    <!-- Continuous mode: all songs scrollable -->
    <div v-else class="songbook-container" ref="continuousContainerRef">
      <div
        v-for="(song, index) in songs"
        :key="song.name"
        class="songbook-page"
        :data-song-title="song.title"
      >
        <h2 class="song-title">{{ song.title }}</h2>
        <div class="cifra-content">
          <div
            v-for="(line, lineIndex) in parsedLines(song.content)"
            :key="lineIndex"
            :class="line.isChord ? 'chord-line' : 'lyric-line'"
          >{{ line.isChord ? transposeLine(line.text, getSongTranspose(song.title)) : (line.text || '\u00A0') }}</div>
        </div>
        <hr v-if="index < songs.length - 1" class="page-break" />
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed, watch, nextTick } from "vue";
import { useFileStore } from "@/stores/file";
import { useLayoutStore } from "@/stores/layout";
import { useI18n } from "vue-i18n";
import { baseURL } from "@/utils/constants";
import { useAuthStore } from "@/stores/auth";

const { t } = useI18n({});
const fileStore = useFileStore();
const layoutStore = useLayoutStore();
const authStore = useAuthStore();

interface Song {
  name: string;
  title: string;
  content: string;
}

interface ParsedLine {
  text: string;
  isChord: boolean;
}

interface SubPage {
  title: string;
  lines: ParsedLine[];
  subPageNum: number;
  totalSubPages: number;
}

interface Spread {
  left: SubPage;
  right: SubPage | null;
}

const songs = ref<Song[]>([]);
const loading = ref(true);
const probeRef = ref<HTMLElement | null>(null);
const pageRef = ref<HTMLElement | null>(null);
const contentRef = ref<HTMLElement | null>(null);
const subPages = ref<SubPage[]>([]);
const probeLines = ref<ParsedLine[]>([]);

let resizeObserver: ResizeObserver | null = null;
let measuredLinesPerPage = 0;

/**
 * Two-pass measurement:
 * Pass 1 — fill probeLines with all lines of the first song, wait for render,
 *           then measure: probeRef.scrollHeight / lineCount = exact line height.
 * Pass 2 — subtract title + padding from pageRef.clientHeight to get availableH,
 *           divide by line height → linesPerPage.
 */
async function measureAndBuild() {
  if (!songs.value.length || !pageRef.value) return;

  const containerH = pageRef.value.clientHeight;
  if (containerH < 50) return;

  // Fill probe with all lines of first song
  const allFirstLines = parsedLines(songs.value[0].content);
  probeLines.value = allFirstLines;
  await nextTick();

  // Measure exact line height from probe
  let lineH = 22;
  if (probeRef.value && allFirstLines.length > 0) {
    lineH = probeRef.value.scrollHeight / allFirstLines.length;
  }

  // cifra-content has flex:1 and fills all available space — measure it directly.
  // Fall back to containerH if contentRef isn't mounted yet.
  const availableH = (contentRef.value?.clientHeight ?? 0) > 50
    ? contentRef.value!.clientHeight
    : containerH;

  // Subtract 1 line as safety margin so the last line is never half-clipped
  const linesPerPage = Math.max(3, Math.floor(availableH / lineH) - 1);

  if (measuredLinesPerPage === linesPerPage) return; // nothing changed
  measuredLinesPerPage = linesPerPage;

  // Build all sub-pages
  const result: SubPage[] = [];
  for (const song of songs.value) {
    const lines = parsedLines(song.content);
    const chunks: ParsedLine[][] = [];
    // Returns the chord line that starts the block containing lines[pos],
    // or pos itself if no chord is found above within the current chunk.
    const findBlockStart = (pos: number, chunkStart: number): number => {
      let p = pos;
      while (p > chunkStart && !lines[p].isChord && lines[p].text.trim()) {
        p--;
      }
      return lines[p].isChord ? p : pos;
    };

    let i = 0;
    while (i < lines.length) {
      let end = Math.min(i + linesPerPage, lines.length);

      // Only adjust the cut if there is more content after it.
      if (end < lines.length) {
        // Find the first non-empty line after the cut point.
        let nextContent = end;
        while (nextContent < lines.length && !lines[nextContent].text.trim()) {
          nextContent++;
        }
        // If that next non-empty line is a lyric (not a chord), it might
        // belong to a chord-block that started inside this chunk → move the
        // cut back to before that chord so the block stays together.
        if (nextContent < lines.length && !lines[nextContent].isChord) {
          const blockStart = findBlockStart(end - 1, i);
          if (blockStart > i) {
            end = blockStart;
            // Strip any trailing empty lines that are now at the tail.
            while (end > i + 1 && !lines[end - 1].text.trim()) {
              end--;
            }
          }
        }
      }

      if (end <= i) end = i + 1; // safety: always make progress
      chunks.push(lines.slice(i, end));
      i = end;
    }
    if (chunks.length === 0) chunks.push([]);
    chunks.forEach((chunk, idx) => {
      result.push({
        title: song.title,
        lines: chunk,
        subPageNum: idx + 1,
        totalSubPages: chunks.length,
      });
    });
  }
  subPages.value = result;
  // Count spreads for dual-page mode: consecutive same-song pages pair up
  if (layoutStore.songbookDualPage) {
    let spreadCount = 0;
    let si = 0;
    while (si < result.length) {
      const next = result[si + 1];
      spreadCount++;
      si += (next && next.title === result[si].title) ? 2 : 1;
    }
    layoutStore.songbookTotalPages = spreadCount;
  } else {
    layoutStore.songbookTotalPages = result.length;
  }
  probeLines.value = []; // clear probe
}

function attachResizeObserver() {
  if (!pageRef.value) return;
  resizeObserver?.disconnect();
  resizeObserver = new ResizeObserver(() => {
    measuredLinesPerPage = 0; // force re-measure on resize
    measureAndBuild();
  });
  resizeObserver.observe(pageRef.value);
}

// Pre-computed spreads for dual-page mode: each spread keeps both pages
// from the same song together; if a song has an odd number of sub-pages
// the last spread has right=null.
const spreads = computed<Spread[]>(() => {
  const result: Spread[] = [];
  let i = 0;
  while (i < subPages.value.length) {
    const left = subPages.value[i];
    const right = subPages.value[i + 1];
    if (right && right.title === left.title) {
      result.push({ left, right });
      i += 2;
    } else {
      result.push({ left, right: null });
      i += 1;
    }
  }
  return result;
});

const currentSubPage = computed(() => {
  if (layoutStore.songbookDualPage) {
    const spread = spreads.value[Math.min(layoutStore.songbookPage, spreads.value.length - 1)];
    return spread?.left ?? null;
  }
  const page = Math.min(layoutStore.songbookPage, subPages.value.length - 1);
  return subPages.value[page] ?? null;
});

const leftSubPage = computed(() => currentSubPage.value);
const rightSubPage = computed(() => {
  const spread = spreads.value[Math.min(layoutStore.songbookPage, spreads.value.length - 1)];
  return spread?.right ?? null;
});

watch(currentSubPage, (page) => {
  if (!layoutStore.songbookPaginated) return;
  if (!page) {
    layoutStore.songbookCurrentTitle = "";
    return;
  }
  let title = page.title;
  const pageLabel = `${layoutStore.songbookPage + 1} / ${subPages.value.length}`;
  const subLabel = page.totalSubPages > 1 ? ` (${page.subPageNum}/${page.totalSubPages})` : "";
  layoutStore.songbookCurrentTitle = `${title} — ${pageLabel}${subLabel}`;
}, { immediate: true });

watch(songs, async () => {
  layoutStore.songbookPage = 0;
  measuredLinesPerPage = 0;
  if (layoutStore.songbookPaginated) {
    await nextTick();
    attachResizeObserver();
    await measureAndBuild();
  } else {
    await nextTick();
    attachSongIntersectionObserver();
  }
});

watch(() => layoutStore.songbookPaginated, async (val) => {
  if (val) {
    songIntersectionObserver?.disconnect();
    songIntersectionObserver = null;
    layoutStore.songbookPage = 0;
    measuredLinesPerPage = 0;
    await nextTick();
    attachResizeObserver();
    await measureAndBuild();
  } else {
    resizeObserver?.disconnect();
    probeLines.value = [];
    await nextTick();
    attachSongIntersectionObserver();
  }
});

watch(() => layoutStore.songbookDualPage, async () => {
  if (layoutStore.songbookPaginated) {
    layoutStore.songbookPage = 0;
    measuredLinesPerPage = 0;
    await nextTick();
    attachResizeObserver();
    await measureAndBuild();
  }
});

function handleTapLeft() {
  layoutStore.songbookPage = Math.max(0, layoutStore.songbookPage - 1);
}

function handleTapRight() {
  layoutStore.songbookPage = Math.min(layoutStore.songbookTotalPages - 1, layoutStore.songbookPage + 1);
}

function handleWrapperClick(e: MouseEvent) {
  if (!layoutStore.songbookPaginated) return;
  // In dual-page mode the divider is the center; in single-page use window center
  const mid = window.innerWidth / 2;
  if (e.clientX < mid) {
    handleTapLeft();
  } else {
    handleTapRight();
  }
}

function handleKeydown(e: KeyboardEvent) {
  if (!layoutStore.songbookPaginated) return;
  // Ignore when user is typing in an input/textarea
  const tag = (e.target as HTMLElement)?.tagName;
  if (tag === "INPUT" || tag === "TEXTAREA") return;

  const total = layoutStore.songbookTotalPages;
  if (e.key === " " || e.key === "ArrowRight" || e.key === "ArrowDown") {
    e.preventDefault();
    layoutStore.songbookPage = Math.min(total - 1, layoutStore.songbookPage + 1);
  } else if (e.key === "ArrowLeft" || e.key === "ArrowUp") {
    e.preventDefault();
    layoutStore.songbookPage = Math.max(0, layoutStore.songbookPage - 1);
  }
}

onMounted(() => {
  window.addEventListener("keydown", handleKeydown);
});
onUnmounted(() => {
  window.removeEventListener("keydown", handleKeydown);
  resizeObserver?.disconnect();
  songIntersectionObserver?.disconnect();
  layoutStore.songbookCurrentTitle = "";
  layoutStore.songbookTotalPages = 0;
});

const CHORD_TOKEN = /^[A-G][b#]?(m|M|maj|min|dim|aug|sus|add)?\d*([\/\(][A-G][b#]?)?$/;

function isChordLine(line: string): boolean {
  const trimmed = line.trim();
  if (!trimmed) return false;
  if (/^\[.*\]/.test(trimmed)) return true;
  const tokens = trimmed.split(/\s+/).filter(Boolean);
  const withoutLabel = tokens[0].endsWith(":") ? tokens.slice(1) : tokens;
  if (withoutLabel.length === 0) return false;
  return withoutLabel.every((tok) => CHORD_TOKEN.test(tok));
}

function parsedLines(content: string): ParsedLine[] {
  return content.split(/\r?\n/).map((text) => ({
    text,
    isChord: isChordLine(text),
  }));
}

// --- Transpose logic ---
const NOTES_SHARP = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
const NOTES_FLAT = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'];

const STORAGE_KEY = 'songbook-transpose';

// Map of song title → semitones offset
const transposeMap = ref<Record<string, number>>({});

function loadTransposeMap() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    transposeMap.value = raw ? JSON.parse(raw) : {};
  } catch {
    transposeMap.value = {};
  }
}

function saveTransposeMap() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(transposeMap.value));
}

const continuousContainerRef = ref<HTMLElement | null>(null);
const scrollVisibleTitle = ref<string>('');
let songIntersectionObserver: IntersectionObserver | null = null;

// In continuous mode, update the header bar with the visible song
watch(scrollVisibleTitle, (title) => {
  if (layoutStore.songbookPaginated || !title) return;
  const idx = songs.value.findIndex(s => s.title === title);
  const total = songs.value.length;
  const label = idx >= 0 ? `${idx + 1} / ${total}` : '';
  layoutStore.songbookCurrentTitle = `${title} — ${label}`;
});

function attachSongIntersectionObserver() {
  songIntersectionObserver?.disconnect();
  songIntersectionObserver = null;
  if (!continuousContainerRef.value) return;
  const pages = continuousContainerRef.value.querySelectorAll<HTMLElement>('.songbook-page[data-song-title]');
  if (!pages.length) return;

  // Track ratio of each song element in view; pick highest visible
  const ratioMap = new Map<string, number>();

  songIntersectionObserver = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      const title = (entry.target as HTMLElement).dataset.songTitle ?? '';
      ratioMap.set(title, entry.intersectionRatio);
    }
    // The song with the highest intersection ratio is "current"
    let bestTitle = '';
    let bestRatio = -1;
    for (const [title, ratio] of ratioMap) {
      if (ratio > bestRatio) { bestRatio = ratio; bestTitle = title; }
    }
    if (bestTitle) scrollVisibleTitle.value = bestTitle;
  }, { threshold: Array.from({ length: 21 }, (_, i) => i / 20) });

  for (const page of pages) {
    ratioMap.set((page as HTMLElement).dataset.songTitle ?? '', 0);
    songIntersectionObserver.observe(page);
  }
}

function getSongTranspose(songTitle: string): number {
  return transposeMap.value[songTitle] ?? 0;
}

// The current song title based on which page/mode is active
const currentSongTitle = computed<string>(() => {
  if (layoutStore.songbookPaginated) {
    return currentSubPage.value?.title ?? '';
  }
  // Continuous mode: use the song most visible in the viewport
  return scrollVisibleTitle.value || songs.value[0]?.title || '';
});

const currentSongTranspose = computed<number>(() => getSongTranspose(currentSongTitle.value));

function changeTranspose(delta: number) {
  const title = currentSongTitle.value;
  if (!title) return;
  let val = getSongTranspose(title) + delta;
  val = ((val % 12) + 12) % 12;
  if (val > 6) val -= 12;
  transposeMap.value[title] = val;
  saveTransposeMap();
}

function resetTranspose() {
  const title = currentSongTitle.value;
  if (!title) return;
  delete transposeMap.value[title];
  saveTransposeMap();
}

function transposeNote(note: string, semitones: number): string {
  if (semitones === 0) return note;
  const isFlat = note.includes('b');
  const noteList = isFlat ? NOTES_FLAT : NOTES_SHARP;
  const idx = noteList.indexOf(note);
  if (idx === -1) {
    // try the other list
    const altList = isFlat ? NOTES_SHARP : NOTES_FLAT;
    const altIdx = altList.indexOf(note);
    if (altIdx === -1) return note;
    return NOTES_SHARP[((altIdx + semitones) % 12 + 12) % 12];
  }
  return noteList[((idx + semitones) % 12 + 12) % 12];
}

function transposeLine(line: string, semitones: number): string {
  if (semitones === 0) return line;
  // Split line into bracket segments [...]  and non-bracket segments.
  // Only transpose chords outside of brackets.
  return line.replace(/(\[[^\]]*\])|(\b[A-G][#b]?(?:maj|min|dim|aug|sus|add|m|M|\d|\(|\/)* *)/g, (match, bracket: string, chord: string) => {
    if (bracket !== undefined) return bracket; // leave [Final], [Verse], etc. untouched
    const root = chord.match(/^[A-G][#b]?/)![0];
    const transposed = transposeNote(root, semitones);
    return transposed + chord.slice(root.length);
  });
}

function removePrefix(url: string) {
  url = url.replace(/\/files\//, "/");
  if (url === "") url = "/";
  return url;
}

async function fetchRawContent(itemUrl: string, modified?: string): Promise<string> {
  const cleanPath = removePrefix(itemUrl);
  const cacheBuster = modified ? Date.parse(modified) : Date.now();
  const url = `${baseURL}/api/raw${cleanPath}?_=${cacheBuster}`;
  const res = await fetch(url, {
    headers: { "X-Auth": authStore.jwt },
    cache: "no-store",
  });
  if (!res.ok) return `[Error loading file: ${res.status}]`;
  return await res.text();
}

onMounted(async () => {
  loadTransposeMap();
  const items = fileStore.req?.items ?? [];
  const txtFiles = items.filter(
    (item: any) => !item.isDir && item.name.toLowerCase().endsWith(".txt")
  );
  txtFiles.sort((a: any, b: any) => a.name.localeCompare(b.name));

  const results: Song[] = [];
  for (const file of txtFiles) {
    const content = await fetchRawContent(file.url, file.modified);
    results.push({
      name: file.name,
      title: file.name.replace(/\.txt$/i, ""),
      content,
    });
  }
  songs.value = results;
  loading.value = false;
});
</script>

<style scoped>
/* Transpose controls */
.transpose-controls {
  position: fixed;
  bottom: 1em;
  right: 1em;
  z-index: 100;
  display: flex;
  align-items: center;
  gap: 0.4em;
  background: rgba(30, 30, 30, 0.9);
  border: 1px solid #555;
  border-radius: 8px;
  padding: 0.3em 0.6em;
  backdrop-filter: blur(6px);
}

.transpose-btn {
  background: #333;
  color: #fff;
  border: 1px solid #666;
  border-radius: 4px;
  width: 2em;
  height: 2em;
  font-size: 1.1em;
  font-weight: bold;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: background 0.15s;
}

.transpose-btn:hover {
  background: #555;
}

.transpose-btn:active {
  background: #ff8c00;
}

.transpose-reset {
  font-size: 1em;
  width: 2em;
}

.transpose-label {
  color: #ff8c00;
  font-family: "Courier New", monospace;
  font-size: 0.9em;
  min-width: 4.5em;
  text-align: center;
  user-select: none;
}

/* Hidden probe: renders lines invisibly to measure exact line height */
.cifra-probe {
  position: absolute;
  visibility: hidden;
  pointer-events: none;
  top: 0;
  left: 0;
  width: 600px;
  max-height: none !important;
  overflow: visible !important;
  height: auto !important;
  flex: none !important;
  border: none !important;
  padding: 0 !important;
}

.songbook-wrapper {
  background: #000;
  min-height: 100%;
  padding: 1em 0;
  position: relative;
}

body.songbook-paginated .songbook-wrapper {
  padding: 0;
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
}

/* Paginated: fills exact remaining height, no scroll */
.songbook-page-full {
  max-width: 900px;
  width: 100%;
  margin: 0 auto;
  padding: 0 1.5em;
  flex: 1;
  min-height: 0;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  position: relative;
}

.songbook-page-full-inner {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 0;
}

.songbook-page-full .cifra-content {
  flex: 1;
  overflow: hidden;
}

/* Continuous mode */
.songbook-container {
  max-width: 900px;
  margin: 0 auto;
  padding: 0 1.5em 1em;
}

.songbook-page:first-child .song-title {
  margin-top: 0.5em;
}

.songbook-page {
  margin-bottom: 2em;
}

.song-title {
  font-size: 1.6em;
  font-weight: bold;
  margin-bottom: 0.5em;
  border-bottom: 2px solid #555;
  padding-bottom: 0.3em;
  color: #fff;
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  flex-shrink: 0;
}

.cifra-content {
  white-space: pre-wrap;
  font-family: "Courier New", Courier, monospace;
  font-size: 0.95em;
  line-height: 1.5;
  background: #000;
  padding: 1em;
  border-radius: 6px;
  border: 1px solid #333;
  overflow-x: auto;
}

.chord-line {
  color: #ff8c00;
  font-weight: bold;
}

.lyric-line {
  color: #ffffff;
}

.page-break {
  border: none;
  border-top: 1px dashed #444;
  margin: 2em 0;
}

/* Dual-page: two columns side by side */
.songbook-dual-wrapper {
  display: flex;
  flex-direction: row;
  flex: 1;
  min-height: 0;
  overflow: hidden;
  padding: 0 0.5em;
  gap: 0;
}

body.songbook-paginated .songbook-dual-wrapper {
  padding: 0;
}

.songbook-page-col {
  flex: 1;
  min-width: 0;
  padding: 0 1em;
  max-width: none;
  margin: 0;
}

.songbook-page-col-divider {
  width: 1px;
  background: #444;
  align-self: stretch;
  flex-shrink: 0;
}

@media print {
  .page-break {
    page-break-after: always;
    break-after: page;
    border: none;
    margin: 0;
  }

  .songbook-container {
    padding: 0;
  }

  .songbook-page {
    margin-bottom: 0;
  }

  header,
  nav,
  #sidebar,
  .action,
  .overlay {
    display: none !important;
  }
}
</style>
