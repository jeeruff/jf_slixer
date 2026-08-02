-- jf_slixer_push_markers.lua
-- Публикует тейк-маркеры выделенного айтема в jf_slixer (JSFX) через gmem.
-- API: gmem_attach, GetSelectedMediaItem, GetActiveTake, GetNumTakeMarkers,
--      GetTakeMarker, GetMediaItemTakeInfo_Value, GetMediaItemInfo_Value
-- Требуется REAPER >= 6.09 (take markers + GetTakeMarker).

local MAGIC = 8888123
local MAX_SLICES = 64

reaper.gmem_attach("jf_slixer")

local item = reaper.GetSelectedMediaItem(0, 0)
if not item then
  reaper.MB("Выдели айтем с тейк-маркерами.", "jf_slixer", 0)
  return
end

local take = reaper.GetActiveTake(item)
if not take or reaper.TakeIsMIDI(take) then
  reaper.MB("Активный тейк должен быть аудио.", "jf_slixer", 0)
  return
end

local n = reaper.GetNumTakeMarkers(take)
if n == 0 then
  reaper.MB("В активном тейке нет тейк-маркеров.", "jf_slixer", 0)
  return
end

local offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
local len  = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
if rate == 0 then rate = 1 end

-- take markers живут в source-времени; переводим в позицию от начала айтема
local pos = {}
for i = 0, n - 1 do
  local srcpos = reaper.GetTakeMarker(take, i)
  local rel = (srcpos - offs) / rate
  if rel >= 0 and rel <= len then
    pos[#pos + 1] = rel
  end
end
table.sort(pos)

local cnt = math.min(#pos, MAX_SLICES)
for i = 1, cnt do
  reaper.gmem_write(8 + (i - 1), pos[i])
end
reaper.gmem_write(2, cnt)
reaper.gmem_write(4, len)
reaper.gmem_write(0, MAGIC)
reaper.gmem_write(1, reaper.gmem_read(1) + 1) -- serial: JSFX подхватит автоматически

reaper.MB(string.format("Отправлено маркеров: %d (длина айтема %.2fs).\njf_slixer подхватит их автоматически.", cnt, len), "jf_slixer", 0)
