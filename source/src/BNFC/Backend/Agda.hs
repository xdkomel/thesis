{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Agda backend.

{-
Generate bindings to Haskell data types for use in Agda.

Example for abstract syntax generated in Haskell backend:

  newtype Id = Id String deriving (Eq, Ord, Show, Read)

  data Def = DFun Type Id [Arg] [Stm]
    deriving (Eq, Ord, Show, Read)

  data Arg = ADecl Type Id
    deriving (Eq, Ord, Show, Read)

  data Stm
      = SExp Exp
      | SInit Type Id Exp
      | SBlock [Stm]
      | SIfElse Exp Stm Stm
    deriving (Eq, Ord, Show, Read)

  data Type = Type_bool | Type_int | Type_double | Type_void
    deriving (Eq, Ord, Show, Read)

This should be accompanied by the following Agda code:

  module <mod> where

  {-# FOREIGN GHC import qualified Data.Text #-}
  {-# FOREIGN GHC import CPP.Abs #-}
  {-# FOREIGN GHC import CPP.Print #-}

  data Id : Set where
    mkId : List Char → Id

  {-# COMPILE GHC Id = data Id (Id) #-}

  data Def : Set where
    dFun : (t : Type) (x : Id) (as : List Arg) (ss : List Stm) → Def

  {-# COMPILE GHC Def = data Def (DFun) #-}

  data Arg : Set where
    aDecl : (t : Type) (x : Id) → Arg

  {-# COMPILE GHC Arg = data Arg (ADecl) #-}

  data Stm : Set where
    sExp    : (e : Exp)                     → Stm
    sInit   : (t : Type) (x : Id) (e : Exp) → Stm
    sBlock  : (ss : List Stm)               → Stm
    sIfElse : (e : Exp) (s s' : Stm)        → Stm

  {-# COMPILE GHC Stm = data Stm
    ( SExp
    | SInit
    | SBlock
    | SIfElse
    ) #-}

  data Type : Set where
    bool int double void : Type

  {-# COMPILE GHC Type = data Type
    ( Type_bool
    | Type_int
    | Type_double
    | Type_void
    ) #-}


  -- Pretty printer

  printId  : Id → String
  printId (mkId s) = String.fromList s

  postulate
    printType    : Type    → String
    printExp     : Exp     → String
    printStm     : Stm     → String
    printArg     : Arg     → String
    printDef     : Def     → String
    printProgram : Program → String

  {-# COMPILE GHC printType    = \ t -> Data.Text.pack (printTree (t :: Type)) #-}
  {-# COMPILE GHC printExp     = \ e -> Data.Text.pack (printTree (e :: Exp))  #-}
  {-# COMPILE GHC printStm     = \ s -> Data.Text.pack (printTree (s :: Stm))  #-}
  {-# COMPILE GHC printArg     = \ a -> Data.Text.pack (printTree (a :: Arg))  #-}
  {-# COMPILE GHC printDef     = \ d -> Data.Text.pack (printTree (d :: Def))  #-}
  {-# COMPILE GHC printProgram = \ p -> Data.Text.pack (printTree (p :: Program)) #-}

-}

module BNFC.Backend.Agda (makeAgda) where

import qualified Data.List as List
import Text.PrettyPrint

import BNFC.CF
-- import BNFC.Utils
import BNFC.Backend.Base           (Backend, mkfile)
import BNFC.Options                (SharedOptions)
import BNFC.Backend.Haskell.HsOpts (agdaFile, agdaFileM, absFileM, printerFileM)

-- | Entry-point for Agda backend.

makeAgda :: SharedOptions -> CF -> Backend
makeAgda opts cf = do
  mkfile (agdaFile opts) $ cf2Agda (agdaFileM opts) (absFileM opts) (printerFileM opts) cf

-- | Generate AST bindings for Agda.

cf2Agda
  :: String  -- ^ Module name.
  -> String  -- ^ Haskell Abs module name.
  -> String  -- ^ Haskell Print module name.
  -> CF      -- ^ Grammar.
  -> String
cf2Agda mod amod pmod cf = render $
  preamble
  $++$
  header mod
  $++$
  importPragmas amod pmod
  $++$
  absyn cf

-- We prefix the Agda types with "#" to not conflict with user-provided nonterminals.
arrow, listT, charT, stringT, stringFromListT :: Doc
arrow = "→"
setT            = "Set"
listT           = "#List"
charT           = "#Char"
stringT         = "#String"
stringFromListT = "#stringFromList"

-- | Hack to insert blank lines.

($++$) :: Doc -> Doc -> Doc
d $++$ d' = d $+$ "" $+$ d'

-- | Preamble: introductory comments.

preamble :: Doc
preamble = vcat $
  [ "-- Agda bindings for the Haskell abstract syntax data types."
  , "-- Generated by BNFC."
  ]

-- | Generate Agda module header.
--   We parametrized the module over the implementation List, Char, String, and stringFromList.
--
-- >>> header "AST"
-- module AST
--   (#List : Set → Set)
--   (#Char : Set)
--   (#String : Set)
--   (#stringFromList : #List #Char → #String)
--   where
--
header :: String -> Doc
header mod = vcat . concat $
  [ [ "module" <+> text mod ]
  , map (nest 2 . parens) parameters
  , [ nest 2 $ "where" ]
  ]
  where
  parameters :: [Doc]
  parameters =
    [ hsep [ listT, colon, setT, arrow, setT ]
    , hsep [ charT, colon, setT ]
    , hsep [ stringT, colon, setT ]
    , hsep [ stringFromListT, colon, listT, charT, arrow, stringT ]
    ]

-- | Import pragmas.
--
-- >>> importPragmas "Foo.Abs" "Foo.Print"
-- {-# FOREIGN GHC import qualified Data.Text #-}
-- {-# FOREIGN GHC import Foo.Abs #-}
-- {-# FOREIGN GHC import Foo.Print #-}
--
importPragmas
  :: String  -- ^ Haskell Abs module
  -> String  -- ^ Haskell Print module
  -> Doc
importPragmas amod pmod = vcat $ map imp [ "qualified Data.Text" , amod, pmod ]
  where
  imp s = hsep [ "{-#", "FOREIGN", "GHC", "import", text s, "#-}" ]

-- | Pretty-print abstract syntax definition in Agda syntax.
--
absyn :: CF -> Doc
absyn = foldr ($++$) empty . map prData . cf2data

-- | Pretty-print Agda data types and pragmas for AST.
--
-- >>> prData (Cat "Nat", [ ("zero", []), ("suc", [Cat "Nat"]) ])
-- data Nat : Set where
--   zero : Nat
--   suc : Nat → Nat
-- <BLANKLINE>
-- {-# COMPILE GHC Nat = data Nat
--   ( zero
--   | suc
--   ) #-}
--
prData :: Data -> Doc
prData (Cat d, cs) = prettyData d cs $++$ pragmaData d cs
prData (c    , _ ) = error $ "prData: unexpected category " ++ show c

-- | Pretty-print AST definition in Agda syntax.
--
-- >>> prettyData "Nat" [ ("zero", []), ("suc", [Cat "Nat"]) ]
-- data Nat : Set where
--   zero : Nat
--   suc : Nat → Nat
-- >>> let stm = Cat "Stm" in prettyData "Stm" [ ("block", [ListCat stm]), ("while", [Cat "Exp", stm]) ]
-- data Stm : Set where
--   block : #List Stm → Stm
--   while : Exp → Stm → Stm
--
prettyData :: String -> [(Fun, [Cat])] -> Doc
prettyData d cs = vcat $
  [ hsep [ "data", text d, colon, "Set", "where" ] ] ++
  map (nest 2 . prettyConstructor d) cs

-- | Generate pragmas to bind Haskell AST to Agda.
--
-- >>> pragmaData "Empty" []
-- {-# COMPILE GHC Empty = data Empty () #-}
--
-- >>> pragmaData "Nat" [ ("zero", []), ("suc", [Cat "Nat"]) ]
-- {-# COMPILE GHC Nat = data Nat
--   ( zero
--   | suc
--   ) #-}
pragmaData :: String -> [(Fun, [Cat])] -> Doc
pragmaData d = \case
  []         -> hsep $ docs ++ [ "()", "#-}" ]
  ((c,_):cs) -> vcat $ [ hsep docs ] ++ (map (nest 2) $
     [ "(" <+> prettyFun c ]
     ++ map (\(c,_) -> "|" <+> prettyFun c) cs
     ++ [ ")" <+> "#-}" ])
  where
  docs = [ "{-#", "COMPILE", "GHC", text d, equals, "data", text d ]


-- | Pretty-print since rule as Agda constructor declaration.
--
-- >>> prettyConstructor "D" ("c", [Cat "A", Cat "B", Cat "C"])
-- c : A → B → C → D
-- >>> prettyConstructor "D" ("c", [])
-- c : D
prettyConstructor :: String -> (Fun,[Cat]) -> Doc
prettyConstructor d (c, as) = hsep . concat $
  [ [ prettyFun c, colon ]
  , List.intersperse arrow $ map prettyCat $ as ++ [Cat d]
  ]

-- | Pretty-print a rule name.
prettyFun :: Fun -> Doc
prettyFun = text

-- | Pretty-print a category as Agda type.
prettyCat :: Cat -> Doc
prettyCat = \case
  Cat s        -> text s
  TokenCat s   -> text s
  CoercCat s _ -> text s
  ListCat c    -> listT <+> parensIf (compositeCat c) (prettyCat c)
  InternalCat  -> error "prettyCat: unexpected case InternalCat"

-- | Is the Agda type corresponding to 'Cat' composite (or atomic)?
compositeCat :: Cat -> Bool
compositeCat = \case
  ListCat{} -> True
  _         -> False

parensIf :: Bool -> Doc -> Doc
parensIf = \case
  True  -> parens
  False -> id