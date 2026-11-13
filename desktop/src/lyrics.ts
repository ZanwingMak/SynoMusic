export type LyricLine = { time: number; text: string };

/** 解析 LRC 时间轴、全局毫秒偏移和多时间标签；纯文本保留原顺序，不伪造同步时间。 */
export function parseLyrics(text: string): LyricLine[] {
 const offset = Number(text.match(/\[offset:\s*([+-]?\d+)\s*\]/i)?.[1] || 0) / 1000;
 const lines: LyricLine[] = [];
 for (const raw of text.replace(/^\ufeff/, "").split(/\r?\n|\r/)) {
  const tags = [...raw.matchAll(/\[(\d+):(\d{1,2})(?:[.:](\d{1,3}))?\]/g)];
  const content = raw.replace(/\[(?:\d+:\d{1,2}(?:[.:]\d{1,3})?|[a-z]+:[^\]]*)\]/gi, "").trim();
  if (tags.length) {
   for (const tag of tags) {
    if (Number(tag[2]) < 60) lines.push({ time: Math.max(0, Number(tag[1]) * 60 + Number(tag[2]) + Number(`0.${tag[3] || 0}`) + offset), text: content });
   }
  } else if (content) lines.push({ time: -1, text: content });
 }
 if (!lines.some(line => line.time >= 0)) return lines;
 const grouped: LyricLine[] = [];
 for (const line of lines.filter(line => line.time >= 0).sort((a, b) => a.time - b.time)) {
  const previous = grouped.at(-1);
  if (previous?.time === line.time) previous.text = [previous.text, line.text].filter(Boolean).join("\n");
  else grouped.push({ ...line });
 }
 return grouped;
}

/** 二分查找正在播放的歌词行；尚未开始和纯文本均不高亮。 */
export function activeLyric(lines: LyricLine[], position: number): number {
 let low = 0, high = lines.length - 1, active = -1;
 while (low <= high) {
  const middle = (low + high) >>> 1;
  if (lines[middle].time >= 0 && lines[middle].time <= position) { active = middle; low = middle + 1; }
  else high = middle - 1;
 }
 return active;
}
