{-# OPTIONS_GHC -Wall #-}
{-# LANGUAGE OverloadedStrings, TemplateHaskell #-}

module FileBrowserUI (runFileBrowserUI) where

import Brick
import Data.List
import Data.Char
import Types
import Parser
import Control.Exception (displayException, try)
import Control.Monad.IO.Class
import Brick.Widgets.Border
import Brick.Widgets.Center
import Brick.Widgets.List
import Brick.Widgets.FileBrowser
import Lens.Micro.Platform
import qualified Graphics.Vty as V


type Event = ()
type Name = ()
data State = State
  { _fb        :: FileBrowser Name
  , _exception :: Maybe String
  , _cards     :: [Card]
  }

makeLenses ''State

app :: App State Event Name
app = App 
  { appDraw = drawUI
  , appChooseCursor = neverShowCursor
  , appHandleEvent = handleEvent
  , appStartEvent = return
  , appAttrMap = const theMap
  }

errorAttr :: AttrName
errorAttr = "error"

theMap :: AttrMap
theMap = attrMap V.defAttr
    [ (listSelectedFocusedAttr, V.black `on` V.yellow)
    , (fileBrowserCurrentDirectoryAttr, V.white `on` V.blue)
    , (fileBrowserSelectionInfoAttr, V.white `on` V.blue)
    , (fileBrowserDirectoryAttr, fg V.blue)
    , (fileBrowserBlockDeviceAttr, fg V.magenta)
    , (fileBrowserCharacterDeviceAttr, fg V.green)
    , (fileBrowserNamedPipeAttr, fg V.yellow)
    , (fileBrowserSymbolicLinkAttr, fg V.cyan)
    , (fileBrowserUnixSocketAttr, fg V.red)
    , (fileBrowserSelectedAttr, V.white `on` V.magenta)
    , (errorAttr, fg V.red)
    ]

-- drawUI :: FileBrowser Name -> [Widget Name]
-- drawUI b = [renderFileBrowser True b]

drawUI :: State -> [Widget Name]
drawUI State{_fb=b, _exception=exc} = [center $ ui <=> help]
    where
        ui = hCenter $
             vLimit 15 $
             hLimit 50 $
             borderWithLabel (txt "Choose a file") $
             renderFileBrowser True b
        help = padTop (Pad 1) $
               vBox [ case exc of
                          Nothing -> emptyWidget
                          Just e -> hCenter $ withDefAttr errorAttr $
                                    str e
                    , hCenter $ txt "Up/Down: select"
                    , hCenter $ txt "/: search, Ctrl-C or Esc: cancel search"
                    , hCenter $ txt "Enter: change directory or select file"
                    , hCenter $ txt "Esc: quit"
                    ]

handleEvent :: State -> BrickEvent Name Event -> EventM Name (Next (State))
-- handleEvent s (VtyEvent (V.EvKey V.KEsc [])) = halt s
-- handleEvent s (VtyEvent ev) = do fb'<- handleFileBrowserEvent ev (s ^. fb)
--                                  continue $ s & fb .~ fb'
handleEvent s@State{_fb=b} (VtyEvent ev) =
    case ev of
        V.EvKey V.KEsc [] | not (fileBrowserIsSearching b) ->
            halt s
        V.EvKey (V.KChar 'c') [V.MCtrl] | not (fileBrowserIsSearching b) ->
            halt s
        _ -> do
            b' <- handleFileBrowserEvent ev b
            let s' = s & fb .~ b'
            -- If the browser has a selected file after handling the
            -- event (because the user pressed Enter), shut down.
            case ev of
                V.EvKey V.KEnter [] ->
                    case fileBrowserSelection b' of
                        [] -> continue s'
                        [fileInfo] -> do
                          let fp = fileInfoFilePath fileInfo
                          strOrExc <- liftIO (try (readFile fp) :: IO (Either IOError String))
                          case strOrExc of
                            Left exc -> continue (s' & exception .~ Just (displayException exc))
                            Right str -> case parseCards str of
                              Left parseError -> continue (s' & exception .~ Just (show parseError))
                              Right result -> halt (s' & cards .~ result)
                        _ -> halt s'

                _ -> continue s'
handleEvent s _ = continue s

runFileBrowserUI :: IO [Card]
runFileBrowserUI = do
  browser <- newFileBrowser selectNonDirectories () Nothing
  let filteredBrowser = setFileBrowserEntryFilter (Just (fileExtensionMatch' "txt")) browser
  s <- defaultMain app (State filteredBrowser Nothing [])
  return (s ^. cards)

fileExtensionMatch' :: String -> FileInfo -> Bool
fileExtensionMatch' ext i = case fileInfoFileType i of
    Just RegularFile -> ('.' : (toLower <$> ext)) `isSuffixOf` (toLower <$> fileInfoFilename i)
    _ -> True