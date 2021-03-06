module CCAR.Model.Person 

where
import CCAR.Main.DBUtils
import GHC.Generics
import Data.Aeson as J
import Yesod.Core
import Control.Monad.IO.Class(liftIO)
import Control.Concurrent
import Control.Concurrent.STM.Lifted
import Control.Concurrent.Async
import qualified  Data.Map as IMap
import Control.Exception
import Control.Monad
import Control.Monad.Logger(runStderrLoggingT)
import Network.WebSockets.Connection as WSConn
import Data.Text as T
import Data.Text.Lazy as L 
import Database.Persist.Postgresql as DB
import Data.Aeson.Encode as En
import Data.Text.Lazy.Encoding as E
import Data.Aeson as J
import Control.Applicative as Appl
import Data.Aeson.Encode as En
import Data.Aeson.Types as AeTypes(Result(..), parse)
import GHC.Generics
import Data.Data
import Data.Typeable 
import System.IO
import Data.Time

data CRUD = Create  | Update PersonId | Query PersonId | Delete PersonId deriving(Show, Eq, Generic)

updateLogin :: Person -> IO (Maybe Person) 
updateLogin p = do
        connStr <- getConnectionString
        poolSize <- getPoolSize
        runStderrLoggingT $ withPostgresqlPool connStr poolSize $ \pool -> 
                liftIO $ do 
                    now <- getCurrentTime
                    flip runSqlPersistMPool pool $ do 
                        DB.updateWhere [PersonNickName ==. (personNickName p)][PersonLastLoginTime =. now]                         
                    return $ Just p 
checkLoginExists :: T.Text  -> IO (Maybe (Entity Person))
checkLoginExists aNickName = dbOps $ do
                	mP <- getBy $ PersonUniqueNickName aNickName
                	return mP 

queryAllPersons :: IO [Entity Person]
queryAllPersons = do dbOps $ DB.selectList [] [LimitTo 200]

getAllNickNames :: IO [T.Text] 
getAllNickNames = do
    persons <- queryAllPersons
    mapM (\(Entity k p) -> return $ personNickName p) persons



insertPerson :: Person -> IO ((Key Person)) 
insertPerson p = do 
        putStrLn $ show $ "Inside insert person " ++ (show p)
        dbOps $ do 
                        pid <- DB.insert p
                        preferences <- DB.insert $ Preferences {preferencesPreferencesFor = pid
                    			, preferencesMaxHistoryCount = 300} -- Need to get this from the default function.
                        $(logInfo) $ T.pack $ show  ("Returning " ++ (show pid))
                        return pid

updatePerson :: PersonId -> Person -> IO (Maybe Person)
updatePerson pid p = dbOps $ do 
                    _ <- DB.replace (pid) p
                    get pid

queryPerson :: PersonId -> IO (Maybe Person) 
queryPerson pid =  dbOps $ get pid 


deletePerson :: PersonId -> Person -> IO (Maybe Person)
deletePerson pid p = dbOps $ do 
                        _ <- DB.delete pid 
                        return $ Just p 

fixPreferences :: Maybe (Entity Person) -> IO (Key Preferences)
fixPreferences (Just (Entity k p1)) = dbOps $ do 
                preferences <- DB.selectFirst [PreferencesPreferencesFor ==. k ][]
                        -- We should have only one preferences instance per person.
                case preferences of
                    Nothing ->  do 
                                DB.insert $ Preferences 
                                    {preferencesPreferencesFor = k 
                                    , preferencesMaxHistoryCount = 300 }



-- How to handle this
fixPreferences Nothing = undefined


getMessageCount :: T.Text -> IO Int 
getMessageCount aNickName = dbOps $ do 
            person <- DB.getBy $ PersonUniqueNickName aNickName
            liftIO $ putStrLn $ "Person " ++ (show person)
            case person of 
                Just (Entity personId _) -> do
                    prefs <- DB.selectFirst [PreferencesPreferencesFor ==. personId][]
                    case (prefs) of
                            Just (Entity _ (Preferences _ count)) -> return count
                            Nothing -> return 300
                Nothing -> return 10



createGuestLogin :: NickName -> IO (Key GuestLogin) 
createGuestLogin aNickName = do 
        currentTime <- getCurrentTime
        dbOps $ do 
            person <- DB.getBy $ PersonUniqueNickName aNickName 
            case person of 
                Just (Entity personId _ ) -> insert $ GuestLogin currentTime personId 

instance ToJSON CRUD
instance FromJSON CRUD
