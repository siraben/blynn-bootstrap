module LowerImplicit where

import Base
import Ast
import CompileM
import LowerBuiltins
import LowerCommon

registerImplicitCalls :: [String] -> [Stmt] -> CompileM ()
registerImplicitCalls locals stmts = case stmts of
  [] -> pure ()
  stmt:rest -> do
    locals' <- registerImplicitCallsStmt locals stmt
    registerImplicitCalls locals' rest

registerImplicitCallsStmt :: [String] -> Stmt -> CompileM [String]
registerImplicitCallsStmt locals stmt = case stmt of
  SDecl _ name initExpr -> do
    maybeRegisterImplicitCallsExpr locals initExpr
    pure (name:locals)
  SDecls decls ->
    registerImplicitCallsDecls locals decls
  SReturn expr -> maybeRegisterImplicitCallsExpr locals expr >> pure locals
  SExpr expr -> registerImplicitCallsExpr locals expr >> pure locals
  SIf cond yes no -> do
    registerImplicitCallsExpr locals cond
    registerImplicitCalls locals yes
    registerImplicitCalls locals no
    pure locals
  SWhile cond body -> do
    registerImplicitCallsExpr locals cond
    registerImplicitCalls locals body
    pure locals
  SDoWhile body cond -> do
    registerImplicitCalls locals body
    registerImplicitCallsExpr locals cond
    pure locals
  SFor initExpr condExpr stepExpr body -> do
    maybeRegisterImplicitCallsExpr locals initExpr
    maybeRegisterImplicitCallsExpr locals condExpr
    maybeRegisterImplicitCallsExpr locals stepExpr
    registerImplicitCalls locals body
    pure locals
  SSwitch value body -> do
    registerImplicitCallsExpr locals value
    registerImplicitCalls locals (switchBodyStatements body)
    pure locals
  SCase expr -> registerImplicitCallsExpr locals expr >> pure locals
  SBlock body -> registerImplicitCalls locals body >> pure locals
  _ -> pure locals

registerImplicitCallsDecls :: [String] -> [(CType, String, Maybe Expr)] -> CompileM [String]
registerImplicitCallsDecls locals decls = case decls of
  [] -> pure locals
  decl:rest -> case decl of
    (_, name, initExpr) -> do
      maybeRegisterImplicitCallsExpr locals initExpr
      registerImplicitCallsDecls (name:locals) rest

maybeRegisterImplicitCallsExpr :: [String] -> Maybe Expr -> CompileM ()
maybeRegisterImplicitCallsExpr locals expr = case expr of
  Nothing -> pure ()
  Just value -> registerImplicitCallsExpr locals value

registerImplicitCallsExpr :: [String] -> Expr -> CompileM ()
registerImplicitCallsExpr locals expr = case expr of
  ECall (EVar name) args -> do
    if stringMember name locals || isIgnoredSideEffectCall name
      then pure ()
      else do
        global <- lookupGlobalType name
        case global of
          Just _ -> pure ()
          Nothing -> bindFunction name
    registerImplicitCallsExprs locals args
  ECall callee args -> do
    registerImplicitCallsExpr locals callee
    registerImplicitCallsExprs locals args
  EIndex base ix -> do
    registerImplicitCallsExpr locals base
    registerImplicitCallsExpr locals ix
  EMember base _ -> registerImplicitCallsExpr locals base
  EPtrMember base _ -> registerImplicitCallsExpr locals base
  EUnary _ value -> registerImplicitCallsExpr locals value
  ESizeofExpr value -> registerImplicitCallsExpr locals value
  ECast _ value -> registerImplicitCallsExpr locals value
  EPostfix _ value -> registerImplicitCallsExpr locals value
  EBinary _ left right -> do
    registerImplicitCallsExpr locals left
    registerImplicitCallsExpr locals right
  ECond cond yes no -> do
    registerImplicitCallsExpr locals cond
    registerImplicitCallsExpr locals yes
    registerImplicitCallsExpr locals no
  EAssign left right -> do
    registerImplicitCallsExpr locals left
    registerImplicitCallsExpr locals right
  _ -> pure ()

registerImplicitCallsExprs :: [String] -> [Expr] -> CompileM ()
registerImplicitCallsExprs locals exprs = case exprs of
  [] -> pure ()
  expr:rest -> do
    registerImplicitCallsExpr locals expr
    registerImplicitCallsExprs locals rest

switchBodyStatements :: [Stmt] -> [Stmt]
switchBodyStatements body = case body of
  [SBlock stmts] -> stmts
  _ -> body
