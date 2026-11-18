local M = {}

local symbols = {
  alpha = "α", beta = "β", gamma = "γ", delta = "δ", epsilon = "ϵ", varepsilon = "ε", zeta = "ζ", eta = "η",
  theta = "θ", vartheta = "ϑ", iota = "ι", kappa = "κ", lambda = "λ", mu = "μ", nu = "ν", xi = "ξ", pi = "π",
  varpi = "ϖ", rho = "ρ", varrho = "ϱ", sigma = "σ", varsigma = "ς", tau = "τ", upsilon = "υ", phi = "ϕ",
  varphi = "φ", chi = "χ", psi = "ψ", omega = "ω", Gamma = "Γ", Delta = "Δ", Theta = "Θ", Lambda = "Λ",
  Xi = "Ξ", Pi = "Π", Sigma = "Σ", Upsilon = "Υ", Phi = "Φ", Psi = "Ψ", Omega = "Ω",
  times = "×", div = "÷", pm = "±", mp = "∓", cdot = "⋅", ast = "∗", star = "⋆", circ = "∘", bullet = "∙",
  leq = "≤", le = "≤", geq = "≥", ge = "≥", neq = "≠", ne = "≠", approx = "≈", equiv = "≡", sim = "∼",
  simeq = "≃", cong = "≅", propto = "∝", ll = "≪", gg = "≫", prec = "≺", succ = "≻",
  infty = "∞", partial = "∂", nabla = "∇", forall = "∀", exists = "∃", nexists = "∄", emptyset = "∅",
  varnothing = "∅", ["in"] = "∈", notin = "∉", ni = "∋", subset = "⊂", supset = "⊃", subseteq = "⊆",
  supseteq = "⊇", cup = "∪", cap = "∩", setminus = "∖", land = "∧", wedge = "∧", lor = "∨", vee = "∨",
  lnot = "¬", neg = "¬", oplus = "⊕", otimes = "⊗", odot = "⊙",
  sum = "∑", prod = "∏", coprod = "∐", int = "∫", iint = "∬", iiint = "∭", oint = "∮", sqrt = "√",
  to = "→", rightarrow = "→", leftarrow = "←", gets = "←", leftrightarrow = "↔", Rightarrow = "⇒",
  Leftarrow = "⇐", Leftrightarrow = "⇔", implies = "⟹", iff = "⟺", mapsto = "↦", uparrow = "↑",
  downarrow = "↓", longrightarrow = "⟶", longleftarrow = "⟵",
  ldots = "…", cdots = "⋯", vdots = "⋮", ddots = "⋱", dots = "…",
  angle = "∠", perp = "⊥", parallel = "∥", mid = "∣", top = "⊤", bot = "⊥", prime = "′",
  hbar = "ℏ", ell = "ℓ", Re = "ℜ", Im = "ℑ", aleph = "ℵ", wp = "℘", degree = "°",
  langle = "⟨", rangle = "⟩", lceil = "⌈", rceil = "⌉", lfloor = "⌊", rfloor = "⌋",
  lbrace = "{", rbrace = "}", vert = "|", Vert = "‖", backslash = "\\",
  quad = "  ", qquad = "    ", [","] = " ", [";"] = " ", [":"] = " ", ["!"] = "", [" "] = " ",
  ["{"] = "{", ["}"] = "}", ["%"] = "%", ["$"] = "$", ["#"] = "#", ["&"] = "&", ["_"] = "_",
  sin = "sin", cos = "cos", tan = "tan", log = "log", ln = "ln", exp = "exp", lim = "lim", max = "max",
  min = "min", det = "det", sup = "sup", inf = "inf", arcsin = "arcsin", arccos = "arccos", arctan = "arctan",
  sinh = "sinh", cosh = "cosh", tanh = "tanh", deg = "deg", gcd = "gcd", mod = "mod",
  left = "", right = "", big = "", Big = "", bigg = "", Bigg = "", displaystyle = "", textstyle = "",
  limits = "", nolimits = "",
}

local sup = {
  ["0"] = "⁰", ["1"] = "¹", ["2"] = "²", ["3"] = "³", ["4"] = "⁴", ["5"] = "⁵", ["6"] = "⁶", ["7"] = "⁷",
  ["8"] = "⁸", ["9"] = "⁹", ["+"] = "⁺", ["-"] = "⁻", ["="] = "⁼", ["("] = "⁽", [")"] = "⁾", a = "ᵃ", b = "ᵇ",
  c = "ᶜ", d = "ᵈ", e = "ᵉ", f = "ᶠ", g = "ᵍ", h = "ʰ", i = "ⁱ", j = "ʲ", k = "ᵏ", l = "ˡ", m = "ᵐ", n = "ⁿ",
  o = "ᵒ", p = "ᵖ", r = "ʳ", s = "ˢ", t = "ᵗ", u = "ᵘ", v = "ᵛ", w = "ʷ", x = "ˣ", y = "ʸ", z = "ᶻ",
  A = "ᴬ", B = "ᴮ", D = "ᴰ", E = "ᴱ", G = "ᴳ", H = "ᴴ", I = "ᴵ", J = "ᴶ", K = "ᴷ", L = "ᴸ", M = "ᴹ", N = "ᴺ",
  O = "ᴼ", P = "ᴾ", R = "ᴿ", T = "ᵀ", U = "ᵁ", V = "ⱽ", W = "ᵂ", [" "] = " ",
}

local sub = {
  ["0"] = "₀", ["1"] = "₁", ["2"] = "₂", ["3"] = "₃", ["4"] = "₄", ["5"] = "₅", ["6"] = "₆", ["7"] = "₇",
  ["8"] = "₈", ["9"] = "₉", ["+"] = "₊", ["-"] = "₋", ["="] = "₌", ["("] = "₍", [")"] = "₎", a = "ₐ", e = "ₑ",
  h = "ₕ", i = "ᵢ", j = "ⱼ", k = "ₖ", l = "ₗ", m = "ₘ", n = "ₙ", o = "ₒ", p = "ₚ", r = "ᵣ", s = "ₛ", t = "ₜ",
  u = "ᵤ", v = "ᵥ", x = "ₓ", [" "] = " ",
}

M.superscript = sup

local styles = {
  mathbb = { N = "ℕ", Z = "ℤ", Q = "ℚ", R = "ℝ", C = "ℂ", P = "ℙ", H = "ℍ" },
  mathcal = { A = "𝒜", B = "ℬ", C = "𝒞", D = "𝒟", E = "ℰ", F = "ℱ", G = "𝒢", H = "ℋ", L = "ℒ", M = "ℳ", N = "𝒩", O = "𝒪", P = "𝒫", R = "ℛ", S = "𝒮", T = "𝒯" },
}

local function script(text, map)
  local out = {}
  for c in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if not map[c] then
      return nil
    end
    out[#out + 1] = map[c]
  end
  return table.concat(out)
end

local render

local function group(src, i)
  local c = src:sub(i, i)
  if c == "{" then
    local depth, j = 1, i + 1
    while j <= #src and depth > 0 do
      local ch = src:sub(j, j)
      if ch == "\\" then
        j = j + 1
      elseif ch == "{" then
        depth = depth + 1
      elseif ch == "}" then
        depth = depth - 1
      end
      j = j + 1
    end
    return src:sub(i + 1, j - 2), j
  elseif c == "\\" then
    local name = src:match("^\\(%a+)", i) or src:sub(i + 1, i + 1)
    return "\\" .. name, i + 1 + #name
  end
  local ch = src:match("^[%z\1-\127\194-\244][\128-\191]*", i)
  return ch, i + #ch
end

render = function(src)
  local out, i, n = {}, 1, #src
  while i <= n do
    local c = src:sub(i, i)
    if c == "\\" then
      local name = src:match("^\\(%a+)", i)
      if name then
        i = i + 1 + #name
        if name == "begin" or name == "end" then
          local env
          env, i = group(src, i)
          if env == "vmatrix" or env == "Vmatrix" then
            out[#out + 1] = env == "vmatrix" and "|" or "‖"
          elseif env == "pmatrix" then
            out[#out + 1] = name == "begin" and "(" or ")"
          elseif env == "bmatrix" then
            out[#out + 1] = name == "begin" and "[" or "]"
          end
        elseif name == "frac" or name == "dfrac" or name == "tfrac" then
          local a, b
          a, i = group(src, i)
          b, i = group(src, i)
          local ra, rb = render(a or ""), render(b or "")
          if #ra > 1 and ra:find("[%+%-%s]") then
            ra = "(" .. ra .. ")"
          end
          if #rb > 1 and rb:find("[%+%-%s]") then
            rb = "(" .. rb .. ")"
          end
          out[#out + 1] = ra .. "/" .. rb
        elseif name == "sqrt" then
          local a
          a, i = group(src, i)
          local r = render(a or "")
          out[#out + 1] = "√" .. (#r > 1 and "(" .. r .. ")" or r)
        elseif styles[name] then
          local a
          a, i = group(src, i)
          out[#out + 1] = (a and styles[name][a]) or render(a or "")
        elseif name == "text" or name == "mathrm" or name == "textbf" or name == "mathbf" or name == "operatorname" or name == "mathit" then
          local a
          a, i = group(src, i)
          out[#out + 1] = a or ""
        elseif symbols[name] then
          out[#out + 1] = symbols[name]
        else
          out[#out + 1] = name
        end
      else
        local nxt = src:sub(i + 1, i + 1)
        if nxt ~= "\\" then
          out[#out + 1] = symbols[nxt] or nxt
        end
        i = i + 2
      end
    elseif c == "^" or c == "_" then
      local a
      a, i = group(src, i + 1)
      local r = render(a or "")
      local s = script(r, c == "^" and sup or sub)
      out[#out + 1] = s or ((c == "^" and "^" or "_") .. (#r > 1 and "(" .. r .. ")" or r))
    elseif c == "{" or c == "}" then
      i = i + 1
    elseif c == "~" or c == "&" then
      out[#out + 1] = " "
      i = i + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

function M.render(src)
  local ok, res = pcall(render, src)
  return ok and res or src
end

return M
