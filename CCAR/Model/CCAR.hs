module CCAR.Model.CCAR 
where
import CCAR.Main.DBUtils
import GHC.Generics
import Data.Aeson as J
import Data.Text as T

data CRUD = Create  | Update | Query CCARId | Delete  | QueryAll T.Text deriving(Show, Eq, Generic)
instance ToJSON CRUD
instance FromJSON CRUD