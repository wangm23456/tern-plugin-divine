--!strict
-- 周易神算独立面板：集成 DeepSeek AI 深度解盘与多维术数体系

type Mode = "iching" | "xiaoliuren" | "qimen" | "vedic" | "tarot"

type CoinToss = {
   c1: number, c2: number, c3: number, sum: number,
   base_bit: number, change_bit: number,
   label: string, symbol: string, change_desc: string,
   score: number,
}

type HexagramResult = {
   name: string, symbol: string, fortune: string, desc: string, score: number,
}

type State = {
   mode: Mode,
   loading: boolean,
   ai_loading: boolean,
   ai_answer: string?,
   tosses: { CoinToss },
   primary: HexagramResult?,
   changed: HexagramResult?,
   has_change: boolean,
   xiaoliuren_res: any?,
   qimen_res: any?,
   vedic_res: any?,
   focused: string?,
   cursor: number?,
   draft: any?,
   birth: any?,
   last_natal: boolean?,
   tarot_res: any?,
   spread: string?,
}

local ui = tern.ui

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

-- ponytail: 常用城市精简表，缺城市往这里加一行即可
local CITY_DB: { [string]: { lat: number, lon: number, zone: number } } = {
   ["北京"] = { lat = 39.9, lon = 116.4, zone = 8 }, ["上海"] = { lat = 31.2, lon = 121.5, zone = 8 },
   ["广州"] = { lat = 23.1, lon = 113.3, zone = 8 }, ["深圳"] = { lat = 22.5, lon = 114.1, zone = 8 },
   ["成都"] = { lat = 30.6, lon = 104.1, zone = 8 }, ["杭州"] = { lat = 30.3, lon = 120.2, zone = 8 },
   ["西安"] = { lat = 34.3, lon = 108.9, zone = 8 }, ["重庆"] = { lat = 29.6, lon = 106.5, zone = 8 },
   ["武汉"] = { lat = 30.6, lon = 114.3, zone = 8 }, ["香港"] = { lat = 22.3, lon = 114.2, zone = 8 },
   ["台北"] = { lat = 25.0, lon = 121.6, zone = 8 }, ["东京"] = { lat = 35.7, lon = 139.7, zone = 9 },
   ["纽约"] = { lat = 40.7, lon = -74.0, zone = -5 }, ["伦敦"] = { lat = 51.5, lon = -0.1, zone = 0 },
}
local TRIGRAM_BITS: { [string]: string } = {
   ["1,1,1"] = "天", ["0,0,0"] = "地", ["1,0,0"] = "雷", ["0,1,1"] = "风",
   ["0,1,0"] = "水", ["1,0,1"] = "火", ["0,0,1"] = "山", ["1,1,0"] = "泽",
}

local HEX_DATA: { [string]: { name: string, symbol: string, fortune: string, desc: string, score: number } } = {
   ["天,天"] = { name = "乾为天", symbol = "䷀", fortune = "大吉", desc = "元亨利贞，刚健笃实。顺应天时，大展宏图。", score = 0.98 }, ["天,地"] = { name = "天地否", symbol = "䷋", fortune = "凶", desc = "闭塞不通，君子退藏。韬光养晦，静待天明。", score = 0.20 },
   ["地,天"] = { name = "地天泰", symbol = "䷊", fortune = "大吉", desc = "天地交感，通达顺畅。春风得意，诸事皆谐。", score = 0.95 }, ["地,地"] = { name = "坤为地", symbol = "䷁", fortune = "吉", desc = "厚德载物，柔顺包容。静以待时，蓄力前行。", score = 0.85 },
   ["水,雷"] = { name = "水雷屯", symbol = "䷂", fortune = "平", desc = "万物初生，艰难创业。宜守勿躁，待时而发。", score = 0.50 }, ["山,水"] = { name = "山水蒙", symbol = "䷃", fortune = "平", desc = "启蒙启智，去伪存真。虚心求教，步步为营。", score = 0.55 },
   ["水,天"] = { name = "水天需", symbol = "䷄", fortune = "吉", desc = "云上于天，耐心守候。修养身心，静候良机。", score = 0.80 }, ["天,水"] = { name = "天水讼", symbol = "䷅", fortune = "凶", desc = "事与愿违，慎起争执。退让为智，慎始善终。", score = 0.25 },
   ["地,水"] = { name = "地水师", symbol = "䷆", fortune = "平", desc = "行军用兵，纪律严明。正道行事，众志成城。", score = 0.60 }, ["水,地"] = { name = "水地比", symbol = "䷇", fortune = "吉", desc = "亲附相依，和谐共赢。结交贤友，同舟共济。", score = 0.82 },
   ["火,天"] = { name = "火天大有", symbol = "䷍", fortune = "大吉", desc = "日丽中天，丰收富足。德行兼备，顺天应人。", score = 0.96 }, ["天,火"] = { name = "天火同人", symbol = "䷌", fortune = "大吉", desc = "志同道合，通力合作。凝聚人心，万事易成。", score = 0.92 },
   ["水,火"] = { name = "水火既济", symbol = "䷾", fortune = "吉", desc = "大功告成，秩序井然。防微杜渐，防初盛后衰。", score = 0.88 }, ["火,水"] = { name = "火水未济", symbol = "䷿", fortune = "平", desc = "未至终局，孕育希望。重新整饬，无限可能。", score = 0.50 },
   ["雷,风"] = { name = "雷风恒", symbol = "䷟", fortune = "吉", desc = "雷动风随，持之以恒。坚守本心，久则自见。", score = 0.80 }, ["风,雷"] = { name = "风雷益", symbol = "䷩", fortune = "大吉", desc = "风雷激荡，增益损益。见善则迁，有过则改。", score = 0.90 },
}
local function fortune_tone(f: string): string
   if f == "大吉" or f == "上上大吉" then return "success"
   elseif f == "吉" or f == "上吉" or f == "中吉" then return "accent"
   elseif f == "平" or f == "中平" then return "info" else return "error" end
end

-- cursor 字节偏移 → input 节点要的 UTF-16 偏移（中文城市名经 IME 输入时两者不等）
local function char_bytes(cp: number): number
   if cp < 0x80 then return 1 elseif cp < 0x800 then return 2
   elseif cp < 0x10000 then return 3 else return 4 end
end

local function to_u16(s: string, byte_pos: number): number
   local n, i = 0, 1
   while i <= byte_pos and i <= #s do
      local cp = utf8.codepoint(s, i)
      n += if cp > 0xFFFF then 2 else 1
      i += char_bytes(cp)
   end
   return n
end

-- 把光标吸附回字符边界（多字节字符内部的偏移会让 utf8 库抛错）
local function snap(s: string, pos: number): number
   pos = math.max(0, math.min(pos, #s))
   while pos > 0 do
      local b = string.byte(s, pos + 1) or 0
      if bit32.band(b, 0xC0) ~= 0x80 then break end
      pos -= 1
   end
   return pos
end

local function make_toss(): CoinToss
   local c1, c2, c3 = if math.random() > 0.5 then 3 else 2, if math.random() > 0.5 then 3 else 2, if math.random() > 0.5 then 3 else 2
   local s = c1 + c2 + c3
   if s == 6 then return { c1 = c1, c2 = c2, c3 = c3, sum = s, base_bit = 0, change_bit = 1, label = "老阴", symbol = "▅▅  ▅▅", change_desc = "动变阳", score = 0.35 }
   elseif s == 7 then return { c1 = c1, c2 = c2, c3 = c3, sum = s, base_bit = 1, change_bit = 1, label = "少阳", symbol = "▅▅▅▅▅", change_desc = "静爻", score = 0.75 }
   elseif s == 8 then return { c1 = c1, c2 = c2, c3 = c3, sum = s, base_bit = 0, change_bit = 0, label = "少阴", symbol = "▅▅  ▅▅", change_desc = "静爻", score = 0.55 }
   else return { c1 = c1, c2 = c2, c3 = c3, sum = s, base_bit = 1, change_bit = 0, label = "老阳", symbol = "▅▅▅▅▅", change_desc = "动变阴", score = 0.90 } end
end

local function evaluate_iching(tosses: { CoinToss }): (HexagramResult?, HexagramResult?, boolean)
   if #tosses < 6 then return nil, nil, false end
   local l_key = tosses[1].base_bit .. "," .. tosses[2].base_bit .. "," .. tosses[3].base_bit
   local u_key = tosses[4].base_bit .. "," .. tosses[5].base_bit .. "," .. tosses[6].base_bit
   local l_trig = TRIGRAM_BITS[l_key] or "天"
   local u_trig = TRIGRAM_BITS[u_key] or "天"
   local h = HEX_DATA[u_trig .. "," .. l_trig] or { name = u_trig .. l_trig .. "卦", symbol = "䷀", fortune = "吉", desc = "顺应自然之理，亨通吉利。", score = 0.70 }
   local primary: HexagramResult = { name = h.name, symbol = h.symbol, fortune = h.fortune, desc = h.desc, score = h.score }

   local has_change = false
   for _, t in tosses do if t.sum == 6 or t.sum == 9 then has_change = true break end end
   local changed: HexagramResult? = nil
   if has_change then
      local cl_key = tosses[1].change_bit .. "," .. tosses[2].change_bit .. "," .. tosses[3].change_bit
      local cu_key = tosses[4].change_bit .. "," .. tosses[5].change_bit .. "," .. tosses[6].change_bit
      local cl_trig = TRIGRAM_BITS[cl_key] or "天"
      local cu_trig = TRIGRAM_BITS[cu_key] or "天"
      local ch_h = HEX_DATA[cu_trig .. "," .. cl_trig] or { name = cu_trig .. cl_trig .. "卦", symbol = "䷀", fortune = "平", desc = "变局渐生，审时度势。", score = 0.60 }
      changed = { name = ch_h.name, symbol = ch_h.symbol, fortune = ch_h.fortune, desc = ch_h.desc, score = ch_h.score }
   end
   return primary, changed, has_change
end

local function call_horosa(tool_name: string, cx: BlockCx, cb: (data: any) -> (), over: any?)
   local d = os.date("*t")
   local payload: any = {
      date = string.format("%04d-%02d-%02d", d.year, d.month, d.day),
      time = string.format("%02d:%02d:%02d", d.hour, d.min, d.sec),
      zone = 8, lat = 39.9, lon = 116.4, defaults_accepted = true,
   }
   if over then for k, v in over do payload[k] = v end end
   local runner = tern.plugin.dir .. "/run_horosa.py"
   tern.process.run({ "python3", runner, tool_name }, {
      stdin = tern.json.encode(payload), timeout = 25,
   }, function(res)
      if res.status == 0 and res.stdout ~= "" then
         local ok, parsed = pcall(function() return tern.json.decode(res.stdout) end)
         if ok and parsed and parsed.ok then cb(parsed) else cb(nil) end
      else cb(nil) end
      cx:render()
   end)
end

local function cast_vedic(state: State, cx: BlockCx, use_birth: boolean?)
   state.loading = true
   state.last_natal = use_birth == true and state.birth ~= nil
   local over: any? = nil
   if use_birth and state.birth then
      local geo = CITY_DB[state.birth.city] or CITY_DB["北京"]
      over = { date = state.birth.date, time = state.birth.time, zone = geo.zone, lat = geo.lat, lon = geo.lon }
   end
   call_horosa("india_chart", cx, function(data)
      state.loading = false
      state.vedic_res = data
   end, over)
end

local MODE_ORDER: { Mode } = { "iching", "xiaoliuren", "qimen", "vedic", "tarot" }
local function get_mode_label(m: Mode): string
   if m == "iching" then return t("六爻", "I Ching")
   elseif m == "xiaoliuren" then return t("小六壬", "Xiao Liu Ren")
   elseif m == "qimen" then return t("奇门", "Qi Men")
   elseif m == "vedic" then return t("吠陀", "Vedic")
   elseif m == "tarot" then return t("塔罗", "Tarot")
   else return m end
end

local function get_spreads(): { { string } }
   return {
      { "single", t("单张", "Single") },
      { "three", t("三张", "Three Cards") },
      { "celtic", t("凯尔特十字", "Celtic Cross") },
      { "relation", t("关系", "Relationship") },
      { "horseshoe", t("马蹄", "Horseshoe") },
   }
end

local function set_mode(state: State, mode: Mode, cx: BlockCx)
   state.mode = mode
   state.ai_answer = nil
   state.focused = nil
   if mode == "vedic" then
      state.focused = "bdate"
      state.cursor = #(tostring((state.draft or {}).date or ""))
      cx:frame({ { "focus", "main.bdate" } })
   end
end

local function render_tabs(state: State): Node
   local buttons: { Node } = {}
   for n, m in MODE_ORDER do
      local active = state.mode == m
      table.insert(buttons, ui.el("button", {
         key = "tab" .. n,
         text = n .. " " .. get_mode_label(m),
         class = if active then "dtab on" else "dtab",
         actions = { click = "tab-" .. n },
      }))
   end
   return ui.el("div", { class = "dtabs" }, buttons)
end

local function call_ai(payload: any, cx: BlockCx, cb: (ans: string?) -> ())
   local runner = tern.plugin.dir .. "/interpret_ai.py"
   tern.process.run({ "python3", runner }, {
      stdin = tern.json.encode(payload), timeout = 25,
   }, function(res)
      if res.status == 0 and res.stdout ~= "" then
         local ok, parsed = pcall(function() return tern.json.decode(res.stdout) end)
         if ok and parsed and parsed.ok then cb(parsed.answer) else cb(nil) end
      else cb(nil) end
      cx:render()
   end)
end

local function render_iching(state: State): Node
   local cards: { Node } = {}

   if #state.tosses == 0 then
      table.insert(cards, ui.card(ui.span("☯ " .. t("六爻神占", "I Ching Divination"), "strong accent"), {
         ui.text({
            ui.span(t("点「起盘」逐爻摇卦，点「一键成卦」六爻齐出，点「AI 解读」出断语。", "Cast line by line with 'Cast', generate full hexagram with 'Auto', or get insights via 'AI Reading'.")),
         }),
      }))
   else
      local cols: { Col } = {
         { id = "pos", head = t("爻位", "Line"), align = "center", priority = 2, grow = 1, truncate = "end" },
         { id = "sym", head = t("爻象", "Yin/Yang"), align = "center", priority = 3, grow = 1, truncate = "end" },
         { id = "ch", head = t("动静", "Change"), align = "center", priority = 2, grow = 1, truncate = "end" },
         { id = "meter", head = t("气运", "Score"), align = "start", priority = 1, grow = 2, truncate = "end" },
      }
      local rows: { { any } } = {}
      local names = if is_zh() then { "初爻", "二爻", "三爻", "四爻", "五爻", "上爻" } else { "Line 1", "Line 2", "Line 3", "Line 4", "Line 5", "Line 6" }
      for i = #state.tosses, 1, -1 do
         local t = state.tosses[i]
         local ch = t.sum == 6 or t.sum == 9
         table.insert(rows, {
            ui.span(names[i], "strong"),
            ui.span(t.symbol, if ch then "warning strong" else "accent strong"),
            ui.span(t.change_desc, if ch then "warning strong" else "muted"),
            ui.meter_cell(t.score),
         })
      end
      table.insert(cards, ui.card(ui.span(t("【六爻卦盘】", "Hexagram Lines: ") .. #state.tosses .. " / 6", "strong"), {
         ui.table(cols, rows),
      }))
   end

   if state.primary then
      local p = state.primary
      table.insert(cards, ui.card(ui.span(t("本卦 · ", "Primary Hexagram · ") .. p.symbol .. " " .. p.name, "strong success"), {
         ui.row({ ui.badge(t("本卦", "Primary"), "success"), ui.badge(p.fortune, fortune_tone(p.fortune)) }),
         ui.meter(p.score, ui.span(t("吉运 ", "Fortune ") .. math.floor(p.score * 100) .. "%")),
         ui.rule(ui.span(t("卦辞", "Judgement"))),
         ui.text(p.desc),
      }))

      if state.changed then
         local c = state.changed
         table.insert(cards, ui.card(ui.span(t("变卦 · ", "Changed Hexagram · ") .. c.symbol .. " " .. c.name, "strong accent"), {
            ui.row({ ui.badge(t("变卦", "Changed"), "accent"), ui.badge(c.fortune, fortune_tone(c.fortune)) }),
            ui.meter(c.score, ui.span(t("变局 ", "Future Trend ") .. math.floor(c.score * 100) .. "%")),
            ui.rule(ui.span(t("变象", "Changed Image"))),
            ui.text(c.desc),
         }))
      end
   end

   return ui.col(cards)
end

local function render_xiaoliuren(state: State): Node
   if not state.xiaoliuren_res then
      return ui.card(ui.span(t("【诸葛马前小六壬】", "Xiao Liu Ren Divination"), "strong"), {
         ui.text({ ui.span(t("点「起盘」依当下时令起课；报数可作三数起课。", "Click 'Cast' to divine by current time, or input numbers as seed.")) }),
      })
   end

   local xl = state.xiaoliuren_res.xiaoliuren or {}
   local stages = xl.stages or {}
   local deities = xl.deities or {}

   local cols: { Col } = {
      { id = "pos", head = t("传位", "Stage"), align = "start", priority = 2, grow = 1, truncate = "end" },
      { id = "name", head = t("神煞", "Deity"), align = "center", priority = 3, grow = 1, truncate = "end" },
      { id = "wuxing", head = t("方位", "Element/Dir"), align = "center", priority = 1, grow = 1, truncate = "end" },
      { id = "meter", head = t("吉运", "Fortune"), align = "start", priority = 1, grow = 2, truncate = "end" },
   }
   local rows: { { any } } = {}
   local total_score = 0
   for _, st in stages do
      total_score += (st.score or 0.5)
      table.insert(rows, {
         ui.span(st.pos or "", "strong"),
         ui.span(st.name or "", (st.tone or "accent") .. " strong"),
         ui.span(st.wuxing or "", "muted"),
         ui.meter_cell(st.score or 0.5),
      })
   end
   local avg = if #stages > 0 then total_score / #stages else 0.5

   local deity_items: { { any } } = {}
   for _, d in deities do
      table.insert(deity_items, { ui.span(d.title or "神煞", "strong"), ui.span(d.meaning or "") })
      if d.remedy and d.remedy ~= "" then
         table.insert(deity_items, { ui.span("化解", "accent"), ui.span(d.remedy, "muted") })
      end
   end

   return ui.col({
      ui.card(ui.span(t("【小六壬三传时序】", "Xiao Liu Ren Stages"), "strong success"), {
         ui.meter(avg, ui.span(t("综合吉运 ", "Overall Fortune ") .. math.floor(avg * 100) .. "%")),
         ui.table(cols, rows),
         ui.rule(ui.span(t("终局决断", "Final Verdict"))),
         ui.text({ ui.span(xl.verdict or t("气运平稳", "Stable fortune"), "strong success") }),
      }),
      ui.card(ui.span(t("【神煞深义与修持】", "Deity Significance & Advice"), "strong accent"), {
         ui.kv(deity_items),
      }),
   })
end

local function render_qimen(state: State): Node
   if not state.qimen_res then
      return ui.card(ui.span(t("【奇门遁甲时家盘】", "Qi Men Dun Jia Plate"), "strong"), {
         ui.text({ ui.span(t("点「起盘」起时家局；所问之事会进引擎与解读。", "Click 'Cast' to generate celestial plate; questions are fed into engine.")) }),
      })
   end

   local qm = state.qimen_res.qimen or {}
   local pals = qm.palaces or {}
   local cols: { Col } = {
      { id = "palace", head = t("宫位", "Palace"), align = "start", priority = 3, grow = 1, truncate = "end" },
      { id = "door", head = t("八门", "Door"), align = "center", priority = 3, grow = 1, truncate = "end" },
      { id = "godstar", head = t("神星", "God/Star"), align = "center", priority = 1, grow = 1, truncate = "end" },
      { id = "stems", head = t("奇仪", "Stems"), align = "center", priority = 1, grow = 1, truncate = "end" },
      { id = "status", head = t("状态", "Status"), align = "center", priority = 2, grow = 1, truncate = "end" },
      { id = "meter", head = t("能量", "Energy"), align = "start", priority = 1, grow = 2, truncate = "end" },
   }
   local rows: { { any } } = {}
   for _, p in pals do
      local is_special = (p.status == "★值使" or p.status == "★值符")
      table.insert(rows, {
         ui.span(p.palace or "", if is_special then "strong accent" else "strong"),
         ui.span(p.door or "", if p.door == "生门" or p.door == "开门" or p.door == "休门" then "success strong" else "accent"),
         ui.span(p.godstar or ""),
         ui.span(p.stems or "", "strong"),
         ui.span(p.status or "平", if is_special then "warning strong" else "muted"),
         ui.meter_cell(p.score or 0.5),
      })
   end

   return ui.col({
      ui.card(ui.span(t("【奇门九宫方盘】", "Qi Men Nine Palaces"), "strong accent"), {
         ui.row({
            ui.badge(qm.ju or t("时家局", "Hour Plate"), "accent"),
            ui.badge(t("符:", "Leader:") .. (qm.zhifu or "TianRui"), "success"),
            ui.badge(t("使:", "Envoy:") .. (qm.zhishi or "DeadDoor"), "warning"),
         }),
         ui.table(cols, rows),
      }),
      ui.card(ui.span(t("【奇门诸事专项详断】", "Qi Men Specific Matters"), "strong success"), {
         ui.kv({
            { ui.span(t("事业", "Career")), ui.span(qm.career or t("谋事吉利，利见贵人", "Favorable for career, meeting mentors")) },
            { ui.span(t("财帛", "Wealth")), ui.span(qm.wealth or t("生门得位，本钱安稳", "Solid foundation for wealth")) },
            { ui.span(t("婚恋", "Relationship")), ui.span(qm.love or t("正缘情深，六合和睦", "Harmonious relationship")) },
            { ui.span(t("化解", "Remedy")), ui.span(qm.remedy or t("移出尖锐之物，摆放绿植", "Remove sharp objects, add green plants"), "accent") },
         }),
      }),
   })
end
local function render_india(state: State): Node
   local cards: { Node } = {}
   local draft = state.draft or { date = "", time = "", city = "北京" }
   local function field(id: string, name: string, ph: string): Node
      local txt = tostring(draft[name] or "")
      local props: any = { key = id, text = txt, placeholder = ph, aria = ph, grow = 1, min = 84 }
      if state.focused == id then
         props.cursor = to_u16(txt, math.min(state.cursor or #txt, #txt))
      end
      return ui.node("input", props)
   end

   if not state.birth then
      table.insert(cards, ui.card(ui.span(t("出生信息", "Birth Information"), "strong accent"), {
         ui.row({
            field("bdate", "date", t("出生日期 1995-08-18", "Birth Date 1995-08-18")),
            field("btime", "time", t("时间 14:30", "Time 14:30")),
            field("bcity", "city", t("城市 北京", "City Beijing")),
         }),
         ui.row({
            ui.el("button", { text = t("起本命盘", "Cast Natal Chart"), class = "dtab on", actions = { click = "cast-natal" } }),
            ui.el("button", { text = t("起即时盘", "Cast Current Time"), class = "dtab", actions = { click = "cast-now" } }),
         }),
         ui.text({ ui.span(t("点框打字 · Esc 退出 · 大运命主星需本命盘", "Click to type · Esc to exit · Natal chart required for Dasha"), "muted") }),
      }))
   else
      local b = state.birth
      table.insert(cards, ui.row({
         ui.badge(t("本命 ", "Natal ") .. b.date .. " " .. b.time .. " " .. b.city, "success"),
         ui.el("button", { text = t("修改", "Edit"), class = "dtab", actions = { click = "edit-birth" } }),
      }))
   end

   if not state.vedic_res then
      if state.birth then
         table.insert(cards, ui.card(ui.span("吠陀星盘 (Vedic Jyotish)", "strong"), {
            ui.text({ ui.span("点底部「起盘」按钮起本命盘。") }),
         }))
      end
      return ui.col(cards)
   end

   local ind = state.vedic_res.vedic or state.vedic_res.india_chart or {}
   local planets = ind.planets or {}
   local yogas = ind.yogas or {}

   local cols: { Col } = {
      { id = "name", head = t("星曜", "Planet"), align = "center", priority = 3, grow = 1, truncate = "end" },
      { id = "sign", head = t("落座", "Sign"), align = "start", priority = 2, grow = 2, truncate = "end" },
      { id = "house", head = t("落宫", "House"), align = "center", priority = 2, grow = 1, truncate = "end" },
      { id = "status", head = t("行运", "Motion"), align = "center", priority = 1, grow = 1, truncate = "end" },
      { id = "meter", head = t("吉运", "Strength"), align = "start", priority = 1, grow = 2, truncate = "end" },
   }
   local rows: { { any } } = {}
   for _, p in planets do
      local is_retro = (p.status == "逆行" or p.status == "R")
      table.insert(rows, {
         ui.span(p.name or "", "strong"),
         ui.span(p.sign or ""),
         ui.span(p.house or "", "accent strong"),
         ui.span(p.status or "", if is_retro then "warning strong" else "success"),
         ui.meter_cell(p.score or 0.7),
      })
   end
   local yoga_items: { { any } } = {}
   for _, y in yogas do
      table.insert(yoga_items, {
         ui.span((y.name or "瑜伽") .. " [" .. (y.strength or "强") .. "]", "strong accent"),
         ui.span(y.stars or "主曜"),
      })
   end

   table.insert(cards, ui.card(ui.span(t("【吠陀九曜星盘】", "Vedic Navagraha Planetary Chart"), "strong success"), {
      ui.row({
         if state.last_natal
            then ui.badge(t("本命盘", "Natal Chart"), "success")
            else ui.badge(t("即时盘 · 看当下时机", "Prashna · Horary Chart"), "warning"),
         ui.badge(t("主:", "Lord:") .. (ind.lord or "Mars"), "accent"),
         ui.badge(ind.nakshatra or "Nakshatra", "info"),
      }),
      ui.table(cols, rows),
   }))
   table.insert(cards, ui.card(ui.span(t("【大运与瑜伽格局】", "Dasha Timing & Planetary Yogas"), "strong accent"), {
      ui.kv({
         { ui.span(t("大运", "Mahadasha"), "strong success"), ui.span(ind.mahadasha or t("主运", "Major Period")) },
         { ui.span(t("小运", "Antardasha"), "strong accent"), ui.span(ind.antardasha or t("小运", "Minor Period")) },
      }),
      if #yoga_items > 0 then ui.rule(ui.span(t("瑜伽格局", "Yogas"))) else ui.text(""),
      if #yoga_items > 0 then ui.kv(yoga_items) else ui.text(""),
      ui.rule(ui.span(t("守护指引", "Remedies & Guidance"))),
      ui.text({ ui.span(ind.remedy or t("配戴属曜宝石提振能量。", "Wear associated planetary gemstones or practice meditation."), "muted") }),
   }))
   return ui.col(cards)
end

-- 报数起卦：心动之数由问者出，盘才属于问者（先天卦序 乾兑离震巽坎艮坤，自下而上）
local XT_BITS: { { number } } = {
   { 1, 1, 1 }, { 1, 1, 0 }, { 1, 0, 1 }, { 1, 0, 0 },
   { 0, 1, 1 }, { 0, 1, 0 }, { 0, 0, 1 }, { 0, 0, 0 },
}

local function parse_nums(raw: string): { number }
   local out = {}
   for tok in string.gmatch(raw or "", "[^,%s，]+") do
      local n = tonumber(tok)
      if n and n > 0 then table.insert(out, math.floor(n)) end
   end
   return out
end

local function toss_from_bits(b: number, moving: boolean): CoinToss
   if b == 1 then
      return { c1 = 3, c2 = 3, c3 = 3, sum = if moving then 9 else 7, base_bit = 1, change_bit = if moving then 0 else 1, label = if moving then "老阳" else "少阳", symbol = "▅▅▅▅▅", change_desc = if moving then "动变阴" else "静爻", score = if moving then 0.90 else 0.75 }
   end
   return { c1 = 2, c2 = 2, c3 = 2, sum = if moving then 6 else 8, base_bit = 0, change_bit = if moving then 1 else 0, label = if moving then "老阴" else "少阴", symbol = "▅▅  ▅▅", change_desc = if moving then "动变阳" else "静爻", score = if moving then 0.35 else 0.55 }
end

local function cast_by_numbers(nums: { number }): { CoinToss }
   local lower = XT_BITS[((nums[1] - 1) % 8) + 1]
   local upper = XT_BITS[((nums[2] - 1) % 8) + 1]
   local moving = ((nums[3] - 1) % 6) + 1
   local tosses: { CoinToss } = {}
   for i = 1, 3 do table.insert(tosses, toss_from_bits(lower[i], i == moving)) end
   for i = 1, 3 do table.insert(tosses, toss_from_bits(upper[i], i + 3 == moving)) end
   return tosses
end

local function render_tarot(state: State): Node
   local cards: { Node } = {}
   local picker: { Node } = {}
   local cur_spread = state.spread or "three"
   for _, sp in get_spreads() do
      table.insert(picker, ui.el("button", {
         key = "sp-" .. sp[1],
         text = sp[2],
         class = if cur_spread == sp[1] then "dtab on" else "dtab",
         actions = { click = "spread-" .. sp[1] },
      }))
   end
   table.insert(cards, ui.card(ui.span(t("塔罗牌阵", "Tarot Spreads"), "strong accent"), {
      ui.el("div", { class = "dtabs" }, picker),
      ui.text({ ui.span(t("选牌阵 · 填所问之事（可选）· 报数可作抽牌种子 · 点「起盘」", "Select spread · Input question (optional) · Number seeds supported · Click 'Cast'"), "muted") }),
   }))

   if state.tarot_res then
      local tt = state.tarot_res.tarot or {}
      local tcards = tt.cards or {}
      if #tcards > 0 then
         local cols: { Col } = {
            { id = "pos", head = t("位置", "Pos"), align = "start", priority = 3, grow = 2, truncate = "end" },
            { id = "role", head = t("位义", "Meaning"), align = "start", priority = 2, grow = 3, truncate = "end" },
            { id = "card", head = t("牌", "Card"), align = "start", priority = 3, grow = 2, truncate = "end" },
            { id = "dir", head = t("正逆", "Orientation"), align = "center", priority = 3, grow = 1, truncate = "end" },
            { id = "keys", head = t("关键词", "Keywords"), align = "start", priority = 1, grow = 3, truncate = "end" },
         }
         local rows: { { any } } = {}
         for _, c in tcards do
            table.insert(rows, {
               ui.span(c.pos or "", "strong"),
               ui.span(c.role or "", "muted"),
               ui.span(c.card or "", "strong"),
               ui.span(if c.upright then t("正位", "Upright") else t("逆位", "Reversed"), if c.upright then "success strong" else "warning strong"),
               ui.span(c.keywords or ""),
            })
         end
         table.insert(cards, ui.card(ui.span(t("逐牌详解", "Card-by-Card Interpretation"), "strong success"), {
            ui.table(cols, rows),
         }))
      end
      if (tt.verdict or "") ~= "" then
         table.insert(cards, ui.card(ui.span(t("综合断语", "Overall Verdict"), "strong accent"), {
            ui.text({ ui.span(tt.verdict, "muted") }),
         }))
      end
   end
   return ui.col(cards)
end

-- 键盘与鼠标按钮共用的四个动作（空格/a/i/r 的唯一实现）
local function do_ai(state: State, cx: BlockCx)
   state.ai_loading = true
   cx:toast("info", t("AI 宗师正在解盘...", "AI Reading in progress..."), t("DeepSeek 正在推演天机与策论", "Analyzing celestial patterns with DeepSeek..."))
   if state.mode == "iching" and not state.primary then
      while #state.tosses < 6 do table.insert(state.tosses, make_toss()) end
      state.primary, state.changed, state.has_change = evaluate_iching(state.tosses)
   end
   local ai_payload: any = { mode = state.mode }
   if tostring((state.draft or {}).question or "") ~= "" then ai_payload.question = state.draft.question end
   if state.mode == "iching" and state.primary then
      ai_payload.primary = state.primary.name
      if state.changed then ai_payload.changed = state.changed.name end
   elseif state.mode == "xiaoliuren" and state.xiaoliuren_res then
      local stages = state.xiaoliuren_res.xiaoliuren and state.xiaoliuren_res.xiaoliuren.stages or {}
      local names = {}
      for _, s in stages do table.insert(names, s.name or "") end
      ai_payload.stages = names
   elseif state.mode == "qimen" and state.qimen_res then
      local qm = state.qimen_res.qimen or {}
      ai_payload.ju = qm.ju
      ai_payload.zhifu = qm.zhifu
      ai_payload.zhishi = qm.zhishi
      ai_payload.jige = qm.jige
      ai_payload.xiongge = qm.xiongge
   elseif state.mode == "vedic" and state.vedic_res then
      local ind = state.vedic_res.vedic or state.vedic_res.india_chart or {}
      ai_payload.lord = ind.lord
      ai_payload.dasha = ind.mahadasha
      ai_payload.nakshatra = ind.nakshatra
      if state.birth then ai_payload.birth_text = state.birth.date .. " " .. state.birth.time .. " " .. state.birth.city end
   elseif state.mode == "tarot" and state.tarot_res then
      local tt = state.tarot_res.tarot or {}
      ai_payload.spread = tt.spread
      local names = {}
      for _, c in (tt.cards or {}) do
         table.insert(names, (c.card or "") .. (if c.upright then "(正)" else "(逆)"))
      end
      ai_payload.cards = names
   end
   call_ai(ai_payload, cx, function(ans)
      state.ai_loading = false
      state.ai_answer = ans or t("AI未能连接，请确认网络或环境变量配置。", "AI service unavailable. Check network or DEEPSEEK_API_KEY.")
      if ans then cx:toast("success", t("AI 解读完成", "AI Reading Completed"), t("天机策论已在面板更新", "Analysis updated on board")) else cx:toast("error", t("AI 解读失败", "AI Reading Failed"), t("未能连接模型服务", "Failed to connect to model service")) end
   end)
end

local function do_primary(state: State, cx: BlockCx)
   state.ai_answer = nil
   local draft = state.draft or {}
   local nums = parse_nums(tostring(draft.nums or ""))
   local over: any = {}
   if tostring(draft.question or "") ~= "" then over.question = draft.question end
   if #nums >= 3 then over.nums = { nums[1], nums[2], nums[3] } end
   if state.mode == "iching" then
      if #nums >= 3 then
         state.tosses = cast_by_numbers(over.nums)
         state.primary, state.changed, state.has_change = evaluate_iching(state.tosses)
      else
         if #state.tosses >= 6 then
            state.tosses = {} state.primary = nil state.changed = nil state.has_change = false
         end
         table.insert(state.tosses, make_toss())
         if #state.tosses == 6 then
            state.primary, state.changed, state.has_change = evaluate_iching(state.tosses)
         end
      end
   elseif state.mode == "xiaoliuren" then
      state.loading = true
      call_horosa("xiaoliuren", cx, function(data)
         state.loading = false
         state.xiaoliuren_res = data
      end, over)
   elseif state.mode == "qimen" then
      state.loading = true
      local q_over: any = {}
      if tostring(draft.question or "") ~= "" then q_over.question = draft.question end
      call_horosa("qimen", cx, function(data)
         state.loading = false
         state.qimen_res = data
      end, q_over)
   elseif state.mode == "tarot" then
      state.loading = true
      local t_over: any = { spread = state.spread or "three" }
      if tostring(draft.question or "") ~= "" then t_over.question = draft.question end
      if #nums >= 1 then
         local seed = {}
         for _, n in nums do table.insert(seed, tostring(n)) end
         t_over.seed = table.concat(seed, "|")
      end
      call_horosa("tarot", cx, function(data)
         state.loading = false
         state.tarot_res = data
      end, t_over)
   else
      cast_india(state, cx, true)
   end
end

local function do_auto(state: State, _cx: BlockCx)
   if state.mode ~= "iching" then return end
   state.ai_answer = nil
   local nums = parse_nums(tostring((state.draft or {}).nums or ""))
   if #nums >= 3 then
      state.tosses = cast_by_numbers({ nums[1], nums[2], nums[3] })
   else
      while #state.tosses < 6 do table.insert(state.tosses, make_toss()) end
   end
   state.primary, state.changed, state.has_change = evaluate_iching(state.tosses)
end

local function do_reset(state: State, _cx: BlockCx)
   state.ai_answer = nil
   if state.mode == "iching" then
      state.tosses = {} state.primary = nil state.changed = nil state.has_change = false
   elseif state.mode == "xiaoliuren" then state.xiaoliuren_res = nil
   elseif state.mode == "qimen" then state.qimen_res = nil
   elseif state.mode == "tarot" then state.tarot_res = nil
   else state.vedic_res = nil
   end
end

local divine_block: BlockDef<State> = {
   init = function(_cx, _args, saved)
      return {
         mode = (saved and saved.mode) or "iching", loading = false, ai_loading = false,
         ai_answer = saved and saved.ai_answer or nil,
         tosses = (saved and saved.tosses) or {}, primary = saved and saved.primary or nil,
         changed = saved and saved.changed or nil, has_change = (saved and saved.has_change) or false,
         xiaoliuren_res = saved and saved.xiaoliuren_res or nil, qimen_res = saved and saved.qimen_res or nil,
         vedic_res = saved and (saved.vedic_res or saved.india_res) or nil, tarot_res = saved and saved.tarot_res or nil,
         last_natal = saved and saved.last_natal or nil,
         focused = nil, cursor = nil, spread = (saved and saved.spread) or "three",
         draft = (saved and saved.draft) or { date = "", time = "", city = "北京", question = "", nums = "" },
         birth = saved and saved.birth or nil,
      } :: any
   end,

   event = function(state, ev, cx)
      if ev.ev == "focus" and type(ev.id) == "string" then
         local id2field = { bdate = "date", btime = "time", bcity = "city", bq = "question", bn = "nums" }
         for id, field in id2field do
            if ev.id == id or ev.id:sub(-#id) == id then
               state.focused = id
               local d = state.draft or {}
               state.cursor = #(tostring(d[field] or ""))
               cx:frame({ { "focus", ev.id } })
               break
            end
         end
      elseif ev.ev == "action" then
         local act = ev.act or ev.id or ""
         if act == "cast-natal" then
            local d = state.draft or {}
            local date_ok = type(d.date) == "string" and d.date:match("^%d%d%d%d%-%d%d%-%d%d$")
            local t = if type(d.time) == "string" then (d.time:gsub("：", ":"):gsub("%s+", "")) else ""
            local time_ok = t:match("^%d%d:%d%d$") ~= nil
            if date_ok and time_ok then
               local city = (type(d.city) == "string" and d.city ~= "") and d.city or "北京"
               d.time = t
               state.birth = { date = d.date, time = t, city = city }
               state.draft = state.birth
               cast_india(state, cx, true)
               cx:toast("success", t("本命盘推演中", "Calculating Natal Chart"), d.date .. " " .. city)
            else
               cx:toast("error", t("出生信息不全", "Incomplete Birth Info"), t("格式：1995-08-18 与 14:30", "Format: 1995-08-18 and 14:30"))
            end
         elseif act == "cast-now" then
            cast_vedic(state, cx, false)
         elseif act == "edit-birth" then
            state.birth = nil
            state.vedic_res = nil
            set_mode(state, "vedic", cx)
         elseif act:sub(1, 7) == "spread-" then
            state.spread = act:sub(8)
         elseif act == "do-primary" then do_primary(state, cx)
         elseif act == "do-auto" then do_auto(state, cx)
         elseif act == "do-ai" then do_ai(state, cx)
         elseif act == "do-reset" then do_reset(state, cx)
         elseif act:sub(1, 4) == "tab-" then
            local n = tonumber(act:sub(5))
            if n and MODE_ORDER[n] then
               set_mode(state, MODE_ORDER[n], cx)
            end
         end
      end
   end,

   title = function(state)
      local titles = {
         iching = t("周易六爻", "I Ching"),
         xiaoliuren = t("小六壬", "Xiao Liu Ren"),
         qimen = t("奇门遁甲", "Qi Men Dun Jia"),
         vedic = t("吠陀占星", "Vedic Astrology"),
         tarot = t("塔罗牌阵", "Tarot Spreads"),
      }
      return titles[state.mode] or t("周易神算", "Divine")
   end,

   view = function(state, _cx)
      local mode_tabs = render_tabs(state)

      local draft = state.draft or {}
      local function ask_field(id: string, name: string, ph: string): Node
         local txt = tostring(draft[name] or "")
         local props: any = { key = id, text = txt, placeholder = ph, aria = ph, grow = 1, min = 60 }
         if state.focused == id then
            props.cursor = to_u16(txt, math.min(state.cursor or #txt, #txt))
         end
         return ui.node("input", props)
      end
      local ask_card = ui.card(ui.span(t("问事 · 报数（可选）", "Query & Numbers (Optional)"), "strong"), {
         ui.row({
            ask_field("bq", "question", t("所问何事（如：这次跳槽行不行）", "Your question (e.g., job change prospect)")),
            ask_field("bn", "nums", t("报数（六爻/小六壬/塔罗种子，如 3 5 7）", "Seeds (I Ching / Xiao Liu Ren / Tarot seeds, e.g. 3 5 7)")),
         }),
      })

      local content_cards: { Node } = { ask_card }
      if state.loading then
         table.insert(content_cards, ui.card(ui.span(t("【引擎推演中】", "Engine Calculating..."), "accent strong"), {
            ui.progress(nil, ui.span(t("正在调用 Horosa 离线引擎排盘...", "Running Horosa calculation engine..."))),
            ui.text(t("瑞士星历与术数算法高速排盘中...", "Computing planetary ephemeris and astrological formulas...")),
         }))
      elseif state.mode == "iching" then table.insert(content_cards, render_iching(state))
      elseif state.mode == "xiaoliuren" then table.insert(content_cards, render_xiaoliuren(state))
      elseif state.mode == "qimen" then table.insert(content_cards, render_qimen(state))
      elseif state.mode == "tarot" then table.insert(content_cards, render_tarot(state))
      else table.insert(content_cards, render_india(state)) end

      if state.ai_loading then
         table.insert(content_cards, ui.card(ui.span(t("🤖 AI 宗师正在深度解盘...", "AI Master Interpreting..."), "accent strong"), {
            ui.progress(nil, ui.span(t("DeepSeek 正在推演天机与行事策论...", "Analyzing patterns with DeepSeek..."))),
            ui.text(t("综合卦气、十神与星曜，正在提炼精准断语...", "Synthesizing planetary aspects and extracting strategic insights...")),
         }))
      elseif state.ai_answer then
         table.insert(content_cards, ui.card(ui.span("🔮 " .. t("AI 宗师天机断语 (DeepSeek)", "AI Divination Insights (DeepSeek)"), "strong accent"), {
            ui.text(state.ai_answer),
         }))
      end

      return {
         main = ui.col({ mode_tabs, ui.col(content_cards) }),
         dock = ui.col({
            ui.el("div", { class = "dtabs" }, {
               ui.el("button", { text = t("起盘", "Cast"), class = "dtab on", actions = { click = "do-primary" } }),
               if state.mode == "iching"
                  then ui.el("button", { text = t("一键成卦", "Auto Cast"), class = "dtab", actions = { click = "do-auto" } })
                  else ui.text(""),
               ui.el("button", { text = t("AI 解读", "AI Reading"), class = "dtab", actions = { click = "do-ai" } }),
               ui.el("button", { text = t("重来", "Reset"), class = "dtab", actions = { click = "do-reset" } }),
            }),
         }),
      }
   end,

   key = function(state, key, cx)
      if state.focused then
         local id2field = { bdate = "date", btime = "time", bcity = "city", bq = "question", bn = "nums" }
         local fk = id2field[state.focused]
         if fk then
            local draft = state.draft or { date = "", time = "", city = "北京" }
            state.draft = draft
            local txt = tostring(draft[fk] or "")
            local cur = snap(txt, math.min(state.cursor or #txt, #txt))
            if cur ~= (state.cursor or -1) then state.cursor = cur end
            if key.name == "escape" or key.name == "enter" then
               state.focused = nil return true
            elseif key.name == "backspace" or key.name == "delete" then
               if cur > 0 then
                  local last = utf8.offset(txt:sub(1, cur), -1)
                  if last then
                     draft[fk] = txt:sub(1, last - 1) .. txt:sub(cur + 1)
                     state.cursor = last - 1
                  end
               end
               return true
            elseif key.name == "left" then
               if cur > 0 then
                  local last = utf8.offset(txt:sub(1, cur), -1)
                  state.cursor = if last then last - 1 else 0
               end
               return true
            elseif key.name == "right" then
               if cur < #txt then
                  local cp = utf8.codepoint(txt, cur + 1)
                  state.cursor = math.min(cur + char_bytes(cp), #txt)
               end
               return true
            elseif key.name == "home" then state.cursor = 0 return true
            elseif key.name == "end" then state.cursor = #txt return true
            elseif key.text and #key.text > 0 and not key.ctrl and not key.meta then
               draft[fk] = txt:sub(1, cur) .. key.text .. txt:sub(cur + 1)
               state.cursor = cur + #key.text
               return true
            end
            return false
         end
      end
      -- ponytail: 全局快捷键已移除（用户要求）；所有动作走底部按钮，键盘只在输入框聚焦时编辑文字
      return false
   end,

   save = function(state)
      return {
         mode = state.mode, draft = state.draft, birth = state.birth, spread = state.spread,
         tosses = state.tosses, primary = state.primary, changed = state.changed, has_change = state.has_change,
         xiaoliuren_res = state.xiaoliuren_res, qimen_res = state.qimen_res,
         vedic_res = state.vedic_res, tarot_res = state.tarot_res, last_natal = state.last_natal,
         ai_answer = state.ai_answer,
      }
   end,
}

tern.block.define("main", divine_block)
