function Div(el)
  if el.classes:includes("warning") then
    return {
      pandoc.RawBlock("latex", "\\begin{mdframed}[backgroundcolor=yellow!20,linecolor=orange!80,linewidth=2pt,roundcorner=5pt]"),
      pandoc.RawBlock("latex", "\\textbf{\\large ! Note:}"),
      el,
      pandoc.RawBlock("latex", "\\end{mdframed}")
    }
  elseif el.classes:includes("note") then
    return {
      pandoc.RawBlock("latex", "\\begin{mdframed}[backgroundcolor=blue!5,linecolor=blue!60,roundcorner=5pt]"),
      pandoc.RawBlock("latex", "\\textbf{Note:}"),
      el,
      pandoc.RawBlock("latex", "\\end{mdframed}")
    }
  elseif el.classes:includes("info") then
    return {
      pandoc.RawBlock("latex", "\\begin{mdframed}[backgroundcolor=green!5,linecolor=green!60,roundcorner=5pt]"),
      pandoc.RawBlock("latex", "\\textbf{Info:}"),
      el,
      pandoc.RawBlock("latex", "\\end{mdframed}")
    }
  end
end

function Table(el)
  for _, col in ipairs(el.colspecs) do
    col.width = pandoc.ColWidthDefault
  end
  return el
end
