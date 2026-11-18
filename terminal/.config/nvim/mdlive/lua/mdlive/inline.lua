-- Spans use 0-based byte columns relative to the parsed text: `s` inclusive, `e` exclusive.
-- `ms` lists the syntax ranges that Live Preview hides when the cursor is away.
local M = {}

local function char(text, i)
  return text:sub(i, i)
end

local function is_space(c)
  return c == "" or c:match("^%s$") ~= nil
end

local function is_punct(c)
  return c ~= "" and c:byte() < 128 and c:match("^%p$") ~= nil
end

local function is_word_byte(b)
  return b and (b >= 128 or string.char(b):match("[%w]") ~= nil)
end

local function skip_code(text, i)
  local run = text:match("^`+", i)
  local len = #run
  local j = i + len
  while true do
    local a, b = text:find("`+", j)
    if not a then
      return nil, i + len
    end
    if b - a + 1 == len then
      return a, b + 1
    end
    j = b + 1
  end
end

local function matching_bracket(text, i)
  local depth, j, n = 0, i, #text
  while j <= n do
    local c = char(text, j)
    if c == "\\" then
      j = j + 2
    elseif c == "`" then
      local _, after = skip_code(text, j)
      j = after
    elseif c == "[" then
      depth = depth + 1
      j = j + 1
    elseif c == "]" then
      depth = depth - 1
      if depth == 0 then
        return j
      end
      j = j + 1
    else
      j = j + 1
    end
  end
end

local function parse_destination(text, k)
  local n = #text
  while k <= n and char(text, k):match("%s") do
    k = k + 1
  end
  local dest
  if char(text, k) == "<" then
    local close = text:find(">", k + 1, true)
    if not close then
      return nil
    end
    dest = text:sub(k + 1, close - 1)
    k = close + 1
  else
    local depth, ds = 0, k
    while k <= n do
      local c = char(text, k)
      if c == "\\" then
        k = k + 2
      elseif c == "(" then
        depth = depth + 1
        k = k + 1
      elseif c == ")" then
        if depth == 0 then
          break
        end
        depth = depth - 1
        k = k + 1
      elseif c:match("%s") then
        break
      else
        k = k + 1
      end
    end
    dest = text:sub(ds, k - 1)
  end
  while k <= n and char(text, k):match("%s") do
    k = k + 1
  end
  local q = char(text, k)
  if q == '"' or q == "'" or q == "(" then
    local closer = q == "(" and ")" or q
    local close = text:find(closer, k + 1, true)
    if not close then
      return nil
    end
    k = close + 1
    while k <= n and char(text, k):match("%s") do
      k = k + 1
    end
  end
  if char(text, k) ~= ")" then
    return nil
  end
  return dest, k
end

local function parse_link(text, i, image)
  local close = matching_bracket(text, i)
  if not close or char(text, close + 1) ~= "(" then
    return nil
  end
  local dest, paren = parse_destination(text, close + 2)
  if not dest then
    return nil
  end
  local start = image and i - 1 or i
  return {
    t = image and "image" or "link",
    s = start - 1,
    e = paren,
    url = dest,
    cs = i,
    ce = close - 1,
    ms = { { start - 1, i }, { close - 1, paren } },
    url_s = close + 1,
    url_e = close + 1 + #dest,
  }
end

local function split_target(inner)
  local target, alias = inner:match("^(.-)|(.*)$")
  if not target then
    target = inner
  end
  local path, sub = target:match("^(.-)#(.*)$")
  if not path then
    path = target
  end
  return target, alias, path, sub
end

local function wikilink(text, i, embed)
  local start = embed and i + 3 or i + 2
  local close = text:find("]]", start, true)
  if not close then
    return nil
  end
  local inner = text:sub(start, close - 1)
  if inner:find("[[", 1, true) then
    return nil
  end
  local target, alias, path, sub = split_target(inner)
  local span = {
    t = embed and "embed" or "wikilink",
    s = i - 1,
    e = close + 1,
    target = target,
    path = path,
    sub = sub,
    alias = alias,
    ts = start - 1,
    te = start - 1 + #target,
  }
  if alias then
    span.ds, span.de = span.te + 1, close - 1
    span.ms = { { i - 1, span.te + 1 }, { close - 1, close + 1 } }
  else
    span.ds, span.de = span.ts, span.te
    span.ms = { { i - 1, start - 1 }, { close - 1, close + 1 } }
    if sub then
      span.hash = span.ts + #path
      if path == "" then
        table.insert(span.ms, { span.hash, span.hash + 1 })
        span.hash = nil
      end
    end
  end
  return span
end

local function bare_url(text, i)
  local u = text:match("^https?://[^%s<>]+", i) or text:match("^www%.[^%s<>]+", i)
  if not u then
    return nil
  end
  while #u > 0 do
    local last = u:sub(-1)
    if last:match("[%.,:;%?!%*_~'\"]") then
      u = u:sub(1, -2)
    elseif last == ")" then
      local _, opens = u:gsub("%(", "")
      local _, closes = u:gsub("%)", "")
      if closes > opens then
        u = u:sub(1, -2)
      else
        break
      end
    else
      break
    end
  end
  if u == "" or u:match("^https?://$") then
    return nil
  end
  return u
end

local function tag_at(text, i)
  local n, j = #text, i + 1
  while j <= n do
    local b = text:byte(j)
    if b >= 128 or string.char(b):match("[%w_/%-]") then
      j = j + 1
    else
      break
    end
  end
  local name = text:sub(i + 1, j - 1)
  if name == "" or not name:match("[^%d]") then
    return nil
  end
  return name, j
end

local function flanking(text, i, len)
  local before = i > 1 and char(text, i - 1) or ""
  local after = char(text, i + len)
  local b_byte, a_byte = text:byte(i - 1), text:byte(i + len)
  if b_byte and b_byte >= 128 then
    before = "a"
  end
  if a_byte and a_byte >= 128 then
    after = "a"
  end
  local left = not is_space(after) and (not is_punct(after) or is_space(before) or is_punct(before))
  local right = not is_space(before) and (not is_punct(before) or is_space(after) or is_punct(after))
  return left, right, before, after
end

local function process_emphasis(delims, out)
  local kinds = { ["*"] = true, ["_"] = true }
  local ci = 1
  while ci <= #delims do
    local closer = delims[ci]
    local matched = false
    if closer.can_close and closer.len > 0 then
      for oi = ci - 1, 1, -1 do
        local op = delims[oi]
        if op.ch == closer.ch and op.can_open and op.len > 0 then
          local ok
          if kinds[op.ch] then
            ok = not ((op.can_close or closer.can_open) and (op.orig + closer.orig) % 3 == 0 and not (op.orig % 3 == 0 and closer.orig % 3 == 0))
          else
            ok = op.len == 2 and closer.len == 2
          end
          if ok then
            local use = kinds[op.ch] and ((op.len >= 2 and closer.len >= 2) and 2 or 1) or 2
            local os = op.pos + op.len - use
            local cs = closer.pos
            local t
            if op.ch == "~" then
              t = "strike"
            elseif op.ch == "=" then
              t = "highlight"
            else
              t = use == 2 and "strong" or "em"
            end
            out[#out + 1] = {
              t = t,
              s = os - 1,
              e = cs - 1 + use,
              cs = os - 1 + use,
              ce = cs - 1,
              ms = { { os - 1, os - 1 + use }, { cs - 1, cs - 1 + use } },
            }
            op.len = op.len - use
            closer.pos = closer.pos + use
            closer.len = closer.len - use
            for k = oi + 1, ci - 1 do
              delims[k].len = 0
            end
            matched = true
            break
          end
        end
      end
    end
    if not matched or closer.len == 0 then
      ci = ci + 1
    end
  end
end

function M.parse(text)
  local out, delims = {}, {}
  local n, i = #text, 1
  while i <= n do
    local c = char(text, i)
    local nxt = char(text, i + 1)
    if c == "\\" and nxt ~= "" and is_punct(nxt) then
      out[#out + 1] = { t = "escape", s = i - 1, e = i + 1, ms = { { i - 1, i } } }
      i = i + 2
    elseif c == "`" then
      local close, after = skip_code(text, i)
      if close then
        local len = after - close
        out[#out + 1] = {
          t = "code",
          s = i - 1,
          e = after - 1,
          cs = i - 1 + len,
          ce = close - 1,
          ms = { { i - 1, i - 1 + len }, { close - 1, after - 1 } },
        }
      end
      i = after
    elseif c == "%" and nxt == "%" then
      local close = text:find("%%", i + 2, true)
      local e = close and close + 1 or n
      out[#out + 1] = { t = "comment", s = i - 1, e = e, open = not close }
      i = e + 1
    elseif c == "$" then
      if nxt == "$" then
        local close = text:find("$$", i + 2, true)
        if close then
          out[#out + 1] = {
            t = "math",
            display = true,
            s = i - 1,
            e = close + 1,
            cs = i + 1,
            ce = close - 1,
            ms = { { i - 1, i + 1 }, { close - 1, close + 1 } },
          }
          i = close + 2
        else
          i = i + 2
        end
      else
        local found
        if nxt ~= "" and not nxt:match("%s") and nxt ~= "$" then
          local j = i + 1
          while true do
            local a = text:find("$", j, true)
            if not a then
              break
            end
            local before = char(text, a - 1)
            if before ~= "\\" and not before:match("%s") and not char(text, a + 1):match("%d") then
              found = a
              break
            end
            j = a + 1
          end
        end
        if found then
          out[#out + 1] = {
            t = "math",
            s = i - 1,
            e = found,
            cs = i,
            ce = found - 1,
            ms = { { i - 1, i }, { found - 1, found } },
          }
          i = found + 1
        else
          i = i + 1
        end
      end
    elseif text:sub(i, i + 2) == "![[" or text:sub(i, i + 1) == "[[" then
      local span = wikilink(text, i, c == "!")
      if span then
        out[#out + 1] = span
        i = span.e + 1
      else
        i = i + (c == "!" and 3 or 2)
      end
    elseif c == "!" and nxt == "[" then
      local span = parse_link(text, i + 1, true)
      if span then
        out[#out + 1] = span
        i = span.e + 1
      else
        i = i + 1
      end
    elseif c == "[" and nxt == "^" then
      local id, after = text:match("^%[%^([^%]%s]+)%]()", i)
      if id and char(text, after) ~= ":" then
        out[#out + 1] = { t = "footref", s = i - 1, e = after - 1, id = id }
        i = after
      else
        i = i + 1
      end
    elseif c == "[" then
      local span = parse_link(text, i, false)
      if span then
        out[#out + 1] = span
        for _, inner in ipairs(M.parse(text:sub(span.cs + 1, span.ce))) do
          inner.s, inner.e = inner.s + span.cs, inner.e + span.cs
          if inner.cs then
            inner.cs, inner.ce = inner.cs + span.cs, inner.ce + span.cs
          end
          for _, m in ipairs(inner.ms or {}) do
            m[1], m[2] = m[1] + span.cs, m[2] + span.cs
          end
          if inner.t ~= "link" and inner.t ~= "url" then
            out[#out + 1] = inner
          end
        end
        i = span.e + 1
      else
        i = i + 1
      end
    elseif c == "^" and nxt == "[" then
      local close = matching_bracket(text, i + 1)
      if close then
        out[#out + 1] = { t = "inline_footnote", s = i - 1, e = close }
        i = close + 1
      else
        i = i + 1
      end
    elseif c == "<" then
      local url, after = text:match("^<([%a][%w%+%.%-]+:[^%s<>]*)>()", i)
      if not url then
        url, after = text:match("^<([%w%.%+%-_]+@[%w%.%-]+%.%a+)>()", i)
      end
      if url then
        out[#out + 1] = {
          t = "autolink",
          s = i - 1,
          e = after - 1,
          url = url,
          cs = i,
          ce = after - 2,
          ms = { { i - 1, i }, { after - 2, after - 1 } },
        }
        i = after
      else
        i = i + 1
      end
    elseif (c == "h" or c == "w") and not is_word_byte(text:byte(i - 1)) and bare_url(text, i) then
      local u = bare_url(text, i)
      out[#out + 1] = { t = "url", s = i - 1, e = i - 1 + #u, url = u }
      i = i + #u
    elseif c == "#" and (i == 1 or is_space(char(text, i - 1))) then
      local name, after = tag_at(text, i)
      if name then
        out[#out + 1] = { t = "tag", s = i - 1, e = after - 1, name = name }
        i = after
      else
        i = i + 1
      end
    elseif c == "*" or c == "_" or c == "~" or c == "=" then
      local len = #text:match("^%" .. c .. "+", i)
      local left, right, before, after = flanking(text, i, len)
      local can_open, can_close
      if c == "_" then
        can_open = left and (not right or is_punct(before))
        can_close = right and (not left or is_punct(after))
      else
        can_open, can_close = left, right
      end
      delims[#delims + 1] = { ch = c, pos = i, len = len, orig = len, can_open = can_open, can_close = can_close }
      i = i + len
    else
      i = i + 1
    end
  end
  process_emphasis(delims, out)
  local bid = text:match("()%s%^[%w%-]+%s*$")
  if bid then
    local id_s, id = text:match("()%^([%w%-]+)%s*$")
    out[#out + 1] = { t = "blockid", s = id_s - 1, e = id_s + #id, id = id }
  end
  table.sort(out, function(a, b)
    if a.s ~= b.s then
      return a.s < b.s
    end
    return a.e > b.e
  end)
  return out
end

function M.split_target(inner)
  return split_target(inner)
end

return M
