{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}

module ReactiveEnglish.Db
  ( AppDb,
    DbConnection,
    DbDialect (..),
    DbOnly (..),
    closeAppDb,
    dbDialect,
    execute,
    execute_,
    insertReturningId,
    openAppDb,
    query,
    query_,
    withAppDbConnection,
    withTransaction,
  )
where

#ifdef POSTGRES_BACKEND
import qualified Data.ByteString.Char8 as BS8
import Data.Pool (Pool, createPool, destroyAllResources, withResource)
#endif
import Data.String (fromString)
#ifdef POSTGRES_BACKEND
import qualified Database.PostgreSQL.Simple as PG
import qualified Database.PostgreSQL.Simple.FromField as PGFromField
import qualified Database.PostgreSQL.Simple.FromRow as PGFromRow
import qualified Database.PostgreSQL.Simple.ToField as PGToField
import qualified Database.PostgreSQL.Simple.ToRow as PGToRow
#endif
import qualified Database.SQLite.Simple as SQLite
import qualified Database.SQLite.Simple.FromField as SQLiteFromField
import qualified Database.SQLite.Simple.FromRow as SQLiteFromRow
import qualified Database.SQLite.Simple.ToField as SQLiteToField
import qualified Database.SQLite.Simple.ToRow as SQLiteToRow
import ReactiveEnglish.Config (DatabaseBackend (..))

data DbDialect
  = SQLiteDialect
  | PostgresDialect
  deriving (Show, Eq)

data DbConnection
  = SQLiteConnection SQLite.Connection
#ifdef POSTGRES_BACKEND
  | PostgresConnection PG.Connection
#endif

data AppDb
  = SQLiteDb SQLite.Connection
#ifdef POSTGRES_BACKEND
  | PostgresDb (Pool PG.Connection)
#endif

newtype DbOnly value = DbOnly value
  deriving (Show, Eq)

instance SQLiteFromField.FromField value => SQLiteFromRow.FromRow (DbOnly value) where
  fromRow = DbOnly <$> SQLiteFromRow.field

instance SQLiteToField.ToField value => SQLiteToRow.ToRow (DbOnly value) where
  toRow (DbOnly value) = [SQLiteToField.toField value]

#ifdef POSTGRES_BACKEND
instance PGFromField.FromField value => PGFromRow.FromRow (DbOnly value) where
  fromRow = DbOnly <$> PGFromRow.field

instance PGToField.ToField value => PGToRow.ToRow (DbOnly value) where
  toRow (DbOnly value) = [PGToField.toField value]
#endif

openAppDb :: DatabaseBackend -> FilePath -> Maybe String -> IO AppDb
openAppDb databaseBackend sqlitePath maybePostgresUrl =
#ifndef POSTGRES_BACKEND
  let _ = maybePostgresUrl
   in
#endif
  case databaseBackend of
    SQLiteBackend ->
      SQLiteDb <$> SQLite.open sqlitePath
#ifdef POSTGRES_BACKEND
    PostgresBackend ->
      case maybePostgresUrl of
        Nothing ->
          fail "DATABASE_BACKEND=postgres requires DATABASE_URL."
        Just postgresUrl ->
          PostgresDb
            <$> createPool
              (PG.connectPostgreSQL (BS8.pack postgresUrl))
              PG.close
              1
              10
              4
#else
    PostgresBackend ->
      fail "This executable was built without PostgreSQL support. Rebuild with cabal flag -fpostgres."
#endif

closeAppDb :: AppDb -> IO ()
closeAppDb appDb =
  case appDb of
    SQLiteDb connection -> SQLite.close connection
#ifdef POSTGRES_BACKEND
    PostgresDb pool -> destroyAllResources pool
#endif

withAppDbConnection :: AppDb -> (DbConnection -> IO value) -> IO value
withAppDbConnection appDb action =
  case appDb of
    SQLiteDb connection -> action (SQLiteConnection connection)
#ifdef POSTGRES_BACKEND
    PostgresDb pool -> withResource pool (action . PostgresConnection)
#endif

dbDialect :: DbConnection -> DbDialect
dbDialect dbConnection =
  case dbConnection of
    SQLiteConnection _ -> SQLiteDialect
#ifdef POSTGRES_BACKEND
    PostgresConnection _ -> PostgresDialect
#endif

#ifdef POSTGRES_BACKEND
execute :: (SQLiteToRow.ToRow params, PGToRow.ToRow params) => DbConnection -> String -> params -> IO ()
#else
execute :: SQLiteToRow.ToRow params => DbConnection -> String -> params -> IO ()
#endif
execute dbConnection sql params =
  case dbConnection of
    SQLiteConnection connection -> SQLite.execute connection (fromString sql) params
#ifdef POSTGRES_BACKEND
    PostgresConnection connection -> PG.execute connection (fromString sql) params *> pure ()
#endif

execute_ :: DbConnection -> String -> IO ()
execute_ dbConnection sql =
  case dbConnection of
    SQLiteConnection connection -> SQLite.execute_ connection (fromString sql)
#ifdef POSTGRES_BACKEND
    PostgresConnection connection -> PG.execute_ connection (fromString sql) *> pure ()
#endif

#ifdef POSTGRES_BACKEND
query ::
  ( SQLiteToRow.ToRow params,
    SQLiteFromRow.FromRow row,
    PGToRow.ToRow params,
    PGFromRow.FromRow row
  ) =>
  DbConnection ->
  String ->
  params ->
  IO [row]
#else
query ::
  ( SQLiteToRow.ToRow params,
    SQLiteFromRow.FromRow row
  ) =>
  DbConnection ->
  String ->
  params ->
  IO [row]
#endif
query dbConnection sql params =
  case dbConnection of
    SQLiteConnection connection -> SQLite.query connection (fromString sql) params
#ifdef POSTGRES_BACKEND
    PostgresConnection connection -> PG.query connection (fromString sql) params
#endif

#ifdef POSTGRES_BACKEND
query_ :: (SQLiteFromRow.FromRow row, PGFromRow.FromRow row) => DbConnection -> String -> IO [row]
#else
query_ :: SQLiteFromRow.FromRow row => DbConnection -> String -> IO [row]
#endif
query_ dbConnection sql =
  case dbConnection of
    SQLiteConnection connection -> SQLite.query_ connection (fromString sql)
#ifdef POSTGRES_BACKEND
    PostgresConnection connection -> PG.query_ connection (fromString sql)
#endif

withTransaction :: DbConnection -> IO value -> IO value
withTransaction dbConnection action =
  case dbConnection of
    SQLiteConnection connection -> SQLite.withTransaction connection action
#ifdef POSTGRES_BACKEND
    PostgresConnection connection -> PG.withTransaction connection action
#endif

#ifdef POSTGRES_BACKEND
insertReturningId ::
  ( SQLiteToRow.ToRow params,
    PGToRow.ToRow params
  ) =>
  DbConnection ->
  String ->
  String ->
  params ->
  IO Int
#else
insertReturningId ::
  SQLiteToRow.ToRow params =>
  DbConnection ->
  String ->
  String ->
  params ->
  IO Int
#endif
insertReturningId dbConnection sqliteSql postgresSql params =
#ifndef POSTGRES_BACKEND
  let _ = postgresSql
   in
#endif
  case dbConnection of
    SQLiteConnection connection -> do
      SQLite.execute connection (fromString sqliteSql) params
      fromIntegral <$> SQLite.lastInsertRowId connection
#ifdef POSTGRES_BACKEND
    PostgresConnection connection -> do
      rows <- PG.query connection (fromString postgresSql) params
      case rows of
        [DbOnly insertedId] -> pure insertedId
        _ -> fail "PostgreSQL INSERT ... RETURNING did not return exactly one id."
#endif
