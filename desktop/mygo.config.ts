import { defineConfig } from "mygo-cli";

// 按目标平台配置桌面构建、签名与商店必需的应用分类。
export default defineConfig(() => ({
  name: "SynoMusic", identifier: "app.synomusic.SynoMusic", version: "1.6.3",
  devUrl: "http://localhost:5173", devCommand: "npm run dev:web", buildCommand: "npm run build:web",
  urlSchemes: ["synomusic-desktop", "synomusic-mac"],
  icon: "resources/icon.png", resources: ["../LICENSE"], license: "GPL-3.0-only", publisher: "ZHENYING MAI",
  resourcesExclude: process.env.SYNOMUSIC_BUILD_TARGET === "windows" ? ["native/**", "darwin/**", "*.entitlements"] : ["native/*.swift"],
  windows: { displayName: "SynoMusic", installDirName: "SynoMusic" },
  frontendDist: "dist", bindings: "src/mygo.ts", out: process.env.SYNOMUSIC_BUILD_OUT ?? "build",
  macos: {
    minimumSystemVersion: "13.0",
    signingIdentity: process.env.SYNOMUSIC_MAC_SIGNING_IDENTITY ?? "-",
    ...(process.env.SYNOMUSIC_MAC_PROFILE ? {
      entitlements: "resources/SynoMusic-Mac.entitlements",
      provisioningProfile: process.env.SYNOMUSIC_MAC_PROFILE,
    } : {}),
    infoPlist: { CFBundleVersion: "56", LSApplicationCategoryType: "public.app-category.music", NSLocalNetworkUsageDescription: "Connect to your authorized music servers on your local network.", ITSAppUsesNonExemptEncryption: false },
  },
}));
