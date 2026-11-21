import catalog from "../../SynoMusic/Resources/developer-apps.json";
import rollKeep from "../../SynoMusic/Resources/DeveloperApps.xcassets/DeveloperRollKeep.imageset/icon.jpg";
import kanata from "../../SynoMusic/Resources/DeveloperApps.xcassets/DeveloperKanata.imageset/icon.jpg";
import meloGo from "../../SynoMusic/Resources/DeveloperApps.xcassets/DeveloperMeloGo.imageset/icon.jpg";
import nightfall from "../../SynoMusic/Resources/DeveloperApps.xcassets/DeveloperNightfall.imageset/icon.jpg";
import { getLanguage } from "./i18n";
import "./developer-apps.css";

const images: Record<string, string> = { DeveloperRollKeep: rollKeep, DeveloperKanata: kanata, DeveloperMeloGo: meloGo, DeveloperNightfall: nightfall };

/** 将目录文案安全放入 HTML 属性和文本，不解释为页面标记。 */
function escape(value: string): string {
  return value.replace(/[&<>"']/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char]!));
}

/** 从与 Apple 客户端共用的离线目录读取文案，遵循应用内语言设置。 */
function text(key: string): string {
  const strings = catalog.strings as Record<string, Record<string, string>>;
  return strings[getLanguage()]?.[key] ?? (getLanguage() === "zh-Hans" ? key : strings.en[key]) ?? key;
}

/** 设置页中的作品卡片标明 Apple 设备要求，点击后使用现有系统链接入口。 */
export function developerAppsSection(): string {
  return `<section class="developer-apps" aria-labelledby="developer-apps-title"><div class="developer-apps-heading"><h2 id="developer-apps-title">${escape(text("更多作品"))}</h2><p>${escape(text("同一位开发者，用心做的其他 App。"))}</p></div><div class="developer-apps-grid">${catalog.apps.map(app => {
    const summary = app.summary as Record<string, string>;
    const platforms = app.platforms.map(platform => platform === "iOS" ? "iPhone · iPad" : "Apple TV").join(" · ");
    return `<button class="developer-app-card" data-link="https://apps.apple.com/app/id${app.id}" aria-label="${escape(app.name + " — " + text("在 App Store 查看"))}"><img src="${images[app.icon]}" width="56" height="56" alt=""><span class="developer-app-copy"><strong>${escape(app.name)}</strong><span>${escape(summary[getLanguage()] ?? summary.en)}</span><small>${platforms}</small></span><span class="developer-app-arrow" aria-hidden="true">↗</span></button>`;
  }).join("")}</div></section>`;
}
