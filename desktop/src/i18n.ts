const entries: Record<string, string[]> = {
  en: ["Your music. Your space.","Library","Albums","Artists","All songs","Smart mixes","Favorites","Playlists","Local music","Downloads","History","Radio","Podcasts","Settings","Search your library","Add server","Import music","Recently added","Made for a little more listening.","Play all","Shuffle","Create playlist","No music yet","Connect your server or import a music folder to get started.","Connect a server","All features. Always free.","Support is optional. Music is for everyone.","Support development","Queue","Lyrics","No lyrics available","Edit lyrics","Save","Cancel","Name","Server address","Username","Password / token","Music source","Connect","Language","Appearance","System","Light","Dark","Crossfade","Equalizer","Sleep timer","Off","minutes","Export servers","Import servers","Privacy policy","Terms of use","Website","Source code","No results","Try another search or connect another music source.","No server connected","Playing next","Clear","Add to playlist","Remove","Download","Ready to listen","Demo library","General","Playback","Your sources","Local files","Search podcasts","Search radio","Subscribe","Subscribed","Fetching your music…","Refresh","Original quality","View on iPhone","Browse by album","Browse by artist","Browse your own collection","Recently played","Favorites, in one place","A mix for every moment","Server profiles","Shared music folders","Trust self-signed certificate","Library ID (optional)","Share / folder","Play","Pause","Synced lyrics","Lyric offset","Text size","Follow lyrics","Add selected to playlist","Manage previous subscriptions","iCloud sync","Sync now","Syncing…","Server playlists","Folders","Genres","More from your library","Use your Plex account","Sign in with Plex","Discover servers","Close window keeps music playing"],
  "zh-Hans": ["你的音乐，你的空间。","资料库","专辑","艺术家","全部歌曲","智能歌单","我喜欢的","我的歌单","本地音乐","下载","历史记录","电台","播客","设置","搜索你的资料库","添加服务器","导入音乐","最近添加","为每一次聆听，留一点时间。","播放全部","随机播放","新建歌单","还没有音乐","连接自己的服务器，或导入一个音乐文件夹。","连接服务器","全部功能，永久免费。","赞助完全自愿，每个人都能自在聆听。","感谢赞助开发","播放队列","歌词","暂无歌词","编辑歌词","保存","取消","名称","服务器地址","用户名","密码 / 令牌","音乐源","连接","语言","外观","跟随系统","浅色","深色","淡入淡出","均衡器","睡眠定时","关闭","分钟","导出服务器","导入服务器","隐私政策","服务条款","官网","源代码","没有找到结果","换一个关键词，或连接其他音乐源。","未连接服务器","接下来播放","清空","添加到歌单","移除","下载","随时开始聆听","演示资料库","通用","播放","你的音乐源","本地文件","搜索播客","搜索电台","订阅","已订阅","正在加载音乐…","刷新","原始音质","在 iPhone 上查看","按专辑浏览","按艺术家浏览","浏览自己的音乐收藏","最近播放","喜欢的音乐，都在这里","每一刻，都有合适的旋律","服务器配置","共享音乐文件夹","信任自签名证书","音乐库 ID（可选）","共享 / 文件夹","播放","暂停","同步歌词","歌词偏移","文字大小","跟随歌词","将选中歌曲添加到歌单","管理历史订阅","iCloud 同步","立即同步","正在同步…","服务器歌单","文件夹","音乐流派","探索资料库中的更多音乐","使用 Plex 账号","登录 Plex","发现服务器","关闭窗口后继续播放音乐"],
  "zh-Hant": ["你的音樂，你的空間。","資料庫","專輯","藝人","所有歌曲","智慧歌單","我的最愛","我的歌單","本機音樂","下載","播放記錄","電台","Podcast","設定","搜尋資料庫","新增伺服器","匯入音樂","最近加入","為每一次聆聽，留一點時間。","全部播放","隨機播放","新增歌單","還沒有音樂","連接自己的伺服器，或匯入音樂資料夾。","連接伺服器","所有功能，永遠免費。","贊助完全自願，每個人都能自在聆聽。","感謝贊助開發","播放佇列","歌詞","尚無歌詞","編輯歌詞","儲存","取消","名稱","伺服器位址","使用者名稱","密碼 / 權杖","音樂來源","連接","語言","外觀","跟隨系統","淺色","深色","交叉淡化","等化器","睡眠計時器","關閉","分鐘","匯出伺服器","匯入伺服器","隱私權政策","服務條款","官網","原始碼","找不到結果","換個關鍵字，或連接其他音樂來源。","未連接伺服器","接下來播放","清空","加入歌單","移除","下載","隨時開始聆聽","示範資料庫","一般","播放","你的音樂來源","本機檔案","搜尋 Podcast","搜尋電台","訂閱","已訂閱","正在載入音樂…","重新整理","原始音質","在 iPhone 上查看","依專輯瀏覽","依藝人瀏覽","瀏覽自己的音樂收藏","最近播放","喜愛的音樂，都在這裡","每一刻，都有合適的旋律","伺服器設定","共享音樂資料夾","信任自簽憑證","音樂庫 ID（選填）","共享 / 資料夾","播放","暫停","同步歌詞","歌詞偏移","文字大小","跟隨歌詞","將所選歌曲加入歌單","管理歷史訂閱","iCloud 同步","立即同步","正在同步…","伺服器歌單","資料夾","音樂類型","探索資料庫中的更多音樂","使用 Plex 帳號","登入 Plex","探索伺服器","關閉視窗後繼續播放音樂"],
  ja: ["あなたの音楽、あなたの空間。","ライブラリ","アルバム","アーティスト","すべての曲","スマートミックス","お気に入り","プレイリスト","ローカル音楽","ダウンロード","履歴","ラジオ","ポッドキャスト","設定","ライブラリを検索","サーバーを追加","音楽を読み込む","最近追加","音楽を、もう少しゆっくり。","すべて再生","シャッフル","プレイリストを作成","音楽がありません","サーバーに接続するか、音楽フォルダを読み込みます。","サーバーに接続","すべての機能が無料。","支援は任意。音楽はみんなのもの。","開発を応援","再生キュー","歌詞","歌詞はありません","歌詞を編集","保存","キャンセル","名前","サーバーアドレス","ユーザー名","パスワード / トークン","音楽ソース","接続","言語","外観","システム","ライト","ダーク","クロスフェード","イコライザー","スリープタイマー","オフ","分","サーバーを書き出す","サーバーを読み込む","プライバシーポリシー","利用規約","ウェブサイト","ソースコード","結果がありません","別の検索語か音楽ソースをお試しください。","サーバー未接続","次に再生","クリア","プレイリストに追加","削除","ダウンロード","音楽を聴く準備ができました","デモライブラリ","一般","再生","音楽ソース","ローカルファイル","ポッドキャストを検索","ラジオを検索","登録","登録済み","音楽を読み込み中…","更新","オリジナル音質","iPhone で表示","アルバムで表示","アーティストで表示","自分の音楽コレクション","最近再生","お気に入りをひとつに","気分に合うミックス","サーバー設定","共有音楽フォルダ","自己署名証明書を信頼","ライブラリ ID（任意）","共有 / フォルダ","再生","一時停止","同期歌詞","歌詞オフセット","文字サイズ","歌詞を追従","選択した曲をプレイリストに追加","以前のサブスクリプションを管理","iCloud 同期","今すぐ同期","同期中…","サーバーのプレイリスト","フォルダ","ジャンル","ライブラリをもっと楽しむ","Plex アカウントを使う","Plex にサインイン","サーバーを検索","ウインドウを閉じても再生を続ける"],
};
const base = entries.en;
const extra: Record<string, string[]> = {
  ko: ["나의 음악, 나만의 공간.","보관함","앨범","아티스트","모든 곡","스마트 믹스","좋아요","재생목록","로컬 음악","다운로드","기록","라디오","팟캐스트","설정","보관함 검색","서버 추가","음악 가져오기","최근 추가","음악을 조금 더 여유롭게.","모두 재생","셔플","재생목록 만들기","음악이 없습니다","서버에 연결하거나 음악 폴더를 가져오세요.","서버 연결","모든 기능은 언제나 무료.","후원은 선택 사항입니다.","개발 후원","재생 대기열","가사","가사가 없습니다","가사 편집","저장","취소","이름","서버 주소","사용자 이름","비밀번호 / 토큰","음악 소스","연결","언어","모양","시스템 설정","라이트","다크","크로스페이드","이퀄라이저","수면 타이머","끔","분","서버 내보내기","서버 가져오기","개인정보 처리방침","이용약관","웹사이트","소스 코드","결과가 없습니다","다른 검색어를 사용하거나 다른 음악 소스에 연결해 보세요.","연결된 서버가 없습니다","다음 재생","지우기","재생목록에 추가","제거","다운로드","음악을 들을 준비가 되었어요","데모 보관함","일반","재생","나의 음악 소스","로컬 파일","팟캐스트 검색","라디오 검색","구독","구독 중","음악을 불러오는 중…","새로 고침","원본 음질","iPhone에서 보기","앨범별 탐색","아티스트별 탐색","나만의 음악 둘러보기","최근 재생","좋아하는 음악을 한곳에","모든 순간에 어울리는 믹스","서버 설정","공유 음악 폴더","자체 서명 인증서 신뢰","보관함 ID(선택 사항)","공유 폴더 / 경로","재생","일시 정지","동기화 가사","가사 시간 조절","글자 크기","가사 따라가기","선택한 곡을 재생목록에 추가","이전 구독 관리","iCloud 동기화","지금 동기화","동기화 중…","서버 재생목록","폴더","장르","보관함에서 더 찾아보기","Plex 계정 사용","Plex에 로그인","서버 찾기","창을 닫아도 음악 계속 재생"],
  de: ["Deine Musik. Dein Raum.","Mediathek","Alben","Künstler","Alle Titel","Smarte Mixe","Favoriten","Playlists","Lokale Musik","Downloads","Verlauf","Radio","Podcasts","Einstellungen","Mediathek durchsuchen","Server hinzufügen","Musik importieren","Zuletzt hinzugefügt","Ein bisschen mehr Zeit für Musik.","Alles abspielen","Zufällig","Playlist erstellen","Noch keine Musik","Verbinde einen Server oder importiere einen Musikordner.","Server verbinden","Alle Funktionen. Immer kostenlos.","Unterstützung ist freiwillig. Musik ist für alle.","Entwicklung unterstützen","Warteschlange","Liedtexte","Keine Liedtexte verfügbar","Liedtexte bearbeiten","Speichern","Abbrechen","Name","Serveradresse","Benutzername","Passwort / Token","Musikquelle","Verbinden","Sprache","Erscheinungsbild","Systemeinstellung","Hell","Dunkel","Überblenden","Equalizer","Einschlaftimer","Aus","Minuten","Server exportieren","Server importieren","Datenschutz","Nutzungsbedingungen","Website","Quellcode","Keine Ergebnisse","Versuche einen anderen Suchbegriff oder verbinde eine andere Musikquelle.","Kein Server verbunden","Als Nächstes","Leeren","Zur Playlist hinzufügen","Entfernen","Herunterladen","Bereit zum Hören","Demo-Mediathek","Allgemein","Wiedergabe","Deine Musikquellen","Lokale Dateien","Podcasts suchen","Radiosender suchen","Abonnieren","Abonniert","Deine Musik wird geladen…","Aktualisieren","Originalqualität","Auf dem iPhone ansehen","Nach Alben durchsuchen","Nach Künstlern durchsuchen","Deine Sammlung entdecken","Zuletzt gespielt","Deine Favoriten an einem Ort","Ein Mix für jeden Moment","Serverprofile","Freigegebene Musikordner","Selbstsigniertem Zertifikat vertrauen","Mediathek-ID (optional)","Freigabe / Ordner","Abspielen","Pause","Synchronisierte Liedtexte","Liedtext-Zeitversatz","Schriftgröße","Liedtext automatisch folgen","Auswahl zur Playlist hinzufügen","Frühere Abonnements verwalten","iCloud-Synchronisierung","Jetzt synchronisieren","Wird synchronisiert…","Server-Playlists","Ordner","Genres","Mehr aus deiner Mediathek","Plex-Konto verwenden","Mit Plex anmelden","Server suchen","Musik beim Schließen des Fensters weiter abspielen"],
  fr: ["Votre musique. Votre espace.","Bibliothèque","Albums","Artistes","Tous les titres","Mix intelligents","Favoris","Playlists","Musique locale","Téléchargements","Historique","Radio","Podcasts","Réglages","Rechercher dans la bibliothèque","Ajouter un serveur","Importer de la musique","Ajouts récents","Un peu plus de temps pour écouter.","Tout écouter","Aléatoire","Créer une playlist","Aucune musique","Connectez un serveur ou importez un dossier de musique.","Connecter un serveur","Tout est gratuit. Toujours.","Le soutien est facultatif. La musique est pour tous.","Soutenir le développement","File d’attente","Paroles","Aucune parole disponible","Modifier les paroles","Enregistrer","Annuler","Nom","Adresse du serveur","Nom d’utilisateur","Mot de passe / jeton","Source musicale","Se connecter","Langue","Apparence","Réglage du système","Clair","Sombre","Fondu enchaîné","Égaliseur","Minuteur de veille","Désactivé","minutes","Exporter les serveurs","Importer les serveurs","Confidentialité","Conditions d’utilisation","Site web","Code source","Aucun résultat","Essayez une autre recherche ou connectez une autre source musicale.","Aucun serveur connecté","À suivre","Effacer","Ajouter à la playlist","Retirer","Télécharger","Prêt pour l’écoute","Bibliothèque de démo","Général","Lecture","Vos sources musicales","Fichiers locaux","Rechercher des podcasts","Rechercher des radios","S’abonner","Abonné","Chargement de votre musique…","Actualiser","Qualité d’origine","Voir sur iPhone","Parcourir par album","Parcourir par artiste","Parcourir votre collection","Écoutés récemment","Vos favoris au même endroit","Un mix pour chaque instant","Profils de serveur","Dossiers musicaux partagés","Faire confiance au certificat autosigné","ID de bibliothèque (facultatif)","Partage / dossier","Lire","Pause","Paroles synchronisées","Décalage des paroles","Taille du texte","Suivre les paroles","Ajouter la sélection à une playlist","Gérer les anciens abonnements","Synchronisation iCloud","Synchroniser maintenant","Synchronisation…","Playlists du serveur","Dossiers","Genres","Explorez votre bibliothèque","Utiliser votre compte Plex","Se connecter avec Plex","Rechercher des serveurs","Continuer la lecture après la fermeture de la fenêtre"],
};
for (const [lang, values] of Object.entries(extra)) entries[lang] = base.map((text,i)=>values[i]??text);
export const languages = [["en","English"],["zh-Hans","简体中文"],["zh-Hant","繁體中文"],["ja","日本語"],["ko","한국어"],["de","Deutsch"],["fr","Français"]];
let current = new URLSearchParams(location.search).get("lang") || localStorage.getItem("synomusic.language") || (navigator.language.startsWith("zh")?"zh-Hans":navigator.language.split("-")[0]);
/** 设置界面语言并保留本机偏好。 */
export function setLanguage(lang: string): void { current = entries[lang] ? lang : "en"; localStorage.setItem("synomusic.language",current); document.documentElement.lang=current; }

const featureLabels: Record<string, string[]> = {
  "Keyboard shortcuts": ["键盘快捷键", "鍵盤快捷鍵", "キーボードショートカット", "키보드 단축키", "Tastenkürzel", "Raccourcis clavier"],
  "Play / pause": ["播放 / 暂停", "播放 / 暫停", "再生 / 一時停止", "재생 / 일시 정지", "Wiedergabe / Pause", "Lecture / pause"],
  "Volume up": ["增大音量", "提高音量", "音量を上げる", "음량 높이기", "Lauter", "Augmenter le volume"],
  "Volume down": ["减小音量", "降低音量", "音量を下げる", "음량 낮추기", "Leiser", "Baisser le volume"],
  "Seek forward": ["快进 10 秒", "快轉 10 秒", "10秒進む", "10초 앞으로", "10 Sekunden vor", "Avancer de 10 secondes"],
  "Seek backward": ["后退 10 秒", "倒轉 10 秒", "10秒戻る", "10초 뒤로", "10 Sekunden zurück", "Reculer de 10 secondes"],
  "Restore defaults": ["恢复默认", "恢復預設", "初期設定に戻す", "기본값 복원", "Standard wiederherstellen", "Rétablir les valeurs"],
  "Click a field and press a key combination. Shortcuts work in the active app window.": ["点击输入框后按下组合键，快捷键仅在当前应用窗口内生效。", "點擊欄位後按下組合鍵，快捷鍵僅在目前應用程式視窗內生效。", "欄をクリックしてキーを押します。ショートカットはアクティブなウインドウで有効です。", "입력란을 누르고 키 조합을 입력하세요. 활성 앱 창에서 작동합니다.", "Feld anklicken und Tastenkombination drücken. Kürzel gelten im aktiven App-Fenster.", "Cliquez sur un champ puis appuyez sur une combinaison. Les raccourcis fonctionnent dans la fenêtre active."],
  "This shortcut is already in use.": ["这个快捷键已被占用。", "這個快捷鍵已被使用。", "このショートカットは使用中です。", "이미 사용 중인 단축키입니다.", "Dieses Kürzel wird bereits verwendet.", "Ce raccourci est déjà utilisé."],
  "Include Command, Control or Option for letter shortcuts.": ["字母快捷键请搭配 Command、Control 或 Option。", "字母快捷鍵請搭配 Command、Control 或 Option。", "文字キーにはCommand、ControlまたはOptionを組み合わせてください。", "문자 단축키에는 Command, Control 또는 Option을 포함하세요.", "Buchstabenkürzel benötigen Command, Control oder Option.", "Associez les lettres à Command, Control ou Option."],
  "Import lyrics": ["导入歌词", "匯入歌詞", "歌詞を読み込む", "가사 가져오기", "Liedtext importieren", "Importer les paroles"],
  "Export lyrics": ["导出歌词", "匯出歌詞", "歌詞を書き出す", "가사 내보내기", "Liedtext exportieren", "Exporter les paroles"],
  "Show in file manager": ["在文件管理器中显示", "在檔案管理器中顯示", "ファイル管理で表示", "파일 관리자에서 표시", "Im Dateimanager anzeigen", "Afficher dans le gestionnaire de fichiers"],
  "Remove from library": ["从资料库移除", "從資料庫移除", "ライブラリから削除", "보관함에서 제거", "Aus Mediathek entfernen", "Retirer de la bibliothèque"],
  "Remove from library without deleting the original file?": ["从资料库移除这个条目？原始音频文件会保留。", "從資料庫移除此項目？原始音訊檔案會保留。", "元のファイルを残してライブラリから削除しますか？", "원본 파일을 유지하고 보관함에서 제거할까요?", "Aus der Mediathek entfernen und Originaldatei behalten?", "Retirer de la bibliothèque en conservant le fichier original ?"],
  "Import audio files":["导入音频文件","匯入音訊檔案","音声ファイルを読み込む","오디오 파일 가져오기","Audiodateien importieren","Importer des fichiers audio"],
  "Clear history":["清空播放历史","清空播放記錄","再生履歴を消去","재생 기록 지우기","Verlauf leeren","Effacer l’historique"],
  "Duration (seconds)":["时长（秒）","時長（秒）","再生時間（秒）","재생 시간(초)","Dauer (Sekunden)","Durée (secondes)"],
  "Yes":["是","是","はい","예","Ja","Oui"],
  "No":["否","否","いいえ","아니요","Nein","Non"],
  "Audio settings": ["音频设置", "音訊設定", "オーディオ設定", "오디오 설정", "Audioeinstellungen", "Réglages audio"],
  "Customize audio": ["调整音频", "調整音訊", "音質を調整", "오디오 조정", "Audio anpassen", "Personnaliser le son"],
  "Custom": ["自定义", "自訂", "カスタム", "사용자 지정", "Benutzerdefiniert", "Personnalisé"],
  "Preamp": ["前级增益（dB）", "前級增益（dB）", "プリアンプ（dB）", "프리앰프(dB)", "Vorverstärkung (dB)", "Préampli (dB)"],
  "Track gain": ["按曲目", "依曲目", "トラック単位", "트랙 기준", "Titelverstärkung", "Gain par titre"],
  "Album gain": ["按专辑", "依專輯", "アルバム単位", "앨범 기준", "Albumverstärkung", "Gain par album"],
  "Balance": ["左右声道平衡", "左右聲道平衡", "左右バランス", "좌우 균형", "Balance", "Balance"],
  "Playback speed": ["播放速度", "播放速度", "再生速度", "재생 속도", "Wiedergabegeschwindigkeit", "Vitesse de lecture"],
  "Preserve pitch": ["保持音高", "保持音高", "音程を維持", "음높이 유지", "Tonhöhe beibehalten", "Conserver la hauteur"],
  "Prevent clipping": ["防止削波失真", "避免削波失真", "クリッピングを防ぐ", "클리핑 방지", "Übersteuerung verhindern", "Éviter la saturation"],
  "Audio visualizer": ["真实音频频谱", "真實音訊頻譜", "オーディオスペクトラム", "실제 오디오 스펙트럼", "Audiospektrum", "Spectre audio"],
  "ReplayGain uses existing tags; tracks without tags keep their original level.": ["ReplayGain 使用音频已有的增益标签；没有标签的曲目保持原始音量。", "ReplayGain 使用音訊既有的增益標籤；沒有標籤的曲目維持原始音量。", "ReplayGainタグがある曲に適用します。タグのない曲は元の音量を維持します。", "기존 ReplayGain 태그를 사용하며 태그가 없는 곡은 원래 음량을 유지합니다.", "ReplayGain verwendet vorhandene Tags. Titel ohne Tags behalten ihren Originalpegel.", "ReplayGain utilise les tags existants. Les titres sans tags gardent leur niveau original."],
  "Reset audio": ["重置音频设置", "重設音訊設定", "音質設定をリセット", "오디오 설정 초기화", "Audio zurücksetzen", "Réinitialiser le son"],
  "Mini player": ["迷你播放器", "迷你播放器", "ミニプレーヤー", "미니 플레이어", "Miniplayer", "Mini-lecteur"],
  "Full player": ["完整播放器", "完整播放器", "通常のプレーヤー", "전체 플레이어", "Vollständiger Player", "Lecteur complet"],
  "Always on top": ["始终置顶", "永遠置頂", "常に手前に表示", "항상 위에 표시", "Immer im Vordergrund", "Toujours au premier plan"],
  "A–B repeat": ["A–B 区间循环", "A–B 區間循環", "A–Bリピート", "A–B 구간 반복", "A–B-Wiederholung", "Répétition A–B"],
  "Audio output": ["音频输出", "音訊輸出", "オーディオ出力", "오디오 출력", "Audioausgabe", "Sortie audio"],
  "Mute": ["静音", "靜音", "ミュート", "음소거", "Stumm", "Couper le son"],
  "Unmute": ["取消静音", "取消靜音", "ミュート解除", "음소거 해제", "Ton einschalten", "Rétablir le son"],
  "Listening stats": ["聆听统计", "聆聽統計", "再生統計", "청취 통계", "Hörstatistik", "Statistiques d’écoute"],
  "Your listening": ["你的聆听记录", "你的聆聽記錄", "あなたの再生記録", "나의 청취 기록", "Deine Hörgewohnheiten", "Votre écoute"],
  "Play count": ["播放次数", "播放次數", "再生回数", "재생 횟수", "Wiedergaben", "Nombre d’écoutes"],
  "Rating": ["评分", "評分", "評価", "별점", "Bewertung", "Note"],
  "Clear rating": ["取消评分", "取消評分", "評価をクリア", "별점 지우기", "Bewertung löschen", "Effacer la note"],
  "Rated tracks": ["已评分曲目", "已評分曲目", "評価済みの曲", "별점을 준 곡", "Bewertete Titel", "Titres notés"],
  "Most played": ["最常播放", "最常播放", "よく再生する曲", "자주 듣는 곡", "Meistgespielt", "Les plus écoutés"],
  "Last played": ["上次播放", "上次播放", "最後に再生", "최근 재생", "Zuletzt gespielt", "Dernière écoute"],
  "Listening statistics start from this update.": ["播放统计从本次更新开始累计，旧记录不作推算。", "播放統計從這次更新起累計，不推算舊記錄。", "再生統計は今回の更新から記録します。", "청취 통계는 이번 업데이트부터 기록됩니다.", "Die Wiedergabestatistik beginnt mit diesem Update.", "Les statistiques commencent avec cette mise à jour."],
  "Possible duplicates": ["可能重复的曲目", "可能重複的曲目", "重複の可能性がある曲", "중복 가능성이 있는 곡", "Mögliche Duplikate", "Doublons possibles"],
  "Matches use title, artist and similar duration. Original files are preserved.": ["按标题、艺人和相近时长查找候选，不自动修改原始文件。", "依標題、藝人和相近時長查找候選，不自動修改原始檔案。", "曲名、アーティスト、近い再生時間で検索します。元のファイルは変更しません。", "제목, 아티스트와 비슷한 재생 시간으로 찾으며 원본은 변경하지 않습니다.", "Abgleich nach Titel, Künstler und ähnlicher Dauer. Originaldateien bleiben erhalten.", "Recherche par titre, artiste et durée proche. Les fichiers originaux sont conservés."],
  "No duplicate candidates": ["未发现重复候选", "未發現重複候選", "重複候補はありません", "중복 후보가 없습니다", "Keine möglichen Duplikate", "Aucun doublon potentiel"],
  "New smart playlist": ["新建智能歌单", "新增智慧歌單", "スマートプレイリストを作成", "스마트 재생목록 만들기", "Neue intelligente Liste", "Nouvelle liste intelligente"],
  "Edit smart playlist": ["编辑智能歌单", "編輯智慧歌單", "スマートプレイリストを編集", "스마트 재생목록 편집", "Intelligente Liste bearbeiten", "Modifier la liste intelligente"],
  "Smart playlist": ["智能歌单", "智慧歌單", "スマートプレイリスト", "스마트 재생목록", "Intelligente Liste", "Liste intelligente"],
  "Match rules": ["匹配方式", "比對方式", "条件の一致", "규칙 일치", "Regeln abgleichen", "Correspondance des règles"],
  "All rules": ["满足全部规则", "符合全部規則", "すべての条件", "모든 규칙", "Alle Regeln", "Toutes les règles"],
  "Any rule": ["满足任一规则", "符合任一規則", "いずれかの条件", "하나 이상의 규칙", "Eine beliebige Regel", "Une règle au choix"],
  "Add rule": ["添加规则", "新增規則", "条件を追加", "규칙 추가", "Regel hinzufügen", "Ajouter une règle"],
  "Contains": ["包含", "包含", "含む", "포함", "Enthält", "Contient"],
  "Does not contain": ["不包含", "不包含", "含まない", "포함하지 않음", "Enthält nicht", "Ne contient pas"],
  "Is": ["等于", "等於", "等しい", "같음", "Ist", "Est"],
  "Is not": ["不等于", "不等於", "等しくない", "같지 않음", "Ist nicht", "N’est pas"],
  "Greater than": ["大于", "大於", "より大きい", "보다 큼", "Größer als", "Supérieur à"],
  "Less than": ["小于", "小於", "より小さい", "보다 작음", "Kleiner als", "Inférieur à"],
  "Within days": ["最近天数内", "最近天數內", "日以内", "최근 일 이내", "Innerhalb von Tagen", "Dans les derniers jours"],
  "Older than days": ["超过天数未播", "超過天數未播", "日以上前", "일 이상 지남", "Älter als Tage", "Plus ancien que ces jours"],
  "Limit tracks": ["曲目上限（0 为不限）", "曲目上限（0 為不限）", "曲数の上限（0は無制限）", "최대 곡 수(0은 무제한)", "Titellimit (0 unbegrenzt)", "Limite de titres (0 sans limite)"],
  "Matching tracks": ["首匹配曲目", "首符合的曲目", "曲が一致", "곡 일치", "passende Titel", "titres correspondants"],
  "Rule field": ["规则字段", "規則欄位", "条件の項目", "규칙 항목", "Regelfeld", "Champ de règle"],
  "Rule operator": ["比较方式", "比較方式", "比較方法", "비교 방식", "Vergleich", "Comparaison"],
  "Rule value": ["规则值", "規則值", "条件の値", "규칙 값", "Regelwert", "Valeur de règle"],
  "No matching tracks": ["暂时没有符合规则的曲目", "目前沒有符合規則的曲目", "条件に合う曲はありません", "조건에 맞는 곡이 없습니다", "Keine passenden Titel", "Aucun titre correspondant"],
  "Import playlist": ["导入歌单", "匯入歌單", "プレイリストを読み込む", "재생목록 가져오기", "Wiedergabeliste importieren", "Importer une liste"],
  "Export playlist": ["导出歌单", "匯出歌單", "プレイリストを書き出す", "재생목록 내보내기", "Wiedergabeliste exportieren", "Exporter une liste"],
  "Unmatched tracks": ["首曲目未匹配", "首曲目未符合", "曲は未一致", "곡 불일치", "nicht zugeordnete Titel", "titres non retrouvés"],
  "Download selected": ["下载选中曲目", "下載所選曲目", "選択した曲をダウンロード", "선택한 곡 다운로드", "Auswahl herunterladen", "Télécharger la sélection"],
  "Available in the desktop app": ["请在桌面客户端使用", "請在桌面用戶端使用", "デスクトップ版で利用できます", "데스크톱 앱에서 사용할 수 있습니다", "In der Desktop-App verfügbar", "Disponible dans l’application de bureau"],
  "Live": ["直播","直播","ライブ","라이브","Live","En direct"],
  "Using saved library. Server unavailable.": ["服务器暂不可用，正在使用已保存的资料库。", "伺服器暫不可用，正在使用已儲存的資料庫。", "サーバーに接続できないため保存済みライブラリを表示しています。", "서버에 연결할 수 없어 저장된 보관함을 표시합니다.", "Server nicht verfügbar. Gespeicherte Mediathek wird verwendet.", "Serveur indisponible. La bibliothèque enregistrée est utilisée."],
  "Downloaded": ["已下载", "已下載", "ダウンロード済み", "다운로드됨", "Heruntergeladen", "Téléchargé"],
  "Downloading…": ["正在下载…", "正在下載…", "ダウンロード中…", "다운로드 중…", "Wird heruntergeladen…", "Téléchargement…"],
  "Remove download": ["移除下载", "移除下載", "ダウンロードを削除", "다운로드 제거", "Download entfernen", "Retirer le téléchargement"],
  "Download removed": ["下载已移除", "下載已移除", "ダウンロードを削除しました", "다운로드를 제거했습니다", "Download entfernt", "Téléchargement retiré"],
  "No downloads yet": ["还没有下载音乐，可从歌曲的更多菜单下载。", "尚未下載音樂，可從歌曲的更多選單下載。", "曲のメニューから音楽をダウンロードできます。", "곡의 더 보기 메뉴에서 음악을 다운로드하세요.", "Lade Musik über das Titelmenü herunter.", "Téléchargez de la musique depuis le menu d’un titre."],
  "No favorites yet": ["点击歌曲旁的爱心，即可收藏喜欢的音乐。", "點擊歌曲旁的愛心，即可收藏喜愛的音樂。", "曲のハートを押してお気に入りに追加できます。", "곡 옆의 하트를 눌러 좋아요에 추가하세요.", "Markiere Titel mit dem Herz als Favoriten.", "Ajoutez des favoris avec le cœur à côté d’un titre."],
  "No listening history yet": ["播放过的歌曲会出现在这里。", "播放過的歌曲會顯示在這裡。", "再生した曲がここに表示されます。", "재생한 곡이 여기에 표시됩니다.", "Abgespielte Titel erscheinen hier.", "Les titres écoutés apparaîtront ici."],
  "This playlist is empty": ["这张歌单暂时没有歌曲。", "這張歌單暫時沒有歌曲。", "このプレイリストには曲がありません。", "이 재생목록은 비어 있습니다.", "Diese Playlist ist leer.", "Cette playlist est vide."],
  "Playback position": ["播放进度", "播放進度", "再生位置", "재생 위치", "Wiedergabeposition", "Position de lecture"],
  "Volume": ["音量", "音量", "音量", "음량", "Lautstärke", "Volume"],
  "Edit server": ["编辑服务器", "編輯伺服器", "サーバーを編集", "서버 편집", "Server bearbeiten", "Modifier le serveur"],
  "Remove server": ["移除服务器", "移除伺服器", "サーバーを削除", "서버 제거", "Server entfernen", "Retirer le serveur"],
  "Sleep timer finished": ["睡眠定时已结束，播放已暂停。", "睡眠計時已結束，播放已暫停。", "スリープタイマーで再生を停止しました。", "수면 타이머가 끝나 재생을 일시 정지했습니다.", "Der Einschlaftimer hat die Wiedergabe pausiert.", "Le minuteur a mis la lecture en pause."],
  "Unknown artist": ["未知艺术家", "未知藝人", "不明なアーティスト", "알 수 없는 아티스트", "Unbekannter Künstler", "Artiste inconnu"],
  "Search": ["搜索", "搜尋", "検索", "검색", "Suchen", "Rechercher"],
  "Episodes": ["查看单集", "查看單集", "エピソード", "에피소드", "Folgen", "Épisodes"],
  "Search for a podcast to get started.": ["搜索节目，或订阅你喜欢的播客。", "搜尋節目，或訂閱喜歡的 Podcast。", "番組を検索してポッドキャストを登録できます。", "프로그램을 검색하거나 팟캐스트를 구독하세요.", "Suche einen Podcast und abonniere deine Favoriten.", "Recherchez un podcast et abonnez-vous à vos favoris."],
  "Playback unavailable. Check the source and audio format.": ["无法播放，请检查音乐源和音频格式。", "無法播放，請檢查音樂來源和音訊格式。", "再生できません。ソースと音声形式を確認してください。", "재생할 수 없습니다. 소스와 오디오 형식을 확인하세요.", "Wiedergabe nicht verfügbar. Quelle und Audioformat prüfen.", "Lecture indisponible. Vérifiez la source et le format audio."],
  "Loading episodes…": ["正在加载单集…", "正在載入單集…", "エピソードを読み込み中…", "에피소드 불러오는 중…", "Folgen werden geladen…", "Chargement des épisodes…"],
  "Reorder": ["拖动排序", "拖動排序", "ドラッグして並べ替え", "드래그하여 재정렬", "Ziehen zum Sortieren", "Glisser pour réorganiser"],
  "Now playing": ["正在播放","正在播放","再生中","지금 재생 중","Jetzt läuft","À l’écoute"],
  "hours": [
    "小时",
    "小時",
    "時間",
    "시간",
    "Std.",
    "heures"
  ],
  "Sort by": [
    "排序",
    "排序",
    "並べ替え",
    "정렬",
    "Sortieren",
    "Trier"
  ],
  "Default order": [
    "默认顺序",
    "預設順序",
    "標準の順序",
    "기본 순서",
    "Standardreihenfolge",
    "Ordre par défaut"
  ],
  "Title": [
    "标题",
    "標題",
    "タイトル",
    "제목",
    "Titel",
    "Titre"
  ],
  "Duration": [
    "时长",
    "時長",
    "再生時間",
    "길이",
    "Dauer",
    "Durée"
  ],
  "Track number": [
    "音轨编号",
    "音軌編號",
    "トラック番号",
    "트랙 번호",
    "Titelnummer",
    "Numéro de piste"
  ],
  "Descending": [
    "降序",
    "降冪",
    "降順",
    "내림차순",
    "Absteigend",
    "Décroissant"
  ],
  "Ascending": [
    "升序",
    "升冪",
    "昇順",
    "오름차순",
    "Aufsteigend",
    "Croissant"
  ],
  "Reverse sort": [
    "反转排序",
    "反轉排序",
    "並び順を反転",
    "정렬 순서 반전",
    "Sortierung umkehren",
    "Inverser le tri"
  ],
  "Selected": [
    "已选择",
    "已選取",
    "選択済み",
    "선택됨",
    "ausgewählt",
    "sélectionnés"
  ],
  "Select all": [
    "全选",
    "全選",
    "すべて選択",
    "모두 선택",
    "Alles auswählen",
    "Tout sélectionner"
  ],
  "Clear selection": [
    "取消选择",
    "取消選取",
    "選択解除",
    "선택 해제",
    "Auswahl aufheben",
    "Désélectionner"
  ],
  "Various artists": [
    "群星",
    "群星",
    "さまざまなアーティスト",
    "여러 아티스트",
    "Verschiedene Künstler",
    "Artistes variés"
  ],
  "Tracks": [
    "首歌曲",
    "首歌曲",
    "曲",
    "곡",
    "Titel",
    "titres"
  ],
  "Play next": [
    "下一首播放",
    "下一首播放",
    "次に再生",
    "다음에 재생",
    "Als Nächstes abspielen",
    "Écouter ensuite"
  ],
  "Add to queue": [
    "加入播放队列",
    "加入播放佇列",
    "キューの末尾に追加",
    "대기열에 추가",
    "Zur Warteschlange hinzufügen",
    "Ajouter à la file"
  ],
  "Added to queue": [
    "已加入队列",
    "已加入佇列",
    "キューに追加しました",
    "대기열에 추가됨",
    "Zur Warteschlange hinzugefügt",
    "Ajouté à la file"
  ],
  "Rename playlist": [
    "重命名歌单",
    "重新命名歌單",
    "プレイリスト名を変更",
    "재생목록 이름 변경",
    "Playlist umbenennen",
    "Renommer la playlist"
  ],
  "Album artist": [
    "专辑艺人",
    "專輯藝人",
    "アルバムアーティスト",
    "앨범 아티스트",
    "Albumkünstler",
    "Artiste de l’album"
  ],
  "Year": [
    "年份",
    "年份",
    "年",
    "연도",
    "Jahr",
    "Année"
  ],
  "Disc number": [
    "碟片编号",
    "碟片編號",
    "ディスク番号",
    "디스크 번호",
    "CD-Nummer",
    "Numéro de disque"
  ],
  "Codec": [
    "编码格式",
    "編碼格式",
    "コーデック",
    "코덱",
    "Codec",
    "Codec"
  ],
  "Bitrate": [
    "比特率",
    "位元率",
    "ビットレート",
    "비트 전송률",
    "Bitrate",
    "Débit"
  ],
  "Sample rate": [
    "采样率",
    "取樣率",
    "サンプルレート",
    "샘플링 속도",
    "Abtastrate",
    "Fréquence d’échantillonnage"
  ],
  "File path": [
    "文件路径",
    "檔案路徑",
    "ファイルの場所",
    "파일 경로",
    "Dateipfad",
    "Chemin du fichier"
  ],
  "Song information": [
    "歌曲信息",
    "歌曲資訊",
    "曲の情報",
    "곡 정보",
    "Titelinformationen",
    "Informations du titre"
  ],
  "Close": [
    "关闭",
    "關閉",
    "閉じる",
    "닫기",
    "Schließen",
    "Fermer"
  ],
  "Back": [
    "后退",
    "返回",
    "戻る",
    "뒤로",
    "Zurück",
    "Retour"
  ],
  "Forward": [
    "前进",
    "前進",
    "進む",
    "앞으로",
    "Vorwärts",
    "Suivant"
  ],
  "Search scope": [
    "搜索范围",
    "搜尋範圍",
    "検索範囲",
    "검색 범위",
    "Suchbereich",
    "Portée de recherche"
  ],
  "Entire library": [
    "整个资料库",
    "整個資料庫",
    "ライブラリ全体",
    "전체 라이브러리",
    "Gesamte Mediathek",
    "Toute la bibliothèque"
  ],
  "Current view": [
    "当前页面",
    "目前頁面",
    "現在の表示",
    "현재 보기",
    "Aktuelle Ansicht",
    "Vue actuelle"
  ],
  "More actions": [
    "更多操作",
    "更多操作",
    "その他の操作",
    "추가 작업",
    "Weitere Aktionen",
    "Autres actions"
  ],
  "Go to artist": [
    "前往艺人",
    "前往藝人",
    "アーティストを表示",
    "아티스트로 이동",
    "Zum Künstler",
    "Voir l’artiste"
  ],
  "Remove from playlist": [
    "从歌单移除",
    "從歌單移除",
    "プレイリストから削除",
    "재생목록에서 제거",
    "Aus Playlist entfernen",
    "Retirer de la playlist"
  ],
  "Previous page": [
    "上一页",
    "上一頁",
    "前のページ",
    "이전 페이지",
    "Vorherige Seite",
    "Page précédente"
  ],
  "Next page": [
    "下一页",
    "下一頁",
    "次のページ",
    "다음 페이지",
    "Nächste Seite",
    "Page suivante"
  ],
  "Save as playlist": [
    "保存为歌单",
    "儲存為歌單",
    "プレイリストとして保存",
    "재생목록으로 저장",
    "Als Playlist speichern",
    "Enregistrer en playlist"
  ],
  "Move up": [
    "上移",
    "上移",
    "上へ移動",
    "위로 이동",
    "Nach oben",
    "Monter"
  ],
  "Move down": [
    "下移",
    "下移",
    "下へ移動",
    "아래로 이동",
    "Nach unten",
    "Descendre"
  ],
  "Remove from queue": [
    "从队列移除",
    "從佇列移除",
    "キューから削除",
    "대기열에서 제거",
    "Aus Warteschlange entfernen",
    "Retirer de la file"
  ],
  "Queue is empty": [
    "队列为空",
    "佇列為空",
    "キューは空です",
    "대기열이 비어 있습니다",
    "Warteschlange ist leer",
    "La file est vide"
  ],
  "Use default order to rearrange": [
    "切换为默认顺序后可拖动排序",
    "切換為預設順序後可拖曳排序",
    "標準の順序で並べ替えてください",
    "기본 순서로 전환한 후 이동하세요",
    "Zum Verschieben Standardreihenfolge wählen",
    "Choisissez l’ordre par défaut pour réorganiser"
  ],
  "Repeat one": [
    "单曲循环",
    "單曲循環",
    "1曲リピート",
    "한 곡 반복",
    "Einen Titel wiederholen",
    "Répéter le titre"
  ],
  "Repeat all": [
    "列表循环",
    "清單循環",
    "すべてリピート",
    "전체 반복",
    "Alle wiederholen",
    "Tout répéter"
  ],
  "Repeat off": [
    "关闭循环",
    "關閉循環",
    "リピートなし",
    "반복 끄기",
    "Wiederholung aus",
    "Répétition désactivée"
  ],
  "Previous track": [
    "上一首",
    "上一首",
    "前の曲",
    "이전 곡",
    "Vorheriger Titel",
    "Titre précédent"
  ],
  "Next track": [
    "下一首",
    "下一首",
    "次の曲",
    "다음 곡",
    "Nächster Titel",
    "Titre suivant"
  ],
  "Search results": [
    "搜索结果",
    "搜尋結果",
    "検索結果",
    "검색 결과",
    "Suchergebnisse",
    "Résultats de recherche"
  ]
};
const featureLanguages = ["zh-Hans","zh-Hant","ja","ko","de","fr"];

/** 按英文键查询本地化文案，缺失时回退到英文。 */
export function t(text: string): string { const index=base.indexOf(text);return index>=0?(entries[current]?.[index]??text):(featureLabels[text]?.[featureLanguages.indexOf(current)]??text); }
/** 返回当前使用的语言。 */
export function getLanguage(): string { return current; }
