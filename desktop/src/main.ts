import { createIcons, icons } from "lucide";
import { Service, events, type State, type Song, type Playlist, type Profile, type Podcast, type RemotePlaylist, type SmartPlaylist, type PlaylistRule } from "./mygo";
import { artwork } from "./artwork";
import { parseLyrics, activeLyric, type LyricLine } from "./lyrics";
import { t, setLanguage, getLanguage, languages } from "./i18n";
import "./style.css";
import "./visual.css";
import "./features.css";
import "./lyrics.css";
import { AudioEffects, equalizerBands, eqFrequencies } from "./audio-effects";
import { smartSongs, possibleDuplicates, listeningStats } from "./collection";
import { defaultShortcuts, shortcutChord, shortcutLabel, shortcuts } from "./shortcuts";

const parameters = new URLSearchParams(location.search);
const demo = parameters.has("demo");
let cloudSupported = demo;
let platform = demo && parameters.get("platform") === "windows" ? "windows" : "darwin";
const app = document.querySelector<HTMLDivElement>("#app")!;
let state: State = { updatedAt: 0, cached: [], profiles: [], playlists: [], imports: [], history: [], favorites: [], favoriteSongs: [], settings: {}, lyrics: {}, podcasts: [], stats: {} };
let songs: Song[] = [], shownSongs: Song[] = [], queue: Song[] = [], current = -1;
let source = "local", view = "library", search = "", busy = true, error = "", panel = "", lyrics = "";
let shuffle = false, repeat: "off" | "all" | "one" = "off", crossfading = false, playGeneration = 0;
let page = 0, queuePage = -1, resumePosition = 0, lastPlaybackSave = 0, nowPlaying = false;
let loadingTrack="";
let lyricsLoading=false,lyricsError="",lyricRequest=0,lyricsSong="";
let parsedLyricsText="",parsedLyrics:LyricLine[]=[],lyricScrollPausedUntil=0;
let searchScope: "library" | "page" = "library";
let backStack: {view:string;search:string}[] = [], forwardStack: {view:string;search:string}[] = [];
const pageSize = 100;
let selected = new Set<string>();
let audio = new Audio(), otherAudio = new Audio();
audio.crossOrigin = "anonymous";otherAudio.crossOrigin = "anonymous";
let timer: ReturnType<typeof setTimeout> | undefined;
const effects = new AudioEffects();
let miniMode=false,miniPinned=true,abStart:number|null=null,abEnd:number|null=null;
let listenedSeconds=0,lastListenPosition=0,playCountRecorded=false,spectrumFrame=0;
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
const nav = [["library","Library","library"],["favorites","Favorites","heart"],["playlists","Playlists","list-music"],["albums","Albums","disc-3"],["artists","Artists","mic-2"],["songs","All songs","music-2"],["mixes","Smart mixes","sparkles"],["server-playlists","Server playlists","server"],["folders","Folders","folders"],["genres","Genres","tags"],["local","Local music","folder-open"],["downloads","Downloads","download"],["history","History","history"],["statistics","Listening stats","chart-no-axes-combined"],["duplicates","Possible duplicates","copy"],["radio","Radio","radio"],["podcasts","Podcasts","podcast"]];

/** 转义用户与服务器内容，禁止音乐标签被解释为 HTML。 */
function h(value: unknown): string { return String(value ?? "").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]!)); }
/** 创建统一图标标记。 */
function icon(name: string): string { return `<i data-lucide="${h(name)}" aria-hidden="true"></i>`; }
/** 将媒体地址转换为 Windows WebView2 支持的本机协议映射。 */
function mediaURL(address: string): string { return platform === "windows" ? address.replace(/^music:\/\/localhost\//, "http://music.localhost/") : address; }
/** 返回本地原创封面或后端代理的真实封面。 */
function cover(song: Song): string { return song.artwork ? mediaURL(song.artwork) : artwork(song.album || song.title); }
/** 使用当前封面营造柔和环境色，图像层不参与交互或辅助阅读。 */
function ambientArtwork(song: Song): string {
 return `<div class="ambient-art" aria-hidden="true" style="--ambient-phase:-${Math.round(performance.now()/1000)%24}s"><img src="${h(cover(song))}" data-cover="${h(song.album)}" alt=""><img src="${h(cover(song))}" data-cover="${h(song.album)}" alt=""></div>`;
}
/** 绘制播放状态指示，只表达播放状态，不模拟音频频谱。 */
function playbackIndicator(): string { return '<span class="playback-indicator" aria-hidden="true"><span></span><span></span><span></span><span></span></span>'; }
/** 歌词加载、失败和纯文本使用独立状态，同步歌词可点击跳转到真实时间。 */
function lyricContent(): string {
 if(lyricsLoading)return `<div class="lyrics-empty" role="status">${icon("loader-circle")}<p>${t("Finding lyrics…")}</p></div>`;
 const lines=lyricLines();
 if(lines.length)return lines.map((line,index)=>line.time>=0?`<button class="lyric-line" data-lyric-index="${index}" data-seek="${line.time}" aria-label="${h(`${duration(line.time)} · ${line.text||t("Instrumental")}`)}">${h(line.text||"♪")}</button>`:`<p class="lyric-line plain-lyric">${h(line.text)}</p>`).join("");
 return `<div class="lyrics-empty"><span class="lyrics-empty-mark">${icon(lyricsError?"wifi-off":"audio-lines")}</span><p>${t(!queue[current]?"Choose a song to see lyrics":lyricsError?"Lyrics unavailable. Check your connection and retry.":"No lyrics available")}</p>${queue[current]?`<div class="actions"><button class="button subtle" data-action="retry-lyrics">${icon("refresh-cw")}${t("Retry")}</button><button class="button subtle" data-action="edit-lyrics">${icon("plus")}${t("Edit lyrics")}</button></div>`:""}</div>`;
}
/** 从收藏快照与已加载音乐源合并歌曲，切换音乐源和离线时不隐藏其他来源的收藏。 */
function favoriteSongs(): Song[] {
 const known=new Map([...state.favoriteSongs,...state.imports,...state.cached,...state.history,...state.playlists.flatMap(list=>list.songs),...songs,...queue].map(song=>[song.id,song]));
 const result=state.favorites.map(id=>known.get(id)).filter((song):song is Song=>!!song);
 return result.reverse();
}
/** 首页使用可见快捷入口，不要求滚过专辑区才能找到收藏与歌单。 */
function collectionShortcuts():string {
 return `<div class="collection-shortcuts"><button data-view="favorites">${icon("heart")}<span><strong>${t("Favorites")}</strong><small>${favoriteSongs().length} ${t("Tracks")}</small></span>${icon("arrow-up-right")}</button><button data-view="playlists">${icon("list-music")}<span><strong>${t("Playlists")}</strong><small>${state.playlists.length} ${t("Playlists")}</small></span>${icon("arrow-up-right")}</button></div>`;
}
/** 收藏集合默认展示全部音乐源，提供当前源筛选并保留播放、多选和歌单操作。 */
function favoritesContent():string {
 return `<div class="page-heading"><p class="eyebrow">${t("Favorites, in one place")}</p><h1>${t("Favorites")} <small>${shownSongs.length}</small></h1><div class="favorites-controls"><label>${t("Music source")}<select id="favorites-scope"><option value="all" ${state.settings.favoritesScope!=="current"?"selected":""}>${t("All sources")}</option><option value="current" ${state.settings.favoritesScope==="current"?"selected":""}>${h(state.profiles.find(profile=>profile.id===source)?.name||t("Local music"))}</option></select></label><div class="actions"><button class="button primary" data-action="play-all" ${shownSongs.length?"":"disabled"}>${icon("play")}${t("Play all")}</button><button class="button" data-action="shuffle-all" ${shownSongs.length?"":"disabled"}>${icon("shuffle")}${t("Shuffle")}</button></div></div></div>${shownSongs.length?`${libraryControls()}${songTable(shownSongs)}`:`<div class="favorites-empty">${icon("heart")}<p>${t("No favorites yet")}</p><button class="button" data-view="songs">${t("Browse your own collection")}</button></div>`}`;
}
/** 显示同步状态与跟随、设置和编辑操作，两处歌词视图保持相同行为。 */
function lyricToolbar():string {
 return `<div class="lyric-toolbar"><span class="lyric-status">${t(lyricsLoading?"Finding lyrics…":lyricLines().some(line=>line.time>=0)?"Synced lyrics":lyricLines().length?"Plain lyrics":"Lyrics")}</span><div>${tool("follow-lyrics","focus","Follow lyrics",state.settings.lyricAutoScroll!=="false")}${tool("lyric-settings","settings-2","Lyric settings")}${tool("edit-lyrics","pencil","Edit lyrics")}</div></div>`;
}
/** 将时长转换为播放器显示格式。 */
function duration(seconds: number): string { if (!Number.isFinite(seconds)||seconds<0) return "0:00";return `${Math.floor(seconds/60)}:${Math.floor(seconds%60).toString().padStart(2,"0")}`; }
/** 返回原生窗口或浏览器演示状态。 */
async function refreshState(): Promise<void> { if(!demo)state=await Service.snapshot();state.stats??={};state.favoriteSongs??=[];applySettings(); }
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
 if(view==="favorites")result=favoriteSongs().filter(song=>state.settings.favoritesScope!=="current"||song.profileID===source);
 if(view==="history")result=state.history||[];
 if(view==="local")result=state.imports||[];
 if(view.startsWith("album:"))result=songs.filter(s=>albumID(s)===view.slice(6)||s.album===view.slice(6));
 if(view.startsWith("artist:"))result=songs.filter(s=>s.artist===view.slice(7)||s.albumArtist===view.slice(7));
 if(view.startsWith("server-playlist:"))result=serverPlaylistSongs;
 else if(view.startsWith("genre:"))result=songs.filter(s=>s.genre===view.slice(6));
 else if(view.startsWith("folder:"))result=songs.filter(s=>folder(s)===view.slice(7));
 else if(view.startsWith("playlist:")){const playlist=state.playlists.find(p=>p.id===view.slice(9));result=playlist?.smart?smartSongs(songs,playlist.smart,state.stats,state.favorites,new Set(cachedSongs.map(song=>song.id))):playlist?.songs||[];}
 if(view==="duplicates")result=possibleDuplicates(songs);
 if(view==="statistics")result=listeningStats(songs,state.stats).top;
 if(view==="mixes")result=[...songs].sort((a,b)=>Number(state.favorites.includes(b.id))-Number(state.favorites.includes(a.id))||a.artist.localeCompare(b.artist)||a.title.localeCompare(b.title)).slice(0,60);
 const needle=search.trim().toLocaleLowerCase();if(needle&&searchScope==="library")result=songs;const filtered=needle?result.filter(s=>[s.title,s.artist,s.album,s.genre].some(v=>(v||"").toLocaleLowerCase().includes(needle))):result;return view.startsWith("playlist:")&&state.playlists.find(item=>item.id===view.slice(9))?.smart?filtered:orderSongs(filtered);
}
/** 根据本地文件或共享路径提取文件夹，远端不提供路径时使用专辑归类。 */
function folder(song: Song): string { const path=song.path||"";return /[\\/]/.test(path)?path.replace(/\\/g,"/").split("/").slice(0,-1).join("/")||song.album:song.album; }
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
 const smart=destination.startsWith("playlist:")?state.playlists.find(item=>item.id===destination.slice(9))?.smart:undefined;
 if(smart&&smart.sourceID!==source)await loadSource(smart.sourceID);
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
 const smart=view.startsWith("playlist:")&&state.playlists.find(item=>item.id===view.slice(9))?.smart;
 return `<div class="library-controls">${smart?`<span class="smart-badge">${icon("sparkles")}${t("Smart playlist")}</span><span class="smart-sort-hidden">`:""}<label>${t("Sort by")}<select id="sort-library">${[["default","Default order"],["title","Title"],["artist","Artists"],["album","Albums"],["duration","Duration"],["trackNumber","Track number"]].map(([value,label])=>`<option value="${value}" ${(state.settings.librarySort||"default")===value?"selected":""}>${t(label)}</option>`).join("")}</select></label><button class="icon-button" data-action="sort-direction" title="${h(t(state.settings.sortDescending==="true"?"Descending":"Ascending"))}" aria-label="${h(t("Reverse sort"))}">${icon(state.settings.sortDescending==="true"?"arrow-down-wide-narrow":"arrow-up-wide-narrow")}</button>${smart?"</span>":""}<span class="selection-count">${selected.size?`${selected.size} ${t("Selected")}`:""}</span>${selected.size?`<button class="button subtle" data-action="add-selected">${t("Add to playlist")}</button><button class="button subtle" data-action="queue-selected">${t("Add to queue")}</button>`:""}<button class="button subtle" data-action="select-all">${t("Select all")}</button>${selected.size?`<button class="button subtle" data-action="download-selected">${t("Download selected")}</button><button class="button subtle" data-action="clear-selection">${t("Clear selection")}</button>`:""}</div>`;
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
 const fields=[["Title",song.title],["Artists",song.artist],["Albums",song.album],["Album artist",song.albumArtist],["Genres",song.genre],["Year",song.year],["Track number",song.trackNumber],["Disc number",song.discNumber],["Duration",duration(song.duration)],["Codec",song.codec?.toUpperCase()],["Bitrate",song.bitrate?`${Math.round(song.bitrate/1000)} kbps`:""],["Sample rate",song.sampleRate?`${song.sampleRate/1000} kHz`:""],["Track gain",song.trackGain==null?"":`${song.trackGain} dB`],["Album gain",song.albumGain==null?"":`${song.albumGain} dB`],["File path",song.path]];
 modal(`<h2>${t("Song information")}</h2>${ratingControl(song)}<p class="audio-note muted">${t("Play count")}: ${state.stats[song.id]?.playCount||0}</p><dl class="track-information">${fields.filter(([,value])=>value).map(([key,value])=>`<div><dt>${h(t(String(key)))}</dt><dd>${h(value)}</dd></div>`).join("")}</dl><button class="button" data-action="close-modal">${t("Close")}</button>`);
}

/** 提供键盘可达的零到五星评分，不将评分与赞助状态关联。 */
function ratingControl(song:Song):string {
 const rating=state.stats[song.id]?.rating||0;
 return `<div class="rating-control" aria-label="${h(t("Rating"))}">${[1,2,3,4,5].map(value=>`<button class="${value<=rating?"rated":""}" data-rate-song="${h(song.id)}" data-rating="${value}" aria-pressed="${value===rating}" aria-label="${value}/5">${icon("star")}</button>`).join("")}<button class="clear-rating" data-rate-song="${h(song.id)}" data-rating="0">${t("Clear rating")}</button></div>`;
}

/** 展示真实累计统计，更新前没有记录的播放次数不作推算。 */
function statisticsContent():string {
 const stats=listeningStats(songs,state.stats);
 return `<div class="page-heading"><p class="eyebrow">${t("Your listening")}</p><h1>${t("Listening stats")}</h1></div><div class="stats-summary"><div><strong>${stats.plays}</strong><span>${t("Play count")}</span></div><div><strong>${stats.rated}</strong><span>${t("Rated tracks")}</span></div><div><strong>${state.favorites.length}</strong><span>${t("Favorites")}</span></div></div><div class="section-title"><h2>${t("Most played")}</h2></div>${stats.top.length?songTable(stats.top):`<p class="muted">${t("Listening statistics start from this update.")}</p>`}`;
}

/** 编辑可重复计算的智能歌单规则，并即时显示当前资料库的匹配数量。 */
function smartPlaylistModal(playlist?:Playlist):void {
 const initial=playlist?.smart||{sourceID:source,match:"all",rules:[{field:"favorite",operator:"equals",value:"true"}],sort:"title",descending:false,limit:100};
 const fields=[["title","Title"],["artist","Artists"],["album","Albums"],["genre","Genres"],["codec","Codec"],["year","Year"],["duration","Duration (seconds)"],["rating","Rating"],["playCount","Play count"],["lastPlayed","Last played"],["favorite","Favorites"],["downloaded","Downloaded"]];
 const numericFields=["year","duration","rating","playCount"],booleanFields=["favorite","downloaded"];
 /** 根据字段限制有效比较方式，避免向用户提供无意义的规则组合。 */
 const allowed=(field:string):string[]=>field==="lastPlayed"?["withinDays","olderDays"]:booleanFields.includes(field)?["equals","notEquals"]:numericFields.includes(field)?["equals","notEquals","greater","less"]:["contains","notContains","equals","notEquals"];
 const operators=[["contains","Contains"],["notContains","Does not contain"],["equals","Is"],["notEquals","Is not"],["greater","Greater than"],["less","Less than"],["withinDays","Within days"],["olderDays","Older than days"]];
 modal(`<h2>${t(playlist?"Edit smart playlist":"New smart playlist")}</h2><form id="smart-playlist-form"><label>${t("Name")}<input name="name" value="${h(playlist?.name||"")}" required></label><label>${t("Match rules")}<select name="match"><option value="all" ${initial.match==="all"?"selected":""}>${t("All rules")}</option><option value="any" ${initial.match==="any"?"selected":""}>${t("Any rule")}</option></select></label><div class="smart-rules"></div><button class="button subtle" type="button" id="add-smart-rule">${icon("plus")}${t("Add rule")}</button><div class="form-grid"><label>${t("Sort by")}<select name="sort">${fields.filter(([key])=>!["favorite","downloaded"].includes(key)).map(([key,label])=>`<option value="${key}" ${initial.sort===key?"selected":""}>${t(label)}</option>`).join("")}</select></label><label>${t("Limit tracks")}<input name="limit" type="number" min="0" max="10000" value="${initial.limit}"></label></div><label class="checkbox-label"><input type="checkbox" name="descending" ${initial.descending?"checked":""}>${t("Descending")}</label><p class="audio-note muted" id="smart-results"></p><p class="form-error" role="alert"></p><div class="actions"><button class="button primary" type="submit">${t("Save")}</button><button class="button" type="button" data-action="close-modal">${t("Cancel")}</button></div></form>`);
 const form=document.querySelector<HTMLFormElement>("#smart-playlist-form")!;
 /** 从可见表单读取全部规则，保留用户正在编辑的值。 */
 const read=():SmartPlaylist=>{
  const data=new FormData(form),ruleFields=data.getAll("ruleField"),ruleOperators=data.getAll("ruleOperator"),values=data.getAll("ruleValue");
  return {sourceID:initial.sourceID,match:String(data.get("match")),sort:String(data.get("sort")),descending:data.has("descending"),limit:Math.min(10000,Math.max(0,Number(data.get("limit"))||0)),rules:ruleFields.map((field,index)=>({field:String(field),operator:String(ruleOperators[index]),value:String(values[index])}))};
 };
 /** 以当前真实歌曲、评分与下载状态更新规则预览。 */
 const preview=():void=>{form.querySelector("#smart-results")!.textContent=`${smartSongs(songs,read(),state.stats,state.favorites,new Set(cachedSongs.map(song=>song.id))).length} ${t("Matching tracks")}`;};
 /** 只重建规则编辑行，避免干扰名称和排序控件。 */
 const draw=(rules:PlaylistRule[]):void=>{
  form.querySelector(".smart-rules")!.innerHTML=rules.map((rule,index)=>`<div class="smart-rule"><select name="ruleField" aria-label="${h(t("Rule field"))}">${fields.map(([value,label])=>`<option value="${value}" ${rule.field===value?"selected":""}>${t(label)}</option>`).join("")}</select><select name="ruleOperator" aria-label="${h(t("Rule operator"))}">${operators.filter(([value])=>allowed(rule.field).includes(value)).map(([value,label])=>`<option value="${value}" ${rule.operator===value?"selected":""}>${t(label)}</option>`).join("")}</select>${booleanFields.includes(rule.field)?`<select name="ruleValue" aria-label="${h(t("Rule value"))}"><option value="true" ${rule.value==="true"?"selected":""}>${t("Yes")}</option><option value="false" ${rule.value==="false"?"selected":""}>${t("No")}</option></select>`:`<input name="ruleValue" ${numericFields.includes(rule.field)||rule.field==="lastPlayed"?'type="number" min="0" step="any"':""} value="${h(rule.value)}" aria-label="${h(t("Rule value"))}">`}<button class="icon-button" type="button" data-remove-rule="${index}" aria-label="${h(t("Remove"))}">${icon("x")}</button></div>`).join("");
  form.querySelectorAll<HTMLElement>("[data-remove-rule]").forEach(button=>button.onclick=()=>draw(read().rules.filter((_,index)=>index!==Number(button.dataset.removeRule))));
  form.querySelectorAll<HTMLSelectElement>('[name="ruleField"]').forEach((select,index)=>select.onchange=()=>{const rules=read().rules;rules[index]={field:select.value,operator:allowed(select.value)[0],value:booleanFields.includes(select.value)?"true":select.value==="lastPlayed"?"30":numericFields.includes(select.value)?"0":""};draw(rules);form.querySelectorAll<HTMLElement>('[name="ruleValue"]')[index]?.focus();});
  createIcons({icons});preview();
 };
 draw(initial.rules);form.oninput=preview;
 form.querySelector<HTMLButtonElement>("#add-smart-rule")!.onclick=()=>{const rules=read().rules;if(rules.length<20)draw([...rules,{field:"genre",operator:"contains",value:""}]);};
 form.onsubmit=event=>{
  event.preventDefault();const name=String(new FormData(form).get("name")||"").trim();if(!name)return;
  const updated:Playlist={id:playlist?.id||"",name,songs:[],smart:read()};const button=form.querySelector<HTMLButtonElement>('[type="submit"]')!;button.disabled=true;
  void(async()=>{try{const saved=demo?{...updated,id:updated.id||crypto.randomUUID()}:await Service.saveSmartPlaylist(updated);state.playlists=[...state.playlists.filter(item=>item.id!==saved.id),saved];await navigate(`playlist:${saved.id}`);}catch(error){form.querySelector(".form-error")!.textContent=String(error);button.disabled=false;}})();
 };
}

/** 按歌曲、专辑与艺人展示整个资料库的搜索结果。 */
function searchResults(): string {
 const albums=uniqueAlbums(shownSongs).slice(0,6);const artists=[...new Set(shownSongs.map(song=>song.artist).filter(Boolean))].slice(0,6);
 return `<div class="search-results-header"><p class="eyebrow">${t("Entire library")}</p><h1>${t("Search results")} · ${h(search)}</h1><p class="muted">${shownSongs.length} ${t("Tracks")}</p></div>${artists.length?`<div class="search-matches">${artists.map(name=>`<button class="button" data-view="artist:${h(name)}">${icon("mic-2")}${h(name)}</button>`).join("")}</div>`:""}${albums.length?`<div class="album-grid">${albums.map(albumCard).join("")}</div>`:""}${shownSongs.length?`${libraryControls()}${songTable(shownSongs)}`:`<p class="muted">${t("Try another search or connect another music source.")}</p>`}`;
}

/** 绘制完整桌面布局，播放器媒体对象独立于 DOM 保存。 */
function render(): void {
 document.querySelectorAll(".artwork-flight").forEach(node=>node.remove());
 const previous=rendered;
 shownSongs=visibleSongs();const count=view==="albums"?uniqueAlbums(shownSongs).length:shownSongs.length;page=Math.max(0,Math.min(page,Math.max(0,Math.ceil(count/pageSize)-1)));
 const closingPlayer=previous.expanded&&!nowPlaying?document.querySelector<HTMLElement>(".expanded-player"):null;
 const closingPanel=previous.panel&&previous.panel!==panel?document.querySelector<HTMLElement>(".detail-panel"):null;
 const origin=previous.expanded!==nowPlaying?document.querySelector<HTMLImageElement>(previous.expanded?".expanded-cover>img":".now-cover"):null;
 const artworkOrigin=origin?{src:origin.currentSrc||origin.src,bounds:origin.getBoundingClientRect()}:null;
 if(closingPanel)closingPanel.style.width=`${closingPanel.offsetWidth}px`;
 const scroll=document.querySelector(".content")?.scrollTop||0;
 rendered={content:JSON.stringify([source,view,page,busy,Boolean(search),searchScope]),panel,expanded:nowPlaying&&!!queue[current],song:queue[current]?.id||"",playing:!audio.paused};
 app.innerHTML=`<div class="mini-heading"><span>${t("Now playing")}</span><div>${tool("pin-mini","pin","Always on top",miniPinned)}${tool("mini-player","expand","Full player")}</div></div><aside class="sidebar"><div class="traffic-space"></div><a class="brand" data-view="library"><span class="brand-mark">${icon("audio-lines")}</span>SynoMusic<span class="mac-label">${platform==="windows"?"WINDOWS":"MAC"}</span></a><div class="source-select">${icon("server")}<select id="source" aria-label="${h(t("Music source"))}"><option value="local" ${source==="local"?"selected":""}>${t("Local music")}</option>${state.profiles.map(p=>`<option value="${h(p.id)}" ${source===p.id?"selected":""}>${h(p.name)}</option>`).join("")}</select>${icon("chevrons-up-down")}</div><p class="nav-label">${t("Your sources")}</p><nav>${nav.map(([id,label,name],i)=>`${i===3?`<div class="nav-divider"></div>`:""}<button class="nav-item ${view===id?"selected":""}" data-view="${id}">${icon(name)}<span>${t(label)}</span>${id==="favorites"&&state.favorites.length?`<small>${state.favorites.length}</small>`:""}</button>`).join("")}</nav><button class="add-playlist" data-action="new-playlist">${icon("plus")} ${t("Create playlist")}</button><div class="sidebar-bottom"><span class="free-dot"></span><span>${t("All features. Always free.")}</span></div><button class="nav-item ${view==="settings"?"selected":""}" data-view="settings">${icon("settings-2")} ${t("Settings")}</button></aside><div class="workspace"><header class="toolbar"><div class="navigation-controls"><button class="icon-button" data-action="back" ${backStack.length?"":"disabled"} aria-label="${h(t("Back"))}">${icon("chevron-left")}</button><button class="icon-button" data-action="forward" ${forwardStack.length?"":"disabled"} aria-label="${h(t("Forward"))}">${icon("chevron-right")}</button></div><div class="breadcrumbs">${icon("panel-left")}<span>SynoMusic</span><span class="slash">/</span><strong>${h(title())}</strong></div><label class="search-field">${icon("search")}<input id="search" type="search" value="${h(search)}" placeholder="${h(t("Search your library"))}" autocomplete="off"><kbd>${platform==="windows"?"Ctrl":"⌘"} K</kbd></label><select id="search-scope" aria-label="${h(t("Search scope"))}"><option value="library" ${searchScope==="library"?"selected":""}>${t("Entire library")}</option><option value="page" ${searchScope==="page"?"selected":""}>${t("Current view")}</option></select>${tool("shortcuts","keyboard","Keyboard shortcuts")}${tool("mini-player","picture-in-picture-2","Mini player")}${tool("refresh","refresh-cw","Refresh")}${tool("server","plus","Add server")}</header><div class="content-split"><main class="content">${content()}</main>${panel?sidePanel():""}</div></div>${player()}<div id="modal-root"></div>`;
 app.classList.toggle("player-expanded",rendered.expanded);
 app.classList.toggle("mini-mode",miniMode);
 app.dataset.playing=String(rendered.playing);
 app.querySelectorAll<HTMLElement>(".sidebar,.workspace").forEach(node=>node.inert=rendered.expanded||miniMode);
 createIcons({icons});bind();bindVisuals();bindLyricControls();
 if(previous.content===rendered.content)document.querySelector(".content")?.scrollTo(0,scroll);
 animateRender(previous,closingPlayer,closingPanel,artworkOrigin);
 document.querySelectorAll<HTMLImageElement>("img[data-cover]").forEach(img=>img.addEventListener("error",()=>{img.src=artwork(img.dataset.cover||"SynoMusic");},{once:true}));
 updateProgress();
}
/** 使用局部过渡表现导航和播放器状态变化，普通数据刷新不重播整页动画。 */
function animateRender(previous:typeof rendered,closingPlayer:HTMLElement|null,closingPanel:HTMLElement|null,artworkOrigin:{src:string;bounds:DOMRect}|null): void {
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
 if(previous.content!==rendered.content&&!rendered.expanded){
  enter(".content",[{opacity:.01,transform:"translateY(12px)"},{opacity:1,transform:"translateY(0)"}],360);
  document.querySelectorAll<HTMLElement>(".album-grid>.album-card,.artist-grid>.artist-card").forEach((node,i)=>{if(i<12)node.animate([{opacity:.01,transform:"translateY(18px)"},{opacity:1,transform:"translateY(0)"}],{duration:440,delay:Math.min(i,7)*32,easing,fill:"backwards"});});
 }
 if(rendered.panel&&previous.panel!==rendered.panel)enter(".detail-panel",[{opacity:.01,transform:"translateX(24px)"},{opacity:1,transform:"translateX(0)"}],320);
 if(closingPanel)leave(closingPanel,document.querySelector(".content-split")!,"translateX(24px)");
 if(rendered.expanded&&!previous.expanded){
  enter(".expanded-player",[{opacity:.01},{opacity:1}],440);
  enter(".expanded-metadata",[{opacity:.01,transform:"translateY(18px)"},{opacity:1,transform:"translateY(0)"}],520,100);
  enter(".expanded-lyrics",[{opacity:.01,transform:"translateY(20px)"},{opacity:1,transform:"translateY(0)"}],520,140);
 }
 if(closingPlayer)leave(closingPlayer,app,"translateY(32px)");
 if(artworkOrigin&&previous.expanded!==rendered.expanded){
  const target=document.querySelector<HTMLImageElement>(rendered.expanded?".expanded-cover>img":".now-cover");
  if(target){
   const from=artworkOrigin.bounds,to=target.getBoundingClientRect();
   const ghost=document.createElement("img");ghost.className="artwork-flight";ghost.src=artworkOrigin.src;ghost.alt="";ghost.setAttribute("aria-hidden","true");
   Object.assign(ghost.style,{left:`${from.left}px`,top:`${from.top}px`,width:`${from.width}px`,height:`${from.height}px`});
   document.body.append(ghost);target.style.opacity="0";
   const animation=ghost.animate([{transform:"translate(0,0) scale(1)"},{transform:`translate(${to.left-from.left}px,${to.top-from.top}px) scale(${to.width/from.width},${to.height/from.height})`}],{duration:560,easing,fill:"forwards"});
   void animation.finished.finally(()=>{target.style.opacity="";ghost.remove();}).catch(()=>{});
  }
 }
 if(previous.song&&previous.song!==rendered.song){
  enter(".now-playing>div",[{opacity:.01,transform:"translateY(5px)"},{opacity:1,transform:"translateY(0)"}]);
  if(rendered.expanded&&previous.expanded)enter(".expanded-art",[{opacity:.2,transform:"scale(.98)"},{opacity:1,transform:"scale(1)"}],360);
  if(rendered.expanded&&previous.expanded)enter(".expanded-player>.ambient-art",[{opacity:0},{opacity:1}],650);
 }
 if(previous.playing!==rendered.playing)enter(".play-button svg",[{opacity:.3,transform:"scale(.7)"},{opacity:1,transform:"scale(1)"}],200);
}

/** 封面以小幅透视响应指针；减少动态效果或触控设备使用静态封面。 */
function bindVisuals(): void {
 startSpectrum();
 const cover=document.querySelector<HTMLElement>(".expanded-cover");
 if(!cover||matchMedia("(prefers-reduced-motion: reduce), (pointer: coarse)").matches)return;
 cover.onpointermove=event=>{
  const rect=cover.getBoundingClientRect(),x=(event.clientX-rect.left)/rect.width-.5,y=(event.clientY-rect.top)/rect.height-.5;
  cover.style.setProperty("--tilt-x",`${-y*5}deg`);cover.style.setProperty("--tilt-y",`${x*5}deg`);
  cover.style.setProperty("--shine-x",`${x*12}%`);cover.style.setProperty("--shine-y",`${y*12}%`);
 };
 cover.onpointerleave=()=>{cover.style.setProperty("--tilt-x","0deg");cover.style.setProperty("--tilt-y","0deg");};
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
 if(view==="favorites")return favoritesContent();
 if(view==="statistics")return statisticsContent();
 if(view==="duplicates")return `<div class="page-heading"><h1>${t("Possible duplicates")}</h1><p>${t("Matches use title, artist and similar duration. Original files are preserved.")}</p></div>${shownSongs.length?`${libraryControls()}${songTable(shownSongs)}`:`<p class="muted">${t("No duplicate candidates")}</p>`}`;
 if(view==="radio"||view==="podcasts")return onlineContent();
 if(busy)return `<div class="page-heading"><p class="eyebrow">SYNO / MUSIC</p><h1>${h(title())}</h1></div><div class="loading-grid">${Array(8).fill('<div class="skeleton"></div>').join("")}</div><p class="muted">${t("Fetching your music…")}</p>`;
 if(error)return `<div class="empty-state">${icon("wifi-off")}<h2>${t("No results")}</h2><p>${h(error)}</p><button class="button primary" data-action="refresh">${t("Refresh")}</button></div>`;

 if(view==="server-playlists")return `<div class="page-heading"><p class="eyebrow">${h(t("Music source"))}</p><h1>${t("Server playlists")}</h1></div><div class="album-grid">${serverPlaylists.map(p=>`<button class="album-card" data-view="server-playlist:${h(p.id)}"><div class="playlist-art">${icon("list-music")}</div><h3>${h(p.name)}</h3><p>${p.count} ${t("Tracks")}</p></button>`).join("")}</div>`;
 if(view==="folders"||view==="genres"){const isFolder=view==="folders";const values=[...new Set(songs.map(song=>isFolder?folder(song):song.genre).filter(Boolean))].sort();return `<div class="page-heading"><h1>${h(title())}</h1></div><div class="album-grid">${values.map(value=>`<button class="album-card" data-view="${isFolder?"folder":"genre"}:${h(value)}"><div class="playlist-art">${icon(isFolder?"folder":"tag")}</div><h3>${h(value)}</h3></button>`).join("")}</div>`;}
 if(view==="playlists")return `<div class="page-heading"><p class="eyebrow">MADE BY YOU</p><h1>${t("Playlists")}</h1><div class="actions"><button class="button primary" data-action="new-playlist">${icon("plus")}${t("Create playlist")}</button><button class="button" data-action="new-smart-playlist">${icon("sparkles")}${t("New smart playlist")}</button><button class="button" data-action="import-playlist">${icon("import")}${t("Import playlist")}</button></div></div><div class="album-grid"><button class="album-card favorites-card" data-view="favorites"><div class="playlist-art">${icon("heart")}</div><strong>${t("Favorites")}</strong><span>${favoriteSongs().length} ${t("Tracks")}</span></button>${state.playlists.map(p=>`<button class="album-card" data-view="playlist:${h(p.id)}"><img src="${artwork(p.name)}" alt=""><strong>${h(p.name)}</strong><span>${p.smart?`${icon("sparkles")} ${t("Smart playlist")}`:`${p.songs.length} ${t("All songs").toLowerCase()}`}</span></button>`).join("")}</div>`;
 if(!shownSongs.length&&view.startsWith("playlist:")&&!state.playlists.find(item=>item.id===view.slice(9))?.smart)return `<div class="page-heading"><h1>${h(title())}</h1><p class="muted">0 ${t("Tracks")}</p><div class="actions"><button class="button" data-action="rename-playlist">${t("Rename playlist")}</button><button class="button" data-action="delete-playlist">${t("Remove")}</button></div></div>`;
 if(!shownSongs.length&&!search&&["downloads","favorites","history"].includes(view))return `<div class="empty-state">${icon(view==="downloads"?"download":view==="favorites"?"heart":"history")}<h1>${h(title())}</h1><p>${t(view==="downloads"?"No downloads yet":view==="favorites"?"No favorites yet":"No listening history yet")}</p><button class="button" data-view="songs">${t("Browse your own collection")}</button></div>`;
 if(!shownSongs.length&&view.startsWith("server-playlist:"))return `<div class="page-heading"><h1>${h(title())}</h1><p class="muted">${t("This playlist is empty")}</p></div>`;
 if(!shownSongs.length&&view.startsWith("playlist:")&&state.playlists.find(item=>item.id===view.slice(9))?.smart)return `<div class="page-heading"><h1>${h(title())}</h1><p>${t("No matching tracks")}</p><div class="actions"><button class="button primary" data-action="edit-smart-playlist">${t("Edit smart playlist")}</button><button class="button" data-action="export-playlist">${t("Export playlist")}</button><button class="button" data-action="delete-playlist">${t("Remove")}</button></div></div>`;
 if(!shownSongs.length)return `<div class="empty-state">${icon(search?"search-x":"disc-3")}<p class="eyebrow">YOUR OWN MUSIC, EVERYWHERE</p><h1>${t(search?"No results":"No music yet")}</h1><p>${t(search?"Try another search or connect another music source.":"Connect your server or import a music folder to get started.")}</p><div class="actions"><button class="button primary" data-action="server">${icon("plus")}${t("Connect a server")}</button><button class="button" data-action="import">${icon("folder-open")}${t("Import music")}</button><button class="button" data-action="import-files">${icon("file-audio")}${t("Import audio files")}</button></div><span class="free-message">${icon("heart")}${t("All features. Always free.")}</span></div>`;
 const albums=uniqueAlbums(shownSongs);
 if(view==="library"&&!search){const first=albums[0];return `<div class="page-heading"><p class="eyebrow">${demo?t("Demo library"):"YOUR PERSONAL SOUNDTRACK"}</p><h1>${t("Your music. Your space.")}</h1><p>${t("Browse your own collection")}</p></div>${collectionShortcuts()}<section class="listening-banner">${ambientArtwork(first)}<div class="banner-copy"><span class="pill">${icon("headphones")} ${t("Ready to listen")}</span><h2>${t("Made for a little more listening.")}</h2><p>${shownSongs.length} ${t("All songs").toLowerCase()} <span>·</span> ${albums.length} ${t("Albums").toLowerCase()} <span>·</span> ${t("Original quality")}</p><div class="actions"><button class="button primary" data-action="play-all">${icon("play")}${t("Play all")}</button><button class="button glass" data-action="shuffle-all">${icon("shuffle")}${t("Shuffle")}</button></div></div><div class="banner-record"><img src="${h(cover(first))}" data-cover="${h(first.album)}" alt="${h(first.album)}"><div class="vinyl"><span></span></div></div></section><div class="section-title"><h2>${t("Albums")}</h2><button data-view="albums">${t("Albums")} ${icon("arrow-up-right")}</button></div><div class="album-grid">${albums.slice(0,10).map(albumCard).join("")}</div><div class="section-title"><h2>${t("Favorites, in one place")}</h2><button data-view="favorites" aria-label="${h(t("Favorites"))}">${icon("arrow-up-right")}</button></div>${songTable(favoriteSongs().slice(0,5))}`;}
 if(view==="albums")return `<div class="page-heading"><p class="eyebrow">${t("Browse by album")}</p><h1>${t("Albums")} <small>${albums.length}</small></h1></div>${libraryControls()}<div class="album-grid">${albums.slice(page*pageSize,(page+1)*pageSize).map(albumCard).join("")}</div>${pagination(albums.length)}`;
 if(view==="artists"){const artists=[...new Set(shownSongs.map(s=>s.artist||""))];return `<div class="page-heading"><p class="eyebrow">${t("Browse by artist")}</p><h1>${t("Artists")} <small>${artists.length}</small></h1></div><div class="artist-grid">${artists.map(name=>`<button class="artist-card" data-view="artist:${h(name)}"><img src="${h(cover(shownSongs.find(song=>song.artist===name)||shownSongs[0]))}" data-cover="${h(name)}" alt=""><strong>${h(name||t("Unknown artist"))}</strong><span>${shownSongs.filter(s=>s.artist===name).length} ${t("All songs").toLowerCase()}</span></button>`).join("")}</div>`;}
 if(view.startsWith("album:")||view.startsWith("artist:"))return `${collectionHeader()}${libraryControls()}${songTable(shownSongs)}`;
 return `<div class="page-heading"><p class="eyebrow">${view==="history"?t("Recently played"):t("Browse your own collection")}</p><h1>${h(title())} <small>${shownSongs.length}</small></h1><div class="actions">${view==="local"?`<button class="button" data-action="import-files">${icon("file-audio")}${t("Import audio files")}</button><button class="button" data-action="import">${icon("folder-open")}${t("Import music")}</button>`:""}<button class="button primary" data-action="play-all">${icon("play")}${t("Play all")}</button><button class="button" data-action="shuffle-all">${icon("shuffle")}${t("Shuffle")}</button>${selected.size?`<button class="button" data-action="add-selected">${icon("list-plus")}${t("Add selected to playlist")} (${selected.size})</button>`:""}${view==="history"?`<button class="button" data-action="clear-history">${t("Clear history")}</button>`:""}${view.startsWith("playlist:")?`<button class="button" data-action="rename-playlist">${icon("pencil")}${t("Rename playlist")}</button><button class="button" data-action="export-playlist">${icon("export")}${t("Export playlist")}</button>${state.playlists.find(item=>item.id===view.slice(9))?.smart?`<button class="button" data-action="edit-smart-playlist">${icon("sparkles")}${t("Edit smart playlist")}</button>`:""}<button class="button" data-action="delete-playlist">${icon("trash-2")}${t("Remove")}</button>`:""}</div></div>${libraryControls()}${songTable(shownSongs)}`;
}
/** 绘制带真实内容与键盘可访问入口的专辑封面。 */
function albumCard(song: Song): string { return `<button class="album-card" data-view="album:${h(albumID(song))}"><div class="album-cover"><img loading="lazy" src="${h(cover(song))}" data-cover="${h(song.album)}" alt="${h(song.album)}"><span class="cover-play">${icon("play")}</span>${song.codec?`<span class="codec">${h((song.codec||"").toUpperCase())}</span>`:""}</div><strong>${h(song.album||song.title)}</strong><span>${h(song.artist)}</span></button>`; }
/** 绘制歌曲列表与选择、收藏、下载和歌单操作。 */
function songTable(list: Song[]): string {
 const editable=view.startsWith("playlist:")&&!state.playlists.find(item=>item.id===view.slice(9))?.smart;
 const paged=list.length>pageSize?list.slice(page*pageSize,(page+1)*pageSize):list;
 return `<div class="song-table ${editable?"editable-playlist":""}"><div class="song-row table-header"><span>#</span><span>${t("All songs")}</span><span>${t("Albums")}</span><span>${icon("clock-3")}</span><span></span></div>${paged.map((song,i)=>`<div class="song-row ${queue[current]?.id===song.id?"playing":""}" data-song-id="${h(song.id)}" ${editable?'data-reorderable="true"':""}><label class="track-number"><span>${queue[current]?.id===song.id?icon("audio-lines"):song.trackNumber&&view.startsWith("album:")?song.trackNumber:page*pageSize+i+1}</span><input type="checkbox" data-select="${h(song.id)}" ${selected.has(song.id)?"checked":""} aria-label="${h(song.title)}"></label><button class="song-info" data-play="${h(song.id)}"><img loading="lazy" src="${h(cover(song))}" data-cover="${h(song.album)}" alt=""><span><strong>${h(song.title)}</strong><small>${h(song.artist)}</small></span></button><button class="album-text" data-view="album:${h(albumID(song))}">${h(song.album)}</button><span class="track-duration">${duration(song.duration)}</span><div class="song-actions">${editable?`<button class="icon-button reorder-handle" data-reorder aria-label="${h(t("Reorder"))}">${icon("grip-vertical")}</button>`:""}<button class="icon-button ${state.favorites.includes(song.id)?"hearted":""}" data-favorite="${h(song.id)}" aria-pressed="${state.favorites.includes(song.id)}" aria-label="${h(t(state.favorites.includes(song.id)?"Unlike song":"Like song"))}">${icon("heart")}</button><details class="track-menu"><summary aria-label="${h(t("More actions"))}">${icon("ellipsis")}</summary><div><button data-queue="${h(song.id)}">${icon("list-start")}${t("Play next")}</button><button data-queue-last="${h(song.id)}">${icon("list-end")}${t("Add to queue")}</button><button data-add="${h(song.id)}">${icon("list-plus")}${t("Add to playlist")}</button><button data-view="artist:${h(song.artist)}">${icon("mic-2")}${t("Go to artist")}</button><button data-info="${h(song.id)}">${icon("info")}${t("Song information")}</button>${song.profileID==="local"?`<button data-reveal="${h(song.id)}">${icon("folder-open")}${t("Show in file manager")}</button><button data-remove-local="${h(song.id)}">${icon("list-minus")}${t("Remove from library")}</button>`:""}${view==="downloads"?`<button data-remove-download="${h(song.id)}">${icon("trash-2")}${t("Remove download")}</button>`:!["local","radio"].includes(song.profileID)?`<button data-download="${h(song.id)}" ${cachedSongs.some(item=>item.id===song.id)||activeDownload===song.id||downloadJobs.includes(song.id)?"disabled":""}>${icon("download")}${t(cachedSongs.some(item=>item.id===song.id)?"Downloaded":activeDownload===song.id||downloadJobs.includes(song.id)?"Downloading…":"Download")}</button>`:""}${editable?`<button data-playlist-remove="${h(song.id)}">${icon("list-minus")}${t("Remove from playlist")}</button>`:""}</div></details></div></div>`).join("")}</div>${list.length>pageSize?pagination(list.length):""}`;
}
/** 分页只影响显示，播放全部和搜索仍使用完整资料库。 */
function pagination(count:number): string { if(count<=pageSize)return "";const total=Math.ceil(count/pageSize);return `<div class="pagination"><button class="button" data-page="${page-1}" ${page===0?"disabled":""}>${t("Previous page")}</button><span>${page*pageSize+1}–${Math.min((page+1)*pageSize,count)} / ${count}</span><button class="button" data-page="${page+1}" ${page+1>=total?"disabled":""}>${t("Next page")}</button></div>`; }
/** 绘制与主内容独立滚动的播放队列或同步歌词。 */
function sidePanel(): string {
 const queueStart=queuePage<0?Math.floor(Math.max(0,current)/100)*100:queuePage*100;
 return `<aside class="detail-panel ${panel==="lyrics"?"lyrics-panel":""}"><div class="panel-heading"><h3>${t(panel==="lyrics"?"Lyrics":"Queue")}</h3>${tool("close-panel","x","Close")}</div>${panel==="lyrics"?`${lyricToolbar()}<div class="lyrics-content" style="--lyric-size:${Number(state.settings.lyricSize)||24}px">${lyricContent()}</div>`:`<div class="queue-summary"><p>${queue.length} ${t("Tracks")} · ${collectionDuration(queue)}</p>${queue.length>100?`<div class="queue-pages"><button class="icon-button" data-queue-page="${Math.floor(queueStart/100)-1}" ${queueStart===0?"disabled":""} aria-label="${h(t("Previous page"))}">${icon("chevron-left")}</button><span>${queueStart+1}–${Math.min(queueStart+100,queue.length)}</span><button class="icon-button" data-queue-page="${Math.floor(queueStart/100)+1}" ${queueStart+100>=queue.length?"disabled":""} aria-label="${h(t("Next page"))}">${icon("chevron-right")}</button></div>`:""}<div class="actions"><button class="button subtle" data-action="save-queue" ${queue.length?"":"disabled"}>${t("Save as playlist")}</button><button class="button subtle" data-action="clear-queue" ${queue.length?"":"disabled"}>${t("Clear")}</button></div></div><div class="queue-list">${queue.length?queue.slice(queueStart,queueStart+100).map((song,offset)=>{const i=queueStart+offset;return `<div class="queue-row ${i===current?"current":""}" data-queue-row="${i}"><button class="queue-item" data-queue-index="${i}"><img loading="lazy" src="${h(cover(song))}" data-cover="${h(song.album)}" alt=""><span><strong>${h(song.title)}</strong><small>${h(song.artist)} · ${duration(song.duration)}</small></span>${i===current?icon("audio-lines"):""}</button><div class="queue-actions"><button class="icon-button reorder-handle" data-reorder aria-label="${h(t("Reorder"))}">${icon("grip-vertical")}</button><button class="icon-button" data-queue-edit="up" data-index="${i}" ${i===0?"disabled":""} aria-label="${h(t("Move up"))}">${icon("chevron-up")}</button><button class="icon-button" data-queue-edit="down" data-index="${i}" ${i+1===queue.length?"disabled":""} aria-label="${h(t("Move down"))}">${icon("chevron-down")}</button><button class="icon-button" data-queue-edit="remove" data-index="${i}" aria-label="${h(t("Remove from queue"))}">${icon("x")}</button></div></div>`;}).join(""):`<p class="muted">${t("Queue is empty")}</p>`}</div>`}</aside>`;
}
/** 缓存解析结果，进度更新只查找当前行，不反复解析整份歌词。 */
function lyricLines(): LyricLine[] {
 if(parsedLyricsText!==lyrics){parsedLyricsText=lyrics;parsedLyrics=parseLyrics(lyrics);}
 return parsedLyrics;
}
/** 请求歌词时显示加载与失败状态；暂停不会使有效响应失效，换歌会忽略过期响应。 */
function requestLyrics(force=false): void {
 const song=queue[current];if(!song||demo)return;
 if(!force&&lyricsSong===song.id&&(lyricsLoading||lyrics))return;
 const generation=++lyricRequest;lyricsSong=song.id;lyricsLoading=true;lyricsError="";refreshLyrics();
 void Service.lyrics(song.id).then(text=>{if(generation===lyricRequest&&queue[current]?.id===song.id)lyrics=text;}).catch(error=>{if(generation===lyricRequest)lyricsError=String(error);}).finally(()=>{if(generation===lyricRequest){lyricsLoading=false;refreshLyrics();}});
}
/** 歌词请求完成时只更新歌词区，保留正在进行的播放器展开动画。 */
function refreshLyrics(): void {
 document.querySelectorAll<HTMLElement>(".lyrics-content").forEach(container=>{
  container.innerHTML=lyricContent();container.dataset.active="";
  const toolbar=container.previousElementSibling;if(toolbar?.matches(".lyric-toolbar"))toolbar.outerHTML=lyricToolbar();
 });
 bindLyricControls();createIcons({icons});updateProgress();
}
/** 绑定歌词工具和时间跳转，手动滚动暂缓跟随，随后自动回到当前行。 */
function bindLyricControls():void {
 document.querySelectorAll<HTMLElement>(".lyric-toolbar [data-action],.lyrics-content [data-action]").forEach(node=>node.onclick=()=>void run(()=>action(node.dataset.action!)));
 document.querySelectorAll<HTMLElement>(".lyrics-content [data-seek]").forEach(node=>node.onclick=()=>{lyricScrollPausedUntil=0;seekPosition(Number(node.dataset.seek));});
 document.querySelectorAll<HTMLElement>(".lyrics-content").forEach(container=>{
  container.onwheel=()=>{lyricScrollPausedUntil=performance.now()+6000;container.dataset.following="false";};
  container.onkeydown=event=>{if(["PageUp","PageDown","Home","End","ArrowUp","ArrowDown"].includes(event.key)){lyricScrollPausedUntil=performance.now()+6000;container.dataset.following="false";}};
 });
}
/** 更新每个可见歌词视图的高亮和居中位置，仅滚动歌词容器，不移动播放器或整页。 */
function updateLyrics():void {
 if(panel!=="lyrics"&&!nowPlaying)return;
 const index=activeLyric(lyricLines(),(audio.src?audio.currentTime:resumePosition)+(Number(state.settings.lyricOffset)||0));
 const following=state.settings.lyricAutoScroll!=="false"&&performance.now()>=lyricScrollPausedUntil;
 document.querySelectorAll<HTMLElement>(".lyrics-content").forEach(container=>{
  const changed=container.dataset.active!==String(index),resuming=following&&container.dataset.following!=="true";
  container.dataset.active=String(index);container.dataset.following=String(following);
  container.querySelectorAll<HTMLElement>("[data-lyric-index]").forEach(line=>{
   const active=Number(line.dataset.lyricIndex)===index;
   line.classList.toggle("current",active);line.classList.toggle("past",Number(line.dataset.lyricIndex)<index);
   if(active)line.setAttribute("aria-current","true");else line.removeAttribute("aria-current");
   if(active&&following&&(changed||resuming)){
    const top=container.scrollTop+line.getBoundingClientRect().top-container.getBoundingClientRect().top-container.clientHeight/2+line.clientHeight/2;
    container.scrollTo({top:Math.max(0,top),behavior:matchMedia("(prefers-reduced-motion: reduce)").matches?"instant":"smooth"});
   }
  });
 });
}
/** 集中保存歌词字号、时间偏移、自动跟随和在线补全偏好。 */
function lyricSettings():void {
 modal(`<h2>${t("Lyric settings")}</h2><form id="lyric-settings"><label>${t("Text size")}<input name="lyricSize" type="number" min="14" max="42" value="${Number(state.settings.lyricSize)||24}" required></label><label>${t("Lyric offset")} (s)<input name="lyricOffset" type="number" min="-60" max="60" step="0.1" value="${Number(state.settings.lyricOffset)||0}" required></label><p class="audio-note muted">${t("Positive offset shows lyrics earlier.")}</p><label class="checkbox-label"><input name="lyricAutoScroll" type="checkbox" ${state.settings.lyricAutoScroll!=="false"?"checked":""}>${t("Follow lyrics")}</label><label class="checkbox-label"><input name="onlineLyrics" type="checkbox" ${state.settings.onlineLyrics!=="false"?"checked":""}>${t("Find online lyrics")}</label><p class="audio-note muted">${t("When lyrics are missing, send song title, artist, album and duration to LRCLIB. Server credentials are never shared.")}</p><div class="actions"><button class="button primary" type="submit">${t("Save")}</button><button class="button" type="button" data-action="close-modal">${t("Cancel")}</button></div></form>`);
 document.querySelector<HTMLFormElement>("#lyric-settings")!.onsubmit=event=>{event.preventDefault();void run(async()=>{
  const data=new FormData(event.currentTarget as HTMLFormElement),previous=state.settings.onlineLyrics;
  state.settings.lyricSize=String(Math.min(42,Math.max(14,Number(data.get("lyricSize"))||24)));state.settings.lyricOffset=String(Math.min(60,Math.max(-60,Number(data.get("lyricOffset"))||0)));
  for(const key of ["lyricAutoScroll","onlineLyrics"])state.settings[key]=String(data.has(key));
  if(!demo)await Service.saveSettings(state.settings);lyricScrollPausedUntil=0;render();if(previous!==state.settings.onlineLyrics)requestLyrics(true);
 });};
}
/** 绘制常驻播放器，切页时保持播放位置与队列。 */
function player(): string { const song=queue[current];return `${nowPlaying?expandedPlayer():""}<footer class="player-bar"><div class="now-playing">${song?`<button class="cover-expand" data-action="now-playing" aria-label="${h(t("Now playing"))}"><img class="now-cover" src="${h(cover(song))}" data-cover="${h(song.album)}" alt=""></button><div><strong>${h(song.title)}</strong><span>${h(song.artist)}</span></div><button class="icon-button ${state.favorites.includes(song.id)?"hearted":""}" data-favorite="${h(song.id)}" aria-pressed="${state.favorites.includes(song.id)}" aria-label="${h(t(state.favorites.includes(song.id)?"Unlike song":"Like song"))}">${icon("heart")}</button>`:`<div class="now-placeholder">${icon("music-2")}</div><div><strong>SynoMusic</strong><span>${t("Ready to listen")}</span></div>`}</div><div class="transport"><div class="transport-buttons">${tool("shuffle","shuffle","Shuffle",shuffle)}${tool("previous","skip-back","Previous track")}<button class="play-button ${loadingTrack?"is-loading":""}" data-action="toggle" aria-label="${h(t(loadingTrack?"Cancel":audio.paused?"Play":"Pause"))}">${icon(loadingTrack?"loader-circle":audio.paused?"play":"pause")}</button>${tool("next","skip-forward","Next track")}${tool("repeat",repeat==="one"?"repeat-1":"repeat",repeat==="one"?"Repeat one":repeat==="all"?"Repeat all":"Repeat off",repeat!=="off")}</div><div class="timeline"><span id="position">0:00</span><input id="progress" type="range" min="0" max="${Number.isFinite(audio.duration)?audio.duration:song?.duration||1}" step="0.1" value="${audio.currentTime}" ${song?.profileID==="radio"?"disabled":""} aria-label="${h(t("Playback position"))}"><span id="duration">${duration(audio.duration||song?.duration||0)}</span></div></div><div class="player-tools">${tool("audio-settings","sliders-horizontal","Audio settings")}${platform==="darwin"?tool("airplay","airplay","Audio output"):""}<button class="volume-button" data-action="mute" aria-label="${h(t(audio.muted?"Unmute":"Mute"))}">${icon(audio.muted?"volume-x":"volume-2")}</button><input id="volume" type="range" min="0" max="1" step="0.01" value="${audio.volume}" aria-label="${h(t("Volume"))}">${tool("lyrics","captions","Lyrics",panel==="lyrics")}${tool("queue","list-music","Queue",panel==="queue")}${tool("now-playing",nowPlaying?"minimize-2":"maximize-2","Now playing",nowPlaying)}</div></footer>`; }
/** 绘制所有免费设置以及隐私与官方链接。 */
function settings(): string {
 const setting=(label:string,control:string)=>`<label class="setting-row"><span>${t(label)}</span>${control}</label>`;
 return `<div class="page-heading"><p class="eyebrow">MAKE YOURSELF AT HOME</p><h1>${t("Settings")}</h1></div><div class="settings-body"><h2>${t("General")}</h2>${setting("Language",`<select id="language">${languages.map(([code,name])=>`<option value="${code}" ${getLanguage()===code?"selected":""}>${name}</option>`).join("")}</select>`)}${setting("Appearance",`<select data-setting="appearance">${["system","light","dark"].map(v=>`<option value="${v}" ${state.settings.appearance===v?"selected":""}>${t(v[0].toUpperCase()+v.slice(1))}</option>`).join("")}</select>`)}<h2>${t("Playback")}</h2>${setting("Crossfade",`<select data-setting="crossfade"><option value="0">${t("Off")}</option>${[2,4,6,8].map(n=>`<option value="${n}" ${Number(state.settings.crossfade)===n?"selected":""}>${n} s</option>`).join("")}</select>`)}${setting("Audio settings",`<button class="button" data-action="audio-settings">${icon("sliders-horizontal")}${t("Customize audio")}</button>`)}${setting("Equalizer",`<select data-setting="equalizer">${["Flat","Bass","Acoustic","Vocal","Electronic","Custom"].map(v=>`<option ${state.settings.equalizer===v?"selected":""}>${v}</option>`).join("")}</select>`)}${setting("Sleep timer",`<select id="sleep"><option value="0" ${sleepDeadline?"":"selected"}>${t("Off")}</option>${[15,30,45,60,90].map(n=>`<option value="${n}" ${sleepDeadline&&sleepMinutes===n?"selected":""}>${n} ${t("minutes")}</option>`).join("")}</select>`)}${setting("Synced lyrics",`<button class="button" data-action="lyric-settings">${icon("captions")}${t("Lyric settings")}</button>`)}${setting("Lyric offset",`<input data-setting="lyricOffset" type="number" min="-60" max="60" step="0.5" value="${Number(state.settings.lyricOffset)||0}">`)}${setting("Text size",`<input data-setting="lyricSize" type="number" min="14" max="42" value="${Number(state.settings.lyricSize)||24}">`)}${platform==="darwin"&&cloudSupported?`<h2>iCloud</h2>${setting("iCloud sync",`<input data-setting="icloud" type="checkbox" ${state.settings.icloud==="true"?"checked":""}>`)}<div class="actions"><button class="button" data-action="sync-cloud">${icon("cloud")}${t("Sync now")}</button></div>${state.settings.lastCloudSync?`<p class="version-label">${h(new Date(state.settings.lastCloudSync).toLocaleString())}</p>`:""}`:""}<h2>${t("Server profiles")}</h2>${state.profiles.map(p=>`<div class="setting-row"><span><strong>${h(p.name)}</strong><small>${h(p.providerType)} · ${h(p.host)}</small></span><button class="button subtle" data-edit-server="${h(p.id)}" aria-label="${h(t("Edit server"))}">${icon("pencil")}</button><button class="button subtle" data-remove-server="${h(p.id)}" aria-label="${h(t("Remove server"))}">${icon("trash-2")}</button></div>`).join("")}<div class="actions"><button class="button" data-action="server">${icon("plus")}${t("Add server")}</button><button class="button" data-action="export">${icon("upload")}${t("Export servers")}</button><button class="button" data-action="import-profiles">${icon("download")}${t("Import servers")}</button></div><div class="support-callout">${icon("heart")}<div><h3>${t("All features. Always free.")}</h3><p>${t("Support is optional. Music is for everyone.")}</p></div><button class="button" data-action="support">${t("View on iPhone")}${icon("arrow-up-right")}</button></div><div class="legal-links">${[["Website","https://zanwingmak.github.io/SynoMusic/"],["Source code","https://github.com/ZanwingMak/SynoMusic"],["Privacy policy","https://zanwingmak.github.io/SynoMusic/privacy.html"],["Terms of use","https://zanwingmak.github.io/SynoMusic/terms.html"]].map(([text,url])=>`<button data-link="${url}">${t(text)}${icon("arrow-up-right")}</button>`).join("")}</div><p class="version-label">SynoMusic for ${platform==="windows"?"Windows":"Mac"} · 1.6.7 · MyGo</p></div>`;
}
/** 播放登记过的歌曲，避免多个异步播放请求交错覆盖状态。 */
async function play(index: number, position=0, sequence=false): Promise<void> {
 if(!queue.length)return;lyrics="";lyricsLoading=false;lyricsError="";lyricsSong="";lyricRequest++;lyricScrollPausedUntil=0;abStart=null;abEnd=null;listenedSeconds=0;lastListenPosition=position;playCountRecorded=false;cancelTransition();current=(index+queue.length)%queue.length;queuePage=-1;const song=queue[current];const generation=playGeneration;if(!sequence)resetShuffle();
 if(demo){render();return;}
 loadingTrack=song.id;render();
 try{
 audio.pause();audio.removeAttribute("src");audio.load();resumePosition=position;
 await ensureSong(song);if(generation!==playGeneration)return;
 if(song.duration>0&&position>=song.duration-1)position=0;
 if(position>0)audio.addEventListener("loadedmetadata",()=>{if(generation===playGeneration)audio.currentTime=position;},{once:true});
 resumePosition=0;audio.src=mediaURL(`music://localhost/stream/${encodeURIComponent(song.id)}`);audio.volume=Math.min(1,Math.max(0,Number(state.settings.volume??"0.7")||0));
 lyrics="";
 applyEQ();applyPlaybackSpeed();
 await effects.resume();
 requestLyrics();await audio.play();if(generation!==playGeneration)return;
 if(Number.isFinite(audio.duration)&&audio.duration>0)song.duration=audio.duration;
 await Service.recordPlay(song);state.history=[song,...state.history.filter(s=>s.id!==song.id)].slice(0,500);syncNowPlaying();render();
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
async function toggle(): Promise<void> { if(!queue[current]){await playList(shownSongs);return;}if(demo)return;if(loadingTrack){pausePlayback();return;}if(audio.paused){if(!audio.src){await play(current,resumePosition);return;}await effects.resume();await audio.play();}else {cancelTransition();audio.pause();}syncNowPlaying();render(); }
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
function seekPosition(position:number): void { if(!Number.isFinite(position)||position<0||!queue[current]||queue[current].profileID==="radio")return;const end=Number.isFinite(audio.duration)?audio.duration:queue[current].duration;position=end>0?Math.min(position,end):position;if(crossfading)cancelTransition();lastListenPosition=position;if(audio.src)audio.currentTime=position;else resumePosition=position;syncNowPlaying();updateProgress(); }
/** 展开专辑封面和同步歌词，继续使用底部同一套播放控件。 */
function expandedPlayer(): string {
 const song=queue[current];if(!song)return "";
 const quality=[song.codec?.toUpperCase(),song.sampleRate?`${song.sampleRate/1000} kHz`:"",song.bitrate?`${Math.round(song.bitrate/1000)} kbps`:""].filter(Boolean);
 const gain=state.settings.replayGain==="album"?song.albumGain??song.trackGain:state.settings.replayGain==="track"?song.trackGain:undefined;if(gain!==undefined)quality.push(`ReplayGain ${gain>=0?"+":""}${gain.toFixed(1)} dB`);
 const upcoming=queue.slice(current+1,current+3);
 return `<section class="expanded-player" aria-label="${h(t("Now playing"))}">${ambientArtwork(song)}<header class="expanded-heading"><span class="expanded-status">${playbackIndicator()}${t("Now playing")}</span><span class="expanded-wordmark">SYNO / MUSIC</span>${tool("now-playing","chevron-down","Close")}</header><div class="expanded-content"><div class="expanded-art"><div class="expanded-cover"><img src="${h(cover(song))}" data-cover="${h(song.album)}" alt="${h(song.album)}"><span class="cover-sheen" aria-hidden="true"></span></div><div class="expanded-metadata"><div class="expanded-track-heading"><h1>${h(song.title)}</h1><button class="icon-button ${state.favorites.includes(song.id)?"hearted":""}" data-favorite="${h(song.id)}" aria-pressed="${state.favorites.includes(song.id)}" aria-label="${h(t(state.favorites.includes(song.id)?"Unlike song":"Like song"))}">${icon("heart")}</button></div><button class="text-link" data-view="artist:${h(song.artist)}">${h(song.artist)}</button><p class="expanded-album">${h(song.album)}</p><div class="quality-tags"><button class="quality-control ${abStart!==null?"active":""}" data-action="ab-loop" title="${h(t("A–B repeat"))}">${abStart===null?"A–B":abEnd===null?`A ${duration(abStart)} → B`:`${duration(abStart)} – ${duration(abEnd)}`}</button><span>${icon("audio-lines")}${h(quality.shift()||t("Original quality"))}</span>${quality.map(label=>`<span>${h(label)}</span>`).join("")}</div><canvas class="audio-spectrum" width="640" height="80" aria-hidden="true" ${state.settings.visualizer==="true"?"":"hidden"}></canvas></div></div><div class="expanded-right"><div class="expanded-lyrics">${lyricToolbar()}<div class="lyrics-content" style="--lyric-size:${Number(state.settings.lyricSize)||24}px">${lyricContent()}</div></div>${upcoming.length?`<section class="stage-queue"><div class="stage-queue-heading"><span>${t("Queue")} <small>${queue.length}</small></span><button class="icon-button" data-action="queue" aria-label="${h(t("Queue"))}">${icon("arrow-up-right")}</button></div>${upcoming.map((item,index)=>`<button class="stage-queue-item" data-queue-index="${current+index+1}"><img src="${h(cover(item))}" data-cover="${h(item.album)}" alt=""><span><strong>${h(item.title)}</strong><small>${h(item.artist)}</small></span><span>${duration(item.duration)}</span>${icon("play")}</button>`).join("")}</section>`:""}</div></div></section>`;
}

/** 更新系统媒体中心，调用只在播放状态变化时触发。 */
function syncNowPlaying(): void { app.dataset.playing=String(!audio.paused);savePlayback();const song=queue[current];if(song&&!demo)void Service.updateNowPlaying({...song,duration:Number.isFinite(audio.duration)?audio.duration:song.duration},!audio.paused,audio.src?audio.currentTime:resumePosition,audio.playbackRate).catch(()=>{}); }
/** 更新进度与歌词高亮，避免每秒重建界面或中断输入。 */
function updateProgress(): void {
 if(!audio.paused&&performance.now()-lastPlaybackSave>5000){lastPlaybackSave=performance.now();savePlayback();}
 const progress=document.querySelector<HTMLInputElement>("#progress");if(progress){progress.max=String(Number.isFinite(audio.duration)?audio.duration:queue[current]?.duration||1);progress.value=String(audio.src?audio.currentTime:resumePosition);progress.style.setProperty("--progress",`${Number(progress.value)/Number(progress.max)*100||0}%`);}
 const position=document.querySelector("#position");if(position)position.textContent=duration(audio.src?audio.currentTime:resumePosition);const end=document.querySelector("#duration");if(end)end.textContent=queue[current]?.profileID==="radio"?t("Live"):duration(audio.duration||queue[current]?.duration||0);
 updateLyrics();
}
/** 将单首或批量选择的歌曲加入用户选定的歌单。 */
function playlistModal(items: Song[]): void {
 modal(`<h2>${t("Add to playlist")}</h2><form id="add-to-playlist"><label>${t("Playlists")}<select name="playlist">${state.playlists.filter(p=>!p.smart).map(p=>`<option value="${h(p.id)}">${h(p.name)}</option>`).join("")}</select></label><label>${t("Create playlist")}<input name="newName" placeholder="${h(t("Name"))}"></label><div class="actions"><button class="button primary" type="submit">${t("Save")}</button><button class="button" type="button" data-action="close-modal">${t("Cancel")}</button></div></form>`);
 document.querySelector<HTMLFormElement>("#add-to-playlist")!.onsubmit=e=>{e.preventDefault();void run(async()=>{const data=new FormData(e.currentTarget as HTMLFormElement);let playlist=state.playlists.find(p=>p.id===data.get("playlist"));const name=String(data.get("newName")||"").trim();if(name){playlist=demo?{id:crypto.randomUUID(),name,songs:[]}:await Service.createPlaylist(name);state.playlists.push(playlist);}if(!playlist||playlist.smart)throw new Error(t("Create playlist"));const seen=new Set(playlist.songs.map(s=>s.id));const updated={...playlist,songs:[...playlist.songs,...items.filter(s=>!seen.has(s.id))]};if(!demo)await Service.savePlaylist(updated);state.playlists=state.playlists.map(item=>item.id===updated.id?updated:item);selected.clear();render();toast(t("Save"));});};
}
/** 弹层打开时隐藏背景交互，关闭时恢复播放器当前模式的可访问状态。 */
function setModalBackground(blocked:boolean):void {
 for(const child of app.children){if(child.id!=="modal-root")(child as HTMLElement).inert=blocked||((rendered.expanded||miniMode)&&child.matches(".sidebar,.workspace"));}
}
/** 显示原生窗口中的可关闭表单弹层。 */
function modal(content: string): void { if(!document.querySelector(".modal-backdrop"))modalFocus=document.activeElement as HTMLElement;const root=document.querySelector("#modal-root")!;setModalBackground(true);root.innerHTML=`<div class="modal-backdrop"><section role="dialog" aria-modal="true" aria-label="SynoMusic" class="modal">${content}</section></div>`;createIcons({icons});root.querySelector<HTMLElement>("input,textarea,select,button")?.focus();root.querySelectorAll<HTMLElement>("[data-action]").forEach(node=>node.onclick=()=>void run(()=>action(node.dataset.action!)));bindRatingActions(root); }
/** 收起弹窗时完成退出动画，再释放表单和遮罩。 */
function closeModal(): void {
 setModalBackground(false);
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
function setupEQ(): void { applyEQ(); }
/** 将当前音频与预备通道的独立增益应用到音频图。 */
function applyEQ(): void { effects.update(state.settings,audio,otherAudio,queue[current],queue[current+1]); }
/** 同时更新当前和预备音频的速度，默认保持音高。 */
function applyPlaybackSpeed():void {
 const speed=Math.min(2,Math.max(.5,Number(state.settings.playbackSpeed)||1));
 for(const element of [audio,otherAudio]){element.playbackRate=speed;element.preservesPitch=state.settings.preservePitch!=="false";}
}
/** 累积实际播放经过的时间，跳转与恢复位置不增加有效播放次数。 */
function trackListening():void {
 const position=audio.currentTime,delta=position-lastListenPosition;lastListenPosition=position;
 if(audio.paused||!queue[current]||queue[current].profileID==="radio")return;
 if(delta>0&&delta<2)listenedSeconds+=delta/(audio.playbackRate||1);
 const threshold=Math.min(30,(Number.isFinite(audio.duration)?audio.duration:queue[current].duration)/2||30);
 if(playCountRecorded||listenedSeconds<threshold)return;
 playCountRecorded=true;const song=queue[current];
 if(demo){const stats=state.stats[song.id]||{rating:0,playCount:0,lastPlayed:0};state.stats[song.id]={...stats,playCount:stats.playCount+1,lastPlayed:Date.now()};return;}
 void Service.recordCompletedPlay(song.id).then(stats=>{state.stats[song.id]=stats;}).catch(error=>{playCountRecorded=false;toast(String(error));});
}
/** 只在播放页可见、音乐播放中且允许动态效果时绘制真实频谱。 */
function startSpectrum():void {
 cancelAnimationFrame(spectrumFrame);
 const canvas=document.querySelector<HTMLCanvasElement>(".audio-spectrum");
 if(!canvas)return;canvas.hidden=state.settings.visualizer!=="true";
 if(canvas.hidden||audio.paused||document.hidden||matchMedia("(prefers-reduced-motion: reduce)").matches)return;
 const context=canvas.getContext("2d");if(!context)return;
 const color=getComputedStyle(canvas).color;
 /** 频谱只读取当前音频图，停止播放后立即释放帧循环。 */
 const draw=():void=>{
  if(!canvas.isConnected||audio.paused||document.hidden)return;
  const data=effects.frequencies();if(!data)return;
  context.clearRect(0,0,canvas.width,canvas.height);context.fillStyle=color;
  for(let index=0;index<40;index++){const height=data[Math.floor(index*data.length/40)]/255*(canvas.height-4);context.globalAlpha=.3+height/canvas.height*.6;context.fillRect(index*16,canvas.height-height,9,height);}
  spectrumFrame=requestAnimationFrame(draw);
 };
 draw();
}
/** 集中编辑十段均衡器、ReplayGain、声道平衡、速度和真实频谱。 */
function audioSettings():void {
 const settings=state.settings,bands=equalizerBands(settings);
 modal(`<h2>${t("Audio settings")}</h2><form id="audio-settings"><label>${t("Equalizer")}<select name="equalizer">${["Flat","Bass","Acoustic","Vocal","Electronic","Custom"].map(name=>`<option value="${name}" ${(settings.equalizer||"Flat")===name?"selected":""}>${t(name)}</option>`).join("")}</select></label><div class="equalizer-bands">${eqFrequencies.map((frequency,index)=>`<label class="eq-band"><span aria-hidden="true">${bands[index]>0?"+":""}${bands[index]}</span><input name="band${index}" type="range" min="-12" max="12" step="1" value="${bands[index]}" aria-label="${frequency} Hz"><span>${frequency>=1000?`${frequency/1000}k`:frequency}</span></label>`).join("")}</div><div class="form-grid"><label>${t("Preamp")}<input name="preamp" type="number" min="-12" max="12" step="1" value="${Number(settings.preamp)||0}"></label><label>ReplayGain<select name="replayGain">${[["off","Off"],["track","Track gain"],["album","Album gain"]].map(([value,label])=>`<option value="${value}" ${(settings.replayGain||"off")===value?"selected":""}>${t(label)}</option>`).join("")}</select></label><label>${t("Balance")}<input name="balance" type="range" min="-1" max="1" step="0.05" value="${Number(settings.balance)||0}"></label><label>${t("Playback speed")}<select name="playbackSpeed">${[.5,.75,1,1.25,1.5,1.75,2].map(value=>`<option value="${value}" ${Number(settings.playbackSpeed||1)===value?"selected":""}>${value}×</option>`).join("")}</select></label></div><label class="checkbox-label"><input name="preservePitch" type="checkbox" ${settings.preservePitch!=="false"?"checked":""}>${t("Preserve pitch")}</label><label class="checkbox-label"><input name="preventClipping" type="checkbox" ${settings.preventClipping!=="false"?"checked":""}>${t("Prevent clipping")}</label><label class="checkbox-label"><input name="visualizer" type="checkbox" ${settings.visualizer==="true"?"checked":""}>${t("Audio visualizer")}</label><p class="muted audio-note">${t("ReplayGain uses existing tags; tracks without tags keep their original level.")}</p><div class="actions"><button class="button primary" type="button" data-action="finish-audio-settings">${t("Close")}</button><button class="button" type="button" data-action="reset-audio">${t("Reset audio")}</button></div></form>`);
 const form=document.querySelector<HTMLFormElement>("#audio-settings")!;
 form.oninput=event=>{
  const target=event.target as HTMLInputElement|HTMLSelectElement,data=new FormData(form);
  if(target.name.startsWith("band"))form.querySelector<HTMLSelectElement>('[name="equalizer"]')!.value="Custom";
  if(target.name==="equalizer"){const preset=equalizerBands({...settings,equalizer:String(data.get("equalizer"))});form.querySelectorAll<HTMLInputElement>('.eq-band input').forEach((input,index)=>input.value=String(preset[index]));}
  for(const key of ["equalizer","preamp","balance","replayGain","playbackSpeed"])settings[key]=String(new FormData(form).get(key));
  for(const key of ["preservePitch","preventClipping","visualizer"])settings[key]=String(new FormData(form).has(key));
  settings.equalizerBands=JSON.stringify([...form.querySelectorAll<HTMLInputElement>('.eq-band input')].map(input=>{input.previousElementSibling!.textContent=`${Number(input.value)>0?"+":""}${input.value}`;return Number(input.value);}));
  applyEQ();applyPlaybackSpeed();startSpectrum();void effects.resume().catch(error=>toast(String(error)));
 };
 form.onchange=()=>{syncNowPlaying();if(!demo)void Service.saveSettings(settings).catch(error=>toast(String(error)));};
}
/** 自定义窗口内快捷键，拒绝重复键和已有的导航、输入快捷键。 */
function shortcutsModal():void {
 const saved=shortcuts(state.settings),labels:Record<string,string>={toggle:"Play / pause",next:"Next track",previous:"Previous track",mute:"Mute","volume-up":"Volume up","volume-down":"Volume down","seek-forward":"Seek forward","seek-backward":"Seek backward","mini-player":"Mini player","now-playing":"Now playing",queue:"Queue",lyrics:"Lyrics"};
 modal(`<h2>${t("Keyboard shortcuts")}</h2><form id="shortcuts-form"><p class="audio-note muted">${t("Click a field and press a key combination. Shortcuts work in the active app window.")}</p><div class="shortcut-list">${Object.keys(defaultShortcuts).map(action=>`<label><span>${t(labels[action])}</span><input readonly data-shortcut="${action}" data-chord="${h(saved[action])}" value="${h(shortcutLabel(saved[action],platform))}" aria-label="${h(t(labels[action]))}"></label>`).join("")}</div><p class="form-error" role="alert"></p><div class="actions"><button class="button primary" type="submit">${t("Save")}</button><button class="button" type="button" id="reset-shortcuts">${t("Restore defaults")}</button><button class="button" type="button" data-action="close-modal">${t("Cancel")}</button></div></form>`);
 const form=document.querySelector<HTMLFormElement>("#shortcuts-form")!;
 form.querySelectorAll<HTMLInputElement>("[data-shortcut]").forEach(input=>input.onkeydown=event=>{
  if(["Tab","Escape"].includes(event.key))return;
  event.preventDefault();event.stopPropagation();const chord=shortcutChord(event);if(!chord)return;
  const reserved=["Primary+KeyK","Primary+KeyA","Primary+KeyC","Primary+KeyV","Primary+KeyX","Primary+KeyZ","Primary+KeyQ","Primary+Shift+KeyQ","Primary+KeyW","Primary+KeyO","Primary+Shift+KeyO","Primary+KeyN","Alt+ArrowLeft","Alt+ArrowRight"];
  if(reserved.includes(chord)||[...form.querySelectorAll<HTMLInputElement>("[data-shortcut]")].some(other=>other!==input&&other.dataset.chord===chord)){form.querySelector(".form-error")!.textContent=t("This shortcut is already in use.");return;}
  if(!/[+]/.test(chord)&&!chord.startsWith("Arrow")&&!/^F\d+$/.test(chord)&&chord!=="Space"){form.querySelector(".form-error")!.textContent=t("Include Command, Control or Option for letter shortcuts.");return;}
  input.dataset.chord=chord;input.value=shortcutLabel(chord,platform);form.querySelector(".form-error")!.textContent="";
 });
 form.querySelector<HTMLButtonElement>("#reset-shortcuts")!.onclick=()=>{form.querySelectorAll<HTMLInputElement>("[data-shortcut]").forEach(input=>{input.dataset.chord=defaultShortcuts[input.dataset.shortcut!];input.value=shortcutLabel(input.dataset.chord,platform);});};
 form.onsubmit=event=>{event.preventDefault();void run(async()=>{state.settings.shortcuts=JSON.stringify(Object.fromEntries([...form.querySelectorAll<HTMLInputElement>("[data-shortcut]")].map(input=>[input.dataset.shortcut,input.dataset.chord])));if(!demo)await Service.saveSettings(state.settings);closeModal();});};
}
/** 执行工具栏、菜单和快捷键共享的动作。 */
async function action(name: string): Promise<void> {
 if(name==="lyric-settings"){lyricSettings();return;}
 if(name==="retry-lyrics"){requestLyrics(true);return;}
 if(name==="follow-lyrics"){state.settings.lyricAutoScroll=String(state.settings.lyricAutoScroll==="false"||lyricScrollPausedUntil>performance.now());lyricScrollPausedUntil=0;if(!demo)await Service.saveSettings(state.settings);render();return;}
 if(name==="volume-up"||name==="volume-down"){audio.volume=Math.min(1,Math.max(0,audio.volume+(name==="volume-up"?.05:-.05)));state.settings.volume=String(audio.volume);if(!demo)await Service.saveSettings(state.settings);render();return;}
 if(name==="seek-forward"||name==="seek-backward"){seekPosition(Math.max(0,(audio.src?audio.currentTime:resumePosition)+(name==="seek-forward"?10:-10)));return;}
 if(name==="import-lyrics"){if(!demo){const text=await Service.importLyrics();if(text)document.querySelector<HTMLTextAreaElement>('[name="lyrics"]')!.value=text;}return;}
 if(name==="export-lyrics"){if(!demo)await Service.exportLyrics(document.querySelector<HTMLTextAreaElement>('[name="lyrics"]')?.value||lyrics);return;}
 if(name==="shortcuts"){shortcutsModal();return;}
 if(name==="new-smart-playlist"){smartPlaylistModal();return;}
 if(name==="edit-smart-playlist"){smartPlaylistModal(state.playlists.find(item=>item.id===view.slice(9)));return;}
 if(name==="import-playlist"){if(demo){toast(t("Available in the desktop app"));return;}const result=await Service.importPlaylist();if(result.playlist?.id){state.playlists.push(result.playlist);await navigate(`playlist:${result.playlist.id}`);if(result.missing)toast(`${result.missing} ${t("Unmatched tracks")}`);}return;}
 if(name==="export-playlist"){const playlist=state.playlists.find(item=>item.id===view.slice(9));if(playlist&&!demo)await Service.exportPlaylist({...playlist,songs:[...shownSongs]});return;}
 if(name==="clear-history"){if(!confirm(t("Clear history")+"?"))return;if(!demo)await Service.clearListeningHistory();state.history=[];render();return;}
 if(name==="download-selected"){for(const song of shownSongs.filter(song=>selected.has(song.id)&&!["local","radio"].includes(song.profileID))){if(song.id!==activeDownload&&!downloadJobs.includes(song.id)&&!cachedSongs.some(item=>item.id===song.id))downloadJobs.push(song.id);}void processDownloads();return;}
 if(name==="finish-audio-settings"){render();return;}
 if(name==="reset-audio"){for(const key of ["equalizer","equalizerBands","preamp","balance","replayGain","playbackSpeed","preservePitch","preventClipping","visualizer"])delete state.settings[key];applyEQ();applyPlaybackSpeed();if(!demo)await Service.saveSettings(state.settings);audioSettings();return;}
 if(name==="mini-player"){miniMode=!miniMode;nowPlaying=false;if(!demo){await Service.setMiniPlayer(miniMode);if(miniMode)await Service.setPlayerOnTop(miniPinned);}render();return;}
 if(name==="pin-mini"){miniPinned=!miniPinned;if(!demo)await Service.setPlayerOnTop(miniPinned);render();return;}
 if(name==="ab-loop"){const position=audio.src?audio.currentTime:resumePosition;if(abStart===null){abStart=position;}else if(abEnd===null&&position>abStart+.5){abEnd=position;}else{abStart=null;abEnd=null;}render();return;}
 if(name==="mute"){const muted=!audio.muted;audio.muted=muted;otherAudio.muted=muted;render();return;}
 if(name==="audio-settings"){audioSettings();return;}
 if(name==="now-playing"){if(miniMode){await action("mini-player");return;}nowPlaying=!nowPlaying;if(nowPlaying)panel="";if(nowPlaying)requestLyrics();render();return;}
 if(name==="back"||name==="forward"){const from=name==="back"?backStack:forwardStack;const to=name==="back"?forwardStack:backStack;const target=from.pop();if(target){to.push({view,search});await navigate(target.view,false);search=target.search;render();}return;}
 if(name==="sort-direction"){state.settings.sortDescending=String(state.settings.sortDescending!=="true");page=0;if(!demo)await Service.saveSettings(state.settings);render();return;}
 if(name==="queue-selected"){enqueue(shownSongs.filter(song=>selected.has(song.id)));return;}
 if(name==="select-all"){shownSongs.forEach(song=>selected.add(song.id));render();return;}if(name==="clear-selection"){selected.clear();render();return;}
 if(name==="queue-next-all"||name==="queue-last-all"){enqueue(shownSongs,name==="queue-next-all");return;}
 if(name==="rename-playlist"){renamePlaylist();return;}
 if(name==="save-queue"){playlistModal(queue);return;}
 if(name==="clear-queue"){lyricRequest++;lyricsLoading=false;lyricsSong="";cancelTransition();audio.pause();audio.removeAttribute("src");audio.load();queue=[];current=-1;resumePosition=0;lyrics="";savePlayback();render();return;}
 if(name==="sync-cloud"){if(!demo){toast(t("Syncing…"));await Service.syncCloud();await refreshState();}render();toast(t("Sync now"));return;}
 if(name==="server"){serverModal();return;}if(name==="close-modal"){closeModal();return;}
 if(name==="play"){if(audio.paused)await toggle();return;}if(name==="pause"){pausePlayback();return;}
 if(name==="toggle"){await toggle();return;}if(name==="next"){await next();return;}if(name==="previous"){await previousTrack();return;}
 if(name==="shuffle"){shuffle=!shuffle;resetShuffle();savePlayback();render();return;}if(name==="repeat"){repeat=repeat==="off"?"all":repeat==="all"?"one":"off";savePlayback();render();return;}
 if(name==="play-all"||name==="shuffle-all"){await playList(shownSongs,name==="shuffle-all");return;}
 if(name==="queue"||name==="lyrics"){nowPlaying=false;panel=panel===name?"":name;if(panel==="lyrics")requestLyrics();render();return;}if(name==="close-panel"){panel="";render();return;}
 if(name==="refresh"){if(["radio","podcasts","downloads","server-playlists"].includes(view)||view.startsWith("server-playlist:"))await navigate(view,false);else await loadSource(source);return;}
 if(name==="import"||name==="import-files"){if(!demo){if(name==="import-files")await Service.importMusicFiles();else await Service.importMusic();await refreshState();}view="local";await loadSource("local");return;}
 if(name==="export"){if(!demo)await Service.exportProfiles();return;}if(name==="import-profiles"){if(!demo){await Service.importProfiles();await refreshState();}render();return;}
 if(name==="support"){if(!demo)await Service.openLink("https://apps.apple.com/app/id6784094020");return;}
 if(name==="airplay"){const player=audio as HTMLAudioElement&{webkitShowPlaybackTargetPicker?:()=>void};if(player.webkitShowPlaybackTargetPicker)player.webkitShowPlaybackTargetPicker();return;}
 if(name==="new-playlist"){playlistModal([]);return;}if(name==="add-selected"){playlistModal(shownSongs.filter(s=>selected.has(s.id)));return;}
 if(name==="delete-playlist"){const id=view.slice(9);if(!confirm(t("Remove")+"?"))return;if(!demo)await Service.deletePlaylist(id);state.playlists=state.playlists.filter(p=>p.id!==id);view="playlists";render();return;}
 if(name==="edit-lyrics"){if(!queue[current]){toast(t("Choose a song to see lyrics"));return;}const editedSong=queue[current].id;modal(`<h2>${t("Edit lyrics")}</h2><form id="lyric-form"><textarea name="lyrics" rows="14">${h(lyrics)}</textarea><div class="actions"><button type="button" class="button" data-action="import-lyrics">${t("Import lyrics")}</button><button type="button" class="button" data-action="export-lyrics">${t("Export lyrics")}</button></div><div class="actions"><button class="button primary">${t("Save")}</button><button type="button" class="button" data-action="close-modal">${t("Cancel")}</button></div></form>`);document.querySelector<HTMLFormElement>("#lyric-form")!.onsubmit=e=>{e.preventDefault();void run(async()=>{lyrics=String(new FormData(e.currentTarget as HTMLFormElement).get("lyrics")||"");if(!demo)await Service.saveLyrics(editedSong,lyrics);lyricRequest++;lyricsLoading=false;lyricsError="";render();});};return;}
}
/** 为曲目信息弹层绑定评分按钮，更新后立即显示新的评分。 */
function bindRatingActions(root:ParentNode=document):void {
 root.querySelectorAll<HTMLElement>("[data-rate-song]").forEach(node=>node.onclick=()=>void run(async()=>{const id=node.dataset.rateSong!,rating=Number(node.dataset.rating);const stats=state.stats[id]||{rating:0,playCount:0,lastPlayed:0};state.stats[id]=demo?{...stats,rating}:await Service.rateSong(id,rating);const song=[...shownSongs,...queue].find(item=>item.id===id);if(song){trackInfo(song);document.querySelector<HTMLElement>(`[data-rate-song="${CSS.escape(id)}"][data-rating="${rating}"]`)?.focus();}}));
}
/** 为当前 DOM 绑定用户操作，所有异步失败都有可见反馈。 */
function bind(): void {
 bindRatingActions();
 document.querySelectorAll<HTMLElement>("[data-reveal]").forEach(node=>node.onclick=()=>void run(async()=>{if(!demo)await Service.revealLocalSong(node.dataset.reveal!);}));
 document.querySelectorAll<HTMLElement>("[data-remove-local]").forEach(node=>node.onclick=()=>void run(async()=>{if(!confirm(t("Remove from library without deleting the original file?") ))return;const id=node.dataset.removeLocal!;if(!demo)await Service.removeLocalSong(id);state.imports=state.imports.filter(song=>song.id!==id);state.playlists=state.playlists.map(playlist=>({...playlist,songs:playlist.songs.filter(song=>song.id!==id)}));if(source==="local")songs=state.imports;render();}));
 document.querySelectorAll<HTMLElement>("[data-queue-page]").forEach(node=>node.onclick=()=>{queuePage=Number(node.dataset.queuePage);render();});
 document.querySelectorAll<HTMLButtonElement>("[data-page]").forEach(node=>node.onclick=()=>{page=Number(node.dataset.page);render();document.querySelector(".content")?.scrollTo(0,0);});
 const sorting=document.querySelector<HTMLSelectElement>("#sort-library");if(sorting)sorting.onchange=()=>void run(async()=>{state.settings.librarySort=sorting.value;page=0;if(!demo)await Service.saveSettings(state.settings);render();});
 const favoritesScope=document.querySelector<HTMLSelectElement>("#favorites-scope");if(favoritesScope)favoritesScope.onchange=()=>void run(async()=>{state.settings.favoritesScope=favoritesScope.value;page=0;selected.clear();if(!demo)await Service.saveSettings(state.settings);render();});
 const scope=document.querySelector<HTMLSelectElement>("#search-scope");if(scope)scope.onchange=()=>{searchScope=scope.value==="page"?"page":"library";page=0;render();};
 document.querySelectorAll<HTMLElement>("[data-info]").forEach(node=>node.onclick=()=>{const song=[...shownSongs,...favoriteSongs()].find(item=>item.id===node.dataset.info);if(song)trackInfo(song);});
 document.querySelectorAll<HTMLElement>("[data-queue-edit]").forEach(node=>node.onclick=()=>void run(()=>editQueue(Number(node.dataset.index),node.dataset.queueEdit!)));
 bindReorderRows(".queue-row",(from,to)=>editQueue(Number(from.dataset.queueRow),"move",Number(to.dataset.queueRow)));
 document.querySelectorAll<HTMLElement>("[data-playlist-remove]").forEach(node=>node.onclick=()=>void run(async()=>{const playlist=state.playlists.find(item=>item.id===view.slice(9));if(playlist)await updatePlaylist({...playlist,songs:playlist.songs.filter(song=>song.id!==node.dataset.playlistRemove)});}));
 document.querySelectorAll<HTMLElement>(".song-row[data-song-id]").forEach(node=>{node.oncontextmenu=event=>{event.preventDefault();document.querySelectorAll<HTMLDetailsElement>(".track-menu[open]").forEach(menu=>menu.open=false);const menu=node.querySelector<HTMLDetailsElement>(".track-menu");if(menu)menu.open=true;};});
 bindReorderRows(".song-row[data-song-id]",async(from,to)=>{const playlist=state.playlists.find(item=>item.id===view.slice(9));if(!playlist)return;if(state.settings.librarySort&&state.settings.librarySort!=="default"){toast(t("Use default order to rearrange"));return;}const list=[...playlist.songs],start=list.findIndex(song=>song.id===from.dataset.songId),end=list.findIndex(song=>song.id===to.dataset.songId);if(start<0||end<0)return;const [song]=list.splice(start,1);list.splice(end,0,song);await updatePlaylist({...playlist,songs:list});});
 document.querySelectorAll<HTMLElement>("[data-view]").forEach(node=>node.onclick=()=>void run(()=>navigate(node.dataset.view!)));
 document.querySelectorAll<HTMLElement>("[data-action]").forEach(node=>node.onclick=()=>void run(()=>action(node.dataset.action!)));
 document.querySelectorAll<HTMLElement>("[data-play]").forEach(node=>node.onclick=()=>void run(async()=>{queue=view==="library"&&!search?favoriteSongs():[...shownSongs];await play(queue.findIndex(s=>s.id===node.dataset.play));}));
 document.querySelectorAll<HTMLElement>("[data-favorite]").forEach(node=>node.onclick=()=>void run(async()=>{const id=node.dataset.favorite!,song=[...shownSongs,...queue,...favoriteSongs()].find(song=>song.id===id),enabled=demo?!state.favorites.includes(id):await Service.toggleFavorite(id);state.favorites=state.favorites.filter(value=>value!==id);if(enabled)state.favorites.push(id);state.favoriteSongs=state.favoriteSongs.filter(song=>song.id!==id);if(enabled&&song)state.favoriteSongs.push(song);render();}));
 document.querySelectorAll<HTMLInputElement>("[data-select]").forEach(node=>node.onchange=()=>{if(node.checked)selected.add(node.dataset.select!);else selected.delete(node.dataset.select!);const focus=node.dataset.select;render();document.querySelector<HTMLInputElement>(`[data-select="${CSS.escape(focus!)}"]`)?.focus();});
 document.querySelectorAll<HTMLElement>("[data-add]").forEach(node=>node.onclick=()=>playlistModal([...shownSongs,...favoriteSongs()].filter((song,index,list)=>song.id===node.dataset.add&&list.findIndex(item=>item.id===song.id)===index)));
 document.querySelectorAll<HTMLElement>("[data-queue],[data-queue-last]").forEach(node=>node.onclick=()=>{const id=node.dataset.queue||node.dataset.queueLast;enqueue([...shownSongs,...favoriteSongs()].filter((song,index,list)=>song.id===id&&list.findIndex(item=>item.id===id)===index),!!node.dataset.queue);});
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
 document.querySelectorAll<HTMLInputElement|HTMLSelectElement>("[data-setting]").forEach(node=>node.onchange=()=>void run(async()=>{state.settings[node.dataset.setting!]=node instanceof HTMLInputElement&&node.type==="checkbox"?String(node.checked):node.value;if(node.dataset.setting==="equalizer"){setupEQ();await effects.resume();applyEQ();}if(!demo)await Service.saveSettings(state.settings);applySettings();render();}));
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
 const seconds=Number(state.settings.crossfade||0);if(abEnd!==null||shuffle||repeat==="one"||!seconds||crossfading||audio.paused||!Number.isFinite(audio.duration)||audio.duration-audio.currentTime>seconds||current+1>=queue.length||demo)return;
 const generation=playGeneration;crossfading=true;const nextSong=queue[current+1];otherAudio.onended=null;otherAudio.ontimeupdate=null;otherAudio.src=mediaURL(`music://localhost/stream/${encodeURIComponent(nextSong.id)}`);otherAudio.volume=0;
 try {
  await ensureSong(nextSong);if(generation!==playGeneration)return;
  applyEQ();applyPlaybackSpeed();await effects.resume();
  await otherAudio.play();if(generation!==playGeneration)return;
  const started=performance.now();
  await new Promise<void>(resolve=>{const tick=()=>{if(generation!==playGeneration){resolve();return;}const ratio=Math.min((performance.now()-started)/(seconds*1000),1),volume=Number(state.settings.volume??"0.7");audio.volume=volume*(1-ratio);otherAudio.volume=volume*ratio;if(ratio<1&&!audio.paused)requestAnimationFrame(tick);else resolve();};tick();});
  if(generation!==playGeneration)return;
  audio.pause();[audio,otherAudio]=[otherAudio,audio];current++;listenedSeconds=0;lastListenPosition=audio.currentTime;playCountRecorded=false;applyEQ();attachAudio();lyrics="";if(Number.isFinite(audio.duration)&&audio.duration>0)nextSong.duration=audio.duration;await Service.recordPlay(nextSong);state.history=[nextSong,...state.history.filter(song=>song.id!==nextSong.id)].slice(0,500);syncNowPlaying();render();
  lyricsSong="";lyricRequest++;requestLyrics();
 }catch(e){if(generation===playGeneration)toast(String(e));}finally{if(generation===playGeneration)crossfading=false;}
}
/** 给当前音频对象挂载播放事件，切换音频实例后重新绑定。 */
function attachAudio(): void { audio.setAttribute("x-webkit-airplay","allow");audio.onended=()=>{if(!crossfading)void run(()=>repeat==="one"?play(current):next());};audio.ontimeupdate=()=>{trackListening();if(abStart!==null&&abEnd!==null&&audio.currentTime>=abEnd){audio.currentTime=abStart;lastListenPosition=abStart;}updateProgress();if(performance.now()-lastUpdate>1000){lastUpdate=performance.now();void crossfadeTick();}};audio.onerror=()=>toast(t("Playback unavailable. Check the source and audio format."));audio.onplay=()=>syncNowPlaying();audio.onpause=()=>syncNowPlaying(); }
/** 启动桌面应用，浏览器演示必须显式使用 demo 参数。 */
async function start(): Promise<void> {
 render();attachAudio();try{if(demo){demoState();applySettings();}else{platform=await Service.platform();cloudSupported=await Service.cloudSupported();await refreshState();audio.volume=Math.min(1,Math.max(0,Number(state.settings.volume??"0.7")||0));source=state.settings.source||state.profiles[0]?.id||"local";if(source!=="local"&&!state.profiles.some(profile=>profile.id===source))source="local";registerSongs([...state.cached,...state.imports,...state.history,...state.playlists.flatMap(list=>list.songs),...state.favoriteSongs]);cachedSongs=await Service.downloads();songs=await Service.cachedLibrary(source);registerSongs(songs);restorePlayback();busy=false;render();const profile=source,generation=loadGeneration;void(async()=>{try{const result=await Service.songs(profile);if(generation===loadGeneration&&source===profile){songs=result;registerSongs(result);render();}}catch(e){if(generation===loadGeneration&&source===profile)toast(songs.length?t("Using saved library. Server unavailable."):String(e));}})();}}catch(e){error=e instanceof Error?e.message:String(e);}finally{busy=false;render();}
 if(!demo&&platform==="darwin"&&cloudSupported&&state.settings.icloud==="true"){void run(async()=>{await Service.syncCloud();await refreshState();render();});setInterval(()=>{if(document.visibilityState==="visible")void run(async()=>{await Service.syncCloud();await refreshState();});},300000);}
 if(!demo){events.playbackCommand.on(command=>void run(()=>action(command)));events.navigationCommand.on(destination=>void run(()=>navigate(destination)));events.seekCommand.on(position=>seekPosition(position));}
 window.addEventListener("pagehide",savePlayback);
 document.addEventListener("visibilitychange",startSpectrum);
 document.addEventListener("keydown",e=>{
  const dialog=document.querySelector<HTMLElement>(".modal-backdrop");
  if(dialog){
   if(e.key==="Escape"){e.preventDefault();closeModal();}
   if(e.key==="Tab"){const nodes=[...dialog.querySelectorAll<HTMLElement>('button:not(:disabled),input:not(:disabled),select,textarea,a[href]')];const first=nodes[0],last=nodes[nodes.length-1];if(e.shiftKey&&document.activeElement===first){e.preventDefault();last?.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus();}}
   return;
  }
  const editing=(e.target as HTMLElement).matches("input,textarea,select,[contenteditable]");const shortcut=!editing?Object.entries(shortcuts(state.settings)).find(([,chord])=>chord===shortcutChord(e))?.[0]:undefined;if(shortcut&&!((e.target as HTMLElement).closest("button,a,summary")&&!e.metaKey&&!e.ctrlKey&&!e.altKey)){e.preventDefault();void run(()=>action(shortcut));return;}if((e.metaKey||e.ctrlKey)&&e.key.toLowerCase()==="k"){e.preventDefault();document.querySelector<HTMLInputElement>("#search")?.focus();}else if((e.altKey&&["ArrowLeft","ArrowRight"].includes(e.key))&&!editing){e.preventDefault();void run(()=>action(e.key==="ArrowLeft"?"back":"forward"));}else if((e.metaKey||e.ctrlKey)&&e.key.toLowerCase()==="a"&&!editing){e.preventDefault();void run(()=>action("select-all"));}else if(e.key==="Escape"){if(document.querySelector(".modal-backdrop")){closeModal();return;}if(nowPlaying){nowPlaying=false;render();}}else if(e.code==="Space"&&!editing&&!(e.target as HTMLElement).closest("button,a,summary")){e.preventDefault();void run(()=>toggle());}});
}
void start();
