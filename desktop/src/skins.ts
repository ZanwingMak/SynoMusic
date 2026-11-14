type Tone = "light" | "dark";
type Palette = readonly [bg:string, surface:string, sidebar:string, line:string, text:string, muted:string, accent:string, soft:string, onAccent:string];
export type Skin = { id:string; name:string; description:string; radius:number; light:Palette; dark:Palette };

export const skins: Skin[] = [
 {id:"studio",name:"Studio",description:"Warm paper and copper details",radius:12,
  light:["#f7f6f3","#fffefa","#efeee8","#e1ddd5","#2d302b","#656b61","#984b36","#ede3d6","#fffaf3"],
  dark:["#1a1d1a","#252a24","#20251f","#394036","#f0f1e9","#a1aa9f","#dd997d","#373b30","#26241c"]},
 {id:"graphite",name:"Graphite",description:"Precise lines and brushed graphite",radius:6,
  light:["#f3f5f6","#fcfdfd","#e9edef","#d7dfe3","#28343c","#5c6973","#3e505d","#e2e8ec","#ffffff"],
  dark:["#191e22","#222a30","#1d2429","#39444c","#ecf0f3","#a7b2ba","#c1d1dc","#303e49","#1d2b35"]},
 {id:"evergreen",name:"Evergreen",description:"Soft moss and rounded surfaces",radius:18,
  light:["#f4f6ef","#fdfef8","#e9eee1","#d9e0cf","#30392d","#606d59","#3d6546","#e3ecd8","#ffffff"],
  dark:["#192119","#242f23","#1d281c","#3b4a36","#eef3e7","#a9b7a0","#b1cc99","#34452c","#202d18"]},
 {id:"seaglass",name:"Sea glass",description:"Frosted glass and quiet tides",radius:15,
  light:["#f1f6f4","#fbfefc","#e2eeea","#d1e0dc","#293c37","#566d65","#326a60","#dcece4","#ffffff"],
  dark:["#182320","#23312c","#1d2a26","#374c43","#e9f2ec","#a3b9ad","#a0d0be","#2e473d","#1a3026"]},
 {id:"rosewood",name:"Rosewood",description:"Rose linen and soft contours",radius:20,
  light:["#faf4f5","#fffafb","#f1e7eb","#e5d7dd","#43333c","#75616d","#89455f","#f0dfe7","#fffafd"],
  dark:["#261d23","#342831","#2d222b","#51404c","#f5edf1","#c1aab8","#e0aac3","#4b3343","#38202e"]},
 {id:"amber",name:"Amber",description:"Amber light and record sleeve texture",radius:9,
  light:["#fbf5e9","#fffbf1","#f0e7d5","#e4d6bb","#42372a","#77654c","#85501e","#f1dfbc","#fffbf3"],
  dark:["#251f18","#332c21","#2d261c","#51442f","#f4eddc","#c1b195","#e1bb79","#493b25","#35270f"]},
];

const systemTone = matchMedia("(prefers-color-scheme: dark)");
const cacheKey = "synomusic.skin";

/** 从已知皮肤中选择有效值，兼容旧设置及其他客户端传来的未知皮肤。 */
export function selectedSkin(id?:string):Skin { return skins.find(skin=>skin.id===id)||skins[0]; }

/** 保留跟随系统、浅色和深色三种模式，皮肤本身不强制改变用户的外观偏好。 */
export function appearanceTone(appearance?:string):Tone {
 return appearance==="dark"||(appearance!=="light"&&systemTone.matches)?"dark":"light";
}

/** 从皮肤配色派生统一界面变量，预览与实际窗口使用同一份颜色。 */
export function skinVariables(skin:Skin,tone:Tone):Record<string,string> {
 const [bg,surface,sidebar,line,text,muted,accent,soft,onAccent]=skin[tone];
 return {bg,surface,sidebar,line,text,muted,accent,soft,"on-accent":onAccent,
  glass:surface+"d9","stage-scrim":bg+"df","hero-scrim":soft+"dc",
  edge:tone==="dark"?line+"cc":"#ffffffb8",shadow:`0 18px 55px ${tone==="dark"?"#10171050":"#303b2814"}`,
  "skin-radius":`${skin.radius}px`};
}

/** 生成仅包含内置变量的缩略图样式，不接收服务器或用户提供的 CSS。 */
export function skinPreviewStyle(skin:Skin,appearance?:string):string {
 return Object.entries(skinVariables(skin,appearanceTone(appearance))).map(([key,value])=>`--${key}:${value}`).join(";");
}

/** 原地切换全窗口皮肤并更新预览；不重建媒体对象、页面或正在编辑的表单。 */
export function applySkin(settings:Record<string,string>,animate=false):void {
 const root=document.documentElement,skin=selectedSkin(settings.skin),tone=appearanceTone(settings.appearance);
 const changed=root.dataset.skin!==skin.id||root.dataset.tone!==tone;
 root.dataset.skin=skin.id;root.dataset.tone=tone;
 root.dataset.appearance=["light","dark"].includes(settings.appearance)?settings.appearance:"system";
 root.style.colorScheme=tone;
 for(const [key,value] of Object.entries(skinVariables(skin,tone)))root.style.setProperty(`--${key}`,value);
 document.querySelectorAll<HTMLElement>("[data-skin-preview]").forEach(node=>node.style.cssText=skinPreviewStyle(selectedSkin(node.dataset.skinPreview),settings.appearance));
 try{localStorage.setItem(cacheKey,JSON.stringify({skin:skin.id,appearance:root.dataset.appearance}));}catch{ /* 禁用本地缓存时仍可使用原生设置。 */ }
 if(animate&&changed&&!matchMedia("(prefers-reduced-motion: reduce)").matches)document.querySelector("#app")?.animate([{opacity:.72},{opacity:1}],{duration:260,easing:"ease-out"});
}

/** 首帧使用已缓存的外观，随后由原生保存的设置覆盖，避免启动时出现亮色闪烁。 */
export function restoreSkin():void {
 try{applySkin(JSON.parse(localStorage.getItem(cacheKey)||"{}"));}catch{applySkin({});}
}

/** 系统深浅色变化只更新主题变量，不打断播放或重建当前页面。 */
export function observeSystemAppearance(settings:()=>Record<string,string>,onChange:()=>void):void {
 systemTone.addEventListener("change",()=>{applySkin(settings(),true);onChange();});
}
