{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Erbic.In.SockService.SockMsgService2 where


import Control.Concurrent hiding (writeChan)
import Control.Exception
import Network.Socket
import qualified Data.Map.Strict as M
import GHC.IO.Exception
import Erbic.IO.Fork

import Control.Concurrent.BoundedChan
import Data.List (intercalate)
import Erbic.Data.Msg.ScanMsg


data SSData a = SSData { name :: String
                       , logger :: BoundedChan String
                       , svcData :: Maybe (ThreadId, MVar ())
                       , connData :: MVar (M.Map ThreadId (MVar ())) }

type ErrMsg = String

data ReadRes = RRData String
             | RRClosed
             | RRError (Maybe Int) ErrMsg
             deriving Show

-- FIXME: how to incorporate logging facility?

class Show s => Service s where
  ssOpen :: IO s
  ssClose :: s -> IO ()
  ssAccept :: s -> IO (s, String)
  ssRead :: s -> Int -> IO ReadRes

  newSS :: HostName -> Int -> BoundedChan String -> IO (SSData s)
  newSS _ _ ch = do
    mvConnData <- newMVar M.empty
    return $ SSData "SockSrvName" ch Nothing mvConnData


  startSS :: SSData s -> IO (SSData s)
  startSS ssd =
    bracketOnError (ssOpen :: IO s) (ssClose) $ \s ->
      bracketOnError (tfork $ ssSocketAccLoop s $ connData ssd)
                     (stopThread 0) $
                     \(tid, mv) -> return $ ssd { svcData = Just (tid, mv) }


  stopSS :: Int -> SSData s -> IO ()
  stopSS t ssd =
    mask_ $ case svcData ssd of
      Just (tid, mv) -> do
        writeChan (logger ssd) $
                  "Stopping service " ++ name ssd ++ " " ++ show tid
        stopThread t (tid, mv)
        writeChan (logger ssd) $
                  "Service thread " ++ show tid ++ " stopped"
        tidsMvsMap <- readMVar $ connData ssd
        writeChan (logger ssd) $
                  "Now stopping connections: " ++ (show $ M.keys tidsMvsMap)
        stopThreadPool t $ connData ssd
        writeChan (logger ssd) $ "All connections stopped"
      Nothing -> return ()


  isSSRunning :: SSData s -> IO Bool
  isSSRunning ssd = case svcData ssd of
    Just (_, mv) -> tryReadMVar mv >>= \case
      Just _ -> return False
      Nothing -> return True
    Nothing -> return False


  ssSocketAccLoop :: s -> MVar (M.Map ThreadId (MVar ())) -> IO ()
  ssSocketAccLoop s mvTids = do
    bracketOnError (ssAccept s) (ssClose . fst) $
       \(s', sa') -> mask_ $ do _ <- tpfork (ssServeConnection s' sa') mvTids
                                return ()
    ssSocketAccLoop s mvTids


  -- FIXME: implement this with orchestration msgs etc...
  ssServeConnection :: s -> String -> IO ()
  ssServeConnection s sa = do
    finally (do tid <- myThreadId
                putStrLn $ "New connection from " ++ show sa ++
                           " on " ++ show s ++
                           " served in " ++ show tid
                doMsgReception s)
            (do ssClose s
                tid <- myThreadId
                putStrLn $ "Closed connection on " ++ show s ++
                           " in " ++ show tid)

-- FIXME: should inform on result (if connection is closed/broken)
doMsgReception :: (Service ss) => ss -> IO ()
doMsgReception s =
  orchRec $ mkScanData "" PPIn
  where
    orchRec sd' = do
      str <- ssRead s 16
      case str of
        RRData data' -> do let (msgs, sd'') = runScan (filter nonCRLF data') sd'
                           putStrLn $ "Read: [" ++ intercalate "|" msgs ++ "]"
                           orchRec sd''
        RRClosed -> putStrLn "Connection closed"
        RRError _ errMsg -> putStrLn $ "Error on connection: " ++ errMsg
    nonCRLF x = x /= '\n' && x /= '\r'


-------------------------------------------------------------------------------
--                                Instances
-------------------------------------------------------------------------------

instance Service Socket where
  ssOpen =
      bracketOnError
        (socket AF_INET Stream defaultProtocol)
        (\s -> do close s
                  putStrLn $ "openSock: Socket closed " ++ show s)
        (\s -> do
            setSocketOption s ReuseAddr 1
            hostAddr <- inet_addr "127.0.0.1"
            putStrLn $ "Acquired socket " ++ show s
            bind s (SockAddrInet 2222 hostAddr)
            listen s 5
            threadDelay $ 1 * 1000 * 1000
            return s)
  ssClose s = close s
  ssAccept s = do (s', sa') <- accept s
                  return (s', show sa')

  ssRead s len = (RRData <$> recv s len) `catch` handler
    where
      handler :: IOException -> IO ReadRes
      handler e = case ioe_type e of
        EOF -> return RRClosed
        _ -> return $ RRError (fromInteger . toInteger <$> ioe_errno e) $ show e