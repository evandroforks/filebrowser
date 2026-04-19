<template>
  <div class="breadcrumbs">
    <div class="breadcrumbs-left">
      <component
        :is="element"
        :to="base || ''"
        :aria-label="t('files.home')"
        :title="t('files.home')"
      >
        <i class="material-icons">home</i>
      </component>

      <span v-for="(link, index) in items" :key="index">
        <span class="chevron"
          ><i class="material-icons">keyboard_arrow_right</i></span
        >
        <component :is="element" :to="link.url">{{ link.name }}</component>
      </span>
    </div>
    <div v-if="$slots.title" class="breadcrumbs-title">
      <slot name="title" />
    </div>
    <div v-if="$slots.actions" class="breadcrumbs-actions">
      <slot name="actions" />
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { useRoute } from "vue-router";

const { t } = useI18n();

const route = useRoute();

const props = defineProps<{
  base: string;
  noLink?: boolean;
}>();

const items = computed(() => {
  const relativePath = route.path.replace(props.base, "");
  const parts = relativePath.split("/");

  if (parts[0] === "") {
    parts.shift();
  }

  if (parts[parts.length - 1] === "") {
    parts.pop();
  }

  const breadcrumbs: BreadCrumb[] = [];

  for (let i = 0; i < parts.length; i++) {
    if (i === 0) {
      breadcrumbs.push({
        name: decodeURIComponent(parts[i]),
        url: props.base + "/" + parts[i] + "/",
      });
    } else {
      breadcrumbs.push({
        name: decodeURIComponent(parts[i]),
        url: breadcrumbs[i - 1].url + parts[i] + "/",
      });
    }
  }

  if (breadcrumbs.length > 3) {
    while (breadcrumbs.length !== 4) {
      breadcrumbs.shift();
    }

    breadcrumbs[0].name = "...";
  }

  return breadcrumbs;
});

const element = computed(() => {
  if (props.noLink) {
    return "span";
  }

  return "router-link";
});
</script>

<style>
.breadcrumbs {
  display: flex;
  align-items: center;
  justify-content: space-between;
  position: relative;
}

.breadcrumbs-left {
  display: flex;
  align-items: center;
  flex: 1;
  min-width: 0;
}

.breadcrumbs-title {
  position: absolute;
  left: 50%;
  transform: translateX(-50%);
  display: flex;
  align-items: center;
  font-size: 1em;
  font-weight: 600;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 40%;
  pointer-events: none;
}

.breadcrumbs-actions {
  display: flex;
  align-items: center;
  gap: 0.25em;
  flex-shrink: 0;
  padding-right: 0.5em;
}

.breadcrumbs-actions .action span:not(.counter) {
  display: none;
}
</style>
