module ParseLite
  ( Consumed(..)
  , Reply(..)
  , P(..)
  , forceConsumed
  , parseRest
  , parseRestWithEnv
  , pEnv
  , pSetEnv
  , pLocalEnv
  , pRaw
  , pFail
  , pPeekMaybe
  , pTake
  , pSkip
  , pTry
  , pOptional
  , pMany
  , pManyUntil
  ) where

import Base

data Consumed a = Consumed a | Unconsumed a

data Reply env tok err a
  = Ok a env [tok]
  | Error err

data P env tok err a = P { runP :: env -> [tok] -> Consumed (Reply env tok err a) }

instance Functor (P env tok err) where
  fmap f p = P $ \env toks -> mapConsumed (runP p env toks)
    where
      mapConsumed consumed = case consumed of
        Unconsumed x -> Unconsumed (mapReply x)
        Consumed x -> Consumed (mapReply x)

      mapReply reply = case reply of
        Ok x env' rest -> Ok (f x) env' rest
        Error err -> Error err

instance Applicative (P env tok err) where
  pure x = P $ \env toks -> Unconsumed (Ok x env toks)
  pf <*> px = do
    f <- pf
    x <- px
    pure (f x)

instance Monad (P env tok err) where
  return = pure
  p >>= f = P $ \env toks -> case runP p env toks of
    Unconsumed reply -> case reply of
      Error err -> Unconsumed (Error err)
      Ok x env' rest -> runP (f x) env' rest
    Consumed reply -> Consumed (case reply of
      Error err -> Error err
      Ok x env' rest -> forceConsumed (runP (f x) env' rest))

forceConsumed :: Consumed a -> a
forceConsumed consumed = case consumed of
  Unconsumed x -> x
  Consumed x -> x

parseRest :: P env tok err a -> env -> [tok] -> Either err (a, [tok])
parseRest p env toks = case forceConsumed (runP p env toks) of
  Error err -> Left err
  Ok x _ rest -> Right (x, rest)

parseRestWithEnv :: P env tok err a -> env -> [tok] -> Either err (a, env, [tok])
parseRestWithEnv p env toks = case forceConsumed (runP p env toks) of
  Error err -> Left err
  Ok x env' rest -> Right (x, env', rest)

pEnv :: P env tok err env
pEnv = P $ \env toks -> Unconsumed (Ok env env toks)

pSetEnv :: env -> P env tok err ()
pSetEnv env = P $ \_ toks -> Unconsumed (Ok () env toks)

pLocalEnv :: (env -> env) -> (env -> env -> env) -> P env tok err a -> P env tok err a
pLocalEnv enter leave action = P $ \env toks ->
  let leaveReply reply = case reply of
        Error err -> Error err
        Ok x env' rest -> Ok x (leave env env') rest
  in
  case runP action (enter env) toks of
    Unconsumed reply -> Unconsumed (leaveReply reply)
    Consumed reply -> Consumed (leaveReply reply)

pRaw :: (env -> [tok] -> Consumed (Reply env tok err a)) -> P env tok err a
pRaw action = P action

pFail :: err -> P env tok err a
pFail err = P $ \_env _toks -> Unconsumed (Error err)

pPeekMaybe :: P env tok err (Maybe tok)
pPeekMaybe = P $ \env toks -> Unconsumed (Ok (case toks of { [] -> Nothing; tok:_ -> Just tok }) env toks)

pTake :: err -> P env tok err tok
pTake eofErr = P $ \_env toks -> case toks of
  [] -> Unconsumed (Error eofErr)
  tok:rest -> Consumed (Ok tok _env rest)

pSkip :: err -> P env tok err ()
pSkip eofErr = P $ \_env toks -> case toks of
  [] -> Unconsumed (Error eofErr)
  _tok:rest -> Consumed (Ok () _env rest)

pTry :: P env tok err a -> P env tok err a
pTry p = P $ \env toks -> case runP p env toks of
  Consumed (Error err) -> Unconsumed (Error err)
  other -> other

pOptional :: P env tok err a -> P env tok err (Maybe a)
pOptional p = P $ \env toks -> case runP p env toks of
  Unconsumed (Error _) -> Unconsumed (Ok Nothing env toks)
  Unconsumed (Ok x env' rest) -> Unconsumed (Ok (Just x) env' rest)
  Consumed (Ok x env' rest) -> Consumed (Ok (Just x) env' rest)
  Consumed (Error err) -> Consumed (Error err)

pMany :: P env tok err a -> P env tok err [a]
pMany p = go id where
  go acc = do
    mx <- pOptional p
    case mx of
      Nothing -> pure (acc [])
      Just x -> go (acc . (x:))

pManyUntil :: P env tok err Bool -> P env tok err a -> P env tok err [a]
pManyUntil done item = do
  stop <- done
  if stop
    then pure []
    else do
      x <- item
      xs <- pManyUntil done item
      pure (x:xs)
