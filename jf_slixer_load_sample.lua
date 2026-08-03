-- jf_slixer_load_sample.lua
-- Нативный файловый диалог → стримит выбранный семпл в АКТИВНУЮ деку jf_slixer
-- через gmem. Работает с любым файлом из любой папки, который REAPER умеет
-- декодировать (wav/aiff/flac/mp3/ogg...). Плагин пересоздавать не нужно.
-- API: gmem_attach/read/write, GetUserFileNameForRead, PCM_Source_CreateFromFile,
--      CreateTakeAudioAccessor, GetAudioAccessorSamples (всё нативное, без расширений)

local CHUNK = 32768   -- кадров за передачу (64k значений gmem)
local DATA  = 16384   -- регион данных в gmem
local MAXFR = 8269824 -- лимит буфера деки в jf_slixer

reaper.gmem_attach("jf_slixer")

local ok, file = reaper.GetUserFileNameForRead("", "jf_slixer: выбери семпл", "")
if not ok then return end

local src = reaper.PCM_Source_CreateFromFile(file)
if not src then
  reaper.MB("Не удалось открыть файл.", "jf_slixer", 0)
  return
end

local srate = reaper.GetMediaSourceSampleRate(src)
local nch = reaper.GetMediaSourceNumChannels(src)
local len = ({reaper.GetMediaSourceLength(src)})[1]
if not srate or srate <= 0 or nch <= 0 or not len or len <= 0 then
  reaper.PCM_Source_Destroy(src)
  reaper.MB("Файл не читается как аудио.", "jf_slixer", 0)
  return
end

local frames = math.min(math.floor(len * srate), MAXFR)

-- временный трек+айтем: AudioAccessor читает только из тейков; удаляется после загрузки
reaper.PreventUIRefresh(1)
local tidx = reaper.CountTracks(0)
reaper.InsertTrackAtIndex(tidx, false)
local tr = reaper.GetTrack(0, tidx)
local item = reaper.AddMediaItemToTrack(tr)
local take = reaper.AddTakeToMediaItem(item)
reaper.SetMediaItemTake_Source(take, src)
reaper.SetMediaItemInfo_Value(item, "D_LENGTH", len)
local acc = reaper.CreateTakeAudioAccessor(take)
reaper.PreventUIRefresh(-1)

local deck = reaper.gmem_read(6)  -- jf_slixer публикует активную деку
if deck ~= 1 then deck = 0 end

reaper.gmem_write(101, deck)
reaper.gmem_write(102, srate)
reaper.gmem_write(103, frames)
reaper.gmem_write(100, 1)  -- header

local pos = 0
local t_wait = reaper.time_precise()

local function cleanup()
  reaper.DestroyAudioAccessor(acc)
  reaper.DeleteTrack(tr)
  reaper.UpdateArrange()
end

local function step()
  if reaper.gmem_read(100) ~= 0 then
    -- ждём, пока плагин заберёт предыдущий пакет
    if reaper.time_precise() - t_wait > 4 then
      reaper.gmem_write(100, 0)
      cleanup()
      reaper.MB("jf_slixer не отвечает - плагин вставлен и не в оффлайне?", "jf_slixer", 0)
      return
    end
    reaper.defer(step)
    return
  end
  t_wait = reaper.time_precise()
  if pos >= frames then
    reaper.gmem_write(100, 3)  -- done: плагин финализирует и авто-нарезает
    cleanup()
    return
  end
  local n = math.min(CHUNK, frames - pos)
  local buf = reaper.new_array(n * nch)
  buf.clear()
  reaper.GetAudioAccessorSamples(acc, srate, nch, pos / srate, n, buf)
  for i = 0, n - 1 do
    local l = buf[i * nch + 1]
    local r = nch > 1 and buf[i * nch + 2] or l
    reaper.gmem_write(DATA + i * 2, l)
    reaper.gmem_write(DATA + i * 2 + 1, r)
  end
  reaper.gmem_write(104, n)
  reaper.gmem_write(105, pos)
  reaper.gmem_write(100, 2)  -- chunk ready
  pos = pos + n
  reaper.defer(step)
end

step()
