module LowerRegisters
  ( registerTypeIntroductions
  , registerExternGlobals
  , registerExprIntroductions
  , registerDiscardedExprIntroductions
  , registerFieldIntroductions
  ) where

import Base
import TypesAst
import CompileM

registerExternGlobals :: [(CType, String)] -> CompileM ()
registerExternGlobals = mapM_ $ \(ty, name) -> do
    registerTypeIntroductions ty
    bindGlobal name ty

registerFieldIntroductions :: [Field] -> CompileM ()
registerFieldIntroductions = registerFieldIntroductionsIn False

registerFieldIntroductionsIn :: Bool -> [Field] -> CompileM ()
registerFieldIntroductionsIn unevaluated = mapM_ $ \(Field ty _) -> registerTypeIntroductionsIn unevaluated ty

registerTypeIntroductions :: CType -> CompileM ()
registerTypeIntroductions = registerTypeIntroductionsIn False

registerTypeIntroductionsIn :: Bool -> CType -> CompileM ()
registerTypeIntroductionsIn unevaluated ty = case ty of
  CPtr inner -> registerTypeIntroductionsIn unevaluated inner
  CArray inner bound -> do
    registerTypeIntroductionsIn unevaluated inner
    maybe (pure ()) (registerExprIntroductionsIn unevaluated) bound
  CFunc ret params -> do
    registerTypeIntroductionsIn unevaluated ret
    mapM_ (registerTypeIntroductionsIn unevaluated) params
  CStructNamed name fields -> do
    registerFieldIntroductionsIn unevaluated fields
    bindStruct name False fields
  CUnionNamed name fields -> do
    registerFieldIntroductionsIn unevaluated fields
    bindStruct name True fields
  CStructDef fields ->
    registerFieldIntroductionsIn unevaluated fields
  CUnionDef fields ->
    registerFieldIntroductionsIn unevaluated fields
  _ -> pure ()

-- Type queries may skip operands whose types do not affect the result. Preserve
-- their syntactic introductions without evaluating them. Resolve calls here at
-- sizeof boundaries and in discarded bootstrap diagnostic arguments; evaluated
-- expressions register types at each cast and sizeof node, not ahead of lowering.
registerExprIntroductions :: Expr -> CompileM ()
registerExprIntroductions = registerExprIntroductionsIn False

-- Bootstrap diagnostics discard values, not the declarations implied by calls.
registerDiscardedExprIntroductions :: Expr -> CompileM ()
registerDiscardedExprIntroductions = registerExprIntroductionsIn True

registerExprIntroductionsIn :: Bool -> Expr -> CompileM ()
registerExprIntroductionsIn unevaluated expr =
  let registerExpr = registerExprIntroductionsIn unevaluated
      registerType = registerTypeIntroductionsIn unevaluated
  in case expr of
    ECall callee args -> do
      case (unevaluated, callee) of
        (True, EVar name) -> resolveCallee name >> pure ()
        _ -> registerExpr callee
      mapM_ registerExpr args
    EIndex base index -> registerExpr base >> registerExpr index
    EMember base _ -> registerExpr base
    EPtrMember base _ -> registerExpr base
    EUnary _ value -> registerExpr value
    ESizeofExpr value -> registerExprIntroductionsIn True value
    ESizeofType ty -> registerTypeIntroductionsIn True ty
    ECast ty value -> registerType ty >> registerExpr value
    EPostfix _ value -> registerExpr value
    EBinary _ left right -> registerExpr left >> registerExpr right
    ECond cond yes no -> do
      registerExpr cond
      registerExpr yes
      registerExpr no
    EAssign left right -> registerExpr left >> registerExpr right
    ECompoundAssign _ left right -> registerExpr left >> registerExpr right
    EInitList values -> mapM_ registerExpr values
    _ -> pure ()
