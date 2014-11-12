module Main where

import DOM

import Control.Monad.Eff
import Control.Monad.Eff.Ref
import Control.Monad.JQuery

import Kanren.Eval
import Kanren.Render

withoutDefault :: forall eff a. Eff (dom :: DOM | eff) a -> JQueryEvent -> JQuery -> Eff (dom :: DOM | eff) Unit
withoutDefault action e _ = do
  action
  preventDefault e

main = do
  history <- newRef []
    
  select "#editButton" >>= 
    on "click" (withoutDefault showEditor)
      
  select "#evalButton" >>= 
    on "click" (withoutDefault (eval history))
      
  select "#undoButton" >>= 
    on "click" (withoutDefault $ do
      sts <- readRef history    
      case sts of
        [] -> return unit
        (st : sts') -> do
          writeRef history sts'
          render history st
    )