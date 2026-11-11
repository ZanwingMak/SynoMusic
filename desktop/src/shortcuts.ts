export const defaultShortcuts:Record<string,string>={toggle:"Primary+KeyP",next:"Primary+ArrowRight",previous:"Primary+ArrowLeft",mute:"Primary+Shift+KeyV","volume-up":"Alt+ArrowUp","volume-down":"Alt+ArrowDown","seek-forward":"ArrowRight","seek-backward":"ArrowLeft","mini-player":"Primary+Shift+KeyM","now-playing":"Primary+Shift+KeyF",queue:"Primary+Shift+KeyQ",lyrics:"Primary+Shift+KeyL"};

/** 将平台修饰键转换为稳定的快捷键标识，字母键不受输入语言影响。 */
export function shortcutChord(event:KeyboardEvent):string {
 if(["Meta","Control","Alt","Shift"].includes(event.key)||!event.code)return "";
 return [event.metaKey||event.ctrlKey?"Primary":"",event.altKey?"Alt":"",event.shiftKey?"Shift":"",event.code].filter(Boolean).join("+");
}

/** 仅接受已知动作的自定义键，损坏配置回退默认值。 */
export function shortcuts(settings:Record<string,string>):Record<string,string> {
 try{const saved=JSON.parse(settings.shortcuts||"{}");return Object.fromEntries(Object.entries(defaultShortcuts).map(([key,value])=>[key,typeof saved[key]==="string"?saved[key]:value]));}catch{return {...defaultShortcuts};}
}

/** 生成 Mac 与 Windows 对应的可读键帽文案。 */
export function shortcutLabel(chord:string,platform:string):string {
 return chord.replace(/Primary/g,platform==="darwin"?"⌘":"Ctrl").replace(/Alt/g,platform==="darwin"?"⌥":"Alt").replace(/Shift/g,"⇧").replace(/Key|Digit/g,"").replace(/ArrowRight/g,"→").replace(/ArrowLeft/g,"←").replace(/ArrowUp/g,"↑").replace(/ArrowDown/g,"↓").replace(/Space/g,"Space").split("+").join(" ");
}
