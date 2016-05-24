module Httpd where

import Network.Socket
import Control.Concurrent
import System.IO
import System.Timeout

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


data StopReq = StopReq { shouldStop :: Bool
                       , stopped :: MVar Bool }

run :: IO ()
run = do
  s <- socket AF_INET Stream defaultProtocol
  hostAddr <- inet_addr "127.0.0.1"
  bind s (SockAddrInet 2222 hostAddr)
  listen s 5

  putStrLn "Waiting for connections. Hit <Enter> to stop"
  mvStopReq <- newStopReq
  _ <- forkIO $ accLoop s mvStopReq
  _ <- getLine
  putStrLn "Signaling accept thread to finish"
  modifyMVar_ mvStopReq $ \(StopReq _ x) -> return $ StopReq True x
  stopReq <- readMVar mvStopReq
  _ <- takeMVar $ stopped stopReq
  putStrLn "Accept thread finished"
  close s

newStopReq :: IO (MVar StopReq)
newStopReq = do
  stopped' <- newEmptyMVar
  newMVar $ StopReq False stopped'

accLoop :: Socket -> MVar StopReq -> IO ()
accLoop s mvStopReq = do
  mr <- timeout 3000000 (accept s)
  case mr of
    Just (s', _) -> do
      putStrLn "Connection accepted"
      _ <- forkIO $ serveConn s'
      accLoop s mvStopReq
    Nothing -> do
      putStrLn "Checking if we need to stop..."
      stopReq <- readMVar mvStopReq
      if shouldStop stopReq
        then putMVar (stopped stopReq) True
        else accLoop s mvStopReq

  -- (s', _) <- accept s
  -- --putStrLn "Connection accepted"
  -- _ <- forkIO $ serveConn s'
  -- accLoop s

serveConn :: Socket -> IO ()
serveConn s = do
  _ <- send s msg
  --putStrLn $ show len ++ " bytes sent"
  close s

-- socket :: Family -> SocketType -> ProtocolNumber -> IO Socket
