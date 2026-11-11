import type { Song, SongStats, SmartPlaylist, PlaylistRule } from "./mygo";

/** 根据真实评分、播放记录与音频标签取得规则字段。 */
function ruleValue(song:Song,field:string,stats:Record<string,SongStats>,favorites:string[],downloads:Set<string>):string|number|boolean {
 if(field==="favorite")return favorites.includes(song.id);
 if(field==="downloaded")return downloads.has(song.id);
 if(["rating","playCount","lastPlayed"].includes(field))return stats[song.id]?.[field as keyof SongStats]||0;
 return song[field as keyof Song] as string|number||"";
}

/** 计算单条规则，时间范围以毫秒时间戳与自然日差值比较。 */
function matches(song:Song,rule:PlaylistRule,stats:Record<string,SongStats>,favorites:string[],downloads:Set<string>):boolean {
 const value=ruleValue(song,rule.field,stats,favorites,downloads),target=rule.value.trim().toLocaleLowerCase(),text=String(value).toLocaleLowerCase();
 switch(rule.operator){
  case "contains":return text.includes(target);
  case "notContains":return !text.includes(target);
  case "equals":return text===target;
  case "notEquals":return text!==target;
  case "greater":return Number(value)>Number(target);
  case "less":return Number(value)<Number(target);
  case "withinDays":return Number(value)>0&&Number(value)>=Date.now()-Math.max(0,Number(target))*86400000;
  case "olderDays":return !Number(value)||Number(value)<Date.now()-Math.max(0,Number(target))*86400000;
  default:return false;
 }
}

/** 动态筛选并排序智能歌单，每次查看都反映当前资料库和评分。 */
export function smartSongs(songs:Song[],smart:SmartPlaylist,stats:Record<string,SongStats>,favorites:string[],downloads:Set<string>):Song[] {
 let result=songs.filter(song=>song.profileID===smart.sourceID&&(!smart.rules.length||(smart.match==="any"?smart.rules.some(rule=>matches(song,rule,stats,favorites,downloads)):smart.rules.every(rule=>matches(song,rule,stats,favorites,downloads)))));
 const direction=smart.descending?-1:1;
 result=[...result].sort((a,b)=>{
  if(["rating","playCount","lastPlayed"].includes(smart.sort))return direction*((stats[a.id]?.[smart.sort as keyof SongStats]||0)-(stats[b.id]?.[smart.sort as keyof SongStats]||0))||a.title.localeCompare(b.title);
  if(["duration","year","trackNumber"].includes(smart.sort))return direction*(Number(a[smart.sort as keyof Song]||0)-Number(b[smart.sort as keyof Song]||0));
  return direction*String(a[smart.sort as keyof Song]||a.title).localeCompare(String(b[smart.sort as keyof Song]||b.title),undefined,{numeric:true,sensitivity:"base"});
 });
 return smart.limit>0?result.slice(0,smart.limit):result;
}

/** 按标题、艺人和相近时长列出可能重复项，不自动合并或删除任何文件。 */
export function possibleDuplicates(songs:Song[]):Song[] {
 const groups=new Map<string,Song[]>();
 for(const song of songs){
  const key=[song.title,song.artist].map(value=>value.normalize("NFKC").toLocaleLowerCase().replace(/[\s\p{P}]+/gu,"")).join("\0");
  if(!song.title||!song.artist)continue;
  const group=groups.get(key)||[];group.push(song);groups.set(key,group);
 }
 return [...groups.values()].flatMap(group=>group.filter(song=>group.some(other=>other.id!==song.id&&song.duration>0&&other.duration>0&&Math.abs(song.duration-other.duration)<=2)));
}

/** 返回本地统计总览，不推断更新前尚未记录的播放次数。 */
export function listeningStats(songs:Song[],stats:Record<string,SongStats>):{plays:number;rated:number;top:Song[]} {
 return {plays:Object.values(stats).reduce((sum,item)=>sum+item.playCount,0),rated:Object.values(stats).filter(item=>item.rating>0).length,top:songs.filter(song=>(stats[song.id]?.playCount||0)>0).sort((a,b)=>stats[b.id].playCount-stats[a.id].playCount).slice(0,30)};
}
