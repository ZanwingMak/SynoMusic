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
