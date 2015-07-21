{-# LANGUAGE ImpredicativeTypes #-}

-- | This module provides a server process (implemented using eprocess) that can receive and run actions in the Interpreter monad.
module Language.Haskell.Interpreter.Server (
-- * Types
        ServerHandle,
-- * Functions
        start, stop, runIn, asyncRunIn, flush
    ) where

import Control.Concurrent.MVar
import Control.Monad.Except
import Control.Monad.Loops
import Control.Monad.Catch (catch)
import Control.Concurrent.Process
import Language.Haskell.Interpreter

-- | The server handle.  It's returned on process creation and should be used
-- afterwards to send messages to it
newtype ServerHandle = SH {handle :: Handle (InterpreterT IO ())}

instance MonadInterpreter m => MonadInterpreter (ReceiverT r m) where
    fromSession = lift . fromSession
    modifySessionRef a = lift . (modifySessionRef a)
    runGhc = lift . runGhc

-- | Starts the server. Usage:
-- @
--      handle <- start
-- @
start :: IO ServerHandle
start = (spawn $ makeProcess runInterpreter interpreter) >>= return . SH
    where interpreter =
            do
                setImports ["Prelude"]
                forever $ recv >>= lift

-- | Asynchronically runs an action and returns the /MVar/ that will be filled
-- with the result when it's there. Usage:
-- @
--      mvar <- asyncRunIn serverhandle action
-- @
asyncRunIn :: ServerHandle              -- ^ The handle of the server that will run the action
            -> InterpreterT IO a        -- ^ The action to be run
            -> IO (MVar (Either InterpreterError a))
asyncRunIn server action = do
                                resVar <- liftIO newEmptyMVar
                                sendTo (handle server) $ try action >>= liftIO . putMVar resVar
                                return resVar

-- | Runs the action. Usage:
-- @
--      result <- runIn serverhandle action
-- @
runIn :: ServerHandle       -- ^ The handle of the server that will run the action
       -> InterpreterT IO a -- ^ The action to be run
       -> IO (Either InterpreterError a)
runIn server action = runHere $ do
                                    me <- self
                                    sendTo (handle server) $ try action >>= sendTo me
                                    recv

-- | Runs all the pending actions (those that where run using 'asyncRunIn'. Usage:
-- @
--      flush serverhandle
-- @
flush :: ServerHandle                    -- ^ The handle of the server that will run the action
      -> IO (Either InterpreterError ()) -- ^ The meaningful results are stored in the corresponding mvars
flush server = runIn server $ return ()

try :: InterpreterT IO b -> InterpreterT IO (Either InterpreterError b)
try a = (a >>= return . Right) `catch` (return . Left)

-- | Stops the server. Usage:
-- @
--      stop serverhandle
-- @
stop :: ServerHandle -> IO ()
stop = kill . handle
