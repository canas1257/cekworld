-- ==============================================================================
-- SCRIPT BOT LUCIFER v2.86: WORLD SCANNER & PLANT CHECKER (v3 Final)
-- Tim Pengembang: Salsa & Anna (@anna) untuk Bos Anas
-- Repositori: https://github.com/canas1257/cekworld.git
-- ==============================================================================

local CONFIG = {
    -- Sumber daftar world:
    -- Bot akan membaca file ini jika ada. Jika kosong/tidak ada, pakai tabel WORLDS.
    WORLD_LIST_FILE = "world_list.txt",

    -- Daftar world manual (Fallback):
    -- Format: "NAMA_WORLD" atau "NAMA_WORLD|DOOR_ID"
    WORLDS = {
        "FARMKU1",
        "FARMKU2|DOOR1",
        "FARMKU3",
    },

    -- ID Seed target spesifik:
    -- 0 = Cek SEMUA jenis tanaman/pohon
    -- > 0 = Hanya cari tanaman dari Seed ID tertentu (contoh: 4585 untuk Pepper Tree)
    TARGET_SEED_ID = 0,

    -- Mode pengecekan:
    -- true  = Hanya hitung tanaman yang siap panen (canHarvest)
    -- false = Hitung tanaman siap panen DAN bibit yang sedang tumbuh
    READY_ONLY = false,

    -- Pengaturan Waktu & Jeda:
    WARP_DELAY = 1500,       -- Jeda tunggu streaming tile selesai pasca-warp (ms)
    WARP_TIMEOUT = 8,        -- Batas maksimal menunggu masuk world (detik)
    MAX_RECONNECT_WAIT = 60, -- Batas maksimal menunggu bot online saat disconnect (detik)
    NEXT_WORLD_DELAY = 1000, -- Jeda sebelum lanjut ke world berikutnya (ms)

    -- Mode Putaran (Looping):
    -- true  = Bot keliling terus-menerus tanpa henti
    -- false = Bot hanya cek 1 kali keliling daftar world lalu selesai
    LOOP_MODE = false,
    LOOP_INTERVAL = 60,      -- Jeda antar putaran jika LOOP_MODE = true (detik)

    -- Folder & File Output TXT:
    OUTPUT_DIR = "output",
    OUTPUT = {
        NUKED      = "output/worlds_nuked.txt",       -- World yang terkonfirmasi NUKED / Inaccessible
        HAS_PLANT  = "output/worlds_has_plant.txt",   -- World yang ADA tanaman
        EMPTY      = "output/worlds_empty.txt",       -- World yang terkonfirmasi KOSONG (0 tanaman)
        FAILED     = "output/worlds_failed.txt",      -- World yang gagal warp / gagal scan (lag/dc)
        REPORT     = "output/worlds_scan_report.txt", -- Rekap detail keseluruhan dengan timestamp
    },

    -- Discord Webhook (Opsional untuk monitoring):
    WEBHOOK = {
        ENABLED = false,
        URL = "https://discord.com/api/webhooks/...",
    }
}

-- ==============================================================================
-- INISIALISASI BOT
-- ==============================================================================
local bot = getBot()
if not bot then
    print("[Error] Bot context tidak ditemukan! Jalankan script di console bot Lucifer.")
    return
end

bot.leave_world_before_warp = false

-- State tracking respon server
local isNukedConfirmed = false
local nukeReasonText = ""
local isServerMaintenance = false

-- ==============================================================================
-- HELPER FILESYSTEM & LOGGING (VALIDASI RETURN LENGKAP & FOLDER OUTPUT)
-- ==============================================================================
local function getTimestamp()
    if os and os.date then
        return os.date("[%Y-%m-%d %H:%M:%S]")
    end
    return "[SCAN]"
end

local function appendToFile(path, text)
    if not path or path == "" then return false end

    -- 1. Coba fungsi native Lucifer v2.86 (periksa boolean return)
    if type(append) == "function" then
        local ok, result = pcall(append, path, text .. "\n")
        if ok and result == true then
            return true
        end
    end

    -- 2. Fallback I/O standar Lua dengan pengecekan f:write dan f:close (flush)
    if io and io.open then
        local f, err = io.open(path, "a")
        if f then
            local writeOk = f:write(text .. "\n")
            local closeOk = f:close()
            if writeOk and closeOk then
                return true
            end
        else
            -- Jika direktori belum ada, coba buat via os.execute jika memungkinkan
            if os and os.execute and path:find("/") then
                local dir = path:match("^(.-)/[^/]+$")
                if dir then
                    pcall(os.execute, "mkdir -p " .. dir)
                    local retryF = io.open(path, "a")
                    if retryF then
                        local wOk = retryF:write(text .. "\n")
                        local cOk = retryF:close()
                        if wOk and cOk then return true end
                    end
                end
            end
            print(string.format("[Error] Gagal membuka file '%s': %s", tostring(path), tostring(err or "unknown")))
        end
    end

    print(string.format("[Error] Gagal menulis ke file '%s'!", tostring(path)))
    return false
end

local function readFileLines(path)
    local lines = {}
    local raw = ""

    if type(read) == "function" then
        local ok, res = pcall(read, path)
        if ok and res and type(res) == "string" then
            raw = res
        end
    end

    if raw == "" and io and io.open then
        local f = io.open(path, "r")
        if f then
            raw = f:read("*a") or ""
            f:close()
        end
    end

    if raw ~= "" then
        for line in raw:gmatch("[^\r\n]+") do
            local clean = line:match("^%s*(.-)%s*$")
            if clean and #clean > 0 and not clean:find("^#") and not clean:find("^//") then
                table.insert(lines, clean)
            end
        end
    end
    return lines
end

local function parseWorldEntry(entry)
    if not entry or entry == "" then return "", "" end
    local w, d = entry:match("^([^|:]+)[|:](.*)$")
    if not w then
        w = entry:match("^([^|:]+)$")
        d = ""
    end
    local cleanW = (w or ""):match("^%s*(.-)%s*$"):upper()
    local cleanD = (d or ""):match("^%s*(.-)%s*$")
    return cleanW, cleanD
end

-- ==============================================================================
-- WEBHOOK NOTIFIKASI
-- ==============================================================================
local function sendWebhookNotification(title, desc, color)
    local cfg = CONFIG.WEBHOOK
    if not cfg or not cfg.ENABLED or not cfg.URL or cfg.URL == "" then
        return
    end
    -- Plain string match (1, true) agar tanda titik literal tidak dianggap pattern regex
    if cfg.URL:find("webhooks/...", 1, true) then
        return
    end

    if type(Webhook) == "table" and Webhook.new then
        pcall(function()
            local wh = Webhook.new(cfg.URL)
            wh.username = "Lucifer Checker (" .. tostring(bot.name) .. ")"
            wh.embed1.use = true
            wh.embed1.title = title
            wh.embed1.description = desc
            wh.embed1.color = color or 3447003
            wh:send()
        end)
    end
end

-- ==============================================================================
-- EVENT LISTENER (FILTER PESAN KETAT UNTUK DETEKSI INACCESSIBLE / NUKED)
-- ==============================================================================
local function inspectServerMessage(msg)
    if not msg then return end
    local clean = type(removeColor) == "function" and removeColor(msg) or msg
    clean = tostring(clean):lower()

    -- 1. Deteksi Server Maintenance (Bukan Nuked!)
    if clean:find("maintenance") or clean:find("server is being updated") then
        isServerMaintenance = true
        return
    end

    -- 2. Deteksi Pesan Nuke / Inaccessible Khusus World dari respons server
    if clean:find("is inaccessible") or clean:find("inaccessible, try another") or clean:find("world is inaccessible") or clean:find("world is nuked") or clean:find("has been nuked") then
        isNukedConfirmed = true
        nukeReasonText = clean
    end
end

if type(addEvent) == "function" and type(Event) == "table" then
    if Event.game_message then addEvent(Event.game_message, checkMessageForNuke or inspectServerMessage) end
    if Event.generic_text then addEvent(Event.generic_text, checkMessageForNuke or inspectServerMessage) end
end

-- ==============================================================================
-- HELPER KONEKSI & RECONNECT GUARD (BOUNDED)
-- ==============================================================================
local function waitOnline(maxSec)
    local limit = maxSec or CONFIG.MAX_RECONNECT_WAIT
    for _ = 1, limit do
        if bot.status == BotStatus.online then
            return true
        end
        if bot.status == BotStatus.account_banned or bot.status == BotStatus.location_banned or bot.status == BotStatus.account_suspended then
            print(string.format("[FATAL] Bot terkena sanksi (%s)! Script dihentikan.", tostring(bot.status)))
            return false
        end
        sleep(1000)
    end
    return false
end

-- ==============================================================================
-- WARP DENGAN PUMPING EVENT AKTIF
-- ==============================================================================
local function executeWarp(worldName, doorId)
    isNukedConfirmed = false
    nukeReasonText = ""
    isServerMaintenance = false

    if not waitOnline(10) then
        return false, "BOT_OFFLINE"
    end

    local upperTarget = worldName:upper()

    -- Branching strict: jangan oper "" ke argumen kedua
    if doorId and doorId ~= "" then
        bot:warp(upperTarget, doorId)
    else
        bot:warp(upperTarget)
    end

    local elapsed = 0
    local pollStep = 0.5
    local maxWait = CONFIG.WARP_TIMEOUT

    while elapsed < maxWait do
        if type(listenEvents) == "function" then
            listenEvents(pollStep)
        else
            sleep(math.floor(pollStep * 1000))
        end
        elapsed = elapsed + pollStep

        -- 1. Respon nuke / inaccessible dari server
        if isNukedConfirmed then
            return false, "INACCESSIBLE"
        end

        -- 2. Server maintenance
        if isServerMaintenance then
            return false, "SERVER_MAINTENANCE"
        end

        -- 3. Cek kedatangan bot
        if (bot:isInWorld(upperTarget) or bot:isInWorld(worldName)) and bot:isInWorld() then
            sleep(CONFIG.WARP_DELAY)
            return true, "SUCCESS"
        end

        if bot.status ~= BotStatus.online then
            return false, "DISCONNECT"
        end
    end

    return false, "WARP_TIMEOUT"
end

-- ==============================================================================
-- SCANNER TANAMAN PADA WORLD
-- Mengembalikan:
-- ok (bool), readyCount (int), growingCount (int), otherPlants (int), errReason (string)
-- ==============================================================================
local function scanWorldPlants(targetWorldName)
    local upperTarget = targetWorldName:upper()

    if not bot:isInWorld(upperTarget) and not bot:isInWorld(targetWorldName) then
        return false, 0, 0, 0, "NOT_IN_TARGET_WORLD"
    end

    if bot.status ~= BotStatus.online then
        return false, 0, 0, 0, "BOT_OFFLINE_DURING_SCAN"
    end

    local world = bot:getWorld()
    if not world then
        return false, 0, 0, 0, "WORLD_OBJECT_NIL"
    end

    local tiles = world:getTilesSafe()
    if not tiles or #tiles == 0 then
        return false, 0, 0, 0, "TILES_SNAPSHOT_EMPTY"
    end

    local readyCount = 0
    local growingCount = 0
    local otherPlants = 0
    local targetSeed = CONFIG.TARGET_SEED_ID or 0

    for _, tile in ipairs(tiles) do
        if tile.fg and tile.fg ~= 0 then
            -- 1. Siap panen (canHarvest)
            if tile:canHarvest() then
                if targetSeed > 0 then
                    if tile.fg == targetSeed then
                        readyCount = readyCount + 1
                    else
                        otherPlants = otherPlants + 1
                    end
                else
                    readyCount = readyCount + 1
                end
            else
                -- 2. Tanaman bertumbuh (Filter ketat: Seed di Growtopia ID ganjil)
                local isSeedItem = (tile.fg % 2 == 1)
                if isSeedItem then
                    local isVerifiedGrowing = false

                    -- Metadata timer pertumbuhan pada extra tile
                    if tile.hasExtra and tile:hasExtra() then
                        local extra = tile:getExtra()
                        if extra and extra.growth ~= nil then
                            isVerifiedGrowing = true
                        end
                    end

                    -- Validasi katalog nama / action_type seed
                    if not isVerifiedGrowing and type(getInfo) == "function" then
                        local info = getInfo(tile.fg)
                        if info and info.name then
                            local lowerName = info.name:lower()
                            if lowerName:find(" seed$", 1, false) or lowerName:find(" seed ", 1, false) or (info.action_type and info.action_type == 19) then
                                isVerifiedGrowing = true
                            end
                        end
                    end

                    if isVerifiedGrowing then
                        if targetSeed > 0 then
                            if tile.fg == targetSeed then
                                growingCount = growingCount + 1
                            else
                                otherPlants = otherPlants + 1
                            end
                        else
                            growingCount = growingCount + 1
                        end
                    end
                end
            end
        end
    end

    if bot.status ~= BotStatus.online or not bot:isInWorld() then
        return false, 0, 0, 0, "DISCONNECT_DURING_SCAN"
    end

    return true, readyCount, growingCount, otherPlants, nil
end

-- ==============================================================================
-- LOGIKA PEMERIKSAAN SATU WORLD
-- ==============================================================================
local function processSingleWorld(worldEntry)
    local worldName, worldDoor = parseWorldEntry(worldEntry)
    if worldName == "" then return end

    local fullLabel = worldName .. (worldDoor ~= "" and ("|" .. worldDoor) or "")
    local timestamp = getTimestamp()

    print(string.format("\n--------------------------------------------------"))
    print(string.format("[%s] Memeriksa: %s...", bot.name, fullLabel))

    -- 1. Eksekusi Warp
    local success, reason = executeWarp(worldName, worldDoor)

    -- Retry 1x jika timeout untuk toleransi lag
    if not success and reason == "WARP_TIMEOUT" then
        print(string.format("[%s] Warp pertama timeout, mencoba ulang 1x...", bot.name))
        sleep(1000)
        success, reason = executeWarp(worldName, worldDoor)
    end

    -- ==========================================================================
    -- 2. EVALUASI HASIL WARP
    -- ==========================================================================

    -- KASUS A: INACCESSIBLE / NUKED TERKONFIRMASI
    if not success and reason == "INACCESSIBLE" then
        print(string.format("[HASIL] ⛔ %s => INACCESSIBLE / NUKED (Pesan: %s)", fullLabel, tostring(nukeReasonText)))
        appendToFile(CONFIG.OUTPUT.NUKED, fullLabel)
        appendToFile(CONFIG.OUTPUT.REPORT, string.format("%s %-20s | STATUS: INACCESSIBLE | Respon: %s", timestamp, fullLabel, nukeReasonText))
        sendWebhookNotification("⛔ World Inaccessible / Nuked", string.format("**World:** `%s`\n**Pesan:** %s", fullLabel, nukeReasonText), 15158332)
        return
    end

    -- KASUS B: SERVER MAINTENANCE
    if not success and reason == "SERVER_MAINTENANCE" then
        print(string.format("[HASIL] ⏸️ %s => GAGAL (SERVER SEDANG MAINTENANCE)", fullLabel))
        appendToFile(CONFIG.OUTPUT.FAILED, string.format("%-18s | Reason: SERVER_MAINTENANCE", fullLabel))
        appendToFile(CONFIG.OUTPUT.REPORT, string.format("%s %-20s | STATUS: FAILED (SERVER_MAINTENANCE)", timestamp, fullLabel))
        return
    end

    -- KASUS C: GAGAL WARP (Timeout / Offline / Lag) -> BUKAN BUKTI NUKE!
    if not success then
        print(string.format("[HASIL] ⚠️ %s => GAGAL WARP (Alasan: %s) -> Ditulis ke FAILED", fullLabel, reason))
        appendToFile(CONFIG.OUTPUT.FAILED, string.format("%-18s | Reason: %s", fullLabel, reason))
        appendToFile(CONFIG.OUTPUT.REPORT, string.format("%s %-20s | STATUS: WARP_FAILED (%s)", timestamp, fullLabel, reason))
        return
    end

    -- ==========================================================================
    -- 3. EVALUASI HASIL SCAN TANAMAN
    -- ==========================================================================
    local scanOk, ready, growing, others, scanErr = scanWorldPlants(worldName)

    -- KASUS D: SCAN GAGAL -> JANGAN ANGGAP KOSONG!
    if not scanOk then
        print(string.format("[HASIL] ⚠️ %s => SCAN GAGAL (Alasan: %s) -> Ditulis ke FAILED", fullLabel, tostring(scanErr)))
        appendToFile(CONFIG.OUTPUT.FAILED, string.format("%-18s | Reason: SCAN_FAILED_%s", fullLabel, tostring(scanErr)))
        appendToFile(CONFIG.OUTPUT.REPORT, string.format("%s %-20s | STATUS: SCAN_FAILED (%s)", timestamp, fullLabel, tostring(scanErr)))
        return
    end

    local targetSeed = CONFIG.TARGET_SEED_ID or 0
    local readyOnly = CONFIG.READY_ONLY

    -- Kasus Target Seed Spesifik Tidak Ditemukan Tapi Ada Tanaman Lain
    if targetSeed > 0 and (ready == 0 and growing == 0) and others > 0 then
        local msg = string.format("Target ID %d tidak ada, tetapi ada %d tanaman lain", targetSeed, others)
        print(string.format("[HASIL] 🔍 %s => TARGET TIDAK DITEMUKAN [%s]", fullLabel, msg))
        appendToFile(CONFIG.OUTPUT.EMPTY, string.format("%-18s | STATUS: TARGET_NOT_FOUND (Ada %d tanaman lain)", fullLabel, others))
        appendToFile(CONFIG.OUTPUT.REPORT, string.format("%s %-20s | STATUS: TARGET_NOT_FOUND | Target: ID %d (0) | Other Plants: %d", timestamp, fullLabel, targetSeed, others))
        return
    end

    -- Kasus READY_ONLY aktif dan ada tanaman tumbuh tapi belum ada yang ready
    if readyOnly and ready == 0 and growing > 0 then
        local msg = string.format("Belum ada pohon siap panen (Masih Tumbuh: %d)", growing)
        print(string.format("[HASIL] ⏳ %s => BELUM SIAP PANEN [%s]", fullLabel, msg))
        appendToFile(CONFIG.OUTPUT.EMPTY, string.format("%-18s | STATUS: NO_READY_PLANTS (Tumbuh: %d)", fullLabel, growing))
        appendToFile(CONFIG.OUTPUT.REPORT, string.format("%s %-20s | STATUS: NO_READY_PLANTS | Ready: 0 | Growing: %d", timestamp, fullLabel, growing))
        return
    end

    local evaluatedTotal = ready + (readyOnly and 0 or growing)

    -- KASUS E: ADA TANAMAN
    if evaluatedTotal > 0 then
        local detailStr = string.format("Total: %d (Siap Panen: %d, Tumbuh: %d)", ready + growing, ready, growing)
        print(string.format("[HASIL] 🌿 %s => ADA TANAMAN [%s]", fullLabel, detailStr))
        appendToFile(CONFIG.OUTPUT.HAS_PLANT, string.format("%-18s | %s", fullLabel, detailStr))
        appendToFile(CONFIG.OUTPUT.REPORT, string.format("%s %-20s | STATUS: ADA TANAMAN | Ready: %-4d | Growing: %-4d | Total: %-4d",
            timestamp, fullLabel, ready, growing, ready + growing))
        sendWebhookNotification("🌿 Ada Tanaman", string.format("**World:** `%s`\n**Siap Panen:** %d\n**Tumbuh:** %d",
            fullLabel, ready, growing), 3066993)

    -- KASUS F: BENAR-BENAR KOSONG (0 Tanaman sama sekali)
    else
        print(string.format("[HASIL] 🍂 %s => TERKONFIRMASI KOSONG (0 Tanaman)", fullLabel))
        appendToFile(CONFIG.OUTPUT.EMPTY, fullLabel)
        appendToFile(CONFIG.OUTPUT.REPORT, string.format("%s %-20s | STATUS: KOSONG_TOTAL", timestamp, fullLabel))
        sendWebhookNotification("🍂 World Kosong", string.format("**World:** `%s`\n**Status:** Bersih / Tanpa Tanaman", fullLabel), 9807270)
    end
end

-- ==============================================================================
-- EKSEKUTOR UTAMA
-- ==============================================================================
local function runScanner()
    print("==================================================")
    print("      LUCIFER WORLD CHECKER BOT v2.86            ")
    print("==================================================")

    while true do
        local worldList = readFileLines(CONFIG.WORLD_LIST_FILE)
        if #worldList == 0 then
            worldList = CONFIG.WORLDS or {}
        end

        if #worldList == 0 then
            print("[Warning] Daftar world kosong! Isi world_list.txt atau CONFIG.WORLDS.")
            break
        end

        print(string.format("\n[Info] Memulai pemeriksaan %d world...", #worldList))

        for index, entry in ipairs(worldList) do
            if not waitOnline(CONFIG.MAX_RECONNECT_WAIT) then
                print("[Fatal] Bot offline melebihi batas waktu tunggu! Menghentikan rotasi scan.")
                appendToFile(CONFIG.OUTPUT.REPORT, string.format("%s BOT_ABORTED | Bot offline melebihi batas tunggu", getTimestamp()))
                return
            end

            print(string.format("\n[%d/%d] Scanning...", index, #worldList))
            processSingleWorld(entry)

            sleep(CONFIG.NEXT_WORLD_DELAY)
        end

        print("\n==================================================")
        print("          PUTARAN PEMERIKSAAN SELESAI            ")
        print("==================================================")

        if not CONFIG.LOOP_MODE then
            print("[Selesai] Mode 1x putaran selesai. Script berhenti.")
            break
        else
            print(string.format("[Loop] Menunggu %d detik sebelum putaran berikutnya...", CONFIG.LOOP_INTERVAL))
            sleep(CONFIG.LOOP_INTERVAL * 1000)
        end
    end
end

-- ==============================================================================
-- CLEANUP
-- ==============================================================================
function on_stop(errorMessage)
    if type(removeEvents) == "function" then
        removeEvents()
    end
    if errorMessage and errorMessage ~= "" then
        print("[Scanner Error]: " .. errorMessage)
    else
        print("[Scanner Berhenti]")
    end
end

runScanner()
