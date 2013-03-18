{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}

import           Yesod
import           Web.XING
import           Network.HTTP.Conduit (newManager, def)
import           Data.Maybe (fromJust, isJust, fromMaybe)
import qualified Data.Map as M
import           YesodHelper ( bootstrapLayout, bootstrapCDN
                             , writeTokenToSession, getTokenFromSession
                             , deleteTokenFromSession )
import qualified Data.ByteString.Char8 as BS
import           Data.Monoid (mappend)
import qualified Data.Text.Encoding as E
import qualified Config

data HelloXING = HelloXING {
    httpManager :: Manager
  , oAuthConsumer :: OAuth
}

instance Yesod HelloXING where
  defaultLayout = bootstrapLayout

mkYesod "HelloXING" [parseRoutes|
  / HomeR GET
  /handshake HandshakeR POST
  /callback CallbackR GET
  /logout LogoutR POST
|]

postHandshakeR :: Handler RepHtml
postHandshakeR = do
  yesod <- getYesod
  let oa = oAuthConsumer yesod
  let manager = httpManager yesod

  (requestToken, url) <- getRequestToken oa manager
  writeTokenToSession "request" requestToken

  redirect $ E.decodeUtf8 url

getCallbackR :: Handler RepHtml
getCallbackR = do
  yesod <- getYesod
  let oa = oAuthConsumer yesod
  let manager = httpManager yesod

  maybeRequestToken <- getTokenFromSession "request"

  maybeVerifier <- lookupGetParam "oauth_verifier"
  let verifier = E.encodeUtf8 (fromMaybe "" maybeVerifier)

  if isJust maybeRequestToken
    then do
      (accessToken, _) <- getAccessToken (fromJust maybeRequestToken) verifier oa manager
      writeTokenToSession "access" accessToken
    else return ()

  redirect HomeR

postLogoutR :: Handler RepHtml
postLogoutR = do
  deleteTokenFromSession "access"
  deleteTokenFromSession "request"
  redirect HomeR

getHomeR :: Handler RepHtml
getHomeR = do
  maybeAccessToken <- getTokenFromSession "access"

  widget <- case maybeAccessToken of
    Just accessToken -> do
      yesod <- getYesod
      users <- getUsers (oAuthConsumer yesod) (httpManager yesod) accessToken ["me"]
      return $ whoAmI (head $ unUserList users)

    Nothing -> return pleaseLogIn

  defaultLayout $ do
    addStylesheetRemote $ bootstrapCDN `mappend` "/css/bootstrap-combined.min.css"
    [whamlet|
      <h1>Welcome to the XING API demo
      ^{widget}
    |]

pleaseLogIn :: Widget
pleaseLogIn =
  toWidget [hamlet|
    <img src="https://www.xing.com/img/n/nobody_m.png">
    <p>Hello unknown user. Please log-in.
    <form method=POST action=@{HandshakeR}>
      <input type=submit value="Login with XING">
  |]

whoAmI
  :: User a
  => a
  -> Widget
whoAmI user = do
  toWidget [hamlet|
    <img src=#{fromMaybe "" $ M.lookup "maxi_thumb" (photoUrls user)}>
    <p>
      <a href=#{permalink user}>#{displayName user}
    <form method=POST action=@{LogoutR}>
      <input type=submit value="Logout">
  |]

main :: IO ()
main = do
  manager <- newManager def
  let port = 3000
  let testConsumer = Config.testConsumer{
    oauthCallback = Just $ "http://localhost:" `mappend` (BS.pack.show) port `mappend` "/callback"
  }
  warpDebug port (HelloXING manager testConsumer)
