-- jf_slixer_helper.lua
-- Фоновый мост для кнопок LOAD / ITEM в jf_slixer.
-- Висит в defer-цикле, ловит команды из плагина через gmem:
--   gmem[7] = 1  -> нативный диалог выбора файла, стрим в активную деку
--   gmem[7] = 2  -> загрузить выделенный айтем (активный тейк как звучит)
-- Heartbeat: gmem[8] инкрементируется каждый тик — плагин видит, что хелпер жив.
-- Запускается автоматически из __startup.lua (или вручную из Actions).

local CHUNK = 32768
local DATA  = 16384
local MAXFR = 8269824

reaper.gmem_attach("jf_slixer")

local acc, tr_tmp = nil, nil
local streaming = false
local pos, frames, srate, nch, t0 = 0, 0, 0, 0, 0
local t_wait = 0
local hb = 0

local function finish()
  if acc then reaper.DestroyAudioAccessor(acc); acc = nil end
  if tr_tmp then
    reaper.DeleteTrack(tr_tmp); tr_tmp = nil
    reaper.UpdateArrange()
  end
  streaming = false
end

local function start_stream(deck)
  reaper.gmem_write(101, deck)
  reaper.gmem_write(102, srate)
  reaper.gmem_write(103, frames)
  reaper.gmem_write(100, 1)  -- header
  pos = 0
  streaming = true
  t_wait = reaper.time_precise()
end

local function active_deck()
  local d = reaper.gmem_read(6)
  if d ~= 1 then d = 0 end
  return d
end

local function cmd_open_file()
  local ok, file = reaper.GetUserFileNameForRead("", "jf_slixer: выбери семпл", "")
  if not ok then return end
  local src = reaper.PCM_Source_CreateFromFile(file)
  if not src then
    reaper.MB("Не удалось открыть файл.", "jf_slixer", 0)
    return
  end
  srate = reaper.GetMediaSourceSampleRate(src)
  if not srate or srate <= 0 then srate = 48000 end
  nch = math.max(1, reaper.GetMediaSourceNumChannels(src))
  if nch > 8 then nch = 8 end
  local len = ({reaper.GetMediaSourceLength(src)})[1] or 0
  if len <= 0 then
    reaper.PCM_Source_Destroy(src)
    reaper.MB("Файл не читается как аудио.", "jf_slixer", 0)
    return
  end
  frames = math.min(math.floor(len * srate), MAXFR)
  reaper.PreventUIRefresh(1)
  local ti = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(ti, false)
  tr_tmp = reaper.GetTrack(0, ti)
  local it = reaper.AddMediaItemToTrack(tr_tmp)
  local tk = reaper.AddTakeToMediaItem(it)
  reaper.SetMediaItemTake_Source(tk, src)
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH", len)
  acc = reaper.CreateTakeAudioAccessor(tk)
  reaper.PreventUIRefresh(-1)
  t0 = 0
  start_stream(active_deck())
end

local function cmd_load_item()
  local item = reaper.GetSelectedMediaItem(0, 0)
  if not item then
    reaper.MB("Выдели аудио-айтем.", "jf_slixer", 0)
    return
  end
  local take = reaper.GetActiveTake(item)
  if not take or reaper.TakeIsMIDI(take) then
    reaper.MB("Активный тейк должен быть аудио.", "jf_slixer", 0)
    return
  end
  local src = reaper.GetMediaItemTake_Source(take)
  srate = src and reaper.GetMediaSourceSampleRate(src) or 0
  if not srate or srate <= 0 then srate = 48000 end
  nch = src and math.max(1, reaper.GetMediaSourceNumChannels(src)) or 2
  if nch > 8 then nch = 8 end
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  if len <= 0 then return end
  frames = math.min(math.floor(len * srate), MAXFR)
  acc = reaper.CreateTakeAudioAccessor(take)
  t0 = reaper.GetAudioAccessorStartTime(acc)
  start_stream(active_deck())
end

local function tick()
  hb = hb + 1
  reaper.gmem_write(8, hb)  -- heartbeat
  if streaming then
    local st = reaper.gmem_read(100)
    if st == 0 then
      t_wait = reaper.time_precise()
      if pos >= frames then
        reaper.gmem_write(100, 3)  -- done
        finish()
      else
        local n = math.min(CHUNK, frames - pos)
        local buf = reaper.new_array(n * nch)
        buf.clear()
        reaper.GetAudioAccessorSamples(acc, srate, nch, t0 + pos / srate, n, buf)
        for i = 0, n - 1 do
          local l = buf[i * nch + 1]
          local r = nch > 1 and buf[i * nch + 2] or l
          reaper.gmem_write(DATA + i * 2, l)
          reaper.gmem_write(DATA + i * 2 + 1, r)
        end
        reaper.gmem_write(104, n)
        reaper.gmem_write(100, 2)  -- chunk ready
        pos = pos + n
      end
    elseif reaper.time_precise() - t_wait > 4 then
      reaper.gmem_write(100, 0)
      finish()
    end
  else
    local cmd = reaper.gmem_read(7)
    if cmd == 1 then
      reaper.gmem_write(7, 0)
      cmd_open_file()
    elseif cmd == 2 then
      reaper.gmem_write(7, 0)
      cmd_load_item()
    end
  end
  reaper.defer(tick)
end

tick()
