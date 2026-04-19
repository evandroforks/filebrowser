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

    <div v-else class="songbook-container">
      <div
        v-for="(song, index) in songs"
        :key="song.name"
        class="songbook-page"
      >
        <h2 class="song-title">{{ song.title }}</h2>
        <pre class="cifra-content">{{ song.content }}</pre>
        <hr v-if="index < songs.length - 1" class="page-break" />
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from "vue";
import { useFileStore } from "@/stores/file";
import { useI18n } from "vue-i18n";
import { baseURL } from "@/utils/constants";
import { useAuthStore } from "@/stores/auth";

const { t } = useI18n({});
const fileStore = useFileStore();
const authStore = useAuthStore();

interface Song {
  name: string;
  title: string;
  content: string;
}

const songs = ref<Song[]>([]);
const loading = ref(true);

const emit = defineEmits(["exit"]);

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
  padding: 2em 1.5em;
}

.songbook-page {
  margin-bottom: 2em;
}

.song-title {
  font-size: 1.6em;
  font-weight: bold;
  margin-bottom: 0.5em;
  border-bottom: 2px solid #ccc;
  padding-bottom: 0.3em;
}

.cifra-content {
  white-space: pre-wrap;
  font-family: "Courier New", Courier, monospace;
  font-size: 0.95em;
  line-height: 1.5;
  background: #fafafa;
  padding: 1em;
  border-radius: 6px;
  border: 1px solid #e0e0e0;
  overflow-x: auto;
}

.page-break {
  border: none;
  border-top: 1px dashed #ccc;
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
