(() => {
  const supported = ['en', 'zh-Hans', 'zh-Hant', 'ja', 'ko', 'de', 'fr'];
  const imageLocales = { en: 'en-US', 'zh-Hans': 'zh-Hans', 'zh-Hant': 'zh-Hant', ja: 'ja', ko: 'ko', de: 'de-DE', fr: 'fr-FR' };
  const appStore = 'https://apps.apple.com/app/id6784094020';
  const release = 'https://github.com/ZanwingMak/SynoMusic/releases/tag/v1.6.4';
  let translations = {};
  let language = 'en';
  let platform = 'mac';

  /** 优先读取用户显式选择，否则按浏览器语言匹配已有翻译。 */
  function preferredLanguage() {
    const requested = new URLSearchParams(location.search).get('lang');
    const saved = localStorage.getItem('synomusic.site.language');
    const candidate = requested || saved || navigator.language || 'en';
    if (supported.includes(candidate)) return candidate;
    if (candidate.startsWith('zh')) return /Hant|TW|HK/i.test(candidate) ? 'zh-Hant' : 'zh-Hans';
    const base = candidate.split('-')[0];
    return supported.includes(base) ? base : 'en';
  }

  /** 查找可信的本地翻译，缺失时保留英文。 */
  function text(key) {
    return translations[language]?.[key] ?? translations.en?.[key] ?? key;
  }

  /** 为本地化产品截图指定资源，找不到时使用已交付的英文截图。 */
  function image(element, filename) {
    if (!element) return;
    const fallback = './assets/images/screens/en-US/' + filename;
    element.onerror = () => { element.onerror = null; element.src = fallback; };
    element.src = './assets/images/screens/' + imageLocales[language] + '/' + filename;
  }

  /** 更新客户端切换区的文案、截图与对应下载入口。 */
  function showClient(nextPlatform) {
    platform = nextPlatform;
    document.querySelectorAll('[data-client]').forEach(button => {
      button.setAttribute('aria-selected', String(button.dataset.client === platform));
      button.tabIndex = button.dataset.client === platform ? 0 : -1;
    });
    document.querySelector('#client-preview').setAttribute('aria-labelledby', 'tab-' + platform);
    document.querySelector('#platform-label').textContent = platform === 'mac' ? 'macOS 13+' : platform === 'windows' ? 'Windows 10 / 11 · Preview' : platform === 'iphone' ? 'iOS 17+' : 'iPadOS 17+';
    document.querySelector('#client-title').innerHTML = text(platform + 'Title');
    document.querySelector('#client-description').textContent = text(platform + 'Body');
    const list = document.querySelector('#client-highlights');
    list.replaceChildren();
    for (const label of text(platform + 'Highlights')) {
      const item = document.createElement('li');
      item.textContent = label;
      list.append(item);
    }
    const area = document.querySelector('#client-downloads');
    area.replaceChildren();
    const link = document.createElement('a');
    link.className = 'button dark';
    link.href = ['mac', 'windows'].includes(platform) ? release : appStore;
    link.textContent = text(platform + 'Button');
    area.append(link);
    document.querySelector('#client-screen').dataset.platform = platform;
    const screenshot = document.querySelector('#client-image');
    screenshot.alt = 'SynoMusic for ' + (platform === 'mac' ? 'Mac' : platform === 'windows' ? 'Windows' : platform === 'iphone' ? 'iPhone' : 'iPad');
    image(screenshot, platform + '-library.png');
  }

  /** 切换整页语言并保留当前客户端选择。 */
  function setLanguage(nextLanguage) {
    language = supported.includes(nextLanguage) ? nextLanguage : 'en';
    localStorage.setItem('synomusic.site.language', language);
    document.documentElement.lang = language;
    document.querySelector('#language').value = language;
    document.querySelectorAll('[data-i18n]').forEach(element => {
      element.innerHTML = text(element.dataset.i18n);
    });
    document.title = 'SynoMusic — ' + document.querySelector('h1').innerText.replace(/\s+/g, ' ');
    image(document.querySelector('#hero-mac'), 'mac-library.png');
    image(document.querySelector('#hero-phone'), 'iphone-player.png');
    image(document.querySelector('#library-detail'), 'iphone-library.png');
    for (const link of document.querySelectorAll('.site-footer a[href^="./privacy.html"], .site-footer a[href^="./terms.html"]')) {
      link.href = link.getAttribute('href').split('?')[0] + '?lang=' + language;
    }
    showClient(platform);
  }

  /** 使用一次性视口观察显示内容，并遵守减少动态效果偏好。 */
  function revealSections() {
    if (!('IntersectionObserver' in window) || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    document.documentElement.classList.add('js-reveal');
    const observer = new IntersectionObserver(entries => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      }
    }, { threshold: 0.06 });
    document.querySelectorAll('.reveal').forEach(element => observer.observe(element));
  }

  /** 加载本地文案并接入语言、键盘与客户端切换。 */
  async function start() {
    try {
      const response = await fetch('./assets/site-copy.json');
      if (!response.ok) throw new Error('Translations unavailable');
      translations = await response.json();
      setLanguage(preferredLanguage());
    } catch (error) {
      console.error(error);
      document.querySelector('#client-title').textContent = 'Your music, at home on Mac.';
      document.querySelector('#client-description').textContent = 'A desktop music client for your own library.';
      document.querySelector('#client-downloads').innerHTML = '<a class="button dark" href="' + release + '">Download for Mac ↗</a>';
    }
    document.querySelector('#language').addEventListener('change', event => setLanguage(event.target.value));
    document.querySelectorAll('[data-client]').forEach(button => {
      button.addEventListener('click', () => showClient(button.dataset.client));
      button.addEventListener('keydown', event => {
        if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
        event.preventDefault();
        const options = ['mac', 'windows', 'iphone', 'ipad'];
        const index = (options.indexOf(platform) + (event.key === 'ArrowRight' ? 1 : options.length - 1)) % options.length;
        showClient(options[index]);
        document.querySelector('#tab-' + options[index]).focus();
      });
    });
    revealSections();
  }
  start();
})();
