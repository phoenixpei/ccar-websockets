{-# LANGUAGE QuasiQuotes, TemplateHaskell, TypeFamilies, OverloadedStrings #-}
module CCAR.Main.Driver
    (driver)
where 

import Yesod.Core
import Yesod.WebSockets
import Yesod.Static
import qualified GHC.Conc as GHCConc
import qualified Data.Text.Lazy as TL
import Control.Monad (forever)
import Control.Monad.Trans.Reader
import Control.Concurrent (threadDelay)
import Control.Monad.IO.Class(liftIO)
import Control.Monad.Logger(runStderrLoggingT)
import Data.Time
import Conduit
import Data.Monoid ((<>))
import Control.Concurrent.STM.Lifted
import Data.Text as T
import Database.Persist
import Database.Persist.Postgresql as DB
import Database.Persist.TH
import Data.Time
import Data.Typeable
import GHC.Generics
import Data.Data
import Data.Aeson as J
import Control.Applicative as Appl
import Data.Aeson.Encode as En
import Data.Aeson.Types as AeTypes(Result(..), parse)
import Data.Text.Lazy.Encoding as E
import Data.Text.Lazy as L
import System.IO
import Data.HashMap.Lazy as LH (HashMap, lookup, member)
share [mkPersist sqlSettings, mkMigrate "migrateAll"] 
    [persistLowerCase| 
        Person
            firstName String 
            lastName String 
            nickName String 
            password String
            deleted Bool default=False
            PersonUniqueNickName nickName
            deriving Show Eq
        TermsAndConditions
            title String
            description String
            acceptDate UTCTime
            deriving Show Eq 
        CCAR 
            scenarioName String
            scenarioText String
            creator PersonId
            deriving Show Eq
            |]

type MyId = PersonId
connStr = "host=localhost dbname=ccar_debug user=ccar password=ccar port=5432"

emptyPerson = Person {personFirstName = "Not known"
                    , personLastName = "Not known"
                    , personNickName = "undefined"
                    , personPassword = "Not known"
                    , personDeleted = False}

data LoginStatus = UserExists | UserNotFound | InvalidPassword | Undefined
    deriving(Show, Typeable, Data, Generic, Eq)

data Login  =    Login {login :: Maybe Person, loginStatus :: Maybe LoginStatus} 
                deriving (Show, Eq)
data UserOperations = UserOperations{operation :: CRUD, person :: Maybe Person} 
                deriving (Show, Eq)
data UserTermsOperations = UserTermsOperations {utOperation :: CRUD, terms :: Maybe TermsAndConditions} 
                deriving(Show, Eq)
data ErrorCommand = ErrorCommand {errorCode :: T.Text, message :: T.Text} 
                deriving (Show, Eq)
data CCARUpload = CCARUpload {uploadedBy :: Maybe Person 
                            , ccarOperation :: CRUD
                            , ccarData :: CCAR} 
                    deriving (Show, Eq)
data Command = CommandLogin Login 
                | CommandUO UserOperations 
                | CommandUTO UserTermsOperations
                | CommandError ErrorCommand deriving(Show, Eq)
data CRUD = Create  | CCAR_Update MyId | Query MyId | Delete MyId deriving(Show, Eq, Generic)
data UserPreferences = UserPreferences {prefs :: T.Text} deriving (Show, Eq, Generic)


genPerson (Person a b c d e) = object ["firstName" .= a
                                       , "lastName" .= b
                                       , "nickName" .= c
                                       , "password" .= d
                                       , "deleted" .= e]
genLogin  (Login a b) = object [
    "commandType" .= (String "Login")
    , "login" .= Just a, "loginStatus" .= b]

genUserOperations (UserOperations o p) = object [
                        "operation" .= o
                        , "person" .= p
                        , "commandType" .= (String "ManageUser")]
genUserTermsOperations (UserTermsOperations o t) = object ["utOperation" .= o, "terms" .= t]
genErrorCommand (ErrorCommand e  m) = object ["errorCode" .= e
                                              , "message" .= m]

genTermsAndConditions (TermsAndConditions t des accept) = object ["title" .= t
                                            , "description" .= des
                                            , "acceptDate" .= accept]
instance ToJSON Person where
    toJSON  = genPerson 

instance ToJSON Login where
    toJSON = genLogin 
instance ToJSON UserOperations where
    toJSON = genUserOperations

instance ToJSON UserTermsOperations where
    toJSON = genUserTermsOperations

instance ToJSON TermsAndConditions where
    toJSON = genTermsAndConditions
instance ToJSON ErrorCommand where
    toJSON = genErrorCommand

instance ToJSON Command where
    toJSON aCommand = 
        case aCommand of
            CommandLogin l -> genLogin l 
            CommandError e -> genErrorCommand e
            CommandUO e -> genUserOperations e
            _ -> genErrorCommand $ ErrorCommand {errorCode = "Unknown" :: T.Text , 
                        message = T.pack (show aCommand)}

genericErrorCommand errorMessage = ErrorCommand {errorCode = T.pack "Error" 
                                       , message = T.pack errorMessage}
parseErrorCommand value= do
        return $ ErrorCommand {errorCode = T.pack "Error"
                               , message = T.pack $ show value}

{-        "DeleteUser" -> parseDeleteUser value
        "UpdateUser" -> parseUpdateUser value
        "CreateUser" -> parseCreateUser value
        "QueryUser"  -> parseQueryUser value
        "CreateUserTerms" -> parseCreateUserTerms value
        "QueryUserTerms" -> parseQueryUserTerms value
        "UpdateUserTerms" -> parseUpdateUserTerms value
        "DeleteUserTerms" -> parseDeleteUserTerms value
        "CreateUserPreferences" -> parseCreateUserPreferences value
        "QueryUserPreferences" -> parseQueryUserPreferences value
        "UpdateUserPreferences" -> parseUpdateUserPreferences value
        "DeleteUserPreferences" -> parseDeleteUserPreferences value
-}

commandType = LH.lookup "commandType"

parseCommand value = do
        case (commandType value) of
            Nothing -> CommandError <$> parseErrorCommand value
            Just cType -> 
                case (cType) of 
                    "Login"-> CommandLogin <$> parseLogin value
                    "ManageUser" -> CommandUO <$> parseCreateUser value
                    _       -> CommandError <$> parseErrorCommand value




parsePerson v = Person <$>
                    v .: "firstName" <*>
                    v .: "lastName" <*>
                    v .: "nickName" <*>
                    v .: "password"  <*>
                    v .: "deleted"



parseCreateUser v = UserOperations <$>
                        v .: "operation" <*> 
                        v .: "person"
parseLogin v = Login <$> 
                v .: "login" <*>
                (v .: "loginStatus")


parseTermsAndConditions v = TermsAndConditions <$>
                        v .: "title" <*>
                        v .: "description" <*>
                        v .: "acceptDate"

instance FromJSON Login where
    parseJSON (Object v) = parseLogin v
    parseJSON _          = Appl.empty

instance FromJSON Person where
    parseJSON (Object v) = parsePerson v
    parseJSON _          = Appl.empty

instance FromJSON TermsAndConditions where
    parseJSON (Object v) = parseTermsAndConditions v
    parseJSON _          = Appl.empty


instance FromJSON Command where
    parseJSON (Object v) = parseCommand v
    parseJSON _         = Appl.empty


iParseJSON :: (FromJSON a) => T.Text -> Either String (Maybe a)
iParseJSON = J.eitherDecode . E.encodeUtf8 . L.fromStrict

pJSON :: (FromJSON a) => T.Text -> IO (Either String (Maybe a))
pJSON  aText = do
    putStrLn $ "pJSON " ++ (T.unpack aText)
    return $ iParseJSON aText
 
decoder = L.toStrict . E.decodeUtf8 . En.encode        
decoderM a = return $ L.toStrict $ E.decodeUtf8 $ En.encode a







data App = App { chan :: (TChan T.Text)
                , getStatic :: Static}

instance Yesod App

mkYesod "App" [parseRoutes|
/ HomeR GET
/static StaticR  Static getStatic
|]

checkLoginExists :: String  -> IO (Maybe (Entity Person))
checkLoginExists aNickName = runStderrLoggingT $ withPostgresqlPool connStr 10 $ \pool ->
        liftIO $ do
            flip runSqlPersistMPool pool $ do
                getBy $ PersonUniqueNickName aNickName

insertPerson :: Person -> IO ((Key Person)) 
insertPerson p = do 
        putStrLn $ "Inside insert person " ++ (show p)
        runStderrLoggingT $ withPostgresqlPool connStr 10 $ \pool -> 
            liftIO $ do
                flip runSqlPersistMPool pool $ do 
                        pid <- insert p
                        liftIO $ putStrLn ("Returning " ++ (show pid))
                        return pid
updatePerson :: MyId -> Person -> IO (Maybe Person)
updatePerson pid p = runStderrLoggingT $ withPostgresqlPool connStr 10 $ \pool ->
    liftIO $ do
            flip runSqlPersistMPool pool $ do
                DB.replace (pid) p
                get pid

queryPerson :: MyId -> IO (Maybe Person) 
queryPerson pid = runStderrLoggingT $ withPostgresqlPool connStr 10 $ \pool ->
            liftIO $ do 
                flip runSqlPersistMPool pool $ 
                    get pid 

deletePerson :: MyId -> Person -> IO (Maybe Person)
deletePerson pid p = updatePerson pid p {personDeleted = True}

{- Read the message, parse and then send it back. -}
processCommand :: Maybe Command  -> IO T.Text
processCommand (Just (CommandLogin aLogin)) = do 
    chk <- checkLoginExists (personNickName p)
    putStrLn $ "Login exists " ++ (show chk)
    case chk of 
        Nothing -> return $ L.toStrict $ E.decodeUtf8 $ J.encode $ CommandLogin $ Login {login = Just p, 
            loginStatus = Just UserNotFound}
        Just (Entity aid a)  -> 
            return $ L.toStrict $ E.decodeUtf8 $ J.encode $ CommandLogin $ 
                Login {login = Just a, loginStatus = Just UserExists}
    where
        p = case (login aLogin) of
                Nothing -> emptyPerson
                Just a -> a 

processCommand (Just (CommandError error)) = 
        return $ L.toStrict $ E.decodeUtf8 $ J.encode $ CommandError error
processCommand Nothing = return 
         $ decoder $ genericErrorCommand "Unable to process command"


processCommand (Just ( CommandUO (UserOperations uo aPerson))) = do
    putStrLn $ "Processing processCommand " ++ (show uo)
    case uo of
        Create  -> do
                personId <- insertPerson person
                liftIO $ putStrLn  $ "Person inserted " ++ (show personId)
                return $ L.toStrict $ E.decodeUtf8 $ J.encode $ CommandUO 
                        $ UserOperations (Create ) (Just person)
        CCAR_Update personId -> do
                updatePerson personId person
                return $ L.toStrict $ E.decodeUtf8 $ J.encode $ CommandUO 
                            $ UserOperations (CCAR_Update personId) (Just person)
        Delete personId -> do 
                deletePerson personId person
                return $ L.toStrict $ E.decodeUtf8 $ J.encode $ 
                        CommandUO $ UserOperations (Delete personId) (Just person)
        Query personId -> do 
                maybePerson <- queryPerson (personId)
                case maybePerson of
                    Nothing -> 
                        return $ L.toStrict $ E.decodeUtf8 $ J.encode $ CommandUO  
                                $ UserOperations (Query personId) Nothing
                    Just (p) -> 
                        return $ L.toStrict $ E.decodeUtf8 $ J.encode $ CommandUO  
                                $ UserOperations (Query personId) (Just p)
    where
        person = case aPerson of
                Nothing -> emptyPerson
                Just a -> a        


processCommandWrapper :: Value -> Command 
processCommandWrapper (Object a)   = 
    case cType of 
        Nothing -> CommandError $ genericErrorCommand "Unable to process command"
        Just aType -> 
            case aType of 
                String "Login" -> 
                        case (parse parseLogin a) of
                            Success r -> CommandLogin r
                            Error s -> CommandError $ genericErrorCommand $ "parse login  "++ s
                String "ManageUser" ->
                        case (parse parseCreateUser a) of
                            Success r -> CommandUO r
                            Error s -> CommandError $ genericErrorCommand $ "parse create user " ++ s

                _ -> CommandError $ genericErrorCommand ("Unable to process command " ++ (show aType))
    where 
        cType =  LH.lookup "commandType" a


processCommandWrapper _ = CommandError $ genericErrorCommand "Not yet implemented"

processIncomingMessage :: Maybe Value -> IO T.Text
processIncomingMessage aCommand = 
    do 
        putStrLn $ "Processing incoming message " ++ (show aCommand)
        case aCommand of 
            Nothing -> do
                    putStrLn $ "Processing error..."
                    return $ L.toStrict $ E.decodeUtf8 $ En.encode   
                        (CommandError $ genericErrorCommand ("Unknown error"))
            Just (Object a) -> do 
                    liftIO $ putStrLn $ "Processing command type " ++ (show (LH.lookup "commandType" a))
                    c <- return $ processCommandWrapper (Object a)
                    liftIO $ putStrLn $ "Processing command " ++ (show c)
                    reply <- processCommand (Just c)
                    return $ L.toStrict $ E.decodeUtf8 $ En.encode reply


ccarApp :: WebSocketsT Handler ()
ccarApp = do
        command <- receiveData
        liftIO $ putStrLn $ "Incoming text " ++ (T.unpack (command :: T.Text))
        liftIO $ putStrLn $ show $ incomingDictionary (command :: T.Text)
        nickNameExists <- liftIO $ processIncomingMessage $ incomingDictionary command
        liftIO $ putStrLn $ show nickNameExists
        sendTextData nickNameExists
        App writeChan _ <- getYesod
        readChan <- atomically $ do
            writeTChan writeChan $ command <> " has joined the chat"
            dupTChan writeChan
        race_
            (forever $ atomically (readTChan readChan) >>= sendTextData)
            (sourceWS $$ mapM_C (\msg -> do 
                x <- liftIO $ processIncomingMessage $ incomingDictionary msg 
                liftIO $ putStrLn $ "Sending " ++ show x ++ ("To the wire : sourceWS")
                atomically $ do
                        writeTChan writeChan x))
        where
            incomingDictionary aText = (J.decode  $ E.encodeUtf8 (L.fromStrict aText)) :: Maybe Value
getHomeR :: Handler Html
getHomeR = do
    webSockets ccarApp
    defaultLayout $ do
        [whamlet|
            <div #output>
            <form #form>
                <input #input autofocus>
        |]
        toWidget [lucius|
            \#output {
                width: 600px;
                height: 400px;
                border: 1px solid black;
                margin-bottom: 1em;
                p {
                    margin: 0 0 0.5em 0;
                    padding: 0 0 0.5em 0;
                    border-bottom: 1px dashed #99aa99;
                }
            }
            \#input {
                width: 600px;
                display: block;
            }
        |]
        toWidget [julius|
            var url = document.URL,
                output = document.getElementById("output"),
                form = document.getElementById("form"),
                input = document.getElementById("input"),
                conn;

            url = url.`("http:", "ws:").replace("https:", "wss:");
            conn = new WebSocket(url);

            conn.onmessage = function(e) {
                var p = document.createElement("p");
                p.appendChild(document.createTextNode(e.data));
                output.appendChild(p);
            };

            form.addEventListener("submit", function(e){
                conn.send(input.value);
                input.value = "";
                e.preventDefault();
            });
        |]


driver :: IO ()
driver = do
    hSetBuffering stdout NoBuffering
    runStderrLoggingT $ withPostgresqlPool connStr 10 $ \pool ->
        liftIO $ do
            flip runSqlPersistMPool pool $ do
                runMigration migrateAll
    chan <- atomically newBroadcastTChan
    static@(Static settings) <- static "static"
    warp 3000 $ App chan static

instance ToJSON LoginStatus
instance FromJSON LoginStatus
instance ToJSON CRUD
instance FromJSON CRUD