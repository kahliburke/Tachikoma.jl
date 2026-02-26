<script setup lang="ts">
defineProps<{
  title?: string
}>()
</script>

<template>
  <div class="terminal-window">
    <div class="title-bar">
      <div class="traffic-lights">
        <span class="light close"></span>
        <span class="light minimize"></span>
        <span class="light maximize"></span>
      </div>
      <span class="title-text">{{ title }}</span>
    </div>
    <div class="window-body">
      <slot />
    </div>
  </div>
</template>

<style scoped>
.terminal-window {
  border-radius: 8px;
  overflow: hidden;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.35), 0 2px 8px rgba(0, 0, 0, 0.2);
  background: #1a1a2e;
  border: 1px solid rgba(255, 255, 255, 0.08);
}

.title-bar {
  display: flex;
  align-items: center;
  height: 32px;
  padding: 0 12px;
  background: linear-gradient(180deg, #2d2d3f 0%, #252538 100%);
  border-bottom: 1px solid rgba(0, 0, 0, 0.3);
  user-select: none;
}

.traffic-lights {
  display: flex;
  gap: 7px;
  align-items: center;
}

.light {
  width: 12px;
  height: 12px;
  border-radius: 50%;
  display: inline-block;
}

.light.close {
  background: #ff5f57;
  border: 1px solid #e0443e;
}

.light.minimize {
  background: #febc2e;
  border: 1px solid #dea123;
}

.light.maximize {
  background: #28c840;
  border: 1px solid #1aab29;
}

.title-text {
  flex: 1;
  text-align: center;
  font-size: 12px;
  color: rgba(255, 255, 255, 0.5);
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  margin-right: 48px; /* balance the traffic lights width */
}

.window-body {
  padding: 0;
  line-height: 0;
}

.window-body :deep(img) {
  width: 100%;
  display: block;
}
</style>
