module Kanren.Render where

import DOM

import Data.Maybe
import Data.Tuple
import Data.Array (length, sortBy, (..))
import Data.Foldable (intercalate)
import Data.Traversable (for)

import Control.Bind
import Control.Apply
import Control.Monad (when, unless)
import Control.Monad.Eff
import Control.Monad.JQuery

import Kanren.Eval
import Kanren.State
import Kanren.Goal
import Kanren.Term
import Kanren.Subst
import Kanren.Var
import Kanren.Obj
import Kanren.Unify

render :: forall eff. State -> Eff (dom :: DOM | eff) Unit 
render st@(State g su var stk) = void do
  -- Update the goal    
    
  select "#goal .lines" >>= remove    
    
  goal <- create "<div>" >>= addClass "lines"
  renderGoal true goal g
  select "#goal" >>= append goal
    
  -- Update the stack    
    
  select "#stack tbody tr" >>= remove
  stackBody <- select "#stack tbody"
  
  for stk $ \g' -> void do 
    tr <- create "<tr>"
    td <- create "<td>"
    pre <- create "<pre>" >>= appendText (renderShortGoal g')
    pre `append` td
    td `append` tr
    tr `append` stackBody
  
  -- Update the substitution
  
  select "#subst tbody tr" >>= remove
  
  substBody <- select "#subst tbody"
  
  for (sortBy (compare `Data.Function.on` fst) su) $ \(Tuple (Var nm) tm) -> do
    tr <- create "<tr>"
    td1 <- create "<td>" >>= appendText ("#" ++ show nm)
    pre <- create "<pre>" >>= appendText (renderTerm (walk su tm))
    td2 <- create "<td>" >>= append pre
    td1 `append` tr
    td2 `append` tr
    tr `append` substBody
  where
      
  renderShortGoal :: Goal -> String
  renderShortGoal Done = "Done"
  renderShortGoal (Fresh ns _) = "fresh " ++ intercalate " " ns
  renderShortGoal (Unify u v) = renderTerm u ++ " == " ++ renderTerm v
  renderShortGoal (Disj _) = "disj"
  renderShortGoal (Conj _) = "conj"
  renderShortGoal (Named name _) = name
    
  renderGoal :: forall eff. Boolean -> JQuery -> Goal -> Eff (dom :: DOM | eff) Unit 
  renderGoal _           jq Done = void do
    "Evaluation complete" `appendText` jq
  renderGoal _           jq Fail = void do
    "Contradiction!" `appendText` jq
  renderGoal renderLinks jq (Fresh ns g) = void do
    let freshNames = TmVar <<< Var <$> (runVar var .. (runVar var + length ns - 1))
        newState = State (replaceAll (zip ns freshNames) g) su nextVar stk
        nextVar = Var (runVar var + length ns)
    link <- linkTo renderLinks (render newState)
              >>= appendText ("(fresh " ++ intercalate " " ns ++ "")
    line <- newLine >>= append link
    line `append` jq
    rest <- indented
    renderGoal false rest g
    rest `append` jq
    close <- newLine >>= appendText ")"
    close `append` jq
  renderGoal renderLinks jq (Unify u v) = void do
    let text = "(= " ++ renderTerm u ++ " " ++ renderTerm v ++ ")"
        action = case unify u v su of
          Nothing -> render $ State Fail su var stk
          Just su' -> render $ unwind $ State Done su' var stk
    link <- linkTo renderLinks action 
              >>= appendText text
    line <- newLine >>= append link
    line `append` jq
  renderGoal renderLinks jq (Named nm ts) = void do
    let text = "(" ++ nm ++ " " ++ intercalate " " (renderTerm <$> ts) ++ ")"
        newState = State (builtIn nm ts) su var stk
    link <- linkTo renderLinks (render newState) 
              >>= appendText text
    line <- newLine >>= append link
    line `append` jq
  renderGoal renderLinks jq (Disj gs) = void do
    line <- newLine >>= appendText "(disj"
    line `append` jq
    
    for gs $ \g -> do
      i <- indented
      a <- linkTo renderLinks (render (unwind (State g su var stk))) 
      renderGoal false a g
      a `append` i
      i `append` jq
    
    close <- newLine >>= appendText ")"
    close `append` jq
  renderGoal renderLinks jq (Conj gs) = void do
    line <- newLine >>= appendText "(conj"
    line `append` jq
    
    for (inContext gs) $ \(Tuple g rest) -> do
      i <- indented
      a <- linkTo renderLinks (render (unwind (State g su var (rest ++ stk)))) 
      renderGoal false a g
      a `append` i
      i `append` jq
      
    close <- newLine >>= appendText ")"
    close `append` jq
  
  unwind :: State -> State
  unwind (State Done subst var (goal : stack)) = State goal subst var stack
  unwind other = other
  
  linkTo :: forall eff a. Boolean -> (Eff (dom :: DOM | eff) a) -> Eff (dom :: DOM | eff) JQuery 
  linkTo true action =
    create "<a href='#'>" 
      >>= on "click" (\e _ -> action *> preventDefault e)
  linkTo false _ = 
    create "<span>"
        
  indented :: forall eff. Eff (dom :: DOM | eff) JQuery
  indented = create "<div>" >>= addClass "indented"
  
  newLine :: forall eff. Eff (dom :: DOM | eff) JQuery
  newLine = create "<div>" >>= addClass "line"
    
  renderTerm :: Term -> String
  renderTerm (TmVar (Var v)) = "#" ++ show v
  renderTerm (TmObj (Obj o)) = o
  renderTerm (TmPair t1 t2) = "(" ++ renderTerm t1 ++ " " ++ renderTerm t2 ++ ")"
    
  spaces = go ""
    where
    go acc 0 = acc
    go acc n = go (acc ++ "  ") (n - 1)
    
  inContext :: forall a. [a] -> [Tuple a [a]]
  inContext = go [] []
    where
    go acc _  []       = acc
    go acc ys (x : xs) = go (Tuple x (ys ++ xs) : acc) (ys ++ [x]) xs