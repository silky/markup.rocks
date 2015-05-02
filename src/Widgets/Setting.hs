{-# LANGUAGE CPP              #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs            #-}
{-# LANGUAGE TemplateHaskell  #-}

module Widgets.Setting where

import           Control.Applicative
import           Control.Monad
import           Control.Monad.IO.Class
import           Data.Default
import           Data.Map                   (Map)
import qualified Data.Map                   as Map
import           Data.Maybe
import           Data.Monoid                ((<>))
import           GHCJS.DOM
import           GHCJS.DOM.DOMWindow        (domWindowGetLocalStorage)
import           GHCJS.DOM.Element
import           GHCJS.DOM.HTMLElement
import           GHCJS.DOM.HTMLElement      (htmlElementSetInnerText)
import           GHCJS.DOM.HTMLInputElement
import           GHCJS.DOM.HTMLLabelElement
import GHCJS.DOM.HTMLSelectElement
import           GHCJS.DOM.Node             (nodeAppendChild)
import           GHCJS.DOM.Storage
import           GHCJS.DOM.Types            (Element (..))
import           Reflex
import           Reflex.Dom
import           Safe                       (readMay)
import           GHCJS.Foreign
import           GHCJS.Types
import           Data.Dependent.Map            (DSum (..))
import           Control.Monad.Ref
import           Reflex
import           Reflex.Dom
import           Reflex.Host.Class

#ifdef __GHCJS__
#define JS(name, js, type) foreign import javascript unsafe js name :: type
#else
#define JS(name, js, type) name :: type ; name = undefined
#endif

JS(makeCheckbox, "jQuery($1)['checkbox']()", HTMLElement -> IO ())
JS(makeDropdown, "checkboxOnChange($1, $2)", HTMLElement -> JSFun (JSString -> IO ()) -> IO ())

data Setting t =
  Setting {_setting_value :: Dynamic t Bool}

data Selection t =
  Selection {_selection_value :: Dynamic t String}

setting :: MonadWidget t m => String -> m (Setting t)
setting labelText =
  do val <- liftIO (getPref labelText False)
     (parent,(input,_)) <-
       elAttr' "div" ("class" =: "ui toggle checkbox") $
       do el "label" (text labelText)
          elAttr' "input"
                  ("type" =: "checkbox" <>
                   if val
                      then "checked" =: "checked"
                      else mempty) $
            return ()
     liftIO (makeCheckbox $ _el_element parent)
     eClick <-
       wrapDomEvent (_el_element parent)
                    elementOnclick $
       liftIO $
       do checked <-
            htmlInputElementGetChecked
              (castToHTMLInputElement $ _el_element input)
          setPref labelText $ show checked
          return checked
     dValue <- holdDyn val eClick
     return (Setting dValue)

selection :: MonadWidget t m
          => String
          -> String
          -> Dynamic t (Map String String)
          -> m (Selection t)
selection labelText k0 options =
  do (eRaw,_) <-
       elAttr' "div" ("class" =: "ui dropdown compact search button") $
       do elClass "span" "text" (text labelText)
          elClass "i" "dropdown icon" $
            return ()
          divClass "menu" $
            do optionsWithDefault <-
                 mapDyn (`Map.union` (k0 =: "")) options
               listWithKey optionsWithDefault $
                 \k v ->
                   elAttr "div"
                          ("data-value" =: k <> "class" =: "item")
                          (dynText v)
     postGui <- askPostGui
     runWithActions <- askRunWithActions
     (eRecv,eRecvTriggerRef) <- newEventWithTriggerRef
     onChangeFun <-
       liftIO $
       syncCallback1
         AlwaysRetain
         True
         (\kStr ->
            do let val = fromJSString kStr
               maybe (return ())
                     (\t ->
                        postGui $
                        runWithActions
                          [t :=>
                           Just val]) =<<
                 readRef eRecvTriggerRef)
     liftIO $ makeDropdown (_el_element eRaw) onChangeFun
     let readKey opts mk =
           fromMaybe k0 $
           do k <- mk
              guard $
                Map.member k opts
              return k
     dValue <-
       combineDyn readKey options =<<
       holdDyn (Just k0) eRecv
     return (Selection dValue)

setPref :: String -> String -> IO ()
setPref key val =
  do mbWindow <- currentWindow
     case mbWindow of
       Nothing -> return ()
       Just win ->
         do Just storage <- domWindowGetLocalStorage win
            storageSetItem storage key val

getPref :: Read a => String -> a -> IO a
getPref key def =
  do mbWindow <- currentWindow
     case mbWindow of
       Nothing -> return def
       Just win ->
         do Just storage <- domWindowGetLocalStorage win
            fromMaybe def . readMay <$>
              storageGetItem storage key