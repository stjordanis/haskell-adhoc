module Main where

import Data.Graph
import Data.List
import Data.CSV
import Data.Tuple
import Data.Tuple.Extra ((&&&))
import Data.Bifunctor
import System.Exit
import Data.Ord

import Text.ParserCombinators.Parsec
import qualified Data.Map as M
import qualified Data.Set as S

type SecId = String
type BenchSecId = SecId
type SecRel = (SecId, BenchSecId)
type ErrorMsg = String
type WarnMsg = String
type RowNum = Int

secIdToIntMap :: [SecId] -> M.Map SecId Int
secIdToIntMap xs = M.fromList $ zip (sort xs) [1..]

invMap :: Ord b => M.Map a b -> M.Map b a
invMap m = M.fromList $ lst
  where
    lst = map swap $ M.toList m

readCsvFile :: FilePath -> IO (Either ParseError [[String]])
readCsvFile fileName = parseFromFile csvFile fileName

csvRecsToSecRels :: [[String]] -> Either ErrorMsg [SecRel]
csvRecsToSecRels xxs = undefined

readSecRels :: FilePath -> HasHeader -> IO (Either ErrorMsg [(RowNum, SecRel)])
readSecRels fileName hasHeader = do
  csv <- parseFromFile csvFile fileName
  return $ verifyStructure csv hasHeader
    where
      verifyStructure (Left parseError) _ = Left $ show parseError
      verifyStructure (Right rows) NoHeader =
        sequence $ map verifyRow $ zip [1..] rows
      verifyStructure (Right rows) SkipHeader =
        sequence $ map verifyRow $ safeTail $ zip [1..] rows

      verifyRow (rowNum, cells) =
        case (safeHead &&& safeHead . drop 16) cells of
          (Just secId, Just benchSecId) -> Right $ (rowNum, (secId, benchSecId))
          (Nothing, _) ->
            Left $ "Error in row " ++ show rowNum ++ ": no first column"
          (_, Nothing) ->
            Left $ "Error in row " ++ show rowNum ++ ": no 17-th column"

      safeTail [] = []
      safeTail xs = tail xs

      safeHead [] = Nothing
      safeHead (x: _) = Just x

checkSecRels :: [(RowNum, SecRel)] -> Either ErrorMsg ([SecRel], [WarnMsg])
checkSecRels xs = checkUniqueKeys (xs, []) >>=
                  undefined --           checkCompletness
  where
    checkUniqueKeys (xs', ws)
      | null nonUniqueSecIds = Right (map snd xs', ws)
      | otherwise = Left $ foldl (\acc [rowNumAndSecId] ->
                                   undefined) "" nonUniqueSecIds
      where
        nonUniqueSecIds = map () $ filter ((>1) . length) groupedSecIds
        groupedSecIds :: M.Map SecId [RowNum]
        groupedSecIds = foldl () M.empty $
                        map (fst . snd &&& fst) xs'
    checkCompletness (xs', ws)
      | S.null setDiff = Right (xs', ws)
      | otherwise =
        Right (foldl (\(xs'', ws'') sr'@(s, bs) ->
                       if S.notMember bs setDiff
                       then (xs'' ++ [sr'], ws'')
                       else (xs'' ++ [(s, "")],
                             ws'' ++ ["Discarded incorrect ref [" ++ bs ++ "] in [" ++ s ++ "]"]))
               ([], ws) xs')
      where
        setDiff =
          (S.fromList $ filter (/="") benchSecIds) S.\\ S.fromList secIds
    secIds = map fst xs
    benchSecIds = map snd xs


buildGraph :: [(Int, Maybe Int)] -> Maybe Graph
buildGraph [] = Nothing
buildGraph srInt = Just $ buildG bounds edges'
  where
    bounds = (foldl1 min sInt, foldl1 max sInt)
    sInt = map fst srInt
    edges' = foldl (\acc (s, mbs) -> case mbs of
                     Just bs -> acc ++ [(bs, s)]
                     Nothing -> acc)
            [] srInt


data HasHeader = NoHeader | SkipHeader

main :: IO ()
main = do
  putStrLn "Up and running"

  errorOrSecRels <- readSecRels "test.csv" SkipHeader
  case errorOrSecRels of
    Left e -> do
      putStrLn $ "CSV parse error: " ++ show e
      exitWith $ ExitFailure 1
    Right secRels -> do
      case checkSecRels secRels of
        Left e' -> do
          putStrLn $ "Invalid security structure: " ++ e'
          exitWith $ ExitFailure 2
        Right (sr, warns) -> do
          mapM_ putStrLn $ ["Security structure warnings:"] ++ warns
          putStrLn ("sr has length of " ++ show (length sr))
          let s2IntMap = secIdToIntMap $ map fst sr
              srInt = map (bimap (s2IntMap M.!) (flip M.lookup s2IntMap)) sr

            --  dff = (S.fromList (map snd sr)) S.\\ (S.fromList (map fst sr))
              mg = buildGraph srInt
          case mg of
            Just g -> do
              putStrLn $ "Graph is: " ++ show (outdegree g)

            Nothing -> putStrLn "Graph construction impossible"
          --mapM_ (putStrLn . show) dff
          exitSuccess