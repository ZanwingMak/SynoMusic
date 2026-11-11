import type { Song } from "./mygo";

export const eqFrequencies=[31,62,125,250,500,1000,2000,4000,8000,16000];
export const eqPresets:Record<string,number[]>={Flat:[0,0,0,0,0,0,0,0,0,0],Bass:[6,5,4,2,0,0,-1,-2,-2,-2],Acoustic:[2,2,1,0,1,2,3,3,2,1],Vocal:[-2,-2,-1,0,2,3,4,3,1,0],Electronic:[4,4,2,0,-2,-2,1,3,4,3]};

/** 解析十段自定义增益，限制范围并兼容旧版均衡器预设。 */
export function equalizerBands(settings:Record<string,string>):number[] {
 if(settings.equalizer!=="Custom")return eqPresets[settings.equalizer||"Flat"]||eqPresets.Flat;
 try{const values=JSON.parse(settings.equalizerBands||"[]");return eqFrequencies.map((_,index)=>Math.min(12,Math.max(-12,Number(values[index])||0)));}catch{return [...eqPresets.Flat];}
}

/** 单个音频上下文处理双通道交叉淡入淡出，音量继续由播放器统一控制。 */
export class AudioEffects {
 private context?:AudioContext;
 private filters:BiquadFilterNode[]=[];
 private inputs=new WeakMap<HTMLAudioElement,GainNode>();
 private preamp?:GainNode;
 private balance?:StereoPannerNode;
 private limiter?:DynamicsCompressorNode;
 private analyser?:AnalyserNode;
 private spectrum=new Uint8Array(128);

 /** 仅在需要效果时创建音频图，原始播放模式不强制经过 DSP。 */
 private connect(elements:HTMLAudioElement[]):void {
  if(this.context)return;
  const context=this.context=new AudioContext(),input=context.createGain();
  for(const element of elements){const gain=context.createGain();context.createMediaElementSource(element).connect(gain);gain.connect(input);this.inputs.set(element,gain);}
  let output:AudioNode=input;
  this.filters=eqFrequencies.map((frequency,index)=>{const filter=context.createBiquadFilter();filter.type=index===0?"lowshelf":index===eqFrequencies.length-1?"highshelf":"peaking";filter.frequency.value=frequency;filter.Q.value=1;output.connect(filter);output=filter;return filter;});
  this.preamp=context.createGain();this.balance=context.createStereoPanner();this.limiter=context.createDynamicsCompressor();this.analyser=context.createAnalyser();
  this.analyser.fftSize=256;this.analyser.smoothingTimeConstant=.82;
  this.limiter.knee.value=0;this.limiter.ratio.value=20;this.limiter.attack.value=.003;this.limiter.release.value=.15;
  output.connect(this.preamp);this.preamp.connect(this.balance);this.balance.connect(this.limiter);this.limiter.connect(this.analyser);this.analyser.connect(context.destination);
 }

 /** 应用均衡器、前级、声道平衡及已有 ReplayGain 标签，缺失标签时保持单位增益。 */
 update(settings:Record<string,string>,audio:HTMLAudioElement,other:HTMLAudioElement,song?:Song,nextSong?:Song):void {
  const bands=equalizerBands(settings);
  if(!this.context&&(bands.some(value=>value!==0)||Number(settings.preamp)||Number(settings.balance)||["track","album"].includes(settings.replayGain)||settings.visualizer==="true"))this.connect([audio,other]);
  if(!this.context)return;
  const now=this.context.currentTime;
  this.filters.forEach((filter,index)=>filter.gain.setTargetAtTime(bands[index],now,.025));
  this.preamp!.gain.setTargetAtTime(10**(Math.min(12,Math.max(-12,Number(settings.preamp)||0))/20),now,.025);
  this.balance!.pan.setTargetAtTime(Math.min(1,Math.max(-1,Number(settings.balance)||0)),now,.025);
  this.limiter!.threshold.setTargetAtTime(settings.preventClipping==="false"?0:-.5,now,.025);
  this.limiter!.ratio.setTargetAtTime(settings.preventClipping==="false"?1:20,now,.025);
  for(const [element,item] of [[audio,song],[other,nextSong]] as const){
   const album=settings.replayGain==="album",enabled=album||settings.replayGain==="track";
   const db=enabled?(album?item?.albumGain??item?.trackGain:item?.trackGain)??0:0;
   let gain=10**(Math.min(20,Math.max(-30,db))/20);
   const peak=album?item?.albumPeak||item?.trackPeak:item?.trackPeak;
   if(settings.preventClipping!=="false"&&peak&&peak>0)gain=Math.min(gain,1/peak);
   this.inputs.get(element)?.gain.setTargetAtTime(gain,now,.025);
  }
 }

 /** 恢复用户手势允许的音频上下文。 */
 async resume():Promise<void> { if(this.context?.state==="suspended")await this.context.resume(); }

 /** 读取真实音频频谱；没有启用音频图时返回空值。 */
 frequencies():Uint8Array|null { if(!this.analyser)return null;this.analyser.getByteFrequencyData(this.spectrum);return this.spectrum; }
}
