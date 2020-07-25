{-# LANGUAGE DataKinds, ExistentialQuantification, GADTs, KindSignatures #-}
module Parser (parseCards) where
  
import qualified Data.List.NonEmpty as NE
import Text.Parsec
import Types

uncurry3 f (a, b, c) = f a b c

parseCards :: String -> Either ParseError [Card]
parseCards = parse pCards "failed when parsing cards"

pCards = pCard `sepEndBy1` seperator
pCard =  uncurry3 MultipleChoice<$> try pMultChoice
     <|> uncurry MultipleAnswer <$> try pMultAnswer
     <|> uncurry Reorder <$> try pReorder
     <|> uncurry OpenQuestion <$> try pOpen
     <|> uncurry Definition <$> pDef

pHeader = do
  many eol
  char '#'
  spaces
  many notEOL

pMultChoice = do
  header <- pHeader
  many eol
  choices <- pChoice `sepBy1` lookAhead (try choicePrefix)
  let (correct, incorrects) = makeMultipleChoice choices
  return (header, correct, incorrects)

pChoice = do
  kind <- oneOf "*-"
  space
  text <- manyTill anyChar $ lookAhead (try (try choicePrefix <|> seperator <|> eof'))
  return (kind, text)

choicePrefix =  string "- "
            <|> string "* "

pMultAnswer = do
  header <- pHeader
  many eol
  options <- pOption `sepBy1` lookAhead (try (char '['))
  return (header, NE.fromList options)

pOption = do
  char '['
  kind <- oneOf "*x "
  string "] "
  text <- manyTill anyChar $ lookAhead (try (seperator <|> string "[" <|> eof'))
  return $ makeOption kind text

pReorder = do
  header <- pHeader
  many eol
  elements <- pReorderElement `sepBy1` lookAhead (try pReorderPrefix)
  let numbers = map fst elements
  if all (`elem` numbers) [1..length numbers]
    then return (header, NE.fromList elements)
    else error $ "A reordering question should have numbers starting from 1 and increase from there without skipping any numbers, but this is not the case:\n" 
                    <> unlines (map show numbers)

pReorderElement = do
  int <- pReorderPrefix
  text <- manyTill anyChar $ lookAhead (try (try seperator <|> try pReorderPrefix <|> eof'))
  return (read int, text)

pReorderPrefix = do
  int <- many1 digit
  string ". "
  return int

pOpen = do
  header <- pHeader
  many eol
  (pre, gap) <- pGap
  sentence <- pSentence

  return (header, P pre gap sentence)

pSentence =  try pPerforated
         <|> pNormal
  
pPerforated = do
  (pre, gap) <- pGap
  Perforated pre gap <$> pSentence 

chars = escaped <|> anyChar
escaped = char '\\' >> char '_'

pGap = do
  pre <- manyTill chars $ lookAhead (try gappedSpecialChars)
  char '_'
  gaps <- manyTill (noneOf "_|") (lookAhead (try gappedSpecialChars)) `sepBy1` string "|"
  char '_'
  return (pre, NE.fromList gaps)

gappedSpecialChars =  seperator
                  <|> string "|"
                  <|> string "_"

pNormal = do
  text <- manyTill (noneOf "_") $ lookAhead $ try $ gappedSpecialChars <|> eof'
  return (Normal text)

pDef = do
  header <- pHeader
  many eol
  descr <- manyTill chars $ lookAhead $ try $ seperator <|> eof'
  return (header, descr)

eol =  try (string "\n\r")
    <|> try (string "\r\n")
    <|> string "\n"
    <|> string "\r"
    <?> "end of line"

eof' = eof >> return [] <?> "end of file"

seperator = do
  sep <- string "---"
  many eol
  return sep

notEOL = noneOf "\n\r"

makeMultipleChoice :: [(Char, String)] -> (CorrectOption, [IncorrectOption])
makeMultipleChoice options = makeMultipleChoice' [] [] 0 options
  where
    makeMultipleChoice' [] _ _ [] = error ("multiple choice had no correct answer: \n" ++ show options)
    makeMultipleChoice' [c] ics _ [] = (c, reverse ics)
    makeMultipleChoice' _ _ _ [] = error ("multiple choice had multiple correct answers: \n" ++ show options)
    makeMultipleChoice' cs ics i (('-', text) : opts) = makeMultipleChoice' cs (IncorrectOption text : ics) (i+1) opts
    makeMultipleChoice' cs ics i (('*', text) : opts) = makeMultipleChoice' (CorrectOption i text : cs) ics (i+1) opts
    makeMultipleChoice' _  _   _ _ = error "impossible"

makeOption :: Char -> String -> Option
makeOption kind text
  | kind `elem` "*x" = Option Correct text
  | otherwise        = Option Incorrect text