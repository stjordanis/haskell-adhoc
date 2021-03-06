{-# LANGUAGE OverloadedStrings #-}
module Httpd where

import Network.Socket hiding (send, recv)
import Network.Socket.ByteString (send, recv)
import Control.Concurrent
import System.IO
import System.Timeout
import Control.Monad
import Control.Exception
import Data.Char (toUpper)
import Data.ByteString.Char8 (pack, unpack)

msg :: String
msg = "HTTP/1.0 200 OK\r\nContent-Length: 5\r\n\r\nPong!\r\n"

wt :: Int
wt = 1

data MyData = MD1 { _id :: Int
                  , _name :: String
                  }
            | MD2 { _time :: Integer }
            deriving (Show, Read)

initMD :: [MyData]
initMD = [ MD1 13 "years"
         , MD1 997 "Police"
         , MD2 1234
         ]

myRead :: IO ()
myRead = do
  h <- openFile "input.txt" ReadMode
  cnt <- rd (0 :: Int) h
  putStrLn $ "Lines " ++ show cnt
  hClose h
  return ()
    where
      rd i h' = do
        eof <- hIsEOF h'
        if eof
          then return i
          else do
            line <- hGetLine h'
            rd (i + length (read line :: [MyData])) h'


run :: IO ()
run = do
  s <- socket AF_INET Stream defaultProtocol
  setSocketOption s ReuseAddr 1
  hostAddr <- inet_addr "127.0.0.1"
  bind s (SockAddrInet 2222 hostAddr)
  listen s 5

  putStrLn "Waiting for connections. Hit <Enter> to stop"
  stopInfo <- makeStopInfo
  _ <- forkIO $ accLoop s stopInfo
  _ <- getLine
  putStrLn "Signaling accept thread to finish"
  putMVar (stopReq stopInfo) ()
  mapM_ takeMVar [finished stopInfo]
  putStrLn "Accept thread finished"
  close s

data StopInfo = SI { stopReq :: MVar ()
                   , finished :: MVar () }

makeStopInfo :: IO StopInfo
makeStopInfo = do
  mvStopReq <- newEmptyMVar
  mvStopped <- newEmptyMVar
  return $ SI mvStopReq mvStopped

accLoop :: Socket -> StopInfo -> IO ()
accLoop s' stopInfo' = accLoop' s' [] stopInfo'
  where
    accLoop' s connsComm stopInfo = do
      mr <- timeout 1000000 (accept s) -- FIXME: can accept throw an exception?
      case mr of
        Just (s'', _) -> do
          putStrLn "Connection accepted"
          thrStopInfo <- makeStopInfo
          _ <- forkIO $ serveConn s'' thrStopInfo
          accLoop' s (thrStopInfo : connsComm) stopInfo
        Nothing ->
          tryTakeMVar (stopReq stopInfo) >>= stopOrLoop
          where
            stopOrLoop Nothing = do
              connsComm' <- filterM (isEmptyMVar . finished) connsComm
              if (length connsComm' /= length connsComm)
                then putStrLn $ "Dropped " ++
                     show (length connsComm - length connsComm') ++
                     " connections"
                else return ()
              accLoop' s connsComm' stopInfo
            stopOrLoop (Just _) =
              stopAllConns >>
              putMVar (finished stopInfo) ()

            stopAllConns =
              putStrLn ("Stopping " ++ (show $ length connsComm) ++
                        " connections") >>
              mapM_ (flip putMVar () . stopReq) connsComm >>
              mapM_ (takeMVar . finished) connsComm


type Code = Int

data ConnState = ConnClose String
               | ConnLoop
               | ConnMsg (Code, String)
               deriving Show



-- FIXME: reading until newline?
serveConn :: Socket -> StopInfo -> IO ()
serveConn s (SI mvStopReq mvFinished) = do
  _ <- try' (send s "100: HELLO\n")
  loop
    where
      loop = read' >>= shouldTerminate >>= process >>= loopOrStop

      read' = try' (timeout 1000000 $ fmap unpack $ recv s 1024)

      shouldTerminate (Left _) = return $ Left "Other party closed connection"
      shouldTerminate (Right x) = do
       stopReq' <- tryTakeMVar mvStopReq
       case stopReq' of
         Just _ -> return $ Left "Thread termination request received"
         Nothing -> return $ Right x

      process (Left x) = return $ ConnClose x
      process (Right (Just msg')) = return $ processMsg $ map toUpper msg'
      process (Right Nothing) = return ConnLoop

      loopOrStop (ConnMsg (code, msg')) =
        try' (send s (pack (show code ++ ": " ++ msg' ++ "\r\n"))) >>
        loop
      loopOrStop ConnLoop = loop
      loopOrStop (ConnClose errMsg) = putStrLn errMsg >>
                                 try' (shutdown s ShutdownBoth) >>
                                 close s >>
                                 putMVar mvFinished ()


processMsg :: String -> ConnState
processMsg = dispatch . sanitize
  where
    sanitize input = case reverse input of
      ('\n' : '\r' : xs) -> reverse xs
      _ -> input
    dispatch "CLOSE" = ConnClose "Close command received, closing channel"
    dispatch cmd = ConnMsg (500, "Unknown command received [" ++ cmd ++ "]")


try' :: IO a -> IO (Either SomeException a)
try' op = do
  res <- try op
  case res of
    Left e -> do
      putStrLn $ "***Exception encountered: " ++ show e
      return $ Left e
    _ -> return res
