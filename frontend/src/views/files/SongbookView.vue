<template>
  <div class="songbook-wrapper">
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
    <div v-else-if="layoutStore.songbookPaginated" class="songbook-page-full" ref="pageRef">
      <div v-if="currentSubPage" class="songbook-page-full-inner">
        <div class="cifra-content" ref="contentRef">
          <div
            v-for="(line, lineIndex) in currentSubPage.lines"
            :key="lineIndex"
            :class="line.isChord ? 'chord-line' : 'lyric-line'"
          >{{ line.text || '\u00A0' }}</div>
        </div>
      </div>
    </div>

    <!-- Continuous mode: all songs scrollable -->
    <div v-else class="songbook-container">
      <div
        v-for="(song, index) in songs"
        :key="song.name"
        class="songbook-page"
      >
        <h2 class="song-title">{{ song.title }}</h2>
        <div class="cifra-content">
          <div
            v-for="(line, lineIndex) in parsedLines(song.content)"
            :key="lineIndex"
            :class="line.isChord ? 'chord-line' : 'lyric-line'"
          >{{ line.text || '\u00A0' }}</div>
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

const songs = ref<Song[]>([]);
const loading = ref(true);
const probeRef = ref<HTMLElement | null>(null);
const pageRef = ref<HTMLElement | null>(null);
const titleRef = ref<HTMLElement | null>(null);
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
    // Returns the index of the chord line that starts the block containing
    // lines[pos], or pos itself if no chord is found above.
    // A "block" is a chord line followed by consecutive non-empty lyric lines.
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

      // 1. Strip trailing empty lines
      let trimmed = end;
      while (trimmed > i + 1 && !lines[trimmed - 1].text.trim()) {
        trimmed--;
      }

      // 2. Strip trailing chord lines (and repeat empty strip)
      while (trimmed > i + 1 && lines[trimmed - 1].isChord) {
        trimmed--;
        while (trimmed > i + 1 && !lines[trimmed - 1].text.trim()) {
          trimmed--;
        }
      }

      // 3. If the very next line (that didn't fit) is a non-empty lyric that
      //    belongs to the same chord-block as the last line on this page,
      //    move the cut back to the chord that started that block — keeping
      //    chord + ALL its lyrics together on the next page.
      if (
        trimmed < lines.length &&
        lines[trimmed].text.trim() &&
        !lines[trimmed].isChord
      ) {
        const blockStart = findBlockStart(trimmed - 1, i);
        if (blockStart > i) {
          // Only move back if we'd still have content on this page
          trimmed = blockStart;
          // Re-strip any empties that are now at the tail
          while (trimmed > i + 1 && !lines[trimmed - 1].text.trim()) {
            trimmed--;
          }
        }
      }

      end = trimmed;
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
  layoutStore.songbookTotalPages = result.length;
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

const currentSubPage = computed(() => {
  const page = Math.min(layoutStore.songbookPage, subPages.value.length - 1);
  return subPages.value[page] ?? null;
});

watch(currentSubPage, (page) => {
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
  }
});

watch(() => layoutStore.songbookPaginated, async (val) => {
  if (val) {
    layoutStore.songbookPage = 0;
    measuredLinesPerPage = 0;
    await nextTick();
    attachResizeObserver();
    await measureAndBuild();
  } else {
    resizeObserver?.disconnect();
    probeLines.value = [];
  }
});

onMounted(() => {});
onUnmounted(() => {
  resizeObserver?.disconnect();
  layoutStore.songbookCurrentTitle = "";
  layoutStore.songbookTotalPages = 0;
});

const emit = defineEmits(["exit"]);

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

.song-counter {
  font-size: 0.5em;
  font-weight: normal;
  color: #888;
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
