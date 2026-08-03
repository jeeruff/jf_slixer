-- jf_slixer_load_item.lua
-- Стримит ВЫДЕЛЕННЫЙ айтем (активный тейк, как он звучит: с playrate и
-- stretch-маркерами) в активную деку jf_slixer через gmem.
-- API: gmem_*, GetSelectedMediaItem, GetActiveTake, CreateTakeAudioAccessor,
--      GetAudioAccessorSamples

local CHUNK = 32768
local DATA  = 16384
local MAXFR = 8286208

reaper.gmem_attach("jf_slixer")

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
local srate = src and reaper.GetMediaSourceSampleRate(src) or 0
if not srate or srate <= 0 then srate = 48000 end
local nch = src and math.max(1, reaper.GetMediaSourceNumChannels(src)) or 2
if nch > 8 then nch = 8 end
local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
if len <= 0 then return end

local frames = math.min(math.floor(len * srate), MAXFR)
local acc = reaper.CreateTakeAudioAccessor(take)
local t0 = reaper.GetAudioAccessorStartTime(acc)

local deck = reaper.gmem_read(6)
if deck ~= 1 then deck = 0 end

reaper.gmem_write(101, deck)
reaper.gmem_write(102, srate)
reaper.gmem_write(103, frames)
reaper.gmem_write(100, 1)  -- header

local pos = 0
local t_wait = reaper.time_precise()

local function step()
  if reaper.gmem_read(100) ~= 0 then
    if reaper.time_precise() - t_wait > 4 then
      reaper.gmem_write(100, 0)
      reaper.DestroyAudioAccessor(acc)
      reaper.MB("jf_slixer не отвечает - плагин вставлен и не в оффлайне?", "jf_slixer", 0)
      return
    end
    reaper.defer(step)
    return
  end
  t_wait = reaper.time_precise()
  if pos >= frames then
    reaper.gmem_write(100, 3)  -- done
    reaper.DestroyAudioAccessor(acc)
    return
  end
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
  reaper.gmem_write(105, pos)
  reaper.gmem_write(100, 2)  -- chunk ready
  pos = pos + n
  reaper.defer(step)
end

step()
