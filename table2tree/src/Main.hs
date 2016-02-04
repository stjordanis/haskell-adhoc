module Main where

import System.Random
import qualified Data.Tree as T
import qualified Data.Map as M
import qualified Data.List

type Level = Int
type Name = String

-- Take 1:
treeBuilder :: (Name, Level, StdGen) -> (String, [(Name, Level, StdGen)])
treeBuilder (name, level, gen)
  | level <= 1 = (name, [])
  | otherwise = (name, zip3 (map ((name++) . (:[])) ['A'..])
                       (repeat (pred level))
                       (take len $ genFld gen'))
  where
    (len, gen') = randomR(0, 3) gen
    genFld = iterate (snd . next)

-- FIXME: Take 2 treeBuilderM should be with State monad

myTree :: T.Tree String
myTree = T.unfoldTree treeBuilder ("R", 4, mkStdGen 2)

walk :: T.Tree a -> [(a, a)]
walk t@(T.Node nme _) = (nme, nme) : walk' t []
  where
    walk' :: T.Tree a -> [(a, a)] -> [(a, a)]
    walk' (T.Node _ []) acc = acc
    walk' (T.Node name forest) acc =
      acc ++
      map (\(T.Node n _) -> (n, name)) forest ++
      (concatMap (flip walk' acc) forest)


main :: IO ()
main = putStrLn "Up and running" >>
       putStrLn (T.drawTree myTree) >>
       putStrLn "Finished"

shuffle :: StdGen -> [a] -> [a]
shuffle _ [] = []
shuffle g xs = elemDrawn : shuffle g' (xs' ++ ys')
  where
    (xs', elemDrawn : ys') = splitAt rndIndex xs
    (rndIndex, g') = randomR (0, pred $ length xs) g

shuffle2 :: StdGen -> [a] -> [a]
shuffle2 g = (shuffle2' g) . toMap
  where
    toMap = M.fromList . (zip [0 :: Int ..])
    shuffle2' g' m
      | M.null m = []
      | otherwise = snd elemDrawn : shuffle2' g'' m'
      where
        (index, g'') = randomR (0, pred $ M.size m) g'
        elemDrawn = M.elemAt index m
        m' = M.deleteAt index m


myTable :: [(String, String)]
myTable = shuffle (mkStdGen 1) $ walk myTree

myMap :: M.Map String [String]
myMap = foldl (\m (e, parent) -> M.alter (f e) parent m
                ) M.empty myTable
  where
    f e' (Just es) = Just $ e' : es
    f e' Nothing =  Just $ [e']


checkShuffle :: StdGen -> [Int] -> Bool
checkShuffle _ [] = True
checkShuffle g xs = (var / fromIntegral avg) < (0.05 :: Double)
  where
    n = 10000
    gens = take n $ iterate (snd . next) g
    xxs = map (flip shuffle2 xs) gens
    sums = map sum $ Data.List.transpose xxs
    avg = sum sums `quot` length sums
    diffs = map (subtract avg) sums
    sumsRo2 = sum $ map (^(2 :: Int)) diffs
    var = sqrt $ fromIntegral $ sumsRo2 `quot` length sums
