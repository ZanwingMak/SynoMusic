import { createIcons, icons } from "lucide";
import { Service, events, type State, type Song, type Playlist, type Profile, type Podcast, type RemotePlaylist } from "./mygo";
import { artwork } from "./artwork";
import { t, setLanguage, getLanguage, languages } from "./i18n";
import "./style.css";

const parameters = new URLSearchParams(location.search);
const demo = parameters.has("demo");
let cloudSupported = demo;
let platform = demo && parameters.get("platform") === "windows" ? "windows" : "darwin";
const app = document.querySelector<HTMLDivElement>("#app")!;
let state: State = { updatedAt: 0, cached: [], profiles: [], playlists: [], imports: [], history: [], favorites: [], settings: {}, lyrics: {}, podcasts: [] };
let songs: Song[] = [], shownSongs: Song[] = [], queue: Song[] = [], current = -1;
let source = "local", view = "library", search = "", busy = true, error = "", panel = "", lyrics = "";
let shuffle = false, repeat: "off" | "all" | "one" = "off", crossfading = false, playGeneration = 0;
let page = 0, queuePage = -1, resumePosition = 0, lastPlaybackSave = 0, nowPlaying = false;
let loadingTrack="";
let searchScope: "library" | "page" = "library";
let backStack: {view:string;search:string}[] = [], forwardStack: {view:string;search:string}[] = [];
const pageSize = 100;
let selected = new Set<string>();
let audio = new Audio(), otherAudio = new Audio();
audio.crossOrigin = "anonymous";otherAudio.crossOrigin = "anonymous";
let timer: ReturnType<typeof setTimeout> | undefined;
let audioContext: AudioContext | undefined;
let filters: BiquadFilterNode[] = [];
let shows: Podcast[] | null = null;
let serverPlaylists: RemotePlaylist[] = [], serverPlaylistSongs: Song[] = [];
let radioSongs: Song[] = [], cachedSongs: Song[] = [], episodeSongs: Song[] = [];
let lastUpdate = 0;
const downloadJobs: string[] = [];
let downloading = false, activeDownload = "", onlineKeyword = "", onlineError = "";
let loadGeneration=0, navigationGeneration=0, sleepDeadline=0, sleepMinutes=0;
const registeredSongs=new Set<string>();
let shuffleRemaining:string[]=[],shuffleHistory:string[]=[];
let modalFocus:HTMLElement|null=null;
let rendered = { content: "", panel: "", expanded: false, song: "", playing: false };
const nav = [["library","Library","library"],["albums","Albums","disc-3"],["artists","Artists","mic-2"],["songs","All songs","music-2"],["mixes","Smart mixes","sparkles"],["favorites","Favorites","heart"],["playlists","Playlists","list-music"],["server-playlists","Server playlists","server"],["folders","Folders","folders"],["genres","Genres","tags"],["local","Local music","folder-open"],["downloads","Downloads","download"],["history","History","history"],["radio","Radio","radio"],["podcasts","Podcasts","podcast"]];

/** 转义用户与服务器内容，禁止音乐标签被解释为 HTML。 */
function h(value: unknown): string { return String(value ?? "").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]!)); }
/** 创建统一图标标记。 */
function icon(name: string): string { return `<i data-lucide="${h(name)}" aria-hidden="true"></i>`; }
/** 将媒体地址转换为 Windows WebView2 支持的本机协议映射。 */
function mediaURL(address: string): string { return platform === "windows" ? address.replace(/^music:\/\/localhost\//, "http://music.localhost/") : address; }
/** 返回本地原创封面或后端代理的真实封面。 */
function cover(song: Song): string { return song.artwork ? mediaURL(song.artwork) : artwork(song.album || song.title); }
/** 将时长转换为播放器显示格式。 */
function duration(seconds: number): string { if (!Number.isFinite(seconds)||seconds<0) return "0:00";return `${Math.floor(seconds/60)}:${Math.floor(seconds%60).toString().padStart(2,"0")}`; }
/** 返回原生窗口或浏览器演示状态。 */
async function refreshState(): Promise<void> { if(!demo)state=await Service.snapshot();applySettings(); }
/** 将保存的外观偏好应用到窗口。 */
function applySettings(): void { document.documentElement.dataset.platform=platform; document.documentElement.dataset.appearance=state.settings.appearance||"system";if(state.settings.language)setLanguage(state.settings.language); }
/** 使用原创虚构音乐资料预览真实界面，不在正式应用中注入演示数据。 */
function demoState(): void {
 const albums=["Quiet Architecture","The Blue Hour","Soft Focus","After the Rain","A Place to Stay","Late Light","Sunday Morning","Open Water","Small Hours","Still Life","Golden Air","Slow Motion"];
 songs=albums.flatMap((album,i)=>[0,1,2].map(j=>({id:`demo-${i}-${j}`,profileID:"demo",title:["First Light","Somewhere, Slowly","Home Again"][j],artist:["SynoMusic Studio","The Quiet Ensemble","North Window","Soft Signals"][i%4],album,genre:["Ambient","Jazz","Acoustic"][i%3],duration:184+i*9+j*22,trackNumber:j+1,codec:"FLAC",artwork:artwork(album)})));
 state.profiles=[{id:"demo",providerType:"synologyAudioStation",name:t("Demo library"),host:"demo.local",port:5001,scheme:"https",username:"demo",isQuickConnect:false,ignoreInvalidCertificate:false}];
 state.favorites=[songs[0].id,songs[4].id];state.history=songs.slice(3,8);state.playlists=[{id:"evening",name:"Evening, uninterrupted",songs:songs.slice(0,8)}];source="demo";
 queue=[songs[0],songs[4],songs[8]];current=0;
}
/** 显示操作结果，不阻断当前播放。 */
function toast(message: string): void { document.querySelector(".toast")?.remove();const node=document.createElement("div");node.className="toast";node.role="status";node.textContent=message;document.body.append(node);setTimeout(()=>node.remove(),4500); }
/** 包装异步界面操作并呈现错误。 */
async function run(action:()=>Promise<unknown>): Promise<void> { try{await action();}catch(e){toast(e instanceof Error?e.message:String(e));} }
/** 登记已在后端加载的歌曲，离线播放无需重复请求服务器。 */
function registerSongs(list:Song[]): void { list.forEach(song=>registeredSongs.add(song.id)); }
/** 从保存快照登记跨资料库播放条目，只有缺失条目时才请求服务器。 */
async function ensureSong(song:Song): Promise<void> {
 if(demo||registeredSongs.has(song.id)||["local","radio","podcast"].includes(song.profileID))return;
 const cached=await Service.cachedLibrary(song.profileID);registerSongs(cached);
 if(!registeredSongs.has(song.id))registerSongs(await Service.songs(song.profileID));
}
/** 加载所选服务器的音乐库并保留可恢复的错误状态。 */
async function loadSource(id: string): Promise<void> {
 const generation=++loadGeneration;++navigationGeneration;const previousSongs=songs;source=id;error="";selected.clear();serverPlaylists=[];serverPlaylistSongs=[];songs=demo?previousSongs:[];busy=true;render();
 try{
  const cached=demo?songs:await Service.cachedLibrary(id);if(generation!==loadGeneration)return;
  if(cached.length){songs=cached;registerSongs(cached);busy=false;render();}
  const result=demo?songs:await Service.songs(id);if(generation!==loadGeneration)return;
  songs=result;registerSongs(result);state.settings.source=id;
  if(!demo)await Service.saveSettings(state.settings);
 }catch(e){if(generation!==loadGeneration)return;if(songs.length){toast(t("Using saved library. Server unavailable."));}else error=e instanceof Error?e.message:String(e);}
 finally{if(generation===loadGeneration){busy=false;render();}}
}
/** 按当前入口、专辑、艺人或歌单计算歌曲视图。 */
function visibleSongs(): Song[] {
 let result=songs;
 if(view==="downloads")result=cachedSongs;
 if(view==="radio")result=radioSongs;
 if(view.startsWith("podcast:"))result=episodeSongs;
 if(view==="favorites")result=songs.filter(s=>state.favorites.includes(s.id));
 if(view==="history")result=state.history||[];
 if(view==="local")result=state.imports||[];
 if(view.startsWith("album:"))result=songs.filter(s=>albumID(s)===view.slice(6)||s.album===view.slice(6));
 if(view.startsWith("artist:"))result=songs.filter(s=>s.artist===view.slice(7)||s.albumArtist===view.slice(7));
 if(view.startsWith("server-playlist:"))result=serverPlaylistSongs;
 else if(view.startsWith("genre:"))result=songs.filter(s=>s.genre===view.slice(6));
 else if(view.startsWith("folder:"))result=songs.filter(s=>folder(s)===view.slice(7));
 else if(view.startsWith("playlist:"))result=state.playlists.find(p=>p.id===view.slice(9))?.songs||[];
 if(view==="mixes")result=[...songs].sort((a,b)=>Number(state.favorites.includes(b.id))-Number(state.favorites.includes(a.id))||a.artist.localeCompare(b.artist)||a.title.localeCompare(b.title)).slice(0,60);
 const needle=search.trim().toLocaleLowerCase();if(needle&&searchScope==="library")result=songs;return orderSongs(needle?result.filter(s=>[s.title,s.artist,s.album,s.genre].some(v=>(v||"").toLocaleLowerCase().includes(needle))):result);
}
/** 根据本地文件或共享路径提取文件夹，远端不提供路径时使用专辑归类。 */
function folder(song: Song): string { const path=song.path||"";return !song.id.startsWith(song.profileID+":music_")&&/[\\/]/.test(path)?path.replace(/\\/g,"/").split("/").slice(0,-1).join("/")||song.album:song.album; }
/** 返回当前内容标题。 */
function title(): string { if(view.startsWith("server-playlist:"))return serverPlaylists.find(p=>p.id===view.slice(16))?.name||t("Server playlists");if(view.startsWith("genre:"))return view.slice(6);if(view.startsWith("folder:"))return view.slice(7); if(view.startsWith("podcast:"))return [...(shows||[]),...state.podcasts].find(p=>p.id===view.slice(8))?.title||t("Podcasts");if(view.startsWith("album:")){try{return JSON.parse(view.slice(6))[0];}catch{return view.slice(6);}}if(view.startsWith("artist:"))return view.slice(7);if(view.startsWith("playlist:"))return state.playlists.find(p=>p.id===view.slice(9))?.name||t("Playlists");return t(nav.find(n=>n[0]===view)?.[1]||"Settings"); }
/** 生成可聚焦的工具按钮。 */
function tool(action: string,name: string,label: string,active=false): string { return `<button class="icon-button${active?" active":""}" data-action="${action}" title="${h(t(label))}" aria-label="${h(t(label))}">${icon(name)}</button>`; }

/** 以专辑名和专辑艺人区分同名发行，兼容旧版仅存专辑名的入口。 */
function albumID(song: Song): string { return JSON.stringify([song.album || song.title, song.albumArtist || ""]); }
/** 返回独立专辑，合辑优先使用服务器提供的专辑艺人。 */
function uniqueAlbums(list: Song[]): Song[] { return [...new Map(list.map(song=>[albumID(song),song])).values()]; }
/** 将时长格式化为合集概要。 */
function collectionDuration(list: Song[]): string { const minutes=Math.round(list.reduce((total,song)=>total+song.duration,0)/60);return minutes>=60?`${Math.floor(minutes/60)} ${t("hours")} ${minutes%60} ${t("minutes")}`:`${minutes} ${t("minutes")}`; }
/** 按用户选择稳定排序；专辑默认按碟号与音轨播放。 */
function orderSongs(list: Song[]): Song[] {
 const key=state.settings.librarySort||"default";
 if(key==="default")return view.startsWith("album:")?[...list].sort((a,b)=>(a.discNumber||0)-(b.discNumber||0)||a.trackNumber-b.trackNumber):list;
 const direction=state.settings.sortDescending==="true"?-1:1;
 return [...list].sort((a,b)=>direction*(key==="duration"?a.duration-b.duration:key==="trackNumber"?((a.discNumber||0)-(b.discNumber||0)||a.trackNumber-b.trackNumber):String(a[key as keyof Song]||"").localeCompare(String(b[key as keyof Song]||""),getLanguage(),{numeric:true,sensitivity:"base"})));
}
/** 保存浏览历史并加载需要远端请求的页面。 */
async function navigate(destination: string, history=true): Promise<void> {
 const generation=++navigationGeneration,profile=source;
 if(history&&destination!==view){backStack.push({view,search});forwardStack=[];}
 view=destination;nowPlaying=false;search="";page=0;selected.clear();error="";busy=false;onlineError="";onlineKeyword="";
 try {
  if(destination==="server-playlists"||destination.startsWith("server-playlist:")){
   busy=true;render();
   if(destination==="server-playlists"){const result=demo?[{id:"demo-remote",name:"Evening, uninterrupted",count:8}]:await Service.serverPlaylists(profile);if(generation===navigationGeneration)serverPlaylists=result;}
   else{const result=demo?songs.slice(0,8):await Service.serverPlaylistSongs(profile,destination.slice(16));if(generation===navigationGeneration){serverPlaylistSongs=result;registerSongs(result);}}
  }
  if(destination==="downloads"){busy=true;render();const result=demo?songs:await Service.downloads();if(generation===navigationGeneration){cachedSongs=result;registerSongs(result);}}
  if(destination==="radio"){busy=true;render();const result=demo?songs:await Service.radio("");if(generation===navigationGeneration){radioSongs=result;registerSongs(result);}}
  if(destination==="podcasts")shows=null;
 }catch(e){if(generation===navigationGeneration)error=e instanceof Error?e.message:String(e);}
 finally{if(generation===navigationGeneration){busy=false;render();document.querySelector(".content")?.scrollTo(0,0);}}
}
/** 显示排序、搜索范围和多选操作，不让大资料库一次创建数千个控件。 */
function libraryControls(): string {
 return `<div class="library-controls"><label>${t("Sort by")}<select id="sort-library">${[["default","Default order"],["title","Title"],["artist","Artists"],["album","Albums"],["duration","Duration"],["trackNumber","Track number"]].map(([value,label])=>`<option value="${value}" ${(state.settings.librarySort||"default")===value?"selected":""}>${t(label)}</option>`).join("")}</select></label><button class="icon-button" data-action="sort-direction" title="${h(t(state.settings.sortDescending==="true"?"Descending":"Ascending"))}" aria-label="${h(t("Reverse sort"))}">${icon(state.settings.sortDescending==="true"?"arrow-down-wide-narrow":"arrow-up-wide-narrow")}</button><span class="selection-count">${selected.size?`${selected.size} ${t("Selected")}`:""}</span>${selected.size?`<button class="button subtle" data-action="add-selected">${t("Add to playlist")}</button><button class="button subtle" data-action="queue-selected">${t("Add to queue")}</button>`:""}<button class="button subtle" data-action="select-all">${t("Select all")}</button>${selected.size?`<button class="button subtle" data-action="clear-selection">${t("Clear selection")}</button>`:""}</div>`;
}
/** 绘制专辑或艺人详情及可操作的关联资料库入口。 */
function collectionHeader(): string {
 const first=shownSongs[0];if(!first)return "";
 const artist=view.startsWith("artist:");const names=[...new Set(shownSongs.map(song=>song.albumArtist||song.artist).filter(Boolean))];
 const artistName=names.length===1?names[0]:t("Various artists");
 return `<section class="collection-header ${artist?"artist-detail":""}"><img src="${h(cover(first))}" data-cover="${h(first.album)}" alt="${h(title())}"><div><p class="eyebrow">${t(artist?"Artists":"Albums")}</p><h1>${h(title())}</h1>${!artist?`<button class="text-link" data-view="artist:${h(artistName)}">${h(artistName)}</button>`:""}<p class="muted">${shownSongs.length} ${t("Tracks")} · ${collectionDuration(shownSongs)}${first.year?` · ${first.year}`:""}</p><div class="actions"><button class="button primary" data-action="play-all">${icon("play")}${t("Play all")}</button><button class="button" data-action="shuffle-all">${icon("shuffle")}${t("Shuffle")}</button><button class="button" data-action="queue-next-all">${icon("list-start")}${t("Play next")}</button><button class="button" data-action="queue-last-all">${icon("list-end")}${t("Add to queue")}</button></div></div></section>${artist?`<div class="section-title"><h2>${t("Albums")}</h2></div><div class="album-grid">${uniqueAlbums(shownSongs).map(albumCard).join("")}</div><div class="section-title"><h2>${t("All songs")}</h2></div>`:""}`;
}
/** 保存队列、当前位置和模式，恢复时保持暂停，避免启动时突然播放。 */
function savePlayback(): void {
 if(demo)return;
 try{localStorage.setItem("synomusic.playback",JSON.stringify({queue,current,position:audio.src?audio.currentTime:resumePosition,shuffle,repeat,shuffleRemaining,shuffleHistory}));}catch{ /* 浏览器存储不可用时仍允许继续播放。 */ }
}
/** 恢复上次播放的有效条目，使用新加载的音乐标签更新旧快照。 */
function restorePlayback(): void {
 if(demo)return;
 try{const saved=JSON.parse(localStorage.getItem("synomusic.playback")||"null");if(!saved||!Array.isArray(saved.queue))return;const known=new Map([...state.cached,...state.history,...songs].map(song=>[song.id,song]));queue=saved.queue.filter((song:Song)=>song&&typeof song.id==="string"&&typeof song.profileID==="string"&&typeof song.title==="string").slice(0,10000).map((song:Song)=>known.get(song.id)||song);current=queue.length?Math.max(0,Math.min(queue.length-1,Math.trunc(Number(saved.current)||0))):-1;resumePosition=Math.max(0,Number(saved.position)||0);if(queue[current]?.duration>0&&resumePosition>=queue[current].duration-1)resumePosition=0;shuffle=saved.shuffle===true;repeat=saved.repeat==="all"||saved.repeat==="one"?saved.repeat:"off";lyrics=state.lyrics[queue[current]?.id]||"";resetShuffle();if(Array.isArray(saved.shuffleRemaining))shuffleRemaining=saved.shuffleRemaining.filter((id:unknown)=>typeof id==="string"&&queue.some(song=>song.id===id));if(Array.isArray(saved.shuffleHistory))shuffleHistory=saved.shuffleHistory.filter((id:unknown)=>typeof id==="string"&&queue.some(song=>song.id===id));}catch{ /* 忽略损坏的旧播放现场，不影响资料库加载。 */ }
}
/** 修改队列并保持当前歌曲身份，删除当前项时立即切换或停止。 */
async function editQueue(index:number,operation:string,target=-1): Promise<void> {
 if(index<0||index>=queue.length)return;
 cancelTransition();const active=queue[current],wasPlaying=!audio.paused;queuePage=-1;
 if(operation==="remove")queue.splice(index,1);
 else{const destination=target>=0?target:index+(operation==="up"?-1:1);if(destination<0||destination>=queue.length)return;const [song]=queue.splice(index,1);queue.splice(destination,0,song);}
 if(operation==="remove"&&index===current){audio.pause();audio.removeAttribute("src");audio.load();resumePosition=0;current=queue.length?Math.min(index,queue.length-1):-1;if(wasPlaying&&current>=0)await play(current);else syncNowPlaying();}
 else current=queue.indexOf(active);
 resetShuffle();savePlayback();render();
}
/** 将歌曲添加到下一首或队尾；空队列只准备歌曲，不自动播放。 */
function enqueue(list:Song[],next=false): void { if(!list.length)return;queuePage=-1;cancelTransition();queue.splice(next?Math.max(0,current+1):queue.length,0,...list);if(current<0)current=0;resetShuffle();savePlayback();render();toast(t(next?"Play next":"Added to queue")); }
/** 用指针捕获完成窗口内拖放排序，保留歌曲按钮的普通点击行为。 */
function bindReorderRows(selector:string,move:(from:HTMLElement,to:HTMLElement)=>Promise<void>): void {
 document.querySelectorAll<HTMLElement>(selector).forEach(row=>{
  row.onpointerdown=event=>{
   const target=event.target as HTMLElement;
   if(event.button!==0||target.closest("button,input,summary,a")&&!target.closest("[data-reorder]"))return;
   event.preventDefault();row.setPointerCapture(event.pointerId);
   const x=event.clientX,y=event.clientY;let destination:HTMLElement|null=null;
   /** 清除本次拖动高亮与临时事件。 */
   const finish=():void=>{destination?.classList.remove("drop-target");row.onpointermove=null;row.onpointerup=null;row.onpointercancel=null;if(row.hasPointerCapture(event.pointerId))row.releasePointerCapture(event.pointerId);};
   row.onpointermove=pointer=>{destination?.classList.remove("drop-target");destination=document.elementFromPoint(pointer.clientX,pointer.clientY)?.closest<HTMLElement>(selector)||null;if(destination!==row)destination?.classList.add("drop-target");};
   row.onpointerup=pointer=>{const to=destination;finish();if(to&&to!==row&&Math.hypot(pointer.clientX-x,pointer.clientY-y)>6)void run(()=>move(row,to));};
   row.onpointercancel=finish;
  };
 });
}

/** 保存本地歌单编辑，先完成持久化再更新界面。 */
async function updatePlaylist(playlist:Playlist): Promise<void> { if(!demo)await Service.savePlaylist(playlist);state.playlists=state.playlists.map(item=>item.id===playlist.id?playlist:item);render(); }
/** 显示歌单重命名表单，提交前保留原名称。 */
function renamePlaylist(): void {
 const playlist=state.playlists.find(item=>item.id===view.slice(9));if(!playlist)return;
 modal(`<h2>${t("Rename playlist")}</h2><form id="rename-playlist"><label>${t("Name")}<input name="name" required value="${h(playlist.name)}"></label><div class="actions"><button class="button primary">${t("Save")}</button><button type="button" class="button" data-action="close-modal">${t("Cancel")}</button></div></form>`);
 document.querySelector<HTMLFormElement>("#rename-playlist")!.onsubmit=event=>{event.preventDefault();const name=String(new FormData(event.currentTarget as HTMLFormElement).get("name")||"").trim();if(name)void run(()=>updatePlaylist({...playlist,name}));};
}
/** 以只读信息展示音轨标签、音质和文件位置。 */
function trackInfo(song:Song): void {
 const fields=[["Title",song.title],["Artists",song.artist],["Albums",song.album],["Album artist",song.albumArtist],["Genres",song.genre],["Year",song.year],["Track number",song.trackNumber],["Disc number",song.discNumber],["Duration",duration(song.duration)],["Codec",song.codec?.toUpperCase()],["Bitrate",song.bitrate?`${Math.round(song.bitrate/1000)} kbps`:""],["Sample rate",song.sampleRate?`${song.sampleRate/1000} kHz`:""],["File path",song.path]];
 modal(`<h2>${t("Song information")}</h2><dl class="track-information">${fields.filter(([,value])=>value).map(([key,value])=>`<div><dt>${h(t(String(key)))}</dt><dd>${h(value)}</dd></div>`).join("")}</dl><button class="button" data-action="close-modal">${t("Close")}</button>`);
}

/** 按歌曲、专辑与艺人展示整个资料库的搜索结果。 */
function searchResults(): string {
 const albums=uniqueAlbums(shownSongs).slice(0,6);const artists=[...new Set(shownSongs.map(song=>song.artist).filter(Boolean))].slice(0,6);
 return `<div class="search-results-header"><p class="eyebrow">${t("Entire library")}</p><h1>${t("Search results")} · ${h(search)}</h1><p class="muted">${shownSongs.length} ${t("Tracks")}</p></div>${artists.length?`<div class="search-matches">${artists.map(name=>`<button class="button" data-view="artist:${h(name)}">${icon("mic-2")}${h(name)}</button>`).join("")}</div>`:""}${albums.length?`<div class="album-grid">${albums.map(albumCard).join("")}</div>`:""}${shownSongs.length?`${libraryControls()}${songTable(shownSongs)}`:`<p class="muted">${t("Try another search or connect another music source.")}</p>`}`;
}

/** 绘制完整桌面布局，播放器媒体对象独立于 DOM 保存。 */
function render(): void {
 const previous=rendered;
 shownSongs=visibleSongs();const count=view==="albums"?uniqueAlbums(shownSongs).length:shownSongs.length;page=Math.max(0,Math.min(page,Math.max(0,Math.ceil(count/pageSize)-1)));
 const closingPlayer=previous.expanded&&!nowPlaying?document.querySelector<HTMLElement>(".expanded-player"):null;
 const closingPanel=previous.panel&&previous.panel!==panel?document.querySelector<HTMLElement>(".detail-panel"):null;
 if(closingPanel)closingPanel.style.width=`${closingPanel.offsetWidth}px`;
 const scroll=document.querySelector(".content")?.scrollTop||0;
 rendered={content:JSON.stringify([source,view,page,busy,Boolean(search),searchScope]),panel,expanded:nowPlaying&&!!queue[current],song:queue[current]?.id||"",playing:!audio.paused};
 app.innerHTML=`<aside class="sidebar"><div class="traffic-space"></div><a class="brand" data-view="library"><span class="brand-mark">${icon("audio-lines")}</span>SynoMusic<span class="mac-label">${platform==="windows"?"WINDOWS":"MAC"}</span></a><div class="source-select">${icon("server")}<select id="source" aria-label="${h(t("Music source"))}"><option value="local" ${source==="local"?"selected":""}>${t("Local music")}</option>${state.profiles.map(p=>`<option value="${h(p.id)}" ${source===p.id?"selected":""}>${h(p.name)}</option>`).join("")}</select>${icon("chevrons-up-down")}</div><p class="nav-label">${t("Your sources")}</p><nav>${nav.map(([id,label,name],i)=>`${i===6?`<div class="nav-divider"></div>`:""}<button class="nav-item ${view===id?"selected":""}" data-view="${id}">${icon(name)}<span>${t(label)}</span>${id==="favorites"&&state.favorites.length?`<small>${state.favorites.length}</small>`:""}</button>`).join("")}</nav><button class="add-playlist" data-action="new-playlist">${icon("plus")} ${t("Create playlist")}</button><div class="sidebar-bottom"><span class="free-dot"></span><span>${t("All features. Always free.")}</span></div><button class="nav-item ${view==="settings"?"selected":""}" data-view="settings">${icon("settings-2")} ${t("Settings")}</button></aside><div class="workspace"><header class="toolbar"><div class="navigation-controls"><button class="icon-button" data-action="back" ${backStack.length?"":"disabled"} aria-label="${h(t("Back"))}">${icon("chevron-left")}</button><button class="icon-button" data-action="forward" ${forwardStack.length?"":"disabled"} aria-label="${h(t("Forward"))}">${icon("chevron-right")}</button></div><div class="breadcrumbs">${icon("panel-left")}<span>SynoMusic</span><span class="slash">/</span><strong>${h(title())}</strong></div><label class="search-field">${icon("search")}<input id="search" type="search" value="${h(search)}" placeholder="${h(t("Search your library"))}" autocomplete="off"><kbd>${platform==="windows"?"Ctrl":"⌘"} K</kbd></label><select id="search-scope" aria-label="${h(t("Search scope"))}"><option value="library" ${searchScope==="library"?"selected":""}>${t("Entire library")}</option><option value="page" ${searchScope==="page"?"selected":""}>${t("Current view")}</option></select>${tool("refresh","refresh-cw","Refresh")}${tool("server","plus","Add server")}</header><div class="content-split"><main class="content">${content()}</main>${panel?sidePanel():""}</div></div>${player()}<div id="modal-root"></div>`;
 app.classList.toggle("player-expanded",rendered.expanded);
 app.dataset.playing=String(rendered.playing);
 app.querySelectorAll<HTMLElement>(".sidebar,.workspace").forEach(node=>node.inert=rendered.expanded);
 createIcons({icons});bind();
 if(previous.content===rendered.content)document.querySelector(".content")?.scrollTo(0,scroll);
 animateRender(previous,closingPlayer,closingPanel);
 document.querySelectorAll<HTMLImageElement>("img[data-cover]").forEach(img=>img.addEventListener("error",()=>{img.src=artwork(img.dataset.cover||"SynoMusic");},{once:true}));
 updateProgress();
}
/** 使用局部过渡表现导航和播放器状态变化，普通数据刷新不重播整页动画。 */
function animateRender(previous:typeof rendered,closingPlayer:HTMLElement|null,closingPanel:HTMLElement|null): void {
 if(matchMedia("(prefers-reduced-motion: reduce)").matches)return;
 const easing="cubic-bezier(0.16, 1, 0.3, 1)";
 /** 播放短暂的合成层动画，完成后由浏览器释放效果。 */
 const enter=(selector:string,frames:Keyframe[],duration=280,delay=0):void=>{document.querySelector(selector)?.animate(frames,{duration,delay,easing,fill:"backwards"});};
 /** 保留正在退出的可视层，禁用交互并在动画结束后移除。 */
 const leave=(node:HTMLElement,host:Element,transform:string):void=>{
  node.inert=true;node.setAttribute("aria-hidden","true");node.classList.add("motion-exit");host.append(node);
  const animation=node.animate([{opacity:1,transform:"translateY(0)"},{opacity:0,transform}],{duration:220,easing:"cubic-bezier(0.4, 0, 1, 1)",fill:"forwards"});
  void animation.finished.finally(()=>node.remove()).catch(()=>{});
 };
 if(previous.content!==rendered.content&&!rendered.expanded)enter(".content",[{opacity:.01,transform:"translateY(10px)"},{opacity:1,transform:"translateY(0)"}]);
 if(rendered.panel&&previous.panel!==rendered.panel)enter(".detail-panel",[{opacity:.01,transform:"translateX(24px)"},{opacity:1,transform:"translateX(0)"}],320);
 if(closingPanel)leave(closingPanel,document.querySelector(".content-split")!,"translateX(24px)");
 if(rendered.expanded&&!previous.expanded){
  enter(".expanded-player",[{opacity:.01,transform:"translateY(36px)"},{opacity:1,transform:"translateY(0)"}],380);
  enter(".expanded-art",[{opacity:.01,transform:"translateY(22px) scale(.96)"},{opacity:1,transform:"translateY(0) scale(1)"}],440,30);
  enter(".expanded-lyrics",[{opacity:.01,transform:"translateY(16px)"},{opacity:1,transform:"translateY(0)"}],380,90);
 }
 if(closingPlayer)leave(closingPlayer,app,"translateY(32px)");
 if(previous.song&&previous.song!==rendered.song){
  enter(".now-playing>div",[{opacity:.01,transform:"translateY(5px)"},{opacity:1,transform:"translateY(0)"}]);
  if(rendered.expanded&&previous.expanded)enter(".expanded-art",[{opacity:.2,transform:"scale(.98)"},{opacity:1,transform:"scale(1)"}],360);
 }
 if(previous.playing!==rendered.playing)enter(".play-button svg",[{opacity:.3,transform:"scale(.7)"},{opacity:1,transform:"scale(1)"}],200);
}

/** 在线搜索保留输入和失败状态，空搜索结果不会回退成已订阅节目。 */
function onlineContent(): string {
 const podcast=view==="podcasts",items=shows??state.podcasts;
 const heading=`<div class="page-heading"><p class="eyebrow">${podcast?"ON DEMAND":"ON AIR"}</p><h1>${t(podcast?"Podcasts":"Radio")}</h1></div><form id="online-search" class="online-search"><input name="keyword" value="${h(onlineKeyword)}" aria-label="${h(t(podcast?"Search podcasts":"Search radio"))}" placeholder="${h(t(podcast?"Search podcasts":"Search radio"))}" required><button class="button primary" type="submit" ${busy?"disabled":""} aria-label="${h(t("Search"))}">${icon(busy?"loader-circle":"search")}</button></form>`;
 if(busy)return heading+`<p class="muted" role="status">${t("Fetching your music…")}</p>`;
 if(error||onlineError)return heading+`<p class="form-error" role="alert">${h(error||onlineError)}</p><button class="button" data-action="refresh">${t("Refresh")}</button>`;
 if(podcast)return heading+(items.length?`<div class="podcast-grid">${items.map(p=>`<article class="podcast-card"><img src="${h(p.artworkURL||artwork(p.title))}" data-cover="${h(p.title)}" alt=""><h3>${h(p.title)}</h3><p>${h(p.author)}</p><div><button class="button" data-podcast="${h(p.id)}">${t("Episodes")}</button><button class="button subtle" data-subscribe="${h(p.id)}">${t(state.podcasts.some(item=>item.id===p.id)?"Subscribed":"Subscribe")}</button></div></article>`).join("")}</div>`:`<p class="muted">${t(shows===null?"Search for a podcast to get started.":"No results")}</p>`);
 return heading+(shownSongs.length?songTable(shownSongs):`<p class="muted">${t("No results")}</p>`);
}

/** 绘制资料库、网格、歌单或设置内容。 */
function content(): string {
 if(search&&searchScope==="library")return searchResults();
 if(view==="settings")return settings();
 if(view==="radio"||view==="podcasts")return onlineContent();
 if(busy)return `<div class="page-heading"><p class="eyebrow">SYNO / MUSIC</p><h1>${h(title())}</h1></div><div class="loading-grid">${Array(8).fill('<div class="skeleton"></div>').join("")}</div><p class="muted">${t("Fetching your music…")}</p>`;
 if(error)return `<div class="empty-state">${icon("wifi-off")}<h2>${t("No results")}</h2><p>${h(error)}</p><button class="button primary" data-action="refresh">${t("Refresh")}</button></div>`;

 if(view==="server-playlists")return `<div class="page-heading"><p class="eyebrow">${h(t("Music source"))}</p><h1>${t("Server playlists")}</h1></div><div class="album-grid">${serverPlaylists.map(p=>`<button class="album-card" data-view="server-playlist:${h(p.id)}"><div class="playlist-art">${icon("list-music")}</div><h3>${h(p.name)}</h3><p>${p.count} ${t("Tracks")}</p></button>`).join("")}</div>`;
 if(view==="folders"||view==="genres"){const isFolder=view==="folders";const values=[...new Set(songs.map(song=>isFolder?folder(song):song.genre).filter(Boolean))].sort();return `<div class="page-heading"><h1>${h(title())}</h1></div><div class="album-grid">${values.map(value=>`<button class="album-card" data-view="${isFolder?"folder":"genre"}:${h(value)}"><div class="playlist-art">${icon(isFolder?"folder":"tag")}</div><h3>${h(value)}</h3></button>`).join("")}</div>`;}
 if(view==="playlists")return `<div class="page-heading"><p class="eyebrow">MADE BY YOU</p><h1>${t("Playlists")}</h1><button class="button primary" data-action="new-playlist">${icon("plus")}${t("Create playlist")}</button></div><div class="album-grid">${state.playlists.map(p=>`<button class="album-card" data-view="playlist:${h(p.id)}"><img src="${artwork(p.name)}" alt=""><strong>${h(p.name)}</strong><span>${p.songs.length} ${t("All songs").toLowerCase()}</span></button>`).join("")}</div>`;
 if(!shownSongs.length&&view.startsWith("playlist:"))return `<div class="page-heading"><h1>${h(title())}</h1><p class="muted">0 ${t("Tracks")}</p><div class="actions"><button class="button" data-action="rename-playlist">${t("Rename playlist")}</button><button class="button" data-action="delete-playlist">${t("Remove")}</button></div></div>`;
 if(!shownSongs.length&&!search&&["downloads","favorites","history"].includes(view))return `<div class="empty-state">${icon(view==="downloads"?"download":view==="favorites"?"heart":"history")}<h1>${h(title())}</h1><p>${t(view==="downloads"?"No downloads yet":view==="favorites"?"No favorites yet":"No listening history yet")}</p><button class="button" data-view="songs">${t("Browse your own collection")}</button></div>`;
 if(!shownSongs.length&&view.startsWith("server-playlist:"))return `<div class="page-heading"><h1>${h(title())}</h1><p class="muted">${t("This playlist is empty")}</p></div>`;
 if(!shownSongs.length)return `<div class="empty-state">${icon(search?"search-x":"disc-3")}<p class="eyebrow">YOUR OWN MUSIC, EVERYWHERE</p><h1>${t(search?"No results":"No music yet")}</h1><p>${t(search?"Try another search or connect another music source.":"Connect your server or import a music folder to get started.")}</p><div class="actions"><button class="button primary" data-action="server">${icon("plus")}${t("Connect a server")}</button><button class="button" data-action="import">${icon("folder-open")}${t("Import music")}</button></div><span class="free-message">${icon("heart")}${t("All features. Always free.")}</span></div>`;
 const albums=uniqueAlbums(shownSongs);
 if(view==="library"&&!search){const first=albums[0];return `<div class="page-heading"><p class="eyebrow">${demo?t("Demo library"):"YOUR PERSONAL SOUNDTRACK"}</p><h1>${t("Your music. Your space.")}</h1><p>${t("Browse your own collection")}</p></div><section class="listening-banner"><div class="banner-copy"><span class="pill">${icon("headphones")} ${t("Ready to listen")}</span><h2>${t("Made for a little more listening.")}</h2><p>${shownSongs.length} ${t("All songs").toLowerCase()} <span>·</span> ${albums.length} ${t("Albums").toLowerCase()} <span>·</span> ${t("Original quality")}</p><div class="actions"><button class="button primary" data-action="play-all">${icon("play")}${t("Play all")}</button><button class="button glass" data-action="shuffle-all">${icon("shuffle")}${t("Shuffle")}</button></div></div><div class="banner-record"><img src="${h(cover(first))}" data-cover="${h(first.album)}" alt="${h(first.album)}"><div class="vinyl"><span></span></div></div></section><div class="section-title"><h2>${t("Albums")}</h2><button data-view="albums">${t("Albums")} ${icon("arrow-up-right")}</button></div><div class="album-grid">${albums.slice(0,10).map(albumCard).join("")}</div><div class="section-title"><h2>${t("Favorites, in one place")}</h2><button data-view="favorites" aria-label="${h(t("Favorites"))}">${icon("arrow-up-right")}</button></div>${songTable(shownSongs.filter(song=>state.favorites.includes(song.id)).slice(0,5))}`;}
 if(view==="albums")return `<div class="page-heading"><p class="eyebrow">${t("Browse by album")}</p><h1>${t("Albums")} <small>${albums.length}</small></h1></div>${libraryControls()}<div class="album-grid">${albums.slice(page*pageSize,(page+1)*pageSize).map(albumCard).join("")}</div>${pagination(albums.length)}`;
 if(view==="artists"){const artists=[...new Set(shownSongs.map(s=>s.artist||""))];return `<div class="page-heading"><p class="eyebrow">${t("Browse by artist")}</p><h1>${t("Artists")} <small>${artists.length}</small></h1></div><div class="artist-grid">${artists.map(name=>`<button class="artist-card" data-view="artist:${h(name)}"><img src="${h(cover(shownSongs.find(song=>song.artist===name)||shownSongs[0]))}" data-cover="${h(name)}" alt=""><strong>${h(name||t("Unknown artist"))}</strong><span>${shownSongs.filter(s=>s.artist===name).length} ${t("All songs").toLowerCase()}</span></button>`).join("")}</div>`;}
 if(view.startsWith("album:")||view.startsWith("artist:"))return `${collectionHeader()}${libraryControls()}${songTable(shownSongs)}`;
 return `<div class="page-heading"><p class="eyebrow">${view==="history"?t("Recently played"):t("Browse your own collection")}</p><h1>${h(title())} <small>${shownSongs.length}</small></h1><div class="actions"><button class="button primary" data-action="play-all">${icon("play")}${t("Play all")}</button><button class="button" data-action="shuffle-all">${icon("shuffle")}${t("Shuffle")}</button>${selected.size?`<button class="button" data-action="add-selected">${icon("list-plus")}${t("Add selected to playlist")} (${selected.size})</button>`:""}${view.startsWith("playlist:")?`<button class="button" data-action="rename-playlist">${icon("pencil")}${t("Rename playlist")}</button><button class="button" data-action="delete-playlist">${icon("trash-2")}${t("Remove")}</button>`:""}</div></div>${libraryControls()}${songTable(shownSongs)}`;
}
/** 绘制带真实内容与键盘可访问入口的专辑封面。 */
function albumCard(song: Song): string { return `<button class="album-card" data-view="album:${h(albumID(song))}"><div class="album-cover"><img loading="lazy" src="${h(cover(song))}" data-cover="${h(song.album)}" alt="${h(song.album)}"><span class="cover-play">${icon("play")}</span>${song.codec?`<span class="codec">${h((song.codec||"").toUpperCase())}</span>`:""}</div><strong>${h(song.album||song.title)}</strong><span>${h(song.artist)}</span></button>`; }
/** 绘制歌曲列表与选择、收藏、下载和歌单操作。 */
function songTable(list: Song[]): string {
 const paged=list.length>pageSize?list.slice(page*pageSize,(page+1)*pageSize):list;
 return `<div class="song-table ${view.startsWith("playlist:")?"editable-playlist":""}"><div class="song-row table-header"><span>#</span><span>${t("All songs")}</span><span>${t("Albums")}</span><span>${icon("clock-3")}</span><span></span></div>${paged.map((song,i)=>`<div class="song-row ${queue[current]?.id===song.id?"playing":""}" data-song-id="${h(song.id)}" ${view.startsWith("playlist:")?'data-reorderable="true"':""}><label class="track-number"><span>${queue[current]?.id===song.id?icon("audio-lines"):song.trackNumber&&view.startsWith("album:")?song.trackNumber:page*pageSize+i+1}</span><input type="checkbox" data-select="${h(song.id)}" ${selected.has(song.id)?"checked":""} aria-label="${h(song.title)}"></label><button class="song-info" data-play="${h(song.id)}"><img loading="lazy" src="${h(cover(song))}" data-cover="${h(song.album)}" alt=""><span><strong>${h(song.title)}</strong><small>${h(song.artist)}</small></span></button><button class="album-text" data-view="album:${h(albumID(song))}">${h(song.album)}</button><span class="track-duration">${duration(song.duration)}</span><div class="song-actions">${view.startsWith("playlist:")?`<button class="icon-button reorder-handle" data-reorder aria-label="${h(t("Reorder"))}">${icon("grip-vertical")}</button>`:""}<button class="icon-button ${state.favorites.includes(song.id)?"hearted":""}" data-favorite="${h(song.id)}" aria-label="${h(t("Favorites"))}">${icon("heart")}</button><details class="track-menu"><summary aria-label="${h(t("More actions"))}">${icon("ellipsis")}</summary><div><button data-queue="${h(song.id)}">${icon("list-start")}${t("Play next")}</button><button data-queue-last="${h(song.id)}">${icon("list-end")}${t("Add to queue")}</button><button data-add="${h(song.id)}">${icon("list-plus")}${t("Add to playlist")}</button><button data-view="artist:${h(song.artist)}">${icon("mic-2")}${t("Go to artist")}</button><button data-info="${h(song.id)}">${icon("info")}${t("Song information")}</button>${view==="downloads"?`<button data-remove-download="${h(song.id)}">${icon("trash-2")}${t("Remove download")}</button>`:!["local","radio"].includes(song.profileID)?`<button data-download="${h(song.id)}" ${cachedSongs.some(item=>item.id===song.id)||activeDownload===song.id||downloadJobs.includes(song.id)?"disabled":""}>${icon("download")}${t(cachedSongs.some(item=>item.id===song.id)?"Downloaded":activeDownload===song.id||downloadJobs.includes(song.id)?"Downloading…":"Download")}</button>`:""}${view.startsWith("playlist:")?`<button data-playlist-remove="${h(song.id)}">${icon("list-minus")}${t("Remove from playlist")}</button>`:""}</div></details></div></div>`).join("")}</div>${list.length>pageSize?pagination(list.length):""}`;
}
/** 分页只影响显示，播放全部和搜索仍使用完整资料库。 */
function pagination(count:number): string { if(count<=pageSize)return "";const total=Math.ceil(count/pageSize);return `<div class="pagination"><button class="button" data-page="${page-1}" ${page===0?"disabled":""}>${t("Previous page")}</button><span>${page*pageSize+1}–${Math.min((page+1)*pageSize,count)} / ${count}</span><button class="button" data-page="${page+1}" ${page+1>=total?"disabled":""}>${t("Next page")}</button></div>`; }
/** 绘制与主内容独立滚动的播放队列或同步歌词。 */
function sidePanel(): string {
 const queueStart=queuePage<0?Math.floor(Math.max(0,current)/100)*100:queuePage*100;
 return `<aside class="detail-panel"><div class="panel-heading"><h3>${t(panel==="lyrics"?"Lyrics":"Queue")}</h3>${tool("close-panel","x","Close")}</div>${panel==="lyrics"?`<div class="lyric-tools"><button class="button subtle" data-action="edit-lyrics">${icon("pencil")}${t("Edit lyrics")}</button></div><div class="lyrics-content" style="font-size:${Number(state.settings.lyricSize)||24}px">${lyricLines().length?lyricLines().map(line=>`<button class="lyric-line" data-seek="${line.time}">${h(line.text)}</button>`).join(""):`<p class="muted">${t("No lyrics available")}</p>`}</div>`:`<div class="queue-summary"><p>${queue.length} ${t("Tracks")} · ${collectionDuration(queue)}</p>${queue.length>100?`<div class="queue-pages"><button class="icon-button" data-queue-page="${Math.floor(queueStart/100)-1}" ${queueStart===0?"disabled":""} aria-label="${h(t("Previous page"))}">${icon("chevron-left")}</button><span>${queueStart+1}–${Math.min(queueStart+100,queue.length)}</span><button class="icon-button" data-queue-page="${Math.floor(queueStart/100)+1}" ${queueStart+100>=queue.length?"disabled":""} aria-label="${h(t("Next page"))}">${icon("chevron-right")}</button></div>`:""}<div class="actions"><button class="button subtle" data-action="save-queue" ${queue.length?"":"disabled"}>${t("Save as playlist")}</button><button class="button subtle" data-action="clear-queue" ${queue.length?"":"disabled"}>${t("Clear")}</button></div></div><div class="queue-list">${queue.length?queue.slice(queueStart,queueStart+100).map((song,offset)=>{const i=queueStart+offset;return `<div class="queue-row ${i===current?"current":""}" data-queue-row="${i}"><button class="queue-item" data-queue-index="${i}"><img loading="lazy" src="${h(cover(song))}" data-cover="${h(song.album)}" alt=""><span><strong>${h(song.title)}</strong><small>${h(song.artist)} · ${duration(song.duration)}</small></span>${i===current?icon("audio-lines"):""}</button><div class="queue-actions"><button class="icon-button reorder-handle" data-reorder aria-label="${h(t("Reorder"))}">${icon("grip-vertical")}</button><button class="icon-button" data-queue-edit="up" data-index="${i}" ${i===0?"disabled":""} aria-label="${h(t("Move up"))}">${icon("chevron-up")}</button><button class="icon-button" data-queue-edit="down" data-index="${i}" ${i+1===queue.length?"disabled":""} aria-label="${h(t("Move down"))}">${icon("chevron-down")}</button><button class="icon-button" data-queue-edit="remove" data-index="${i}" aria-label="${h(t("Remove from queue"))}">${icon("x")}</button></div></div>`;}).join(""):`<p class="muted">${t("Queue is empty")}</p>`}</div>`}</aside>`;
}
/** 解析带多时间标签的 LRC，保留没有时间标签的纯文本。 */
function lyricLines(): {time:number;text:string}[] { return lyrics.split("\n").flatMap(line=>{const tags=[...line.matchAll(/\[(\d+):(\d+(?:\.\d+)?)\]/g)];const text=line.replace(/\[[^\]]*\]/g,"").trim();return text?(tags.length?tags.map(m=>({time:Number(m[1])*60+Number(m[2]),text})):[{time:-1,text}]):[];}).sort((a,b)=>a.time-b.time); }
/** 为当前歌曲读取歌词，并忽略已切换歌曲的过期响应。 */
function requestLyrics(): void {
 const song=queue[current],generation=playGeneration;if(!song||demo)return;
 void Service.lyrics(song.id).then(text=>{if(generation===playGeneration&&queue[current]?.id===song.id){lyrics=text;refreshLyrics();}}).catch(()=>{});
}
/** 歌词请求完成时只更新歌词区，保留正在进行的播放器展开动画。 */
function refreshLyrics(): void {
 const lines=lyricLines();
 document.querySelectorAll<HTMLElement>(".lyrics-content").forEach(container=>{
  container.innerHTML=lines.length?lines.map(line=>`<button class="lyric-line" data-seek="${line.time}">${h(line.text)}</button>`).join(""):`<p class="muted">${t("No lyrics available")}</p>`;
  container.querySelectorAll<HTMLElement>("[data-seek]").forEach(node=>node.onclick=()=>{const time=Number(node.dataset.seek);if(time>=0)seekPosition(time);});
 });
 updateProgress();
}
/** 绘制常驻播放器，切页时保持播放位置与队列。 */
function player(): string { const song=queue[current];return `${nowPlaying?expandedPlayer():""}<footer class="player-bar"><div class="now-playing">${song?`<button class="cover-expand" data-action="now-playing" aria-label="${h(t("Now playing"))}"><img class="now-cover" src="${h(cover(song))}" data-cover="${h(song.album)}" alt=""></button><div><strong>${h(song.title)}</strong><span>${h(song.artist)}</span></div><button class="icon-button ${state.favorites.includes(song.id)?"hearted":""}" data-favorite="${h(song.id)}" aria-label="${h(t("Favorites"))}">${icon("heart")}</button>`:`<div class="now-placeholder">${icon("music-2")}</div><div><strong>SynoMusic</strong><span>${t("Ready to listen")}</span></div>`}</div><div class="transport"><div class="transport-buttons">${tool("shuffle","shuffle","Shuffle",shuffle)}${tool("previous","skip-back","Previous track")}<button class="play-button ${loadingTrack?"is-loading":""}" data-action="toggle" aria-label="${h(t(loadingTrack?"Cancel":audio.paused?"Play":"Pause"))}">${icon(loadingTrack?"loader-circle":audio.paused?"play":"pause")}</button>${tool("next","skip-forward","Next track")}${tool("repeat",repeat==="one"?"repeat-1":"repeat",repeat==="one"?"Repeat one":repeat==="all"?"Repeat all":"Repeat off",repeat!=="off")}</div><div class="timeline"><span id="position">0:00</span><input id="progress" type="range" min="0" max="${Number.isFinite(audio.duration)?audio.duration:song?.duration||1}" step="0.1" value="${audio.currentTime}" ${song?.profileID==="radio"?"disabled":""} aria-label="${h(t("Playback position"))}"><span id="duration">${duration(audio.duration||song?.duration||0)}</span></div></div><div class="player-tools">${platform==="darwin"?tool("airplay","airplay","Playback"):""}${icon("volume-2")}<input id="volume" type="range" min="0" max="1" step="0.01" value="${audio.volume}" aria-label="${h(t("Volume"))}">${tool("lyrics","captions","Lyrics",panel==="lyrics")}${tool("queue","list-music","Queue",panel==="queue")}${tool("now-playing",nowPlaying?"minimize-2":"maximize-2","Now playing",nowPlaying)}</div></footer>`; }
/** 绘制所有免费设置以及隐私与官方链接。 */
function settings(): string {
 const setting=(label:string,control:string)=>`<label class="setting-row"><span>${t(label)}</span>${control}</label>`;
 return `<div class="page-heading"><p class="eyebrow">MAKE YOURSELF AT HOME</p><h1>${t("Settings")}</h1></div><div class="settings-body"><h2>${t("General")}</h2>${setting("Language",`<select id="language">${languages.map(([code,name])=>`<option value="${code}" ${getLanguage()===code?"selected":""}>${name}</option>`).join("")}</select>`)}${setting("Appearance",`<select data-setting="appearance">${["system","light","dark"].map(v=>`<option value="${v}" ${state.settings.appearance===v?"selected":""}>${t(v[0].toUpperCase()+v.slice(1))}</option>`).join("")}</select>`)}<h2>${t("Playback")}</h2>${setting("Crossfade",`<select data-setting="crossfade"><option value="0">${t("Off")}</option>${[2,4,6,8].map(n=>`<option value="${n}" ${Number(state.settings.crossfade)===n?"selected":""}>${n} s</option>`).join("")}</select>`)}${setting("Equalizer",`<select data-setting="equalizer">${["Flat","Bass","Acoustic","Vocal","Electronic"].map(v=>`<option ${state.settings.equalizer===v?"selected":""}>${v}</option>`).join("")}</select>`)}${setting("Sleep timer",`<select id="sleep"><option value="0" ${sleepDeadline?"":"selected"}>${t("Off")}</option>${[15,30,45,60,90].map(n=>`<option value="${n}" ${sleepDeadline&&sleepMinutes===n?"selected":""}>${n} ${t("minutes")}</option>`).join("")}</select>`)}${setting("Lyric offset",`<input data-setting="lyricOffset" type="number" min="-60" max="60" step="0.5" value="${Number(state.settings.lyricOffset)||0}">`)}${setting("Text size",`<input data-setting="lyricSize" type="number" min="14" max="42" value="${Number(state.settings.lyricSize)||24}">`)}${platform==="darwin"&&cloudSupported?`<h2>iCloud</h2>${setting("iCloud sync",`<input data-setting="icloud" type="checkbox" ${state.settings.icloud==="true"?"checked":""}>`)}<div class="actions"><button class="button" data-action="sync-cloud">${icon("cloud")}${t("Sync now")}</button></div>${state.settings.lastCloudSync?`<p class="version-label">${h(new Date(state.settings.lastCloudSync).toLocaleString())}</p>`:""}`:""}<h2>${t("Server profiles")}</h2>${state.profiles.map(p=>`<div class="setting-row"><span><strong>${h(p.name)}</strong><small>${h(p.providerType)} · ${h(p.host)}</small></span><button class="button subtle" data-edit-server="${h(p.id)}" aria-label="${h(t("Edit server"))}">${icon("pencil")}</button><button class="button subtle" data-remove-server="${h(p.id)}" aria-label="${h(t("Remove server"))}">${icon("trash-2")}</button></div>`).join("")}<div class="actions"><button class="button" data-action="server">${icon("plus")}${t("Add server")}</button><button class="button" data-action="export">${icon("upload")}${t("Export servers")}</button><button class="button" data-action="import-profiles">${icon("download")}${t("Import servers")}</button></div><div class="support-callout">${icon("heart")}<div><h3>${t("All features. Always free.")}</h3><p>${t("Support is optional. Music is for everyone.")}</p></div><button class="button" data-action="support">${t("View on iPhone")}${icon("arrow-up-right")}</button></div><div class="legal-links">${[["Website","https://zanwingmak.github.io/SynoMusic/"],["Source code","https://github.com/ZanwingMak/SynoMusic"],["Privacy policy","https://zanwingmak.github.io/SynoMusic/privacy.html"],["Terms of use","https://zanwingmak.github.io/SynoMusic/terms.html"]].map(([text,url])=>`<button data-link="${url}">${t(text)}${icon("arrow-up-right")}</button>`).join("")}</div><p class="version-label">SynoMusic for ${platform==="windows"?"Windows":"Mac"} · 1.6.3 · MyGo</p></div>`;
}
/** 播放登记过的歌曲，避免多个异步播放请求交错覆盖状态。 */
async function play(index: number, position=0, sequence=false): Promise<void> {
 if(!queue.length)return;cancelTransition();current=(index+queue.length)%queue.length;queuePage=-1;const song=queue[current];const generation=playGeneration;if(!sequence)resetShuffle();
 if(demo){render();return;}
 loadingTrack=song.id;render();
 try{
 audio.pause();
 await ensureSong(song);if(generation!==playGeneration)return;
 if(song.duration>0&&position>=song.duration-1)position=0;
 if(position>0)audio.addEventListener("loadedmetadata",()=>{if(generation===playGeneration)audio.currentTime=position;},{once:true});
 resumePosition=0;audio.src=mediaURL(`music://localhost/stream/${encodeURIComponent(song.id)}`);audio.volume=Math.min(1,Math.max(0,Number(state.settings.volume??"0.7")||0));
 lyrics="";
 if(state.settings.equalizer&&state.settings.equalizer!=="Flat")setupEQ();
 await audioContext?.resume();
 await audio.play();if(generation!==playGeneration)return;
 if(Number.isFinite(audio.duration)&&audio.duration>0)song.duration=audio.duration;
 await Service.recordPlay(song);state.history=[song,...state.history.filter(s=>s.id!==song.id)].slice(0,500);syncNowPlaying();render();
 void Service.lyrics(song.id).then(text=>{if(generation!==playGeneration)return;lyrics=text;if(panel==="lyrics"||nowPlaying)refreshLyrics();}).catch(()=>{});
 }catch(error){if(generation!==playGeneration)return;audio.pause();throw error;}finally{if(generation===playGeneration){loadingTrack="";render();}}
}
/** 重建本轮随机候选，保证一轮内不会重复播放同一歌曲。 */
function resetShuffle(): void { shuffleRemaining=[...new Set(queue.filter((_,i)=>i!==current).map(song=>song.id))];shuffleHistory=[]; }
/** 停止所有音频通道并更新系统状态，适用于暂停、队列结束和睡眠计时。 */
function pausePlayback(): void { cancelTransition();audio.pause();syncNowPlaying();render(); }
/** 根据实际播放历史返回上一首，已播放超过三秒时优先回到曲首。 */
async function previousTrack(): Promise<void> {
 if((audio.src?audio.currentTime:resumePosition)>3){seekPosition(0);return;}
 const previous=shuffle?shuffleHistory.pop():undefined;
 if(shuffle&&!previous){seekPosition(0);return;}
 const index=previous?queue.findIndex(song=>song.id===previous):Math.max(0,current-1);
 if(shuffle&&queue[current])shuffleRemaining.unshift(queue[current].id);
 await play(Math.max(0,index),0,true);
}
/** 按当前列表开始顺序或随机播放。 */
async function playList(list: Song[],random=false): Promise<void> { shuffle=random;queue=[...list];if(random){for(let i=queue.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[queue[i],queue[j]]=[queue[j],queue[i]];}}await play(0);savePlayback(); }
/** 播放或暂停，不改变队列位置。 */
async function toggle(): Promise<void> { if(!queue[current]){await playList(shownSongs);return;}if(demo)return;if(loadingTrack){pausePlayback();return;}if(audio.paused){if(!audio.src){await play(current,resumePosition);return;}await audioContext?.resume();await audio.play();}else {cancelTransition();audio.pause();}syncNowPlaying();render(); }
/** 播放下一首，列表结束后根据循环设置决定是否停止。 */
async function next(): Promise<void> {
 if(!queue.length)return;
 if(shuffle){
  shuffleRemaining=shuffleRemaining.filter(id=>id!==queue[current]?.id&&queue.some(song=>song.id===id));
  if(!shuffleRemaining.length){if(repeat!=="all"){pausePlayback();return;}resetShuffle();}
  if(!shuffleRemaining.length){await play(current,0,true);return;}
  const [id]=shuffleRemaining.splice(Math.floor(Math.random()*shuffleRemaining.length),1);shuffleHistory.push(queue[current].id);
  await play(queue.findIndex(song=>song.id===id),0,true);return;
 }
 if(current+1>=queue.length&&repeat!=="all"){pausePlayback();return;}
 await play(current+1,0,true);
}
/** 跳转播放位置，同时允许在恢复后的暂停状态预设起播点。 */
function seekPosition(position:number): void { if(!Number.isFinite(position)||position<0||!queue[current]||queue[current].profileID==="radio")return;const end=Number.isFinite(audio.duration)?audio.duration:queue[current].duration;position=end>0?Math.min(position,end):position;if(crossfading)cancelTransition();if(audio.src)audio.currentTime=position;else resumePosition=position;syncNowPlaying();updateProgress(); }
/** 展开专辑封面和同步歌词，继续使用底部同一套播放控件。 */
function expandedPlayer(): string {
 const song=queue[current];if(!song)return "";
 return `<section class="expanded-player" aria-label="${h(t("Now playing"))}"><header class="expanded-heading"><span>${t("Now playing")}</span>${tool("now-playing","chevron-down","Close")}</header><div class="expanded-content"><div class="expanded-art"><img src="${h(cover(song))}" data-cover="${h(song.album)}" alt="${h(song.album)}"><h1>${h(song.title)}</h1><button class="text-link" data-view="artist:${h(song.artist)}">${h(song.artist)}</button><p class="muted">${h(song.album)} · ${h((song.codec||"").toUpperCase())}</p></div><div class="expanded-lyrics"><div class="panel-heading"><h3>${t("Lyrics")}</h3>${tool("edit-lyrics","pencil","Edit lyrics")}</div><div class="lyrics-content">${lyricLines().length?lyricLines().map(line=>`<button class="lyric-line" data-seek="${line.time}">${h(line.text)}</button>`).join(""):`<p class="muted">${t("No lyrics available")}</p>`}</div></div></div></section>`;
}

/** 更新系统媒体中心，调用只在播放状态变化时触发。 */
function syncNowPlaying(): void { savePlayback();const song=queue[current];if(song&&!demo)void Service.updateNowPlaying({...song,duration:Number.isFinite(audio.duration)?audio.duration:song.duration},!audio.paused,audio.src?audio.currentTime:resumePosition).catch(()=>{}); }
/** 更新进度与歌词高亮，避免每秒重建界面或中断输入。 */
function updateProgress(): void {
 if(!audio.paused&&performance.now()-lastPlaybackSave>5000){lastPlaybackSave=performance.now();savePlayback();}
 const progress=document.querySelector<HTMLInputElement>("#progress");if(progress){progress.max=String(Number.isFinite(audio.duration)?audio.duration:queue[current]?.duration||1);progress.value=String(audio.src?audio.currentTime:resumePosition);progress.style.setProperty("--progress",`${audio.currentTime/Number(progress.max)*100||0}%`);}
 const position=document.querySelector("#position");if(position)position.textContent=duration(audio.src?audio.currentTime:resumePosition);const end=document.querySelector("#duration");if(end)end.textContent=queue[current]?.profileID==="radio"?t("Live"):duration(audio.duration||queue[current]?.duration||0);
 if(panel==="lyrics"||nowPlaying){const lines=lyricLines();const position=audio.currentTime+Number(state.settings.lyricOffset||0);let active=-1;lines.forEach((line,i)=>{if(line.time>=0&&line.time<=position)active=i;});document.querySelectorAll<HTMLElement>(".lyric-line").forEach((line,i)=>{const was=line.classList.contains("current");line.classList.toggle("current",i===active);if(i===active&&!was){const container=line.closest<HTMLElement>(".expanded-lyrics,.detail-panel");if(container){const offset=line.getBoundingClientRect().top-container.getBoundingClientRect().top;container.scrollTo({top:container.scrollTop+offset-container.clientHeight/2+line.clientHeight/2,behavior:matchMedia("(prefers-reduced-motion: reduce)").matches?"instant":"smooth"});}}});}
}
/** 将单首或批量选择的歌曲加入用户选定的歌单。 */
function playlistModal(items: Song[]): void {
 modal(`<h2>${t("Add to playlist")}</h2><form id="add-to-playlist"><label>${t("Playlists")}<select name="playlist">${state.playlists.map(p=>`<option value="${h(p.id)}">${h(p.name)}</option>`).join("")}</select></label><label>${t("Create playlist")}<input name="newName" placeholder="${h(t("Name"))}"></label><div class="actions"><button class="button primary" type="submit">${t("Save")}</button><button class="button" type="button" data-action="close-modal">${t("Cancel")}</button></div></form>`);
 document.querySelector<HTMLFormElement>("#add-to-playlist")!.onsubmit=e=>{e.preventDefault();void run(async()=>{const data=new FormData(e.currentTarget as HTMLFormElement);let playlist=state.playlists.find(p=>p.id===data.get("playlist"));const name=String(data.get("newName")||"").trim();if(name){playlist=demo?{id:crypto.randomUUID(),name,songs:[]}:await Service.createPlaylist(name);state.playlists.push(playlist);}if(!playlist)throw new Error(t("Create playlist"));const seen=new Set(playlist.songs.map(s=>s.id));const updated={...playlist,songs:[...playlist.songs,...items.filter(s=>!seen.has(s.id))]};if(!demo)await Service.savePlaylist(updated);state.playlists=state.playlists.map(item=>item.id===updated.id?updated:item);selected.clear();render();toast(t("Save"));});};
}
/** 显示原生窗口中的可关闭表单弹层。 */
function modal(content: string): void { modalFocus=document.activeElement as HTMLElement;const root=document.querySelector("#modal-root")!;root.innerHTML=`<div class="modal-backdrop"><section role="dialog" aria-modal="true" aria-label="SynoMusic" class="modal">${content}</section></div>`;createIcons({icons});root.querySelector<HTMLElement>("input,textarea,button")?.focus();root.querySelectorAll<HTMLElement>('[data-action="close-modal"]').forEach(node=>node.onclick=closeModal); }
/** 收起弹窗时完成退出动画，再释放表单和遮罩。 */
function closeModal(): void {
 const backdrop=document.querySelector<HTMLElement>(".modal-backdrop");if(!backdrop)return;
 if(matchMedia("(prefers-reduced-motion: reduce)").matches){backdrop.remove();modalFocus?.focus();return;}
 backdrop.inert=true;
 backdrop.querySelector(".modal")?.animate([{opacity:1,transform:"scale(1)"},{opacity:0,transform:"translateY(8px) scale(.98)"}],{duration:160,fill:"forwards"});
 void backdrop.animate([{opacity:1},{opacity:0}],{duration:180,fill:"forwards"}).finished.finally(()=>{backdrop.remove();modalFocus?.focus();}).catch(()=>{});
}
/** 显示服务器配置表单，敏感凭证不预填或保存到网页。 */
function serverModal(profile?: Profile): void {
 const p=profile||{id:"",providerType:"synologyAudioStation",name:"",host:"",port:0,scheme:"https",username:"",ignoreInvalidCertificate:false,isQuickConnect:false};
 modal(`<h2>${t(p.id?"Edit server":"Add server")}</h2><form id="server-form"><label>${t("Music source")}<select name="providerType">${[["synologyAudioStation","Synology Audio Station"],["plex","Plex"],["jellyfin","Jellyfin"],["emby","Emby"],["webDAV","WebDAV"],["smb","SMB"]].map(([id,name])=>`<option value="${id}" ${p.providerType===id?"selected":""}>${name}</option>`).join("")}</select></label><div class="form-grid"><label>${t("Name")}<input name="name" value="${h(p.name)}" required></label><label>${t("Server address")}<input name="host" value="${h(profile&&p.providerType!=="smb"?`${p.scheme}://${p.host.includes(":")?`[${p.host}]`:p.host}${p.port?`:${p.port}`:""}${profile.basePath||""}`:p.host)}" placeholder="https://nas.example.com:5001" required></label><label>${t("Username")}<input name="username" value="${h(p.username)}" autocomplete="username"></label><label>${t("Password / token")}<input name="password" type="password" autocomplete="current-password"></label><label>QuickConnect ID<input name="quickConnectID" value="${h(p.quickConnectID||"")}"></label><label>OTP<input name="otp" autocomplete="one-time-code" inputmode="numeric"></label><label>${t("Library ID (optional)")}<input name="musicLibraryID" value="${h(p.musicLibraryID||"")}"></label><label>${t("Share / folder")}<input name="folder" value="${h(p.folder||"")}" placeholder="Music"></label></div><label class="checkbox-label"><input name="trust" type="checkbox" ${p.ignoreInvalidCertificate?"checked":""}>${t("Trust self-signed certificate")}</label><p class="form-error" role="alert"></p><div class="actions"><button class="button primary" type="submit">${t("Connect")}</button><button class="button" type="button" data-action="close-modal">${t("Cancel")}</button></div></form>`);
 document.querySelector<HTMLFormElement>("#server-form")!.onsubmit=event=>{event.preventDefault();const form=event.currentTarget as HTMLFormElement;const data=new FormData(form);const button=form.querySelector<HTMLButtonElement>('[type="submit"]')!;button.disabled=true;button.textContent=t("Fetching your music…");void(async()=>{try{const qc=String(data.get("quickConnectID")||"").trim();const saved:Profile={...p,name:String(data.get("name")),host:String(data.get("host")),basePath:"",providerType:String(data.get("providerType")),username:String(data.get("username")),port:profile?.port||0,quickConnectID:qc,isQuickConnect:!!qc,musicLibraryID:String(data.get("musicLibraryID")||""),folder:String(data.get("folder")||""),ignoreInvalidCertificate:data.has("trust")};const result=demo?{...saved,id:saved.id||crypto.randomUUID()}:await Service.saveProfile(saved,String(data.get("password")||""),String(data.get("otp")||""));if(demo){state.profiles.push(result);}else await refreshState();view="library";await loadSource(result.id);}catch(e){form.querySelector(".form-error")!.textContent=e instanceof Error?e.message:String(e);button.disabled=false;button.textContent=t("Connect");}})();};
}
/** 按顺序执行下载任务，并显示每个任务完成或失败的结果。 */
async function processDownloads(): Promise<void> {
 if(downloading)return;downloading=true;
 try{while(downloadJobs.length){activeDownload=downloadJobs.shift()!;render();try{if(!demo)await Service.download(activeDownload);cachedSongs=demo?[...cachedSongs,...songs.filter(song=>song.id===activeDownload&&!cachedSongs.some(item=>item.id===song.id))]:await Service.downloads();toast(`${t("Downloaded")} · ${songs.find(song=>song.id===activeDownload)?.title||""}`);}catch(e){toast(String(e));}}}
 finally{activeDownload="";downloading=false;render();}
}
/** 建立 Web Audio 均衡器链，供用户实时调整播放音色。 */
function setupEQ(): void { if(audioContext)return;audioContext=new AudioContext();const node=audioContext.createMediaElementSource(audio);const other=audioContext.createMediaElementSource(otherAudio);const input=audioContext.createGain();node.connect(input);other.connect(input);let previous:AudioNode=input;[60,230,910,3600,14000].forEach(frequency=>{const filter=audioContext!.createBiquadFilter();filter.type="peaking";filter.frequency.value=frequency;filter.Q.value=1;previous.connect(filter);previous=filter;filters.push(filter);});previous.connect(audioContext.destination);applyEQ(); }
/** 应用用户选择的均衡器预设。 */
function applyEQ(): void { const presets:Record<string,number[]>={Flat:[0,0,0,0,0],Bass:[6,4,0,-1,-2],Acoustic:[2,1,1,3,2],Vocal:[-2,-1,3,4,1],Electronic:[4,2,-2,1,4]};const gains=presets[state.settings.equalizer||"Flat"]||presets.Flat;filters.forEach((filter,i)=>filter.gain.value=gains[i]); }
/** 执行工具栏、菜单和快捷键共享的动作。 */
async function action(name: string): Promise<void> {
 if(name==="now-playing"){nowPlaying=!nowPlaying;if(nowPlaying)panel="";if(nowPlaying)requestLyrics();render();return;}
 if(name==="back"||name==="forward"){const from=name==="back"?backStack:forwardStack;const to=name==="back"?forwardStack:backStack;const target=from.pop();if(target){to.push({view,search});await navigate(target.view,false);search=target.search;render();}return;}
 if(name==="sort-direction"){state.settings.sortDescending=String(state.settings.sortDescending!=="true");page=0;if(!demo)await Service.saveSettings(state.settings);render();return;}
 if(name==="queue-selected"){enqueue(shownSongs.filter(song=>selected.has(song.id)));return;}
 if(name==="select-all"){shownSongs.forEach(song=>selected.add(song.id));render();return;}if(name==="clear-selection"){selected.clear();render();return;}
 if(name==="queue-next-all"||name==="queue-last-all"){enqueue(shownSongs,name==="queue-next-all");return;}
 if(name==="rename-playlist"){renamePlaylist();return;}
 if(name==="save-queue"){playlistModal(queue);return;}
 if(name==="clear-queue"){cancelTransition();audio.pause();audio.removeAttribute("src");audio.load();queue=[];current=-1;resumePosition=0;lyrics="";savePlayback();render();return;}
 if(name==="sync-cloud"){if(!demo){toast(t("Syncing…"));await Service.syncCloud();await refreshState();}render();toast(t("Sync now"));return;}
 if(name==="server"){serverModal();return;}if(name==="close-modal"){closeModal();return;}
 if(name==="play"){if(audio.paused)await toggle();return;}if(name==="pause"){pausePlayback();return;}
 if(name==="toggle"){await toggle();return;}if(name==="next"){await next();return;}if(name==="previous"){await previousTrack();return;}
 if(name==="shuffle"){shuffle=!shuffle;resetShuffle();savePlayback();render();return;}if(name==="repeat"){repeat=repeat==="off"?"all":repeat==="all"?"one":"off";savePlayback();render();return;}
 if(name==="play-all"||name==="shuffle-all"){await playList(shownSongs,name==="shuffle-all");return;}
 if(name==="queue"||name==="lyrics"){nowPlaying=false;panel=panel===name?"":name;if(panel==="lyrics")requestLyrics();render();return;}if(name==="close-panel"){panel="";render();return;}
 if(name==="refresh"){if(["radio","podcasts","downloads","server-playlists"].includes(view)||view.startsWith("server-playlist:"))await navigate(view,false);else await loadSource(source);return;}
 if(name==="import"){if(!demo){await Service.importMusic();await refreshState();}view="local";await loadSource("local");return;}
 if(name==="export"){if(!demo)await Service.exportProfiles();return;}if(name==="import-profiles"){if(!demo){await Service.importProfiles();await refreshState();}render();return;}
 if(name==="support"){if(!demo)await Service.openLink("https://apps.apple.com/app/id6784094020");return;}
 if(name==="airplay"){const player=audio as HTMLAudioElement&{webkitShowPlaybackTargetPicker?:()=>void};if(player.webkitShowPlaybackTargetPicker)player.webkitShowPlaybackTargetPicker();return;}
 if(name==="new-playlist"){playlistModal([]);return;}if(name==="add-selected"){playlistModal(shownSongs.filter(s=>selected.has(s.id)));return;}
 if(name==="delete-playlist"){const id=view.slice(9);if(!confirm(t("Remove")+"?"))return;if(!demo)await Service.deletePlaylist(id);state.playlists=state.playlists.filter(p=>p.id!==id);view="playlists";render();return;}
 if(name==="edit-lyrics"){modal(`<h2>${t("Edit lyrics")}</h2><form id="lyric-form"><textarea name="lyrics" rows="14">${h(lyrics)}</textarea><div class="actions"><button class="button primary">${t("Save")}</button><button type="button" class="button" data-action="close-modal">${t("Cancel")}</button></div></form>`);document.querySelector<HTMLFormElement>("#lyric-form")!.onsubmit=e=>{e.preventDefault();void run(async()=>{lyrics=String(new FormData(e.currentTarget as HTMLFormElement).get("lyrics")||"");if(queue[current]&&!demo)await Service.saveLyrics(queue[current].id,lyrics);render();});};return;}
}
/** 为当前 DOM 绑定用户操作，所有异步失败都有可见反馈。 */
function bind(): void {
 document.querySelectorAll<HTMLElement>("[data-queue-page]").forEach(node=>node.onclick=()=>{queuePage=Number(node.dataset.queuePage);render();});
 document.querySelectorAll<HTMLButtonElement>("[data-page]").forEach(node=>node.onclick=()=>{page=Number(node.dataset.page);render();document.querySelector(".content")?.scrollTo(0,0);});
 const sorting=document.querySelector<HTMLSelectElement>("#sort-library");if(sorting)sorting.onchange=()=>void run(async()=>{state.settings.librarySort=sorting.value;page=0;if(!demo)await Service.saveSettings(state.settings);render();});
 const scope=document.querySelector<HTMLSelectElement>("#search-scope");if(scope)scope.onchange=()=>{searchScope=scope.value==="page"?"page":"library";page=0;render();};
 document.querySelectorAll<HTMLElement>("[data-info]").forEach(node=>node.onclick=()=>{const song=shownSongs.find(item=>item.id===node.dataset.info);if(song)trackInfo(song);});
 document.querySelectorAll<HTMLElement>("[data-queue-edit]").forEach(node=>node.onclick=()=>void run(()=>editQueue(Number(node.dataset.index),node.dataset.queueEdit!)));
 bindReorderRows(".queue-row",(from,to)=>editQueue(Number(from.dataset.queueRow),"move",Number(to.dataset.queueRow)));
 document.querySelectorAll<HTMLElement>("[data-playlist-remove]").forEach(node=>node.onclick=()=>void run(async()=>{const playlist=state.playlists.find(item=>item.id===view.slice(9));if(playlist)await updatePlaylist({...playlist,songs:playlist.songs.filter(song=>song.id!==node.dataset.playlistRemove)});}));
 document.querySelectorAll<HTMLElement>(".song-row[data-song-id]").forEach(node=>{node.oncontextmenu=event=>{event.preventDefault();document.querySelectorAll<HTMLDetailsElement>(".track-menu[open]").forEach(menu=>menu.open=false);const menu=node.querySelector<HTMLDetailsElement>(".track-menu");if(menu)menu.open=true;};});
 bindReorderRows(".song-row[data-song-id]",async(from,to)=>{const playlist=state.playlists.find(item=>item.id===view.slice(9));if(!playlist)return;if(state.settings.librarySort&&state.settings.librarySort!=="default"){toast(t("Use default order to rearrange"));return;}const list=[...playlist.songs],start=list.findIndex(song=>song.id===from.dataset.songId),end=list.findIndex(song=>song.id===to.dataset.songId);if(start<0||end<0)return;const [song]=list.splice(start,1);list.splice(end,0,song);await updatePlaylist({...playlist,songs:list});});
 document.querySelectorAll<HTMLElement>("[data-view]").forEach(node=>node.onclick=()=>void run(()=>navigate(node.dataset.view!)));
 document.querySelectorAll<HTMLElement>("[data-action]").forEach(node=>node.onclick=()=>void run(()=>action(node.dataset.action!)));
 document.querySelectorAll<HTMLElement>("[data-play]").forEach(node=>node.onclick=()=>void run(async()=>{queue=[...shownSongs];await play(queue.findIndex(s=>s.id===node.dataset.play));}));
 document.querySelectorAll<HTMLElement>("[data-favorite]").forEach(node=>node.onclick=()=>void run(async()=>{const id=node.dataset.favorite!;if(!demo)await Service.toggleFavorite(id);state.favorites=state.favorites.includes(id)?state.favorites.filter(v=>v!==id):[...state.favorites,id];render();}));
 document.querySelectorAll<HTMLInputElement>("[data-select]").forEach(node=>node.onchange=()=>{if(node.checked)selected.add(node.dataset.select!);else selected.delete(node.dataset.select!);const focus=node.dataset.select;render();document.querySelector<HTMLInputElement>(`[data-select="${CSS.escape(focus!)}"]`)?.focus();});
 document.querySelectorAll<HTMLElement>("[data-add]").forEach(node=>node.onclick=()=>playlistModal(shownSongs.filter(s=>s.id===node.dataset.add)));
 document.querySelectorAll<HTMLElement>("[data-queue],[data-queue-last]").forEach(node=>node.onclick=()=>{const id=node.dataset.queue||node.dataset.queueLast;enqueue(shownSongs.filter(song=>song.id===id),!!node.dataset.queue);});
 document.querySelectorAll<HTMLElement>("[data-download]").forEach(node=>node.onclick=()=>{const id=node.dataset.download!;if(id===activeDownload||downloadJobs.includes(id))return;downloadJobs.push(id);void processDownloads();});
 document.querySelectorAll<HTMLElement>("[data-remove-download]").forEach(node=>node.onclick=()=>void run(async()=>{const id=node.dataset.removeDownload!;if(!demo)await Service.removeDownload(id);cachedSongs=cachedSongs.filter(song=>song.id!==id);render();toast(t("Download removed"));}));
 document.querySelectorAll<HTMLElement>("[data-queue-index]").forEach(node=>node.onclick=()=>void run(()=>play(Number(node.dataset.queueIndex))));
 document.querySelectorAll<HTMLElement>("[data-seek]").forEach(node=>node.onclick=()=>{const time=Number(node.dataset.seek);if(time>=0)seekPosition(time);});
 document.querySelectorAll<HTMLElement>("[data-link]").forEach(node=>node.onclick=()=>void run(async()=>{if(!demo)await Service.openLink(node.dataset.link!);}));
 document.querySelectorAll<HTMLElement>("[data-edit-server]").forEach(node=>node.onclick=()=>serverModal(state.profiles.find(p=>p.id===node.dataset.editServer)));
 document.querySelectorAll<HTMLElement>("[data-remove-server]").forEach(node=>node.onclick=()=>void run(async()=>{if(!confirm(t("Remove")+"?"))return;const id=node.dataset.removeServer!;if(!demo)await Service.removeProfile(id);state.profiles=state.profiles.filter(p=>p.id!==id);if(source===id){await loadSource("local");}else render();}));
 const searchInput=document.querySelector<HTMLInputElement>("#search")!;
 /** 搜索刷新后恢复光标，中文输入法组词期间保留原输入框。 */
 const updateSearch=(event:Event):void=>{if(event instanceof InputEvent&&event.isComposing)return;const start=searchInput.selectionStart,end=searchInput.selectionEnd;search=searchInput.value;page=0;render();const next=document.querySelector<HTMLInputElement>("#search")!;next.focus();next.setSelectionRange(start,end);};
 searchInput.oninput=updateSearch;searchInput.addEventListener("compositionend",updateSearch);
 document.querySelector<HTMLSelectElement>("#source")!.onchange=e=>{view="library";void run(()=>loadSource((e.target as HTMLSelectElement).value));};
 document.querySelector<HTMLInputElement>("#progress")!.oninput=e=>seekPosition(Number((e.target as HTMLInputElement).value));
 document.querySelector<HTMLInputElement>("#volume")!.oninput=e=>{audio.volume=Number((e.target as HTMLInputElement).value);state.settings.volume=String(audio.volume);if(!demo)void Service.saveSettings(state.settings).catch(e=>toast(String(e)));};
 const language=document.querySelector<HTMLSelectElement>("#language");if(language)language.onchange=()=>void run(async()=>{setLanguage(language.value);state.settings.language=language.value;if(!demo)await Service.saveSettings(state.settings);render();});
 document.querySelectorAll<HTMLInputElement|HTMLSelectElement>("[data-setting]").forEach(node=>node.onchange=()=>void run(async()=>{state.settings[node.dataset.setting!]=node instanceof HTMLInputElement&&node.type==="checkbox"?String(node.checked):node.value;if(node.dataset.setting==="equalizer"){setupEQ();await audioContext?.resume();applyEQ();}if(!demo)await Service.saveSettings(state.settings);applySettings();render();}));
 const sleep=document.querySelector<HTMLSelectElement>("#sleep");if(sleep)sleep.onchange=()=>{
  clearTimeout(timer);sleepMinutes=Number(sleep.value);sleepDeadline=sleepMinutes>0?Date.now()+sleepMinutes*60000:0;
  if(sleepDeadline){timer=setTimeout(()=>{sleepDeadline=0;sleepMinutes=0;pausePlayback();toast(t("Sleep timer finished"));},sleepMinutes*60000);toast(`${t("Sleep timer")} · ${sleepMinutes} ${t("minutes")}`);}
 };
 const online=document.querySelector<HTMLFormElement>("#online-search");if(online)online.onsubmit=e=>{
  e.preventDefault();onlineKeyword=String(new FormData(online).get("keyword")||"").trim();const keyword=onlineKeyword,destination=view,generation=++navigationGeneration;busy=true;error="";onlineError="";render();
  void(async()=>{try{if(destination==="radio"){const result=demo?songs:await Service.radio(keyword);if(generation===navigationGeneration){radioSongs=result;registerSongs(result);}}else{const result=demo?[]:await Service.searchPodcasts(keyword,getLanguage().startsWith("zh")?"CN":"US");if(generation===navigationGeneration)shows=result;}}catch(error){if(generation===navigationGeneration)onlineError=error instanceof Error?error.message:String(error);}finally{if(generation===navigationGeneration){busy=false;render();}}})();
 };

 document.querySelectorAll<HTMLElement>("[data-podcast]").forEach(node=>node.onclick=()=>{
  const show=[...(shows||[]),...state.podcasts].find(p=>p.id===node.dataset.podcast);if(!show)return;const generation=++navigationGeneration;busy=true;error="";render();
  void(async()=>{try{const result=demo?songs:await Service.podcastEpisodes(show);if(generation!==navigationGeneration)return;episodeSongs=result;registerSongs(result);backStack.push({view,search});view="podcast:"+show.id;search="";page=0;}catch(error){if(generation===navigationGeneration)onlineError=String(error);}finally{if(generation===navigationGeneration){busy=false;render();}}})();
 });

 document.querySelectorAll<HTMLElement>("[data-subscribe]").forEach(node=>node.onclick=()=>void run(async()=>{const show=[...(shows||[]),...state.podcasts].find(p=>p.id===node.dataset.subscribe);if(!show)return;const enabled=!state.podcasts.some(p=>p.id===show.id);if(!demo)await Service.subscribe(show,enabled);state.podcasts=state.podcasts.filter(p=>p.id!==show.id);if(enabled)state.podcasts.push(show);render();}));
}
/** 用户选曲或暂停时取消旧过渡，避免旧动画覆盖新播放请求。 */
function cancelTransition(): void { playGeneration++;loadingTrack="";crossfading=false;otherAudio.pause();audio.volume=Math.min(1,Math.max(0,Number(state.settings.volume??"0.7")||0)); }
/** 在同一播放代次内进行淡入淡出；用户选曲时立即停止旧动画。 */
async function crossfadeTick(): Promise<void> {
 const seconds=Number(state.settings.crossfade||0);if(shuffle||repeat==="one"||!seconds||crossfading||audio.paused||!Number.isFinite(audio.duration)||audio.duration-audio.currentTime>seconds||current+1>=queue.length||demo)return;
 const generation=playGeneration;crossfading=true;const nextSong=queue[current+1];otherAudio.onended=null;otherAudio.ontimeupdate=null;otherAudio.src=mediaURL(`music://localhost/stream/${encodeURIComponent(nextSong.id)}`);otherAudio.volume=0;
 try {
  await ensureSong(nextSong);if(generation!==playGeneration)return;
  await otherAudio.play();if(generation!==playGeneration)return;
  const started=performance.now();const volume=Number(state.settings.volume??"0.7");
  await new Promise<void>(resolve=>{const tick=()=>{if(generation!==playGeneration){resolve();return;}const ratio=Math.min((performance.now()-started)/(seconds*1000),1);audio.volume=volume*(1-ratio);otherAudio.volume=volume*ratio;if(ratio<1&&!audio.paused)requestAnimationFrame(tick);else resolve();};tick();});
  if(generation!==playGeneration)return;
  audio.pause();[audio,otherAudio]=[otherAudio,audio];current++;attachAudio();lyrics="";if(Number.isFinite(audio.duration)&&audio.duration>0)nextSong.duration=audio.duration;await Service.recordPlay(nextSong);syncNowPlaying();render();
  void Service.lyrics(nextSong.id).then(text=>{if(generation===playGeneration){lyrics=text;if(panel==="lyrics"||nowPlaying)refreshLyrics();}}).catch(()=>{});
 }catch(e){if(generation===playGeneration)toast(String(e));}finally{if(generation===playGeneration)crossfading=false;}
}
/** 给当前音频对象挂载播放事件，切换音频实例后重新绑定。 */
function attachAudio(): void { audio.setAttribute("x-webkit-airplay","allow");audio.onended=()=>{if(!crossfading)void run(()=>repeat==="one"?play(current):next());};audio.ontimeupdate=()=>{updateProgress();if(performance.now()-lastUpdate>1000){lastUpdate=performance.now();void crossfadeTick();}};audio.onerror=()=>toast(t("Playback unavailable. Check the source and audio format."));audio.onplay=()=>syncNowPlaying();audio.onpause=()=>syncNowPlaying(); }
/** 启动桌面应用，浏览器演示必须显式使用 demo 参数。 */
async function start(): Promise<void> {
 render();attachAudio();try{if(demo){demoState();applySettings();}else{platform=await Service.platform();cloudSupported=await Service.cloudSupported();await refreshState();audio.volume=Math.min(1,Math.max(0,Number(state.settings.volume??"0.7")||0));source=state.settings.source||state.profiles[0]?.id||"local";if(source!=="local"&&!state.profiles.some(profile=>profile.id===source))source="local";registerSongs([...state.cached,...state.imports,...state.history,...state.playlists.flatMap(list=>list.songs)]);cachedSongs=await Service.downloads();songs=await Service.cachedLibrary(source);registerSongs(songs);restorePlayback();busy=false;render();const profile=source,generation=loadGeneration;void(async()=>{try{const result=await Service.songs(profile);if(generation===loadGeneration&&source===profile){songs=result;registerSongs(result);render();}}catch(e){if(generation===loadGeneration&&source===profile)toast(songs.length?t("Using saved library. Server unavailable."):String(e));}})();}}catch(e){error=e instanceof Error?e.message:String(e);}finally{busy=false;render();}
 if(!demo&&platform==="darwin"&&cloudSupported&&state.settings.icloud==="true"){void run(async()=>{await Service.syncCloud();await refreshState();render();});setInterval(()=>{if(document.visibilityState==="visible")void run(async()=>{await Service.syncCloud();await refreshState();});},300000);}
 if(!demo){events.playbackCommand.on(command=>void run(()=>action(command)));events.navigationCommand.on(destination=>void run(()=>navigate(destination)));events.seekCommand.on(position=>seekPosition(position));}
 window.addEventListener("pagehide",savePlayback);
 document.addEventListener("keydown",e=>{
  const dialog=document.querySelector<HTMLElement>(".modal-backdrop");
  if(dialog){
   if(e.key==="Escape"){e.preventDefault();closeModal();}
   if(e.key==="Tab"){const nodes=[...dialog.querySelectorAll<HTMLElement>('button:not(:disabled),input:not(:disabled),select,textarea,a[href]')];const first=nodes[0],last=nodes[nodes.length-1];if(e.shiftKey&&document.activeElement===first){e.preventDefault();last?.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus();}}
   return;
  }
  const editing=(e.target as HTMLElement).matches("input,textarea,select,[contenteditable]");if((e.metaKey||e.ctrlKey)&&e.key.toLowerCase()==="k"){e.preventDefault();document.querySelector<HTMLInputElement>("#search")?.focus();}else if((e.altKey&&["ArrowLeft","ArrowRight"].includes(e.key))&&!editing){e.preventDefault();void run(()=>action(e.key==="ArrowLeft"?"back":"forward"));}else if((e.metaKey||e.ctrlKey)&&e.key.toLowerCase()==="a"&&!editing){e.preventDefault();void run(()=>action("select-all"));}else if(e.key==="Escape"){if(document.querySelector(".modal-backdrop")){closeModal();return;}if(nowPlaying){nowPlaying=false;render();}}else if(e.code==="Space"&&!editing&&!(e.target as HTMLElement).closest("button,a,summary")){e.preventDefault();void run(()=>toggle());}});
}
void start();
