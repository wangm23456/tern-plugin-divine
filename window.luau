--!strict
-- 窗口端：注册调色板命令与 Carly AI 对话入口
local function is_zh(): boolean
   local cfg_lang = tern.getenv("TERN_LANG") or tern.getenv("PLUGIN_LANG")
   if cfg_lang and #cfg_lang > 0 then
      return string.find(string.lower(cfg_lang), "zh") ~= nil
   end
   local home = tern.getenv("HOME") or ""
   if #home > 0 then
      local s_paths = {
         home .. "/Library/Application Support/Tern/settings.json",
         home .. "/.config/tern/settings.json",
      }
      for _, sp in s_paths do
         if tern.fs.exists(sp) then
            local ok, raw = pcall(function() return tern.fs.read(sp, 32768) end)
            if ok and raw and #raw > 0 then
               local pok, data = pcall(function() return tern.json.decode(raw) end)
               if pok and type(data) == "table" and type(data.language) == "string" then
                  return string.find(string.lower(data.language), "zh") ~= nil
               end
            end
         end
      end
   end
   local env_lang = (tern.getenv("LANG") or "") .. (tern.getenv("LC_ALL") or "") .. (tern.getenv("LC_MESSAGES") or "")
   if #env_lang > 0 and (string.find(string.lower(env_lang), "zh") ~= nil or string.find(string.lower(env_lang), "cn") ~= nil) then
      return true
   end
   if #home > 0 then
      local pref_path = home .. "/Library/Preferences/.GlobalPreferences.plist"
      if tern.fs.exists(pref_path) then
         local ok, bytes = pcall(function() return tern.fs.read(pref_path, 16384) end)
         if ok and bytes and (string.find(bytes, "zh-Hans") or string.find(bytes, "zh-Hant") or string.find(bytes, "zh_CN")) then
            return true
         end
      end
   end
   return false
end

local function t(zh: string, en: string): string
   return if is_zh() then zh else en
end

tern.command({
   id = "open",
   title = t("周易神算: 开启占卜面板", "Divine: Open Divination Panel"),
   icon = "sparkle",
   run = function(cx)
      cx:new_block("divine.main", nil, "beside")
      cx:toast("info", t("周易神算", "Divine"), t("按 Space 起盘摇卦，1-4 换模式，按 i 键 AI 解盘", "Space to cast, 1-4 switch mode, i for AI reading"))
   end,
})

tern.command({
   id = "carly",
   title = t("周易神算: Carly 深度解盘对话", "Divine: Deep Reading with Carly"),
   icon = "sparkle",
   run = function(cx)
      cx:ask_carly(t(
         "请为我详细解读当前占卜面板上的卦象与盘局，分析时运阻力与行动策略。",
         "Please give me a detailed reading of the current divination hexagram and plate, analyzing timing, obstacles, and recommended actions."
      ))
   end,
})

