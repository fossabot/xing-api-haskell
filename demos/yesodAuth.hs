{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}

import           Yesod
import           Yesod.Auth
import           Yesod.Auth.XING
import qualified Yesod.Auth.Message as Msg
import           Network.HTTP.Conduit (newManager, def)
import           Data.Text (Text)
import           Data.Monoid (mappend)
import qualified Config
import           YesodHelper (bootstrapCDN, bootstrapLayout, alertMessage)

data XINGAuth = XINGAuth {
  httpManager :: Manager
}

instance Yesod XINGAuth where
  approot = ApprootStatic "http://localhost:3000"
  defaultLayout = bootstrapLayout

mkYesod "XINGAuth" [parseRoutes|
  / RootR GET
  /auth AuthR Auth getAuth
|]

instance YesodAuth XINGAuth where
  type AuthId XINGAuth = Text
  getAuthId creds = return $ lookup "oauth_token" (credsExtra creds)
  loginDest _     = RootR
  logoutDest _    = RootR
  onLogin         = alertMessage Msg.NowLoggedIn
  authPlugins _   = [xingAuth (oauthConsumerKey Config.testConsumer) (oauthConsumerSecret Config.testConsumer)]
  authHttpManager = httpManager

instance RenderMessage XINGAuth FormMessage where
 renderMessage _ _ = defaultFormMessage

getRootR :: Handler RepHtml
getRootR = do
  maid <- maybeAuthId
  defaultLayout $ do
    addScriptRemote "http://code.jquery.com/jquery-1.9.1.min.js"
    addStylesheetRemote $ bootstrapCDN `mappend` "/css/bootstrap-combined.min.css"
    addScriptRemote     $ bootstrapCDN `mappend` "/js/bootstrap.min.js"
    setTitle "XING API demo"
    toWidget [julius|
      $(window).ready(function () {
        $('.alert').alert();
      });
    |]
    [whamlet|
      <h1>Welcome to the XING API demo
      $maybe aid <- maid
        <p>Nice to meet you, #{show aid}
        <a href=@{AuthR LogoutR}>Logout
      $nothing
        <p>Hello unknown user. Please log-in.
        <a href=@{AuthR xingLoginRoute}>Login with XING
    |]

main :: IO ()
main = do
  manager <- newManager def
  warpDebug 3000 $ XINGAuth manager