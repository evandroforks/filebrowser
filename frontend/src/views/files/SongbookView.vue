<template>
  <div class="songbook-wrapper">
    <div v-if="loading" class="message delayed">
      <div class="spinner">
        <div class="bounce1"></div>
        <div class="bounce2"></div>
        <div class="bounce3"></div>
      </div>
      <span>{{ t("files.loading") }}</span>
    </div>

    <!-- Paginated mode: one song at a time -->
    <div v-else-if="layoutStore.songbookPaginated" class="songbook-container">
      <div v-if="currentSong" class="songbook-page">
        <h2 class="song-title">
          {{ currentSong.title }}
          <span class="song-counter">{{ layoutStore.songbookPage + 1 }} / {{ songs.length }}</span>
        </h2>
        <div class="cifra-content">
          <div
            v-for="(line, lineIndex) in parsedLines(currentSong.content)"
            :key="lineIndex"
            :class="line.isChord ? 'chord-line' : 'lyric-line'"
          >{{ line.text || '\u00A0' }}</div>
        </div>
      </div>
    </div>

    <!-- Continuous mode: all songs -->
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
import { ref, onMounted, computed, watch } from "vue";
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

const songs = ref<Song[]>([]);
const loading = ref(true);

const currentSong = computed(() => {
  const page = Math.min(layoutStore.songbookPage, songs.value.length - 1);
  return songs.value[page] ?? null;
});

// Clamp page index when songs load
watch(songs, () => {
  layoutStore.songbookPage = 0;
});

const emit = defineEmits(["exit"]);

const CHORD_TOKEN = /^[A-G][b#]?(m|M|maj|min|dim|aug|sus|add)?\d*([\/\(][A-G][b#]?)?$/;

function isChordLine(line: string): boolean {
  // Match lines that are section markers like [Intro] or chord-only lines
  const trimmed = line.trim();
  if (!trimmed) return false;
  // Section markers like [Intro], [Verse 1], etc.
  if (/^\[.*\]/.test(trimmed)) return true;
  // Split by whitespace; every non-empty token must look like a chord
  const tokens = trimmed.split(/\s+/).filter(Boolean);
  // Allow section labels followed by chords: e.g. "Intro: C7 Fm7"
  const withoutLabel = tokens[0].endsWith(":") ? tokens.slice(1) : tokens;
  if (withoutLabel.length === 0) return false;
  return withoutLabel.every((t) => CHORD_TOKEN.test(t));
}

function parsedLines(content: string) {
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

async function fetchRawContent(itemUrl: string): Promise<string> {
  const cleanPath = removePrefix(itemUrl);
  const url = `${baseURL}/api/raw${cleanPath}`;
  const res = await fetch(url, {
    headers: {
      "X-Auth": authStore.jwt,
    },
  });
  if (!res.ok) {
    return `[Error loading file: ${res.status}]`;
  }
  return await res.text();
}

onMounted(async () => {
  const items = fileStore.req?.items ?? [];
  const txtFiles = items.filter(
    (item: any) =>
      !item.isDir && item.name.toLowerCase().endsWith(".txt")
  );

  // Sort alphabetically
  txtFiles.sort((a: any, b: any) => a.name.localeCompare(b.name));

  const results: Song[] = [];
  for (const file of txtFiles) {
    const content = await fetchRawContent(file.url);
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
}

.song-counter {
  font-size: 0.5em;
  font-weight: normal;
  color: #888;
}

.songbook-wrapper {
  background: #000;
  min-height: 100%;
  padding: 1em 0;
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

  /* Hide navigation elements when printing */
  header,
  nav,
  #sidebar,
  .action,
  .overlay {
    display: none !important;
  }
}
</style>
