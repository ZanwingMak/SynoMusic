/** 根据标题生成本地原创几何唱片封面，不请求第三方图片。 */
export function artwork(seed: string): string {
  let hash = 0;
  for (const char of seed) hash = ((hash << 5) - hash + char.charCodeAt(0)) | 0;
  const palettes = [["#d96f4f", "#f6d0a3", "#6e383b"], ["#395d69", "#b8c7bf", "#dfb687"], ["#5a6049", "#dfd5ad", "#a99566"], ["#63546a", "#d5babc", "#b37565"], ["#283949", "#afbbbc", "#db8356"], ["#a48665", "#efe4cb", "#5c6762"]];
  const [base, light, dark] = palettes[Math.abs(hash) % palettes.length];
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 500 500"><rect width="500" height="500" fill="${base}"/><circle cx="375" cy="125" r="150" fill="${light}"/><path d="M-50 550V270Q200 20 550 300V550" fill="${dark}"/><path d="M-30 500V365Q225 155 540 410V510" fill="${light}" opacity=".55"/><g fill="none" stroke="${light}" opacity=".23">${[110,135,160,185,210].map(r=>`<circle cx="245" cy="300" r="${r}"/>`).join("")}</g><rect x="34" y="34" width="54" height="3" fill="${light}"/><text x="34" y="65" font-family="Helvetica,sans-serif" font-size="12" letter-spacing="4" fill="${light}">SYNO / STUDIO</text><text x="34" y="451" font-family="Helvetica,sans-serif" font-size="26" fill="white" font-weight="500">${seed.replace(/[<>&"']/g, "").slice(0,26)}</text></svg>`;
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
}
