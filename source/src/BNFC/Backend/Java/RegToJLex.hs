module BNFC.Backend.Java.RegToJLex (printRegJLex, escapeChar) where

-- modified from pretty-printer generated by the BNF converter

import AbsBNF
import Data.Char

-- the top-level printing method
printRegJLex :: Reg -> String
printRegJLex = render . prt 0

-- you may want to change render and parenth

render :: [String] -> String
render = rend (0 :: Int) where
  rend i ss = case ss of
    "["      :ts -> cons "["  $ rend i ts
    "("      :ts -> cons "("  $ rend i ts
    t  : "," :ts -> cons t    $ space "," $ rend i ts
    t  : ")" :ts -> cons t    $ cons ")"  $ rend i ts
    t  : "]" :ts -> cons t    $ cons "]"  $ rend i ts
    t        :ts -> space t   $ rend i ts
    _            -> ""
  cons s t  = s ++ t
  new i s   = s
  space t s = if null s then t else t ++ s

parenth :: [String] -> [String]
parenth ss = ["("] ++ ss ++ [")"]

-- the printer class does the job
class Print a where
  prt :: Int -> a -> [String]
  prtList :: [a] -> [String]
  prtList = concat . map (prt 0)

instance Print a => Print [a] where
  prt _ = prtList

instance Print Char where
  prt _ c = [escapeChar c]
  prtList s = map (concat . prt 0) s

escapeChar :: Char -> String
escapeChar '^' = "\\x5E" -- special case, since \^ is a control character escape
escapeChar x | x `elem` jlexReserved = '\\' : [x]
escapeChar x = [x]

-- Characters that must be escaped in JLex regular expressions
jlexReserved :: [Char]
jlexReserved = ['?', '*', '+', '|', '(', ')', '^', '$', '.', '[', ']', '{', '}', '"', '\\']

prPrec :: Int -> Int -> [String] -> [String]
prPrec i j = if j<i then parenth else id

instance Print Ident where
  prt _ (Ident i) = [i]

instance Print Reg where
  prt i e = case e of
   RSeq reg0 reg -> prPrec i 2 (concat [prt 2 reg0 , prt 3 reg])
   RAlt reg0 reg -> prPrec i 1 (concat [prt 1 reg0 , ["|"] , prt 2 reg])

   -- JLex does not support set difference
   --RMinus reg0 reg -> prPrec i 1 (concat [prt 2 reg0 , ["#"] , prt 2 reg])
   RMinus reg0 REps -> prt i reg0 -- REps is identity for set difference
   RMinus RAny reg@(RChar _) ->  prPrec i 3 (concat [["[^"],prt 0 reg,["]"]])
   RMinus RAny (RAlts str) ->  prPrec i 3 (concat [["[^"],prt 0 str,["]"]])
   -- FIXME: maybe we could add cases for char - RDigit, RLetter etc.
   RMinus reg0 reg -> error $ "JLex does not support general set difference"

   RStar reg -> prPrec i 3 (concat [prt 3 reg , ["*"]])
   RPlus reg -> prPrec i 3 (concat [prt 3 reg , ["+"]])
   ROpt reg  -> prPrec i 3 (concat [prt 3 reg , ["?"]])
   REps  -> prPrec i 3 (["[^.]"])
   RChar c -> prPrec i 3 (concat [prt 0 c])
   RAlts str -> prPrec i 3 (concat [["["],prt 0 str,["]"]])
   RSeqs str -> prPrec i 2 (concat (map (prt 0) str))
   RDigit  -> prPrec i 3 (concat [["{DIGIT}"]])
   RLetter  -> prPrec i 3 (concat [["{LETTER}"]])
   RUpper  -> prPrec i 3 (concat [["{CAPITAL}"]])
   RLower  -> prPrec i 3 (concat [["{SMALL}"]])
   RAny  -> prPrec i 3 (concat [["."]])


